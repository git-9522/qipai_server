local skynet = require "skynet"
local proxypack = require "proxypack"
local socket = require "socket"
local cjson = require "cjson"
local pb = require 'protobuf'
local msgdef = require "msgdef"
local server_def = require "server_def"
local dbdata = require "dbdata"
local sharedata = require "sharedata"
local util = require "util"
local player_class = require "player_class"
local constant = require "constant"
local data_access = require "data_access"

local table_insert = table.insert
local table_remove = table.remove

local handler
local internal

local msg_handler

local CMD = {}
local client_fd
local player
local curr_uid
local global_configs

local quitting  --正在退出的时候不能接受任何请求

local logining
local ip

local last_ping_time
local DEBUG = skynet.getenv("debug") or false
local server_name = skynet.getenv "server_name"

--------------------关注该session的连接情况----------------
local function watch_session(game_session,uid,observing)
    local gateway_id = game_session >> 31
    local request
    if observing then
        request = 'observe_fd'
    else
        request = 'unobserve_fd'
    end

    R().gateway(gateway_id):send('.watchdog','common',request,R().get_source(),game_session,uid)
end

---------------------------------------------------------------

local function get_msgid(msgname)
    return msgdef.name_to_id[msgname]
end

local function get_msg_module_name(msgid)
    print("msgid",msgid)
    local m = msgdef.id_to_name[msgid]
    if not m then return end
    return m[1],m[2] --[1]->module,[2]->name
end

local function send_to_gateway(msgname,msg)
    if client_fd <= 0 then
        dbglog(curr_uid,'this client is not connected',client_fd,'skip',msgname)
        return false
    end

    local msgid = get_msgid(msgname)
    if not msgid then
        skynet.error('unknown msgname',msgname,msgid)
        return
    end

    local msg_body = pb.encode(msgname,msg)
	local package = proxypack.pack_client_message(0,msgid,msg_body)

    local gateway_id = client_fd >> 31
    R().gateway(gateway_id):send('.watchdog',server_name,'sendto',client_fd,package)

    print(string.format('[%s]<<<<<player[%s] got a request[%s] content(%s)',
        skynet.address(skynet.self()),tostring(curr_uid),msgname,cjson.encode(msg)))

    return true
end

local function save_data()
    if not player then
        return
    end

    local user_data = player.user_data
    if not user_data:get_dirty_fields() then
        dbglog('there is nothing changed after last saving',curr_uid)
        return
    end

    --暂时全量存库
    local data_copy = user_data:deep_copy()
    --save player data
    R().dbsvr{key=curr_uid}:send('.msg_handler','update',curr_uid,cjson.encode(data_copy))

    user_data:clear_dirty_fields()
end

local function quit()
    dbglog('player is quit now!!!')

    quitting = true

    --再一次检查数据是否保存
    save_data()

    if player then
        local continue_time = util.get_now_time() - player.login_time
        player:billlog('logout',{r = reason,continue_time = continue_time})
    end

    skynet.send(msg_handler,'lua','on_agent_exit',curr_uid,skynet.self())
    
    skynet.exit()
end

local function on_login(player,msg,first)
    player:check_time_cross(global_configs)

    local user_data = player.user_data

    if not first or not player.base_data then
        player.base_data = data_access.pull_base_data(curr_uid) or {}
    end

    local base_data = player.base_data
    local rsp = {
        name  = user_data.name,
        gems  = base_data.gems or 0,
        coins = base_data.coins or 0,
        level = user_data.level,
        icon  = user_data.icon,
        sex  = user_data.sex,
        play_total_count = user_data.play_total_count,
        play_win_count = user_data.play_win_count,
        server_time = util.get_now_time(),
        ping_interval = tonumber(skynet.getenv "ping_interval") or 20,
        roomcards = base_data.roomcards,
    }

    rsp.can_change_name = player:can_change_name()

    send_to_gateway('login.RSP_LOGIN',rsp)

    local messages = skynet.call('.opration_message_mgr','lua','get_messages')
    internal.send_opration_message(messages)
    
    return true
end

local function do_cocall()
    --必须去拉取充值、离线的数据
    local cocall = require("cocall")
    local ok,ret = cocall(5,
        {f = data_access.pull_user_data, id = 'user_data', params = {curr_uid}},
        {f = data_access.pull_user_info, id = 'user_info', params = {curr_uid}},
        {f = data_access.pull_offline_data, id = 'offline_data', params = {curr_uid}},
        {f = data_access.pull_base_data, id = 'base_data', params = {curr_uid}}
    )
    if not ok then
        errlog('failed to cocall',tostring_r(ret))
    end

    return {
        user_data = ret.user_data,
        user_info = ret.user_info,
        offline_data = ret.offline_data,
        base_data = ret.base_data
    }
end

