local skynet = require "skynet"
local cjson = require "cjson"
local proxypack = require "proxypack"
local msgdef = require "msgdef"
local pb = require 'protobuf'
local table_def = require "table_def"
local utils = require "utils"
local sharedata = require "sharedata"
local error_code = require "error_code"

local string_format = string.format
local server_id = tonumber(skynet.getenv "server_id")

local table_insert = table.insert
local table_unpack = table.unpack

local MAX_PLAYER_NUM = 3

local curr_table_num = 0
local closing_server = false
local table_list = {}
local player_table_map = {}
local asyn_data_time_map = {}
local asyn_ftables_time_map = {}

local internal = {}
local table_handler = {}

local stat_data_time = 0

local curr_index = 0
local max_index = 1 << 32 - 1

local function new_table_id()
    local index = curr_index
    curr_index =  curr_index + 1
    if curr_index >= max_index then
        curr_index = 0
    end
    return index
end

local function make_table_gid(table_id)
    return server_id << 32 | table_id
end

local function extract_table_gid(table_gid)
    return table_gid >> 32,table_gid & 0xFFFFFFFF
end

local function get_msgid(msgname)
    return msgdef.name_to_id[msgname]
end

--所有的好友房都存放在此
local friend_tables_t2p_map = {}
local friend_tables_p2t_map = {}
local function link_ftable(table_id,password)
    assert(not friend_tables_p2t_map[password],'password already exist ' .. password)
    friend_tables_t2p_map[table_id] = password
    friend_tables_p2t_map[password] = table_id
end

local function remove_ftable(table_id)
    local password = assert(friend_tables_t2p_map[table_id])
    assert(friend_tables_p2t_map[password] == table_id)
    friend_tables_t2p_map[table_id] = nil
    friend_tables_p2t_map[password] = nil
end

local function send_to_gateway(uid,client_fd,msgname,msg)
    local msgid = get_msgid(msgname)
    if not msgid then
        skynet.error('unknown msgname',msgname,msgid)
        return
    end

    local msg_body = pb.encode(msgname,msg)
    local package = proxypack.pack_client_message(0,msgid,msg_body)

    local gateway_id = client_fd >> 31
    R().gateway(gateway_id):send('.watchdog','tablesvr','sendto',client_fd,package)

    print(string.format('[%s]<<<<<player[%s] send to a request[%s] content(%s)',
        skynet.address(skynet.self()),tostring(uid),msgname,cjson.encode(msg)))

    return true
end

function internal.get_playing_player_count()
    local playing_count = 0
    for uid,_ in pairs(player_table_map) do
        playing_count = playing_count + 1
    end

    return skynet.retpack(playing_count)
end

function internal.get_table_stats(_,_,from_src,toservice,flag)
    --if asyn_data_time_map[from_src] ~= flag then
        R().dest(from_src):send(toservice,'report_table_stats',
            server_id,curr_table_num,closing_server)
        asyn_data_time_map[from_src] = flag
    --end
end

function internal.get_ftable_stats(_,_,from_src,toservice,flag)
    if asyn_ftables_time_map[from_src] ~= flag then
        R().dest(from_src):send(toservice,'report_ftable_stats',
            server_id,friend_tables_p2t_map,curr_table_num)
        asyn_ftables_time_map[from_src] = flag
    else
        R().dest(from_src):send(toservice,'report_ftable_stats',
            server_id,false,curr_table_num)
    end
end

local function get_addr(uid)
    local table_id = player_table_map[uid]
    if not table_id then 
        return nil,error_code.PLAYER_NOT_ON_TABLE
    end
    
    local addr = table_list[table_id]
    if not addr then
        return nil,error_code.TABLE_IS_NOT_EXISTING
    end
    return addr
end

function internal.on_table_delete(_,source,table_id,player_uids)
    assert(table_list[table_id] == source,
        string.format('%s == %s',tostring(table_list[table_id]),tostring(source)))
    table_list[table_id] = nil
    curr_table_num = curr_table_num - 1

    --保证所有的玩家都会被清空
    for _,uid in pairs(player_uids) do
        if player_table_map[uid] == table_id then
            player_table_map[uid] = nil
        end
    end

    if friend_tables_t2p_map[table_id] then
        remove_ftable(table_id)
    end
    
    skynet.retpack(true)
end

function internal.disconnect(_,_,uid,game_session)
    local table_id = player_table_map[uid]
    if not table_id then
        errlog('this uid is not in table now',uid)
        return
    end
    
    player_table_map[uid] = nil
    local addr = assert(table_list[table_id])
    skynet.send(addr,'lua','disconnect',uid,game_session)
end

function internal.leave(_,source,uid)
    local addr = get_addr(uid)
    if addr == source then
        player_table_map[uid] = nil
    end
end

