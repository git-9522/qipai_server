local skynet = require "skynet"
local socket = require "socket"
local xuezhan = require "xuezhan"
local utils = require "utils"
local proxypack = require "proxypack"
local msgdef = require "msgdef"
local pb = require 'protobuf'
local cjson = require "cjson"
local server_def = require "server_def"
local util = require "util"
local table_def = require "table_def"
local sharedata = require "sharedata"
local offline_op = require "offline_op"
local error_code = require "error_code"
local reason = require "reason"
local cocall = require "cocall"
local game_robot = require "xuezhan_robot"

local select_server = require("router_selector")
local global_config 

local table_insert = table.insert
local table_remove = table.remove
local table_sort   = table.sort
local table_unpack = table.unpack
local math_floor = math.floor
local string_format = string.format

local table_players = {}
local player_status_list = {}
local player_info_list = {}
--玩家的顺序
local ordered_players = {}

-----每一局的对战记录--------------
local record_list = {}
--------------------玩家进场状态---------------------
local PLAYER_STATUS_READY = 1
local PLAYER_STATUS_NOREADY = 2
local PLAYER_STATUS_PLAYING = 4

-------------------发给客户通知的状态--------------------
local PLAYER_STATUS_TRUSTEE = 3
local EVENT_STATUS_STAND = 5
local EVENT_STATUS_SITDOWN = 6

--------------是否封顶-------------------
local FENGDING_NOT = 0
local FENGDING_YES = 1
-------------------管理---------------------

local cur_instance

local handler = {}
local internal = {}

local REGISTER_CLIENT_FD = 0
local ROBOT_CLIENT_FD = -1
local OFFLINE_CLIENT_FD = -2

-------------------托管管理------------------------
local trusteed_players = {}
local TIMEOUT_TIMES_TO_TRUSTEE = 2

local robot_manager = {}

-----------------观战列表--------------------------
local look_player_list = {}

--------------------游戏关服管理--------------------
local colsing_server = false

------------------解散管理------------------------------
local is_round_over = false
local agree_dissovle_map
local NOT_START_DISSVOLE_NUM = 1
local STARTED_DISSVOLE_NUM   = 2

local RECYCLEING_TABLE_TIMEOUT = 60
local recycling_table_start_time
local TOUPIAO_TIME = 30

local DISS_REASON_CREATE = 1
local toupiao_end_time
local DISS_REASON_TOUPIAO = 2
local DISS_REASON_ROUND_OVER = 3
local DISS_REASON_TIME_OUT = 4
local DISS_REASON_CLOSE_SERVER = 5

local DISS_TOUPIAO_RESULT_INIT = -1
local DISS_TOUPIAO_RESULT_REFUSE = 0
local DISS_TOUPIAO_RESULT_AGREE = 1
-----------------------游戏状态------------------------
local TABLE_STATUS_WAITTING_READY = 3 --等待准备
local TABLE_STATUS_CHECK_START = 4
local TABLE_STATUS_DEAL_CARDTOON = 5
local TABLE_STATUS_HUANSANZHANG = 6
local TABLE_STATUS_HUANSANZHANG_CARTOON = 7
local TABLE_STATUS_DINGQUE = 8        
local TABLE_STATUS_PLAYING = 9
local TABLE_STATUS_GAMEOVER = 10
local TABLE_STATUS_AUDIT_RESULT = 11
local TABLE_STATUS_RESTART = 12

local table_info 
local creator_uid
local curr_round
local ftable_expiry_time
local ftable_unstart_expiry_time

local curr_status
local curr_enter_list = {}
local curr_locked_uids = {}
local nodizhu_times = 1
local MAX_NODIZHU_TIMES = 2

--------------------游戏时长管理--------------------
local game_start_time = 0
local game_over_time  = 0
local deal_cardtoon_end_time = 0

-----------------------游戏状态------------------------
return function(params)
local ddz = params.ddz
local trustee_AI = params.trustee_AI

local tablesvr_id = tonumber(skynet.getenv "server_id")
local self_table_type,self_table_id,self_password 

local this_table_gid