function login(msg)
	local uid = curr_uid

    if logining then
        errlog(uid,'fetching data now... please wait')
        return
    end
    
    if player then
        --多次登录则多次返回
        return on_login(player,msg)
    end

    --向数据服务取得玩家个人数据
    logining = true
    local result = do_cocall()
    local user_data = result.user_data
    if not user_data then
        errlog(uid,'invalid querying')
        return
    end

	dbglog('agent received',tostring_r(user_data))

    player = player_class.new(curr_uid,dbdata.new_from('user',user_data))
    local curr_time = util.get_now_time()

    player.last_save_time = curr_time
    player.login_time = curr_time
    player.user_data.last_login_time = curr_time
    player.user_data.last_login_ip = ip

    --检查字段是否存在，不存在则补齐
    if player:check_user_data(result) then
        player:billlog('new_player',{})
    end

    handler = require("handler")
    handler._init_(player,send_to_gateway,global_configs)

    internal = require("internal")
    internal._init_(player,send_to_gateway,global_configs)

    --至此登录结束
    logining = false
    player:billlog('login',{login_time = player.login_time})

    player.base_data = result.base_data

    watch_session(client_fd,curr_uid,true)
    
    return on_login(player,msg,true)
end

local function dispatch(_, _,  ...)
    if quitting then
        skynet.error('now is quitting...')
        return
    end
    local head_uid,msgid,msg,sz = ...

    local module,name = get_msg_module_name(msgid)
    if not module or not name then
        errlog('invalid msgid',msgid,module,name)
        return
    end

    local pbname = module .. '.' .. name
    local req_msg = pb.decode(pbname,msg,sz)
    if not req_msg then
        errlog("hall agent pb decode error",pbname)
        return
    end

    print(string.format('[%s]>>>>>player[%d] got a request[%s][msgid:%d][sz:%d] content(%s)',
        skynet.address(skynet.self()),curr_uid,pbname,msgid,sz,cjson.encode(req_msg)))

    last_ping_time = util.get_now_time()

    if module == 'login' and name == 'REQ_LOGIN' then
        login(req_msg)
    else
        if not player then
            errlog('other requests required logined')
            return
        end

        assert(handler)
        local module_table = handler[module]
        if module_table and module_table[name] then
            local ret = module_table[name](req_msg,client_fd)
            if not ret then
                errlog('failed to handle requrest',pbname)
            end
        else
            errlog('unknown requrest',pbname)
        end
    end
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
        return proxypack.unpack_client_message(msg,sz)
	end,
	dispatch = dispatch
}

local function routine_handle()
    local curr_time = util.get_now_time()
    if curr_time - last_ping_time >= 720 then
        if not DEBUG then
            dbglog(curr_uid,'this guy is too long to ping, offline now')
            return quit()
        end
    end

    if not player then
        return
    end

    if curr_time - player.last_save_time >= 300 then
        player.last_save_time = curr_time
        dbglog(curr_uid,'save to db...')
        save_data()
    end

    player:check_time_cross(global_configs)
end

local function routine_check()
    while true do
        skynet.sleep(10 * 100)
        local ok,msg = pcall(routine_handle)
        if not ok then errlog(msg) end
    end
end

---------------------------CMD--------------------------------
function CMD.start(conf)
    msg_handler = conf.msg_handler
	client_fd = conf.fd
    curr_uid = conf.uid
    last_ping_time = util.get_now_time()
    ip = conf.ip

    skynet.fork(routine_check)
    return true
end

function CMD.instead(new_client_fd)
    assert(client_fd ~= new_client_fd,'invalid insteading ' .. tostring(new_client_fd))
    
    last_ping_time = util.get_now_time()
    
    if client_fd > 0 then
        local gateway_id = client_fd >> 31
        R().gateway(gateway_id):send('.watchdog','hallsvr','active_close',
            client_fd,curr_uid,R().get_source())
    else
        dbglog(curr_uid,'this agent is not online')
    end

    client_fd = new_client_fd

    watch_session(client_fd,curr_uid,true)

    return true
end

--disconnect不会清理agent,只会把client_fd设成-1
--agent等过期删除
function CMD.disconnect(reason)
    dbglog('player is offlined now',reason)

    --先保存下数据
    save_data()

    --再打log
    if player then
        local continue_time = util.get_now_time() - player.login_time
        player:billlog('logout',{r = reason,continue_time = continue_time})
    end

    client_fd = -1
end

function CMD.close_server()
    dbglog('close_server save player data')
    quit()
end

---------------------------CMD--------------------------------
skynet.start(function()
	skynet.dispatch("lua", function(_,_, param,...)
        if type(param) == 'string' then
            local f = assert(CMD[param],'unknown param '.. param)
            skynet.retpack(f(...))
            return
        end

        local uid = param

        if not player then
            print('no player',uid)
            return
        end

        if quitting then
            print('already quitting',uid)
            return
        end

        if player.uid ~= uid then
            print('not the same uid',player.uid,uid)
            return
        end

        last_ping_time = util.get_now_time()
        
        local action = (...)
        local f = internal[action]
        if not f then
            errlog('unknown action',action)
        else
            f(select(2,...))
        end
	end)

    sharedata.query("global_configs")

    global_configs = setmetatable({},{
        __index = function(t,k) 
            return sharedata.query("global_configs")[k]
        end
    })

    player_class.init(global_configs)
end)