local function alloc_new_table_addr(table_type,payload)
    local service_name = table_def.server_name_map[table_type]
    if not service_name then
        errlog('unknown table_type',table_type)
        return
    end

    local table_id = new_table_id()

    table_list[table_id] = false
    local addr = skynet.newservice(service_name)
    table_list[table_id] = addr
    curr_table_num = curr_table_num + 1
    skynet.call(addr,'lua','start',{
        table_id = table_id,
        table_type = table_type,
        table_gid = make_table_gid(table_id),
        payload = payload,
    })

    billlog({op="enter",table_type = table_type,table_id = table_id,addr = addr})

    return table_id,addr
end 

local function _create_ftable(uid,table_info,password)
    local table_type = table_info.table_type
    local table_id,addr = alloc_new_table_addr(table_type,table_info)
    if not table_id or not addr then
        errlog(uid,'could alloc new table',table_type,table_id,addr)
        return
    end

    link_ftable(table_id,password)

    return make_table_gid(table_id)
end

function internal.create_ftable(_,_,uid,table_info,password)
    if friend_tables_p2t_map[password] then
        --这个房间已经存在了,可能是出现了不一致
        errlog(uid,'this table is already existing',password)
        skynet.retpack(-99)
        return
    end

    local r = { _create_ftable(uid,table_info,password) }
    if #r > 0 then
        skynet.retpack(table_unpack(r))
    end
end

function internal.register_all(_,_,table_data,player_data_list)
    local table_type = table_data.table_type
    if not table_def.table_type_map[table_type] then
        errlog("unknown table type",table_type)
        return
    end

    local table_id = alloc_new_table_addr(table_type)
    local addr = assert(table_list[table_id])
    
    if not skynet.call(addr,'lua','register_all',player_data_list) then
        --注册不成功，直接把服务关掉
        skynet.send(addr,'lua','exit')
        table_list[table_id] = nil
        curr_table_num = curr_table_num - 1
        errlog('failed to register_all!!!!!')
        return skynet.retpack(-1)
    end

    local table_gid = make_table_gid(table_id)
    skynet.retpack(table_gid)
end

function internal.touch_table(_,_,table_gid)
    local _,table_id = extract_table_gid(table_gid)
    local addr = table_list[table_id]
    if not addr then
        return skynet.retpack(false)
    end

    local key = friend_tables_t2p_map[table_id]
    if not key then
        errlog(table_gid,'unidentified table key',key)
        return skynet.retpack(false)
    end

    --延长一下删除时间
    skynet.send(addr,'lua','touch',key)
    
    return skynet.retpack(key)
end

function internal.get_ftable_info(_,_,valid_tables)
    local table_info_list = {}
    for password,enter_time in pairs(valid_tables) do
        local table_gid = friend_tables_p2t_map[password]
        if not table_gid then
            goto continue
        end
        local _,table_id = extract_table_gid(table_gid)
        local addr = table_list[table_id]
        if not addr then
            errlog("ftable is not exist",password)
            goto continue
        end

        local table_info = skynet.call(addr,'lua','get_ftable_info')
        if table_info then
            table_info_list[password] = table_info
        end

        ::continue::
    end
    skynet.retpack(table_info_list)
end

function internal.update_coins_on_table(_,_,uid,table_gid,coins)
    local _,table_id = extract_table_gid(table_gid)
    local addr = table_list[table_id]
    if not addr then
        return skynet.retpack(false)
    end
    skynet.send(addr,'lua','update_coins_on_table',uid,coins)
    return skynet.retpack(true)
end

-----------------------------------------------------------------------------
function table_handler.table_REQ_CONFIG_CARDS(uid,msg,game_session)
    print(uid,game_session)
    local game_type = msg.game_type
    local self_cards = utils.str_split(msg.self_cards,".") or {}
    local cards1 = utils.str_split(msg.cards1,".") or {}
    local cards2 = utils.str_split(msg.cards2,".") or {}
    local cards3 = utils.str_split(msg.cards3,".") or {}
    local laizi_id = msg.laizi_id

    local all_cards = {}
    local function convert_to_number(t) 
        for k,v in pairs(t) do
            t[k] = tonumber(v)
        end
    end

    local getcards = function(cards)
        if cards then
            convert_to_number(cards)
            for id,card in ipairs(cards) do
                local count = all_cards[card] or 0
                count = count + 1
                all_cards[card] = count
            end
        end
    end
    if game_type == 2 then
    --血战配牌验证
        if #self_cards > 13 or #cards1 > 13 or #cards2 > 13 or #cards3 > 13 then
            send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = error_code.INPUT_ERROR})
            return
        end
        
        getcards(self_cards)
        getcards(cards1)
        getcards(cards2)
        getcards(cards3)

        for card,count in pairs(all_cards) do
            if card > 39 or card < 11 or count > 4 then
                send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = error_code.INPUT_ERROR})
                return
            end
        end
    else
    --斗地主配牌验证
        if #self_cards > 17 or #cards1 > 17 or #cards2 > 17 then
            send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = error_code.INPUT_ERROR})
            return
        end

        if laizi_id and laizi_id < 0 then
            send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = error_code.INPUT_ERROR})
            return
        end 
        
        --验证
        
        
        getcards(self_cards)
        getcards(cards1)
        getcards(cards2)

        for card,count in pairs(all_cards) do
            if card > 15 or count > 4 then
                send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = error_code.INPUT_ERROR})
                return
            end
        end
    end
    local key = string_format('player_%d_%d',game_type,uid)
    local bret = skynet.call(".cache_data","lua","get",key)
    if #self_cards == 0 and #cards1 == 0 and not #cards2 == 0 then
        if bret then
            skynet.send(".cache_data","lua","set",key,nil)
            send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = 0})
            return true
        end
    end
    local cards_info = {}
    cards_info.game_type = game_type
    cards_info.self_cards = self_cards
    cards_info.cards1 = cards1
    cards_info.cards2 = cards2
    cards_info.cards3 = cards3
    cards_info.laizi_id = laizi_id or 0
    print_r(cards_info)
    skynet.send(".cache_data",'lua','set',key,cards_info)
    send_to_gateway(uid,game_session,'table.RSP_CONFIG_CARDS',{result = 0})

    return true