local function make_tiles(xz)
    local player_tiles_map = xz.player_tiles_map
    local keys = {}
    for k in pairs(player_tiles_map) do
        keys[#keys + 1] = k
    end

    -- player_tiles_map[keys[1]] = {11,11,11,11,12,12,12,13,13,13,14,18,18}
    -- player_tiles_map[keys[2]] = {21,21,21,21,22,22,22,22,23,23,23,23,24}
    -- player_tiles_map[keys[3]] = {31,31,31,31,32,32,32,32,33,33,33,33,34}
    -- player_tiles_map[keys[4]] = {15,15,15,15,16,16,16,16,17,17,17,17,18}

    player_tiles_map[keys[1]] = {11,11,11,12,12,12,13,13,13,17,18,19,31}
    player_tiles_map[keys[2]] = {27,27,27,28,28,28,29,29,29,31,31,32,32}
    player_tiles_map[keys[3]] = {11,39,22,23,23,24,24,25,26,26,27,28,29}
    player_tiles_map[keys[4]] = {31,38,32,32,33,34,35,36,36,36,37,38,38}

    print("ooooooooooooooooooooooooooooooooooooooooooooo")
    print_r(player_tiles_map)

    local all_used_tiles = {}
    for i = 1,3 do
        for j = 1,9 do
            local tile = i*10+j
            all_used_tiles[tile] = 4
        end
    end

    for k,player_tile_list in pairs(player_tiles_map) do
        for _,tile in pairs(player_tile_list) do
            local c = all_used_tiles[tile]
            assert(c > 0)
            c = c -1
            if c > 0 then
                all_used_tiles[tile] = c
            else
                all_used_tiles[tile] = nil
            end
        end
    end

    local tile_list = {}
    for tile,count in pairs(all_used_tiles) do
        for i = 1,count do
            tile_list[#tile_list + 1] = tile
        end
    end

    xz.tile_list = tile_list

    -- xz.player_dingque_map[keys[1]] = 3
    -- xz.player_dingque_map[keys[2]] = 3
    -- xz.player_dingque_map[keys[3]] = 3
    -- xz.player_dingque_map[keys[4]] = 3

    xz.test_player_draw_tile[keys[1]] = 11

    xz.banker_uid = keys[3]
end

local function send_to_gateway(uid,client_fd,...)
    if client_fd <= 0 then
        return
    end
    return utils.send_to_gateway(0,uid,client_fd,...)
end

local function notify_others(action,excepted_uid,msg)
    for uid, fd in pairs(table_players) do
        if uid ~= excepted_uid then
            send_to_gateway(uid,fd,action,msg)
        end
    end
end

local function notify_all(action,msg)
    return notify_others(action,nil,msg)
end

local function get_player_num()
    local n = 0
    for _,_ in pairs(table_players) do
        n = n + 1
    end
    return n
end

---------------------------------------------------------------------------
local function trigger_event(action,...)
    for _,AIobj in pairs(robot_manager) do
        local f = AIobj[action]
        if f then
            f(AIobj,...)
        end
    end
end

local function run_robots()
    for _,AIobj in pairs(robot_manager) do
        skynet.fork(function() AIobj:update() end)
    end
end

local function is_robot(uid)
    return table_players[uid] == ROBOT_CLIENT_FD
end

local function get_ready_player_num()
    local count = 0
    for uid,status in pairs(player_status_list) do
        if status ~= PLAYER_STATUS_READY then
            if is_robot(uid) then
                trigger_event('on_ready')
            end
            return false
        end
        count = count + 1
    end

    return count
end

local function get_player_state(uid)
    local state = 0
    local ready_status = player_status_list[uid]
    --准备状态
    if ready_status == PLAYER_STATUS_NOREADY then
        ready_status = 0
    elseif ready_status == PLAYER_STATUS_READY then
        ready_status = 1
    elseif ready_status == PLAYER_STATUS_PLAYING then
        ready_status = 2       
    end

    --在线状态
    local online_status = 1
    if table_players[uid] and table_players[uid] == OFFLINE_CLIENT_FD then
        online_status = 0
    end
    online_status = online_status << 2

    --托管状态
    local trust_status = 0
    if trusteed_players[uid] and trusteed_players[uid] >= TIMEOUT_TIMES_TO_TRUSTEE then
        trust_status = 1
    end 
    trust_status = trust_status << 3

    state = ready_status | online_status | trust_status
    return state
end

local function notify_event_status(uid)
    local state = get_player_state(uid)
    
    local msg = {uid = uid,state = state}
    notify_others('majiang.NTF_EVENT',nil,msg)
end

local function notify_player_leave(uid,status)
    notify_others('majiang.NTF_PLAYER_LEAVE',uid,{uid = uid,status = status})
end

local function watch_session(game_session,uid,observing)
    if game_session <= 0 then
        return
    end
    local gateway_id = game_session >> 31
    local request
    if observing then
        request = 'observe_fd'
    else
        request = 'unobserve_fd'
    end

    R().gateway(gateway_id):send('.watchdog','tablesvr',request,R().get_source(),game_session,uid)
end

local function is_trusteed(uid)
    local t = trusteed_players[uid]
    return t and t >= TIMEOUT_TIMES_TO_TRUSTEE
end

local function get_round_serial()
    local rsp_round_serial = {}
    for i=1,#record_list do
        local round_info = {}
        round_info.round = i
        local player_list = {}
        for _,o in pairs(record_list[i]) do
            table_insert(player_list,{uid = o.uid,add_score = o.add_score})
        end
        round_info.player_list = player_list
        table_insert(rsp_round_serial,round_info)
    end
    return rsp_round_serial
end

local function get_rank_list()
    local rsp_rank_list = {} 
    for _,uid in pairs(ordered_players) do
        local one_player_info = {}
        one_player_info.uid = uid
        one_player_info.round_times = #record_list
        local win_times = 0
        local score = 0
        for i=1,#record_list do
            for j=1,#record_list[i] do
                if record_list[i][j].uid == uid then
                    if record_list[i][j].add_score > 0 then
                        win_times = win_times + 1
                    end
                    score = score + record_list[i][j].add_score
                    break
                end
            end 
        end
        one_player_info.win_times = win_times
        one_player_info.score = score
        table_insert(rsp_rank_list,one_player_info)  
    end
    table_sort(rsp_rank_list,function(a,b) return a.score > b.score end)

    for i=1,#rsp_rank_list do
        rsp_rank_list[i].rank = i
    end

    return rsp_rank_list
end

local function get_player_score(uid,rank_list)
    local curr_score = 0
    if not rank_list then
        rank_list = get_rank_list()
    end    
    for i=1,#rank_list do
        if uid == rank_list[i].uid then
            curr_score = rank_list[i].score
        end
    end
    return curr_score
end

local function notify_player_enter(uid)
    local player_info = assert(player_info_list[uid])
    local player = {
        uid = uid,
        name = player_info.name,
        position = player_info.position,
        coins = player_info.coins,
        icon = player_info.icon,
        sex = player_info.sex,
        state = get_player_state(uid),
        player_ip = player_info.player_ip,
    }

    notify_others('majiang.NTF_PLAYER_ENTER',uid,{player = player})
end

---------------------------------------------------------------------------
local function lock_one_player(uid,table_gid)
    local ok,succ = R().exdbsvr(1):call('.tlock_mgr','set_on_table',uid,table_gid,table_gid)
    if not ok then
        errlog(uid,'failed to set_on_table')
        return
    end

    if not succ then
        return
    end

    curr_locked_uids[uid] = true
    return 0
end

local function unlock_one_player(uid,table_gid)
    R().exdbsvr(1):send('.tlock_mgr','unset_on_table',uid,this_table_gid)
    curr_locked_uids[uid] = nil
end

local function unlock_all_players()
    for uid,_ in pairs(table_players) do
        unlock_one_player(uid,this_table_gid)
    end
end

local function are_all_players_locked()
    for _,r in pairs(curr_locked_uids) do
        if not r then
            return false
        end
    end

    return true
end

---------------------------------------------------------------------------
local function get_player_enter_data(uid,client_fd)
     --先拉取玩家信息
     local names_library = global_configs.names_library
     if client_fd == ROBOT_CLIENT_FD then
        local player_data = {
            uid = uid,
            name = names_library[util.randint(1,#names_library)],
            coins = util.randint(9999,1999999),
            win_times = util.randint(10,1000),
            failure_times = util.randint(10,1000),
            sex = util.randint(1,2),
        } 
        player_data.icon = tostring(player_data.sex)
        return player_data
     else
        local ok,base_data = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
        if not ok then
            errlog(uid,'failed to get base_data',uid)
            return
        end
        local ok,enter_data = R().hallsvr({key=uid}):call('.msg_handler','get_enter_data',uid)
        if not ok then
            errlog(uid,'failed to get enter_data')
            enter_data = {}
        end
        local ip_str = enter_data.player_ip
        local player_data = {
            uid = base_data.uid,
            name = enter_data.name or '',
            coins = base_data.coins,
            win_times = base_data.win_times,
            failure_times = base_data.losing_times,
            icon = enter_data.icon or '',
            sex = enter_data.sex or 1,
            player_ip = ip_str:sub(1,ip_str:find(':') - 1),
        }

        return player_data
    end    
end

local function get_table_conf()
    local conf = {}
    conf.creator_uid = creator_uid
    conf.curr_round = curr_round
    conf.password = self_password
    conf.total_round = table_info.total_count
    conf.limit_rate = table_info.limit_rate
    conf.zimo_addition = table_info.zimo_addition
    conf.dianganghua   = table_info.dianganghua
    conf.exchange_three = table_info.exchange_three
    conf.hujiaozhuanyi = table_info.hujiaozhuanyi
    conf.duanyaojiu = table_info.duanyaojiu
    conf.daiyaojiu = table_info.daiyaojiu
    conf.jiangdui = table_info.jiangdui
    conf.mengqing = table_info.mengqing
    conf.tiandi_hu = table_info.tiandi_hu
    conf.haidilaoyue = table_info.haidilaoyue
    conf.base_score = table_info.base_score

    return conf
end

local function get_player_info_list()
    local tmp_player_info_list = {}

    for uid,data in pairs(player_info_list) do
        table_insert(tmp_player_info_list,{
                uid = uid,
                name = data.name,
                position = data.position,
                coins = data.coins,
                icon = data.icon,
                sex = data.sex,
                state = get_player_state(uid),
                player_ip = data.player_ip,
        })
    end 

    return tmp_player_info_list
end

local function enter(uid,client_fd)
    print('now enter ========================',uid,client_fd)
    if table_players[uid] then
        local data = get_player_enter_data(uid,client_fd)
        if not data then
            errlog(uid,'failed to get_player_enter_data')
            return false,error_code.CANNOT_ENTER_TEMOPORARILY
        end

        --有空位的话直接坐到位置上
        local player_info = assert(player_info_list[uid],'no player info ' .. tostring(uid))
        if not player_info.name then
            player_info.name = data.name
        end
        if not player_info.icon then
            player_info.icon = data.icon
        end
        player_info.coins = data.coins
        player_info.win_times = data.win_times
        player_info.failure_times = data.failure_times
    elseif curr_round == 0 then
        local num = get_player_num()
        if num >= xuezhan.REQUIRED_PLAYER_NUM then
            errlog(uid,'that player num is enough')
            return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
        end
        if client_fd ~= ROBOT_CLIENT_FD then
            if  not lock_one_player(uid,this_table_gid) then
                errlog(uid,'failed to lock player,you may have been in other table')
                return false,error_code.CANNOT_ENTER_FTABLE_LOCKED
            end
        end

        local data = get_player_enter_data(uid,client_fd)
        if not data then
            errlog(uid,'failed to get_player_enter_data')
            return false,error_code.CANNOT_ENTER_TEMOPORARILY
        end

        --有空位的话直接坐到位置上
        local position = 1
        while ordered_players[position] do
            position = position + 1
        end

        if position > xuezhan.REQUIRED_PLAYER_NUM then
            unlock_one_player(uid,this_table_gid)
            errlog(uid,'that player num is enough four people',position)
            return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
        end

        data.position = position
        ordered_players[position] = uid
        player_info_list[uid] = data
        if client_fd ~= ROBOT_CLIENT_FD then
            player_status_list[uid] = PLAYER_STATUS_NOREADY
        else
            player_status_list[uid] = PLAYER_STATUS_READY
        end    
    else
        errlog(uid,'that player have not been registed yet')
        return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
    end
    --通知其它玩家当前玩家进来
    notify_player_enter(uid)
    
    table_players[uid] = client_fd

    local enter_info = {}
    enter_info.ftable_info = get_table_conf()
    enter_info.player_info_list = get_player_info_list()
    if cur_instance then
        enter_info.game_status = cur_instance:get_game_status(uid)
    end

    print("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",cur_instance)
    print_r(enter_info)

    return true,{game_type = 2,table_type = self_table_type, majiang_enter_info = enter_info}
end

local function finish_game()
    local ok,result = cur_instance:get_game_result()
    if not ok then
        return
    end

    return result
end

local function set_all_unready()
    for uid,status in pairs(player_status_list) do
        assert(status == PLAYER_STATUS_PLAYING)
        player_status_list[uid] = PLAYER_STATUS_NOREADY
    end
end

local function set_all_untrustee()
    for uid,status in pairs(trusteed_players) do
        trusteed_players[uid] = nil
    end    
end

local function set_ready(uid,ready)
    assert(player_status_list[uid])
    if ready then
        player_status_list[uid] = PLAYER_STATUS_READY
    else
        player_status_list[uid] = PLAYER_STATUS_NOREADY 
    end
    notify_event_status(uid)
    return true
end


------------------------------------托管相关---------------------------------
--托管出牌
local function trustee_play()
    local uid = cur_instance:get_curr_player_uid()
    if cur_instance:is_playing() then
        local hu,tile = trustee_AI.trustee_play(uid,cur_instance)
        if hu then
            dbglog('player-hu--------------------',uid)
            handler.REQ_WIN(uid,{})
        else
            dbglog('player---------------------',uid,tile)
            handler.REQ_DISCARD(uid,{tile = tile})
        end
    end
end

local function check_trusteed_player(curr_time)
    local uid = cur_instance:get_curr_player_uid()
    local timeout_times = trusteed_players[uid] or 0
    print("ssssssssss",uid,timeout_times)
    if timeout_times >= TIMEOUT_TIMES_TO_TRUSTEE then
        trustee_play()
        return
    elseif cur_instance:is_playing() and curr_time >= cur_instance:get_curr_player_endtime() then
        print("uuuuuuuuuuuuu",cur_instance:get_curr_player_endtime(),curr_time)
        timeout_times = timeout_times + 1
        trusteed_players[uid] = timeout_times
        trustee_play()

        if timeout_times >= TIMEOUT_TIMES_TO_TRUSTEE then
            notify_event_status(uid)
        else
            send_to_gateway(uid,table_players[uid],'ddz.NTF_PLAY_TIMEOUT',{
                times = 1,total_times = TIMEOUT_TIMES_TO_TRUSTEE})
        end
        return
    end

    return
end

local function are_all_players_ready()
    if get_player_num() < xuezhan.REQUIRED_PLAYER_NUM then
        return false
    end

    print(get_ready_player_num(),xuezhan.REQUIRED_PLAYER_NUM)
    if get_ready_player_num() ~= xuezhan.REQUIRED_PLAYER_NUM then
        return false
    end

    return true
end

local function make_defined_rules(table_info)
    assert(table_info)
    return {
        huansanzhang = table_info.exchange_three,
        hujiaozhuanyi = table_info.hujiaozhuanyi,
        duanyaojiu = table_info.duanyaojiu,
        daiyaojiu = table_info.daiyaojiu,
        jiangdui = table_info.jiangdui,
        mengqing = table_info.mengqing,
        tiandi_hu = table_info.tiandi_hu,
        haidilaoyue = table_info.haidilaoyue,
        base_score = table_info.base_score,
        limit_rate = table_info.limit_rate,
        dianganghua = table_info.dianganghua,
        zimo_addition = table_info.zimo_addition,
    }
end

local function can_start()
    if cur_instance then
        return false,-1
    end

    local instance = xuezhan:new()
    instance:init()

    local defined_rules = make_defined_rules(table_info)
    instance:start(ordered_players,defined_rules)
    instance:shuffle_and_deal()

    for uid,status in pairs(player_status_list) do
        player_status_list[uid] = PLAYER_STATUS_PLAYING
    end

    return instance
end

local function notify_start()
    print('now notify game is started....')

    local ntf = {}
    for _,uid in pairs(ordered_players) do
        ntf.game_status = cur_instance:get_game_status(uid)
        ntf.fround = curr_round
        send_to_gateway(uid,table_players[uid],'majiang.NTF_START',ntf)
    end
end

local function notify_exchange_three_start()
    local ntf = {
        exchange_end_time = cur_instance:get_huangsanzhang_end_time(),
        exchange_direction = cur_instance:get_huangsanzhang_direction(),
    }
    for _,uid in pairs(ordered_players) do
        ntf.tile_list = cur_instance:get_auto_huansanzhang(uid)
        send_to_gateway(uid,table_players[uid],'majiang.NTF_EXCHANGE_THREE_START',ntf)
    end
end

local function notify_dingque_start()
    local ntf = {dingque_end_time = cur_instance:get_dingque_end_time()}
    notify_all('majiang.NTF_DINGQUE_START',ntf)
end

local function notify_next_play(ret,is_draw)
    local end_time = cur_instance:get_curr_player_endtime()
    local ntf = { uid = ret.uid,is_draw = is_draw,op_end_time = end_time}
    if not is_draw then
        notify_all('majiang.NTF_NEXT_DISCARD_PLAYER',ntf)
        return
    end

    for _,uid in pairs(ordered_players) do
        if uid == ret.uid then
            local option = {gang = ret.gang or ret.bugang,angang = ret.angang,hu = ret.hu}
            local msg = {tile = ret.tile,option = option,op_end_time = end_time}
            if is_robot(uid) then
                robot_manager[uid]['on_option'](robot_manager[uid],msg.option)
            else
                send_to_gateway(uid,table_players[uid],'majiang.NTF_DRAW_TILE',msg)
            end    
        else
            ntf.tile = ret.tile
            send_to_gateway(uid,table_players[uid],'majiang.NTF_NEXT_DISCARD_PLAYER',ntf)
        end
    end
end

local function notify_player_option(uid,msg,end_time)
    local op = { peng = msg.peng,gang = msg.gang,angang = msg.angang,hu = msg.hu }
    send_to_gateway(uid,table_players[uid],'majiang.NTF_PLAYER_OPTION',{option = op,op_end_time = end_time})
end

local function notify_player_win(uid,hupai_result,score_result)
    local fangpao_uid = uid
    if hupai_result.fangpao then
        fangpao_uid = hupai_result.fangpao
    end

    local addtion
    for uid,record_list in pairs(score_result) do
        for _,record in pairs(record_list) do
            if record.hu_type then
                addtion = record.addtion
            end
        end
    end

    local ntf = {
        uid = uid,
        tile = hupai_result.tile,
        hu_type = hupai_result.hupai_result.type,
        fangpao_uid = fangpao_uid,
        addtion = addtion,
    }
    notify_all('majiang.NTF_WIN',ntf)
end

local function notify_player_gang(uid)
    -- body
end

local function notify_player_money_update(score_result)
    if not score_result then
        return
    end

    local money_update_list = {}
    for uid,record_list in pairs(score_result) do
        local tmp = {uid = uid,update_score = 0,score_detail = {}}
        local update_score = 0
        for _,record in pairs(record_list) do
            update_score = update_score + record.score
            local addtion 
            if record.addtion then
                addtion = {}
                addtion.duanyaojiu = record.addtion.duanyaojiu
                addtion.mengqing = record.addtion.mengqing
                addtion.haidilaoyue = record.addtion.haidilaoyue
                addtion.dianganghua = record.addtion.dianganghua
                addtion.gangshangpao = record.addtion.gangshangpao
                addtion.zimo_addition = record.addtion.zimo_addition
                addtion.gen_count = record.addtion.gen_count
                addtion.tiandihu = record.addtion.tiandihu
                addtion.hujiaozhuangyi = record.addtion.hujiaozhuangyi
                addtion.qianggang = record.addtion.qianggang
            end
            local msg = {op_type = record.op_type,score = record.score,hu_type = record.hu_type,uid_list = record.uid_list,addtion = addtion}
            table_insert(tmp.score_detail,msg)
        end
        tmp.update_score = update_score
        table_insert(money_update_list,tmp)
    end

    print_r(money_update_list)
    notify_all('majiang.NTF_UPDATE_MONEY',{money_update = money_update_list})
end

local function notify_game_over_socre_result()
    local game_over_score_result = assert(cur_instance:get_game_over_score_result()) 
    notify_player_money_update(game_over_score_result)
end

local function check_start(curr_time)
    local instance,msg = can_start()
    if not instance then
        dbglog('failed to can_start()',msg)
        return
    end
    print('now start the game...')

    cur_instance = instance
    return true
end

local function check_huansanzhang_over(curr_time)
    cur_instance:check_and_auto_huansanzhang(curr_time)
    
    if cur_instance:check_huansanzhang_over() then
        local player_huangsanzhang_map = cur_instance:get_player_changed_tiles_map()
        for uid,msg in pairs(player_huangsanzhang_map) do
            send_to_gateway(uid,table_players[uid],'majiang.NTF_HUANSANZHANG_TILES',msg)
        end
        return true
    end
    return false
end

local function check_huansanzhang_cardtoon_over(curr_time)
    if cur_instance:check_huansanzhang_cardtoon_over(curr_time) then
        return true
    end

    return false
end

local function check_dingque_over(curr_time)
    cur_instance:check_and_auto_dingque(curr_time)

    if cur_instance:check_dingque_over() then
        local tmp_list = {}
        local dingque_map = cur_instance:get_player_dingque_map()
        for uid,dingque in pairs(dingque_map) do
            local tmp = {uid = uid,flower = dingque}
            table_insert(tmp_list,tmp)
        end

        local msg = {player_dingque_list = tmp_list}
        notify_all('majiang.NTF_DINGQUE',msg)
        return true
    end
    return false
end

local function start_play(curr_time)
    local ok,result = cur_instance:start_play()
    assert(ok)
    notify_next_play(result,false)

    print("ssssssssssssssssssssssssssssssssss start_play")
    local msg = { hu = result.hu,angang = result.angang }
    player_end_time = cur_instance:get_curr_player_endtime()
    notify_player_option(result.uid,msg,player_end_time)
end

local function check_play_over(curr_time)
    if cur_instance:is_game_over() then
        return true
    end
    
    check_trusteed_player(curr_time)

    local ok,result = cur_instance:check_playing(curr_time)
    print("check_play_over88888888888888888888888",ok)
    print_r(result)
    if ok then
        print("check_play_over9999999999999999999")
        print_r(result)
        if result.drawing then
            notify_next_play(result.drawing,true)
        end

        if result.discard then
        end

        print("5555555555555555555555",result.auto)
        if result.auto then
            print("66666666666666666666")
            for uid,data in pairs(result.auto) do
                print("77777777777777777777777777",data.gangpeng,data.hu)
                if data.hu then
                    notify_player_win(uid,data.hu.hupai_result,data.hu.score_result)
                    notify_player_money_update(data.hu.score_result)
                    if data.hu.yipaoduoxiang then
                        notify_all('majiang.NTF_YIPAODUOXIANG',{dianpao_uid = data.hu.hupai_result.fangpao})
                    end
                elseif data.gangpeng and data.gangpeng == xuezhan.YAOPAI_OP_GANG then
                    if data.ret.ok then
                        local ntf = {uid = uid,gang_type = xuezhan.TYPE_GANG,tile = data.ret.result,ganged_uid = data.ret.ganged_uid}
                        notify_all('majiang.NTF_GANG',ntf)
                        print("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzz")
                        print_r(data.ret.score_result)
                        notify_player_money_update(data.ret.score_result)
                    end
                elseif data.gangpeng and data.gangpeng == xuezhan.YAOPAI_OP_PENG then
                    print("77777777777777777")
                    if data.ret.ok then
                        print("88888888888888888888888",data.ret.result)
                        print_r(data)
                        print_r(data.ret)
                        notify_all('majiang.NTF_PENG',{uid = uid,tile = data.ret.result,penged_uid = data.ret.penged_uid})
                        notify_next_play({uid = cur_instance:get_curr_player_uid()},false)
                    end
                elseif data.gangpeng and data.gangpeng == xuezhan.YAOPAI_OP_BUGANG then
                    print("9999999999999999999999999999999999")
                    print_r(data)
                    notify_player_money_update(data.ret)
                end
            end
        end
    end


    return false
end

local function audit_game_result()
    ---------------------------结算界面-------------------------------------
    local player_left_card_list = cur_instance:get_player_left_card_list()
    local player_record_list = cur_instance:get_player_record_list()
    local ntf = {
        player_record_list = player_record_list,
        player_left_card_list = player_left_card_list,
        liuju = cur_instance:is_liuju(),
    }

    --print_r(ntf)
    notify_all('majiang.NTF_GAMEOVER',ntf)

    assert(not record_list[curr_round])
    record_list[curr_round] = player_record_list

    local save_info = {}
    for k,v in pairs(player_record_list) do
        local _uid = v.uid
        local _name = assert(player_info_list[_uid].name)
        local _icon = assert(player_info_list[_uid].icon)
        table_insert(save_info,{uid = _uid,name = _name,icon = _icon,score = v.add_score})
    end

    --记录写入数据库
    local conf = {
        table_type = self_table_type,
        round_info = save_info,
        curr_round = curr_round,
    }

    local ok,key = R().exdbsvr(1):call('.ftable_handler','save_round_records',self_password,conf)
    if not ok then
        errlog(uid,"save_record failed")
        return false
    end

    local str_date = os.date("%Y%m%d%H%M%S")
    billlog({op = "fcard_record",table_gid = str_date .. "_" .. self_table_id,game_type = 2,
            table_type = self_table_type,begin_time = game_start_time,end_time = util.get_now_time(),
            curr_round = curr_round,password = self_password,player_record_list = player_record_list})
    
    return true
end

local function update_toupiao_result(curr_time)
    assert(agree_dissovle_map)
    if not toupiao_end_time then
        return true
    end

    if curr_time < toupiao_end_time then
        return false
    end

    for uid,r in pairs(agree_dissovle_map) do
        if r == DISS_TOUPIAO_RESULT_INIT then
            --超时了就同意
            agree_dissovle_map[uid] = DISS_TOUPIAO_RESULT_AGREE
            --通知其他玩家
            local ntf = {uid = uid,is_agree = 1}
            notify_others('majiang.NTF_TOUPIAO',uid,ntf)
        end
    end

    return true
end

--return[over,dismiss result]
local function check_toupiao_result()
    local agree_number = 0
    local total_player_num = 0
    local refues_number = 0
    for _,r in pairs(agree_dissovle_map) do
        if r == DISS_TOUPIAO_RESULT_AGREE then
            agree_number = agree_number + 1
        elseif r == DISS_TOUPIAO_RESULT_REFUSE then
            refues_number = refues_number + 1    
        end

        total_player_num = total_player_num + 1
    end

    if refues_number > 0 then
        return true,false
    end

    if agree_number >= math.floor(total_player_num * 3 / 4) then
        return true,true
    end

    return false
end

local function check_empty_table_recycle(curr_time)
    --如果有开始过对局了，则不做空桌回收
    if curr_round > 0 then
        return false
    end

    --如果当前有人在这里，则不做空桌回收
    if next(table_players) then
        if recycling_table_start_time then
            recycling_table_start_time = nil
        end
        return false
    end

    if not recycling_table_start_time then
        recycling_table_start_time = curr_time
        return false
    end

    --假如已经过了1分钟还没有人进来，则可以回收该桌子
    if curr_time - recycling_table_start_time >= RECYCLEING_TABLE_TIMEOUT then
        return true
    end

    return false
end

local function make_player_total_record(player_total_record,records)
    player_total_record.total_score = player_total_record.total_score + records.add_score

    for _,record in pairs(records.add_score_detail) do
        if record.op_type == xuezhan.OP_ZIMO then
            player_total_record.zimo_count = player_total_record.zimo_count + 1
        end
        if record.op_type == xuezhan.OP_DIANPAO then
            player_total_record.jiepao_count = player_total_record.jiepao_count + 1
        end
        if record.op_type == xuezhan.OP_BY_DIANPAO then
            player_total_record.dianpao_count = player_total_record.dianpao_count + 1
        end
        if record.op_type == xuezhan.OP_ANGANG then
            player_total_record.angang_count = player_total_record.angang_count + 1
        end
        if record.op_type == xuezhan.OP_GANG then
            player_total_record.gang_count = player_total_record.gang_count + 1
        end
        if record.op_type == xuezhan.OP_TINGPAI then
            player_total_record.dajiao_count = player_total_record.dajiao_count + 1
        end
    end
end

local function get_total_record_list()
    local total_record_map = {}
    for _,records in pairs(record_list) do
        for _,player_records in pairs(records) do
            if not total_record_map[player_records.uid] then
                total_record_map[player_records.uid] = {
                    uid = player_records.uid,
                    total_score = 0,
                    zimo_count = 0,
                    jiepao_count = 0,
                    dianpao_count = 0,
                    angang_count = 0,
                    gang_count = 0,
                    dajiao_count = 0
                }
            end
            make_player_total_record(total_record_map[player_records.uid],player_records)
        end
    end

    local total_record_list = {}
    for _,record in pairs(total_record_map) do
        table_insert(total_record_list,record)
    end
    return total_record_list
end

local function dissmiss_table(dismiss_reason)
    for uid,fd in pairs(table_players) do
        if fd > 0 then
            watch_session(fd,uid,false)
        end
    end
    --玩家解除桌子锁定
    unlock_all_players()

    print("eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",cur_instance)
    local ntf2 = {total_record_list = get_total_record_list()}
    notify_all('majiang.NTF_TOTAL_RECORD',ntf2)
    print("fffffffffffffffffffffffffffffffffffffffff")
    print_r(ntf2.total_record_list)

    local ntf = {reason = dismiss_reason}
    notify_all('majiang.NTF_FTABLE_DISS',ntf)

    local ntf1 = {rank_list = get_rank_list(),round_list=get_round_serial()}
    notify_all('majiang.NTF_ROUND_OVER',ntf1)

    
    --告知fmatchsvr该桌子已被解散
    R().fmatchsvr(1):send('.table_mgr','dismiss_friend_table',self_password,this_table_gid)

    billlog({op = "close_table",status = curr_status,password = self_password})

    return true
end

local function check_close_table(curr_time)
    local dismiss = false
    local dismiss_reason

    if not dismiss and is_round_over then
        dismiss = true
        dismiss_reason = DISS_REASON_ROUND_OVER
    end

    if not dismiss and agree_dissovle_map then
        update_toupiao_result(curr_time)
        local over,ret = check_toupiao_result()
        if over then
            if ret then
                dismiss = true
                if toupiao_end_time then
                    dismiss_reason = DISS_REASON_TOUPIAO
                else
                    dismiss_reason = DISS_REASON_CREATE
                end
            else
                notify_all('majiang.NTF_FTABLE_DISS',{result = error_code.FTABLE_DISS_FAIL})
            end

            toupiao_end_time = nil
            agree_dissovle_map = nil
        end
    end
    if not dismiss and curr_round == 0 and curr_time >= ftable_unstart_expiry_time then
        dissmiss = true
        dissmiss_reason = DISS_REASON_TIME_OUT
    end

    if not dismiss and curr_round > 0 and curr_time >= ftable_expiry_time then
        dismiss = true
        dismiss_reason = DISS_REASON_TIME_OUT
    end

    if not dismiss and colsing_server == true then
        dismiss = true
        dismiss_reason = DISS_REASON_CLOSE_SERVER
    end

    local recycle
    if not dismiss and check_empty_table_recycle(curr_time) then
        recycle = true
    end

    if not dismiss and not recycle then
        --既不解散也不回收
        return
    end

    if dismiss then
        --解散的话需要显示去请求，因为有退房卡补偿
        local ok,ret = xpcall(dissmiss_table,debug.traceback,dismiss_reason)
        if not ok then
            errlog(ret)
        end
    else
        --此处是回收，可以不通知fmatchsvr
        assert(recycle)
    end

    skynet.call('.table_mgr','lua','on_table_delete',self_table_id,ordered_players)

    dbglog('now delete this table',self_table_id,ordered_players)

    skynet.exit()
end

local function get_robot_num()
    local num = 0
    for _,_ in pairs(robot_manager) do
        num = num + 1
    end
    return num
end


local function check_add_robot() 
    local robot_num = get_robot_num()
    local player_num = get_player_num()
    if player_num == 0 or player_num == xuezhan.REQUIRED_PLAYER_NUM then
        return
    end

    if robot_num >= xuezhan.REQUIRED_PLAYER_NUM - player_num then
        return
    end

    local curr_time = util.get_now_time()
    if curr_time - table_info.created_time < 30  then
        return
    end

    local robots_ids = {1999999991,1999999992,1999999993}
    print("player_num",player_num)
    for i = player_num + 1,xuezhan.REQUIRED_PLAYER_NUM do
        local uid = assert(table_remove(robots_ids))

        local robot_obj = game_robot.new(uid,trustee_AI,skynet.self(),ROBOT_CLIENT_FD)

        robot_manager[uid] = robot_obj
    end
    run_robots()

    trigger_event('on_enter')
    
    return true
end

-------------------------------游戏主循环------------------------
local function update(curr_time)
    --print('=============curr status',tostring(curr_status))
    
    if skynet.getenv "DEBUG" and not skynet.getenv "shenhe" and
       curr_status == TABLE_STATUS_WAITTING_READY and curr_round == 0 then
        check_add_robot()
    end

    if curr_status == TABLE_STATUS_WAITTING_READY then
        print("tttttttttttttttttttt",tostring_r(curr_locked_uids))
        if are_all_players_ready() and are_all_players_locked() then
            curr_status = TABLE_STATUS_CHECK_START
            curr_round = curr_round + 1
        end
    elseif curr_status == TABLE_STATUS_CHECK_START then
        if check_start(curr_time) then
            --第一次开始，在匹配房标记一下
            if curr_round == 1 then 
                R().fmatchsvr(1):send('.table_mgr','ftable_start',self_password)
            end

            game_start_time = util.get_now_time()
            trigger_event('on_start',cur_instance)
            --make_tiles(cur_instance)
            notify_start()

            curr_status = TABLE_STATUS_DEAL_CARDTOON
            deal_cardtoon_end_time = game_start_time + 7
        end
    elseif curr_status == TABLE_STATUS_DEAL_CARDTOON then
        if curr_time >= deal_cardtoon_end_time then
            if table_info.exchange_three then
                curr_status = TABLE_STATUS_HUANSANZHANG 
                notify_exchange_three_start()
            else
                curr_status = TABLE_STATUS_DINGQUE
                notify_dingque_start()
            end
        end
    elseif curr_status == TABLE_STATUS_HUANSANZHANG then
        if check_huansanzhang_over(curr_time) then
            curr_status = TABLE_STATUS_HUANSANZHANG_CARTOON
        end
    elseif curr_status == TABLE_STATUS_HUANSANZHANG_CARTOON then
        if check_huansanzhang_cardtoon_over(curr_time) then
            curr_status = TABLE_STATUS_DINGQUE
            notify_dingque_start()
        end
    elseif curr_status == TABLE_STATUS_DINGQUE then
        if check_dingque_over(curr_time) then
            start_play(curr_time)
            trigger_event('on_start_play')
            curr_status = TABLE_STATUS_PLAYING
        end
    elseif curr_status == TABLE_STATUS_PLAYING then
        if check_play_over(curr_time) then
            notify_game_over_socre_result()
            curr_status = TABLE_STATUS_GAMEOVER
        end
    elseif curr_status == TABLE_STATUS_GAMEOVER then
        curr_status = TABLE_STATUS_AUDIT_RESULT
        set_all_untrustee()
    elseif curr_status == TABLE_STATUS_AUDIT_RESULT then
        audit_game_result()
        if curr_round >= table_info.total_count then
            is_round_over = true
        end
        curr_status = TABLE_STATUS_RESTART
    elseif curr_status == TABLE_STATUS_RESTART then
        cur_instance = nil
        set_all_unready()
        trigger_event('on_game_over')
        curr_status = TABLE_STATUS_WAITTING_READY
    else
        errlog('unknown status...',curr_status)
    end

    check_close_table(curr_time)
end

local function game_update()
    curr_status = TABLE_STATUS_WAITTING_READY
    while true do
        local curr_time = util.get_now_time()
        local ok,ret = xpcall(update,debug.traceback,curr_time)
        if not ok then 
            errlog(ret)
        end
        skynet.sleep(50)
    end
end


function internal.get_player_num()
    return get_player_num()
end
---------------------------客户端请求类处理----------------------------------------
function handler.REQ_READY(uid,msg,game_session)
    --准备的时候也需要检查一下金币是否足够
    if colsing_server then
        errlog("server is closing now !!!!",curr_status)
        return 
    end

    if curr_status ~= TABLE_STATUS_WAITTING_READY then
        errlog("curr_status is not waiting ready !! ",curr_status)
        return
    end

    set_ready(uid,true)

    print("=================================88888888888888888")
    print_r(record_list)
    print_r(get_rank_list())
    print_r(get_round_serial())

    send_to_gateway(uid,game_session,'majiang.RSP_READY',{})
    
    return true
end

function handler.REQ_DISCARD(uid,msg)
    if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! REQ_DISCARD ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end
    if not cur_instance then
        errlog("cur_instance is nil")
        return 
    end

    local ok,rsp = cur_instance:do_discard(uid,msg.tile)    
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_DISCARD',{result = rsp})
        return 
    end
    trigger_event('on_play',uid)
    --出牌成功响应
    send_to_gateway(uid,table_players[uid],'majiang.RSP_DISCARD',{tile = msg.tile})
    --通知其他人
    local ntf = {uid = uid,tile = msg.tile}
    ntf.new_end_time = cur_instance:get_curr_player_endtime()
    notify_others('majiang.NTF_DISCARD',uid,ntf)

    for uid,ret in pairs(rsp.op_map) do
         if is_robot(uid) then
            print("zzzzzzzzzzzzzzzzzzzz")
            local op = { peng = ret.peng,gang = ret.gang,angang = ret.angang,hu = ret.hu }
            robot_manager[uid]['on_option'](robot_manager[uid],op)
        else
            notify_player_option(uid,ret,ntf.new_end_time)
            local timeout_times = trusteed_players[uid] or 0
            if (ret.peng or ret.gang or ret.angang or ret.hu) and 
                timeout_times >= TIMEOUT_TIMES_TO_TRUSTEE then
                if ret.hu then
                    handler.REQ_WIN(uid,{})
                else
                    handler.REQ_PASS(uid,{})
                end
            end
                
        end 
    end
    
    return true
end

function handler.REQ_PENG(uid,msg)
    if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! REQ_PENG ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end
    if not cur_instance then
        errlog("cur_instance is nil")
        return 
    end

    local ok,ret = cur_instance:do_peng(uid)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_PENG',{result = ret})
        return 
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_PENG',{})

    return true
end

function handler.REQ_GANG(uid,msg)
    if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! REQ_GANG ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end
    if not cur_instance then
        errlog("cur_instance is nil")
        return 
    end

    local ok,ret,tile,score_result,player_hu_op_map = cur_instance:do_gang(uid,msg.tile)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_GANG',{result = ret})
        return 
    end
    if not ret then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_GANG',{})
        return
    end
    if ret == xuezhan.TYPE_ANGANG or ret == xuezhan.TYPE_BUGANG then
        local ntf = {uid = uid,gang_type = ret,tile = tile,ganged_uid = uid}
        notify_all('majiang.NTF_GANG',ntf)
        notify_player_money_update(score_result)

        if next(player_hu_op_map) then
            local msg = {hu = true}
            player_end_time = cur_instance:get_curr_player_endtime()
            for uid,_ in pairs(player_hu_op_map) do
                notify_player_option(uid,msg,player_end_time)
            end
        end
    end

    send_to_gateway(uid,table_players[uid],'majiang.RSP_GANG',{})

    return true
end

function handler.REQ_WIN(uid,msg)
    if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! REQ_WIN ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end

    if not cur_instance then
        errlog("cur_instance is nil")
        return 
    end

    local ok,ret = cur_instance:do_hu(uid)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_WIN',{result = ret})
        return 
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_WIN',{})

    notify_player_win(uid,ret.hupai_result,ret.score_result)
    notify_player_money_update(ret.score_result)
    if ret.yipaoduoxiang then
       notify_all('majiang.NTF_YIPAODUOXIANG',{dianpao_uid = ret.hupai_result.fangpao})   
    end

    return true
end

function handler.REQ_PASS(uid,msg)
    if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! REQ_PASS ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end

    if not cur_instance then
        errlog("cur_instance is nil")
        return 
    end

    if uid == cur_instance:get_curr_player_uid() then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_PASS',{})
        return
    end

    local ok,ret = cur_instance:do_pass(uid)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_PASS',{result = ret})
        return 
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_PASS',{})

    return true
end

local function set_trustee(uid,setting)
    if setting then
        trusteed_players[uid] = TIMEOUT_TIMES_TO_TRUSTEE
    else
        trusteed_players[uid] = nil
    end
end

function handler.REQ_TRUSTEE(uid,msg)
    local setting = msg.trust > 0
    
    set_trustee(uid,setting)

    local state = 0
    if trusteed_players[uid] then
        state = 1
    end

    send_to_gateway(uid,table_players[uid],'majiang.RSP_TRUSTEE',{state = state})

    notify_event_status(uid)
end

function handler.REQ_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_CHAT',{result = error_code.REQ_CHAT_TOO_FAST})
        return
    end
    player_info.last_chat_time = curr_time

    local str_content
    if msg.str_content then
        str_content = skynet.call('.textfilter','lua','replace_sensitive',msg.str_content)
    end

    print("=============REQ_CHAT==========",str_content)
    send_to_gateway(uid,table_players[uid],'majiang.RSP_CHAT',{content_id = msg.content_id,str_content = str_content})

    local ntf = {
        uid = uid,
        content_id = msg.content_id,
        str_content = str_content,
    }
    notify_others('majiang.NTF_CHAT',uid,ntf)

    return true
end

function handler.REQ_VOICE_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        errlog('voice chatting too fast ...',uid)
        send_to_gateway(uid,table_players[uid],'majiang.RSP_VOICE_CHAT',{result = error_code.REQ_CHAT_TOO_FAST})
        return
    end
    player_info.last_chat_time = curr_time

    send_to_gateway(uid,table_players[uid],'majiang.RSP_VOICE_CHAT',{voice_id = msg.voice_id})
    local ntf = {uid = uid,voice_id = msg.voice_id}
    notify_others('majiang.NTF_VOICE_CHAT',uid,ntf)

    return true
end

function handler.REQ_INTERACT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        errlog('voice chatting too fast ...',uid)
        send_to_gateway(uid,table_players[uid],'majiang.RSP_INTERACT',{result = error_code.REQ_INTERACT_TOO_FAST})
        return
    end
    player_info.last_chat_time = curr_time

    local rsp = {recv_uid = msg.uid,context_id = msg.context_id}
    send_to_gateway(uid,table_players[uid],'majiang.RSP_INTERACT',rsp)

    local ntf = {send_uid = uid,recv_uid = msg.uid,context_id = msg.context_id}
    notify_others('majiang.NTF_INTERACT',uid,ntf)

    return true
end

local function leave(uid)
    assert(table_players[uid])

    if curr_round > 0 then
        --假如当前是已经开始游戏，则将状态设置为离线状态
        assert(table_players[uid] ~= OFFLINE_CLIENT_FD)
        table_players[uid] = OFFLINE_CLIENT_FD
        notify_event_status(uid)
        return 1
    else
        --游戏未开始 清除掉玩家
        for _,uid in pairs(ordered_players) do
            set_ready(uid,false)
        end

        table_players[uid] = nil
        local player_info = assert(player_info_list[uid])
        player_info_list[uid] = nil
        assert(ordered_players[player_info.position] == uid)
        ordered_players[player_info.position] = nil

        unlock_one_player(uid,this_table_gid)
        notify_player_leave(uid,0)
        return 0
    end
end

function handler.REQ_LEAVE(uid,msg,game_session)
    if table_players[uid] ~= game_session then
        send_to_gateway(uid,game_session,'majiang.RSP_LEAVE',{result = -11})
        errlog(uid,'invalid status',table_players[uid],game_session)
        return
    end

    if curr_round > 0 then
        send_to_gateway(uid,game_session,'majiang.RSP_LEAVE',{result = error_code.ALREADY_START})
        return
    end

    local ret = leave(uid)

    send_to_gateway(uid,game_session,'majiang.RSP_LEAVE',{status = ret})

    watch_session(game_session,uid,false)
    
    skynet.send('.table_mgr','lua','leave',uid)

    return true
end

--请求解散
function handler.REQ_DISMISS_TOUPIAO(uid,msg)
    if curr_round <= 0 and uid ~= creator_uid then
        errlog("you are not creator_uid, cant dissovle")
        --TODO 你不是房主，不能发起投票
        send_to_gateway(uid,table_players[uid],'majiang.RSP_DISMISS_TOUPIAO',{result = error_code.PERMISSION_DENIDE})
        return
    end
    
    if agree_dissovle_map then
        errlog(uid,"there is another dismiss toupiao...")
        --TODO 已经有一场投票了
        send_to_gateway(uid,table_players[uid],'majiang.RSP_DISMISS_TOUPIAO',{result = error_code.ARLEADY_AGREE})
        return
    end

    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end

    agree_dissovle_map = {}
    if curr_round > 0 then
        --已经开过局了，需要征求大家的同意
        for _uid in pairs(table_players) do
            agree_dissovle_map[_uid] = DISS_TOUPIAO_RESULT_INIT
        end

        assert(agree_dissovle_map[uid] == DISS_TOUPIAO_RESULT_INIT,'unexpected uid ' .. tostring(uid))
        agree_dissovle_map[uid] = DISS_TOUPIAO_RESULT_AGREE
        
        toupiao_end_time = util.get_now_time() + TOUPIAO_TIME


        local ntf = {uid = uid,end_time = toupiao_end_time}
        notify_all('majiang.NTF_TOUPIAO_PANEL',ntf)
    else
        --未开过局,房主解散,默认所有的成员都同意
        assert(uid == creator_uid)
        for _uid in pairs(table_players) do
            agree_dissovle_map[_uid] = DISS_TOUPIAO_RESULT_AGREE
        end
    end

    send_to_gateway(uid,table_players[uid],'majiang.RSP_DISMISS_TOUPIAO',{})

    return true
end

--其它人投票
function handler.REQ_TOUPIAO(uid,msg)
    if not agree_dissovle_map then
        errlog(uid,'there have not a toupiao')
        send_to_gateway(uid,table_players[uid],'majiang.RSP_TOUPIAO',{result = error_code.PERMISSION_DENIDE})
        return
    end
    
    if agree_dissovle_map[uid] ~= DISS_TOUPIAO_RESULT_INIT then
        errlog(uid,"you has agree dissovle!! on REQ_TOUPIAO")
        send_to_gateway(uid,table_players[uid],'majiang.RSP_TOUPIAO',{result = error_code.ARLEADY_AGREE})
        return
    end

    local attitude = DISS_TOUPIAO_RESULT_REFUSE
    if msg.is_agree == 1 then
        attitude = DISS_TOUPIAO_RESULT_AGREE
    end

    agree_dissovle_map[uid] = attitude

    local rsp = {result = 0,is_agree = msg.is_agree}
    send_to_gateway(uid,table_players[uid],'majiang.RSP_TOUPIAO',rsp)

    --通知其他玩家
    local ntf = {uid = uid,is_agree = msg.is_agree}
    notify_others('majiang.NTF_TOUPIAO',uid,ntf)

    return true
end

function handler.REQ_HUANSANZHANG(uid,msg)
    if curr_status ~= TABLE_STATUS_HUANSANZHANG then
        errlog("curr_status is not huansanzhang !! ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end

    local ok,ret = cur_instance:set_huansanzhang(uid,msg.tile_list)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_HUANSANZHANG',{result = ret})
        return
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_HUANSANZHANG',{})

    return true
end

function handler.REQ_DINGQUE(uid,msg)
    if curr_status ~= TABLE_STATUS_DINGQUE then
        errlog("curr_status is not dingque !! ",curr_status)
        return
    end
    if not table_players[uid] then
        errlog(uid,"you are not a player")
        return
    end

    local ok,ret = cur_instance:set_dingque(uid,msg.flower)
    if not ok then
        send_to_gateway(uid,table_players[uid],'majiang.RSP_DINGQUE',{result = ret})
        return
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_DINGQUE',{})

    return true
end

function internal.disconnect(uid,game_session)
    dbglog(uid,'disconnect...',table_players[uid],game_session)
    if table_players[uid] ~= game_session then
        errlog(uid,'invalid status',table_players[uid],game_session)
        return
    end

    local ret = leave(uid)
    dbglog(uid,'disconnect...',ret)
    return true
end

function internal.close_server()
    colsing_server = true
end

function internal.enter(uid,game_session)
    local ok,r = enter(uid,game_session)
    if not ok then
        send_to_gateway(uid,game_session,'table.RSP_ENTER',{result = r})
        return false
    end

    r.result = 0
    send_to_gateway(uid,game_session,'table.RSP_ENTER',r)
    watch_session(game_session,uid,true)

    --进房了就要去记录一下进房记录
    R().exdbsvr(1):call('.fuser_handler','add_self_ftable',
        uid,self_password,util.get_now_time())

    --TODO 先注释掉 还没有托管
    -- local update_trustee = is_trusteed(uid)
    -- set_trustee(uid,false)

    -- if update_trustee then
    --     notify_event_status(uid)
    -- end
    return true
end

function internal.touch(key)
    if recycling_table_start_time then
        recycling_table_start_time = recycling_table_start_time + 10
    end
end

function internal.start(conf)
    dbglog(tostring(conf))
    self_table_id = conf.table_id
    self_table_type = conf.table_type
    this_table_gid = conf.table_gid

    table_info = conf.payload
    self_password = table_info.password
    creator_uid = table_info.creator_uid
    ftable_expiry_time = table_info.expiry_time
    ftable_unstart_expiry_time = table_info.unstart_expiry_time
    curr_round = table_info.curr_round

    dbglog(self_password,tostring_r(table_info))

    skynet.fork(game_update)
    dbglog(string.format('table<%d>,type(%d) got start',self_table_id,self_table_type))

    if curr_round ~= 0 then
        errlog('invalid curr_round',self_password)
    end
    return true
end

function internal.exit()
    skynet.exit()
end

function internal.update_coins_on_table(uid,coins)
    return true
end

function internal.get_ftable_info()
    local table_data = {}
    local player_number = 0
    for _,data in pairs(player_info_list) do
        player_number = player_number + 1
    end
    table_data.player_number = player_number
    table_data.zimo_addition = table_info.zimo_addition
    return table_data
end

function handler.REQ_PLAYER_INFO(uid,msg)
    local player_uid = msg.uid
    local player_info = assert(player_info_list[player_uid])
    local coins = 0
    local total_count = 0
    local win_percent = 0

    local ok,base_data = R().basesvr({key=player_uid}):call('.msg_handler','get_base_data',player_uid)
    if not ok then
        errlog(uid,'failed to get_base_data info',player_uid)
    end

    if base_data then
        coins = base_data.coins
        total_count = base_data.win_times + base_data.losing_times
        if total_count ~= 0 then
            win_percent = math_floor(base_data.win_times/total_count*100)
        end    
    end

    local rsp = {
        name = player_info.name,
        icon = player_info.icon,
        sex = player_info.sex,
        coins = coins,
        total_count = total_count,
        win_percent = win_percent,
        uid = player_uid,
        player_ip = player_info.player_ip,
    }
    send_to_gateway(uid,table_players[uid],'majiang.RSP_PLAYER_INFO',rsp)

    return true
end

function handler.REQ_ROUND_INFO(uid,msg)
    local msg = {rank_list = get_rank_list(),round_list = get_round_serial()}
    send_to_gateway(uid,table_players[uid],'majiang.RSP_ROUND_INFO',msg)
    return true
end

function handler.REQ_TEST_DRAW(uid,msg)
    local ret = 0
    if cur_instance then
        ret = cur_instance:set_next_draw_tile(uid,msg.tile)
    end
    send_to_gateway(uid,table_players[uid],'majiang.RSP_TEST_DRAW',{result = ret})

    return true
end

--=================================table protocols=================
local function update_player_heartbeat(uid)
    local player_info = player_info_list[uid]
    if player_info then
        player_info.last_ping_time = util.get_now_time()
    end
end

local function get_msg_module_name(msgid)
    local m = msgdef.id_to_name[msgid]
    if not m then return end
    return m[1],m[2] --[1]->module,[2]->name
end

local function dispatch_client_message(game_session,uid,msg,size)
    local _,msgid,pbmsg,pbsize = proxypack.unpack_client_message(msg,size)
    local module,name = get_msg_module_name(msgid)

    if not module or not name then
        print('invalid msgid',msgid,module,name)
        return
    end

    local pbname = module .. '.' .. name
    local req_msg = pb.decode(pbname,pbmsg,pbsize)
    if not req_msg then
        errlog(uid,"xztable pb decode error",pbname)
        return
    end

    dbglog(string.format('[%s]>>>>>player[%s] got a request[%s] content(%s)',
        skynet.address(skynet.self()),tostring(uid),pbname,cjson.encode(req_msg)))

    local f = handler[name]
    if not f then
        errlog('unknown action',pbname)
        return
    end

    local ret = f(uid,req_msg,game_session)
    if not ret then
        errlog(string.format('failed to handle requrest(%s.%s)',module,name))
    end

    update_player_heartbeat(uid)
end

local function dispatch(_,_,game_session,uid,data)
    local msg,size = proxypack.pack_raw(data)
    local ok,errmsg = xpcall(dispatch_client_message,debug.traceback,game_session,uid,msg,size)
    skynet.trash(msg,size)  --这里需要保证内存被释放
    if not ok then 
        errlog(errmsg)
    end
end

skynet.register_protocol {
    name = "client",
    id = skynet.PTYPE_CLIENT,
    unpack = skynet.unpack,
    dispatch = dispatch
}

skynet.start(function()
    skynet.dispatch("lua",function(session,source,action,...)
        dbglog('internal request',action,...)
        local f = internal[action]
        if f then
            skynet.retpack(f(...))
        else
            handler[action](...)
        end
    end)

    sharedata.query("global_configs")
    global_configs = setmetatable({},{
        __index = function(t,k) 
            return sharedata.query("global_configs")[k]
        end
    })
end)

end