end

---------------------------------table enter------------------------
function table_handler.table_REQ_ENTER(uid,msg,game_session)
    local table_gid = msg.table_gid
    local table_server_id,table_id = extract_table_gid(table_gid)
    print(table_server_id,table_id)
    print_r(table_list)

    if table_server_id ~= server_id then
        errlog(uid,'this is not the table server',server_id,table_server_id)
        return
    end
    dbglog(uid,'player enter table now...')
    local addr = table_list[table_id]
    if not addr then
        errlog(uid,'invalid table_gid unset this table',table_gid)
        send_to_gateway(uid,game_session,'table.RSP_ENTER',
            {result = error_code.TABLE_IS_NOT_EXISTING})
        --玩家已经不在这个桌子上，去解一下锁？
        R().exdbsvr(1):send('.tlock_mgr','unset_on_table',uid,table_gid)
        return
    end
    local ok = skynet.call(addr,'lua','enter',uid,game_session)
    if not ok then
        errlog(uid,'failed to enter',tostring(table_gid))
        return
    else
        --进房了则修改玩家当前的桌子映射
        player_table_map[uid] = table_id
    end

    return true
end
--=================================table protocal=================

--=================================close server===================
function internal.close_server()
    closing_server = true
    for table_id,addr in pairs(table_list) do
        skynet.send(addr,'lua','close_server')
    end
end
--=================================close server===================
local function get_msg_module_name(msgid)
    local m = msgdef.id_to_name[msgid]
    if not m then return end
    return m[1],m[2] --[1]->module,[2]->name
end

local function dispatch_client_message_locally(game_session,uid,f,pbname,msg,size)
    local _,msgid,pbmsg,pbsize = proxypack.unpack_client_message(msg,size)

    local req_msg = pb.decode(pbname,pbmsg,pbsize)
    if not req_msg then
        errlog(uid,"table_mgr pb decode error",pbname)
        return
    end

    dbglog(string.format('>>>>>player[%s] got a request[%s] content(%s)',
        tostring(uid),pbname,cjson.encode(req_msg)))

    local ret = f(uid,req_msg,game_session)
    if not ret then
        errlog('failed to handle requrest',pbname)
    end
end

local function relay_to_table(game_session,uid,data,module,name)
    local addr,code = get_addr(uid)
    if addr then
        skynet.send(addr,'client',game_session,uid,data)
    else
        --不在桌子上则发统一的result给客户端
        dbglog(uid,"player's table is not exist now !")

        --replace the REQ to RSP
        local rsp_name = string_format('%s.RSP%s',module,name:sub(4))
        return send_to_gateway(uid,game_session,rsp_name,
            {result = code})
    end
end

local function dispatch(_,_,game_session,uid,data)
    local _,msgid = proxypack.peek_client_message(data)
    local module,name = get_msg_module_name(msgid)
    if not module or not name then
        errlog('invalid msgid',msgid,module,name)
        return
    end

    local handler_name = string_format('%s_%s',module,name)
    local f = table_handler[handler_name]
    if not f then
        return relay_to_table(game_session,uid,data,module,name)
    end

    local pbname = string_format('%s.%s',module,name)
    local msg,size = proxypack.pack_raw(data)
    local ok,ret = xpcall(dispatch_client_message_locally,debug.traceback,
        game_session,uid,f,pbname,msg,size)
    skynet.trash(msg,size)  --这里需要保证内存被释放
    if not ok then 
        errlog(ret)
    end
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = skynet.unpack,
    pack = skynet.pack,
    dispatch = dispatch
}

local function handle_request(session,source,action,...)
    dbglog('fffffffffffff',action,...)
    local f = assert(internal[action],'unknown action ' .. action)
    f(session,source,...)
end

skynet.start(function()
	skynet.dispatch("lua",function(session,source,...)
		handle_request(session,source,...)
	end)
end)
