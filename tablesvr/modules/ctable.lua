local skynet = require "skynet"
local socket = require "socket"
local ddz = require "ddz"
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
local game_robot = require "game_robot"
local error_code = require "error_code"
local reason = require "reason"
local cocall = require "cocall"
local constant = require "constant"


local select_server = require("router_selector")
local global_config 

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local math_floor = math.floor
local string_format = string.format

local table_players = {}
local player_status_list = {}
local player_info_list = {}

--玩家的顺序
local ordered_players = {}
--------------------玩家进场状态---------------------
local PLAYER_STATUS_READY = 1
local PLAYER_STATUS_NOREADY = 2
local PLAYER_STATUS_PLAYING = 4

local PLAYER_STATUS_TRUSTEE = 3
--------------------抢地主方式---------------------
local SET_DIZHU_WAY_ROB = 1
local SET_DIZHU_WAY_SCORE = 2

-------------------加倍方式-------------------
local JIABEI_TYPE_GIVEUP = 0
local JIABEI_TYPE_PUTONG = 1
local JIABEI_TYPE_CHAOJI = 2
-------------------面板加倍按钮状态-------------------
local JIABEI_DISABLE = 0
local JIABEI_PUTONG = 1
local JIABEI_CHAOJI = 2
local JIABEI_PUTONG_CHAOJI = 3

-------------------管理---------------------

local curr_ddz_instance

local handler = {}
local internal = {}

local REGISTER_CLIENT_FD = 0
local ROBOT_CLIENT_FD = -1
local OFFLINE_CLIENT_FD = -2

--------------------机器人管理---------------------
local TIMEOUT_TIMES_TO_TRUSTEE = 2
local robot_manager = {}

-------------------托管管理------------------------
local trusteed_players = {}

--------------------明牌管理-----------------------
local mingpai_players = {}
local MINGPAI_STATUS_NO = 1
local MINGPAI_STATUS_YES = 2
--------------------游戏时长管理--------------------
local game_start_time = 0
local game_over_time  = 0

--------------------游戏关服管理--------------------
local colsing_server = false

--------------------结算----------------------------
local FENGDING_NOT = 0
local FENGDING_CHANGCI = 1
local FENGDING_JINBI = 2
local POCHAN_NOT = 0
local POCHAN_YES = 1

-----------------------游戏状态------------------------
local TABLE_STATUS_REGISTERED = 1 --刚刚注册
local TABLE_STATUS_WAITING_ENTER = 2
local TABLE_STATUS_WAITTING_READY = 3 --等待准备
local TABLE_STATUS_PAY_TICKET = 4
local TABLE_STATUS_CHECK_START = 5
local TABLE_STATUS_ROB_DIZHU = 6
local TABLE_STATUS_PLAYING = 7
local TABLE_STATUS_GAMEOVER = 8
local TABLE_STATUS_RESTART = 9
local TABLE_STATUS_NODIZHU = 10  --选不出地主，重新开始
local TABLE_STATUS_NODIZHU_RESTART = 11
local TABLE_STATUS_JIABEI = 12

local curr_status
local curr_enter_list = {}
local waiting_enter_timeout
local curr_paid_tickets = {}
local curr_locked_uids
local nodizhu_times = 1
local MAX_NODIZHU_TIMES = 3
local start_waiting_for_ready_time
-----------------------游戏状态------------------------
return function(params)
local ddz = params.ddz
local trustee_AI = params.trustee_AI
local robot_AI = params.robot_AI
local keep_table = params.keep_table


local tablesvr_id = tonumber(skynet.getenv "server_id")
local self_table_type,self_table_id

local this_table_gid

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
    notify_others('ddz.NTF_EVENT',nil,msg)
end

local function notify_score_and_rate_detail()
    assert(curr_ddz_instance)
    for uid, fd in pairs(table_players) do
        local score_rate_detail = curr_ddz_instance:get_score_rate_detail(uid)

        local msg = {
            score_rate_detail = score_rate_detail,
        }
        send_to_gateway(uid,fd,'ddz.NTF_SCORE_AND_RATE_DETAIL',msg)
    end
end

local function notify_player_enter(uid)
    local player_info = assert(player_info_list[uid])
    local cards_count = 0

    if curr_ddz_instance then
        local cards_id = curr_ddz_instance:get_player_card_ids(uid)
        if cards_id then
            cards_count = #cards_id
        end
    end

    local player = {
        uid = uid,
        name = player_info.name,
        cards_count = cards_count,
        position = player_info.position,
        coins = player_info.coins
    }

    notify_others('ddz.NTF_PLAYER_ENTER',uid,{player = player})
end


local function notify_money_changed(uid,chged)
    local ntf = {}
    local flags = 0

    if chged.coins then
        ntf.coins = chged.coins
        flags = flags | (1 << 0)
    end

    if chged.gems then
        ntf.gems = chged.gems
        flags = flags | (1 << 1)
    end

    if chged.roomcards then
        ntf.roomcards = chged.roomcards
        flags = flags | (1 << 2)
    end

    ntf.flags = flags
    local fd = assert(table_players[uid])
    send_to_gateway(uid,fd,'hall.NTF_USER_MONEY',ntf)
    return true
end

local function add_task_process(uid,task_type)
    R().hallsvr{key=uid}:send('.msg_handler','toagent',uid,
				'add_task_process',task_type)
end

local function send_table_base_score_and_rate(uid)
    if not curr_ddz_instance then
        return
    end
    
    local base_score,rate = curr_ddz_instance:get_base_score_and_rate()
    local rsp = {
        base_score = base_score,
        rate = rate,
    }
    
    if uid then
        local fd = assert(table_players[uid])
        if fd > 0 then
            --send_to_gateway(uid,fd,'table.NTF_SCORE_AND_RATE',rsp)
        end
        return
    end

    for uid,fd in pairs(table_players) do
        if fd > 0 then
           --send_to_gateway(uid,fd,'table.NTF_SCORE_AND_RATE',rsp)
        end
    end
end

local function set_table_base_rate(ddz_instance)
    assert(ddz_instance)
    local roomdata = global_configs.roomdata
    assert(roomdata[self_table_type])
    ddz_instance:set_rate(tonumber(roomdata[self_table_type].rate))
end

local function set_table_base_score(ddz_instance)
    assert(ddz_instance)
    local roomdata = global_configs.roomdata
    assert(roomdata[self_table_type])
    ddz_instance:set_base_score(tonumber(roomdata[self_table_type].score))
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

local function is_robot(uid)
    return table_players[uid] == ROBOT_CLIENT_FD
end

local function get_response_list(ddz_instance)
    local curr_card_suit_type,curr_card_suit,key = ddz_instance:get_last_card_suit() 
    --notify
    local players_card_id_list = {}
    local players_info_list = {}
    local common = {
        dizhu_uid = ddz_instance:get_dizhu_uid(),
        dizhu_card_id_list = ddz_instance:get_dizhu_card_ids(),
        next_player_uid = ddz_instance:get_next_player_uid(),
        must_play = 0,
        end_time = ddz_instance:get_play_end_time(),
        curr_card_suit_type = curr_card_suit_type,
        curr_card_suit = curr_card_suit,
        curr_card_suit_key = key,
    }

    if ddz_instance:is_must_play(ddz_instance:get_next_player_uid()) then
        common.must_play = 1
    end

    local copy = function(common)
        local o = {}
        for k,v in pairs(common) do
            o[k] = v
        end
        return o
    end

    for uid,_ in pairs(table_players) do
        players_card_id_list[uid] = assert(ddz_instance:get_player_card_ids(uid))
    end

    for _,uid in ipairs(ordered_players) do
        local r = {}
        local cards_ids = players_card_id_list[uid]
        local player_info = assert(player_info_list[uid])
        local r = {
            uid = uid,
            name = player_info.name,
            cards_count = #cards_ids,
            position = player_info.position,
            state = get_player_state(uid),
            coins = player_info.coins,
            icon = player_info.icon,
            sex = player_info.sex,
        }

        if player_info.mingpai_status == MINGPAI_STATUS_YES then
            r.cards_count = -1
            r.card_id_list = assert(players_card_id_list[uid])
        end
    

        table_insert(players_info_list,r)
    end

    local rsp_list = {}
    print_r(players_info_list)
    for position,uid in ipairs(ordered_players) do
        local rsp = copy(common)
        local tmp_list = {}
        for _,v in ipairs(players_info_list) do
            table_insert(tmp_list,copy(v))
        end
        
        local self_info = assert(tmp_list[position])
        assert(self_info.uid == uid)
        self_info.card_id_list = assert(players_card_id_list[uid])
        self_info.cards_count = -1

        rsp.players_info_list = tmp_list
        rsp_list[uid] = rsp
    end 

    return rsp_list
end

local function get_card_note_info(uid,ddz_instance)
    local other_player_cards = ddz_instance:get_other_player_cards(uid)
    local other_player_record = {}

    local records = ddz_instance:get_player_record()
    for _uid,player_record in pairs(records) do
        if uid ~= _uid then
            local record = { uid = _uid,player_records = {} }
            for _,card_record in pairs(player_record) do
                table_insert(record.player_records,{card_list = card_record})
            end

            table_insert(other_player_record,record)
        end
    end

    return {other_player_cards = other_player_cards,other_player_record = other_player_record}
end

---------------------------------------------------------------------------
local function lock_one_player(uid,table_gid)
    local ok,succ = R().exdbsvr(1):call('.tlock_mgr','set_on_table',uid,table_gid)
    if not ok then
        errlog(uid,'failed to set_on_table')
        return
    end

    if not succ then
        return -10
    end

    return 0
end

local function get_all_human_uids()
    local uids = {}
    for uid,fd in pairs(table_players) do
        if not is_robot(uid) then
            table_insert(uids,uid)
        end
    end
    return uids
end

local function _lock_all_players(locked_uids,uids)
    local tasks = {}
    for _,uid in pairs(uids) do
        table_insert(tasks,{ f = lock_one_player,id = uid,params = {uid,this_table_gid}})
        locked_uids[uid] = false
    end

    local ok,results = cocall(5,table_unpack(tasks))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
        return
    end

    local succ = true
    for uid,r in pairs(results) do
        if r == 0 then
            locked_uids[uid] = true
        else
            succ = false
            errlog(uid,'failed to set on table ...',this_table_gid)
        end
    end

    if not succ then
        for uid,r in pairs(results) do
            --有人未成功，则释放已经成功的人,以免坑了其它玩家
            --有可能玩家在设置成功后，返回到该节点的时候超时了，因而该玩家也需要解开锁
            --反正如果解锁的时候，玩家不是当前的table_gid也是无法被解开的
            R().exdbsvr(1):send('.tlock_mgr','unset_on_table',uid,this_table_gid)
        end
    end

    return succ
end

local function lock_all_players()
    if curr_locked_uids then
        return true
    end
    curr_locked_uids = {}
    local uids = get_all_human_uids()
    return _lock_all_players(curr_locked_uids,uids) 
end

local function lock_all_players_on_register(uids)
    assert(not curr_locked_uids)
    curr_locked_uids = {}
    return _lock_all_players(curr_locked_uids,uids) 
end

local function unlock_all_players()
    local uids = get_all_human_uids()
    for _,uid in pairs(uids) do
        --这里不用call的原因是，即使解锁失败了也没有办法，所以暂时就只send
        R().exdbsvr(1):send('.tlock_mgr','unset_on_table',uid,this_table_gid)
    end
    curr_locked_uids = nil
end

local function are_all_players_locked()
    assert(curr_locked_uids)
    for _,r in pairs(curr_locked_uids) do
        if not r then
            return false
        end
    end

    return true
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

local function get_response_dizhu_history()
    local history_list = curr_ddz_instance:get_rob_dizhu_history_list()
    --参与次数:0是不叫，1是叫，2是抢,3是不抢
    local tmp_map = {}
    local is_call = true
    for _,r in ipairs(history_list) do
        local uid = r.uid
        if r.is_rob then
            if is_call then
                tmp_map[uid] = 1
            else
                tmp_map[uid] = 2
            end
            is_call = false
        else
            if is_call then
                --放弃，正在叫地主，这是不叫
                tmp_map[uid] = 0
            else
                --放弃，不在叫地主，这是不抢
                tmp_map[uid] = 3
            end
        end
    end

    local set_dizhu_history_list = {}
    for uid,status in pairs(tmp_map) do
        table_insert(set_dizhu_history_list,{
            uid = uid,
            status = status,
        })
    end

    return set_dizhu_history_list
end

local function enter(uid,client_fd)
    print('now enter ========================',uid,client_fd)
    if not table_players[uid] then
        errlog(uid,'that player have not been registed yet')
        return false
    end
    local roomdata = assert(global_configs.roomdata)
    table_players[uid] = client_fd
    notify_player_enter(uid)

    local enter_info = {}
    enter_info.has_card_note = player_info_list[uid].has_card_note
    if not curr_ddz_instance then
        local players_info_list = {}
        for _uid,player_info in pairs(player_info_list) do
                table_insert(players_info_list,{
                    uid = _uid,
                    name = player_info.name,
                    position = player_info.position,
                    coins = player_info.coins,
                    icon = player_info.icon,
                    sex = player_info.sex,
                    state = get_player_state(_uid)
                })
        end 

        enter_info.waiting_table_status = {
            players_info_list = players_info_list,
        }
        enter_info.game_status = 0
    else
        local last_round_records = curr_ddz_instance:get_last_round_records()
        local rsp_list = get_response_list(curr_ddz_instance)
        enter_info.game_status = 1        
        enter_info.table_status = assert(rsp_list[uid])
        enter_info.last_card_records = last_round_records

        local setting_uid,cur_count,setting_end_time,set_dizhu_way = curr_ddz_instance:get_setting_info()
        local set_status = {
            uid = setting_uid,
            cur_count = cur_count,
            end_time = setting_end_time,
            set_dizhu_way = set_dizhu_way,
            rob_count = curr_ddz_instance:get_rob_count(),
        }

        enter_info.set_dizhu_status = set_status

        if curr_status == TABLE_STATUS_ROB_DIZHU then
            enter_info.set_dizhu_history_list = get_response_dizhu_history()
        end
        enter_info.score_rate_detail = curr_ddz_instance:get_score_rate_detail(uid)
    end

    return true,{table_type = self_table_type, game_type = 1, ddz_enter_info = enter_info}
end

local function finish_game()
    local ok,result = curr_ddz_instance:get_game_result()
    if not ok then
        return
    end

    trigger_event('on_game_over')

    return result
end

local function mingpai(uid,rate)
    --mingpai_players[uid] = true
    local record_list = curr_ddz_instance:get_card_record_list()
    if record_list and #record_list > 0 then
        return false
    end

    curr_ddz_instance:set_mingpai(uid,rate)
    
    --通知其他玩家
    local ntf = {
        uid = uid,
        card_id_list = assert(curr_ddz_instance:get_player_card_ids(uid))
    }
    notify_all('ddz.NTF_MINGPAI',ntf)
    notify_score_and_rate_detail()
    return true
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

local function set_all_unmingpai()
    for uid,player_info in pairs(player_info_list) do
        player_info.mingpai_status = MINGPAI_STATUS_NO
    end    
end

local function check_play_update_task(uid,card_suit_type)
    if card_suit_type == ddz.CARD_SUIT_TYPE_FEIJI or 
        card_suit_type == ddz.CARD_SUIT_TYPE_FEIJIDAICIBANG then
        add_task_process(uid,constant.TASK_PLAY_FEIJI)
    elseif card_suit_type == ddz.CARD_SUIT_TYPE_WANGZHA then
        notify_score_and_rate_detail()
        add_task_process(uid,constant.TASK_PLAY_WANGZHA)
    elseif card_suit_type == ddz.CARD_SUIT_TYPE_ZHADAN or
        card_suit_type == ddz.CARD_SUIT_TYPE_RUANZHA then
        print('fff',constant.TASK_PLAY_ZHADAN)
        notify_score_and_rate_detail()
        add_task_process(uid,constant.TASK_PLAY_ZHADAN)       
    end    
end

local function play(uid,card_suit,card_suit_type,key)
    if not curr_ddz_instance then
        return false,{result = -1}
    end

    --考虑到不出牌的情况
    if #card_suit == 0 then
        local ok,ret = curr_ddz_instance:donot_play(uid)
        if not ok then
            skynet.error('failed to donot_play',uid)  
            return false,{result = ret}
        end

        local next_player_uid = curr_ddz_instance:get_next_player_uid()
        local must_play = 0
        if curr_ddz_instance:is_must_play(next_player_uid) then
            must_play = 1
        end

        trigger_event('on_play',uid,card_suit)
        
        return true,{
            result = 0,
            next_player_uid = next_player_uid,
            must_play = must_play,
            end_time = curr_ddz_instance:get_play_end_time(),
        }
    end
    local ok,payload = curr_ddz_instance:play(uid,card_suit,card_suit_type,key)
    if not ok then
        return false,{result = payload}
    end

    local next_player_uid = curr_ddz_instance:get_next_player_uid()
    local must_play = 0
    if curr_ddz_instance:is_must_play() then
         must_play = 1
    end

    local card_suit_type = payload.card_suit_type
    check_play_update_task(uid,card_suit_type)
    
    trigger_event('on_play',uid,payload.card_suit)

    return true,{
        result = 0,
        card_suit_type = payload.card_suit_type,
        card_suit = payload.card_suit,
        next_player_uid = next_player_uid,
        must_play = must_play,
        end_time = curr_ddz_instance:get_play_end_time(),
        card_suit_key = payload.card_suit_key,
        original_card_suit = payload.original_card_suit,
    }
end

local function rob_dizhu(uid,score,is_rob)
    if not curr_ddz_instance then
        return false,-1000
    end

    if not curr_ddz_instance:is_rob_dizhu() then
        errlog('is not a robbing time')
        return false,-2000
    end

    if curr_ddz_instance:get_setting_uid() ~= uid then
        return false,-3000
    end

    print(uid,"score",score,"is_rob",is_rob)
    local forced = nodizhu_times >= MAX_NODIZHU_TIMES
    curr_ddz_instance:rob_dizhu(uid,score,is_rob,forced)

    trigger_event('on_rob_dizhu',uid,score,is_rob)
    --response 
    local setting_uid,cur_count,setting_end_time,set_dizhu_way = curr_ddz_instance:get_setting_info()
    local set_status = {
        uid = setting_uid,
        cur_count = cur_count,
        end_time = setting_end_time,
        set_dizhu_way = set_dizhu_way,
        rob_count = curr_ddz_instance:get_rob_count(),
    }

    local rsp_is_rob = 0
    if is_rob then
        rsp_is_rob = 1
    end
    local msg = {
        pre_uid = uid,
        score = score,
        is_rob = rsp_is_rob,
        set_dizhu_status = set_status,
    }
    
    notify_others('ddz.NTF_ROBDIZHU',uid,msg)

    local rsp = {result = 0,score = score,is_rob = rsp_is_rob,set_dizhu_status = set_status}
    send_to_gateway(uid,table_players[uid],'ddz.RSP_ROBDIZHU',rsp)

    return true
end

local function set_ready(uid)
    assert(player_status_list[uid])
    player_status_list[uid] = PLAYER_STATUS_READY

    notify_event_status(uid)
    return true
end


------------------------------------托管相关---------------------------------
--托管出牌
local function trustee_play()
    local uid = curr_ddz_instance:get_next_player_uid()
    local play_params = trustee_AI.trustee_play(uid,curr_ddz_instance)
	dbglog('player---------------------',uid,
        string.format('[%s]',tostring_r(play_params)))
    local ok,rsp = play(uid,table_unpack(play_params))
    print_r(rsp)

    local fd = table_players[uid]
    send_to_gateway(uid,fd,'ddz.RSP_PLAY',rsp)
    assert(ok)
    local msg = {
        player_uid = uid,
        card_suit_type = rsp.card_suit_type,
        card_suit = rsp.card_suit,
        next_player_uid = rsp.next_player_uid,
        must_play = rsp.must_play,
        end_time = rsp.end_time,
        card_suit_key = rsp.card_suit_key,
        original_card_suit = rsp.original_card_suit,
    }
    notify_all('ddz.NTF_PLAY',msg)
end

local function check_trusteed_player(curr_time)
    local uid = curr_ddz_instance:get_next_player_uid()
    local timeout_times = trusteed_players[uid] or 0

    if timeout_times >= TIMEOUT_TIMES_TO_TRUSTEE then
        trustee_play()
        return
    elseif curr_time >= curr_ddz_instance:get_play_end_time() then
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
------------------------------------------------------------------------------
local function check_all_enter(curr_time)
    if curr_time >= waiting_enter_timeout then
        return true
    end

    for uid,fd in pairs(table_players) do
        if fd == REGISTER_CLIENT_FD then
            return false
        end
    end

    return true
end

local function can_ready_for_robot(uid)
    local player_info = assert(player_info_list[uid])
    local roomdata = assert(global_configs.roomdata)
    local cost = assert(roomdata[self_table_type].cost)

    return player_info.coins >= cost
end

local function can_ready(uid)
    if curr_status ~= TABLE_STATUS_WAITTING_READY then
        errlog("curr_status is not waiting ready !! ",curr_status)
        return
    end

    if is_robot(uid) then
        return can_ready_for_robot(uid)
    end
    --查检下金币是否可以准备
    local roomdata = assert(global_configs.roomdata)
    local cost = assert(roomdata[self_table_type].cost)

    local ok,able = R().basesvr({key=uid}):call('.msg_handler',
        'can_reduce_coins',uid,cost)
    if not ok then
        errlog(uid,'failed to pay ticket',cost)
        return
    end

    if not able then
        dbglog(uid,'you dont have enough money for ticket')
        return false
    end

    return true
end

local function are_all_players_ready()
    if #ordered_players < ddz.MAX_PLAYER_NUM then
        return false
    end

    for _,status in pairs(player_status_list) do
        if status ~= PLAYER_STATUS_READY then
            return false
        end
    end

    return true
end

local function pay_one_ticket(uid,coins)
    local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler',
        'pay_one_ticket',uid,coins,reason.COST_ON_PAY_TICKET)
    if not ok then
        errlog(uid,'failed to pay ticket',coins,succ)
        return
    end
    if not succ then
        errlog(uid,'failed to pay ticket',coins)
        return
    end

    return {
        curr_coins = ret.curr,
        has_card_note = ret.has_card_note
    } 
end

local function pay_all_tickets()
    curr_paid_tickets = {}
    local roomdata = assert(global_configs.roomdata)
    local cost = assert(roomdata[self_table_type].cost)

    local payers = {}
    for uid,fd in pairs(table_players) do
        if fd ~= ROBOT_CLIENT_FD then
            curr_paid_tickets[uid] = false
            table_insert(payers,{ f = pay_one_ticket,id = uid,params = {uid,cost} })  
        end
    end
    
    local ok,results = cocall(5,table_unpack(payers))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
    end

    --检查下是否每个人都扣款成功
    for uid,r in pairs(results) do
        if r and r.curr_coins then
            curr_paid_tickets[uid] = true
            notify_money_changed(uid,{coins = r.curr_coins})
            notify_others('ddz.NTF_MONEY_CHANGE',nil,{uid = uid,coins = r.curr_coins})
            local player_info = assert(player_info_list[uid])
            player_info.coins = r.curr_coins
            player_info.has_card_note = r.has_card_note
        else
            errlog(uid,'failed to pay ticket',coins,cost,r)
        end
    end
end

local function are_all_tickets_paid()
    if not curr_paid_tickets then
        errlog('failed to check curr_paid_tickets is nil')
        return false
    end
    for _,paid in pairs(curr_paid_tickets) do
        if not paid then
            return false
        end
    end

    return true
end


local function can_start()
    if curr_ddz_instance then
        return false,-1
    end

    if #ordered_players < ddz.MAX_PLAYER_NUM then
        return false,-2
    end

    for _,status in pairs(player_status_list) do
        if status ~= PLAYER_STATUS_READY then
            return false,-3
        end
    end

    local ddz_instance = ddz:new()
    ddz_instance:init()

    for _,uid in ipairs(ordered_players) do
        ddz_instance:enter(uid)
    end

    local ok = ddz_instance:check_and_start()
    if not ok then
        return false,-3
    end

    ddz_instance:shuffle()
    ddz_instance:deal()
    
    ddz_instance:setingdizhu_status(ddz.SET_DIZHU_WAY_ROB)

    set_table_base_score(ddz_instance)
    
    set_table_base_rate(ddz_instance)

    for _uid,status in pairs(player_status_list) do
        player_status_list[_uid] = PLAYER_STATUS_PLAYING
    end

    return ddz_instance
end

local function notify_start(curr_ddz_instance)
    local rsp_list = get_response_list(curr_ddz_instance)
    print('now notify game is started....')
    local setting_uid,cur_count,setting_end_time,set_dizhu_way = curr_ddz_instance:get_setting_info()
    local set_status = {
        uid = setting_uid,
        cur_count = cur_count,
        end_time = setting_end_time,
        set_dizhu_way = set_dizhu_way,
        rob_count = curr_ddz_instance:get_rob_count(),
    }
    
    for uid,fd in pairs(table_players) do
        local detail = curr_ddz_instance:get_score_rate_detail(uid)
        local  msg = {
            table_status = rsp_list[uid],
            set_dizhu_status = set_status,
            score_rate_detail = detail,
            has_card_note = player_info_list[uid].has_card_note
        }
        send_to_gateway(uid,fd,'ddz.NTF_START',msg)
    end 

    --TODO 此处应该封装到ntf_start和rsp_enter里面去
   -- send_table_base_score_and_rate()
end

local function check_start(curr_time)
    local ddz_instance,msg = can_start()
    if not ddz_instance then
        dbglog('failed to can_start()',msg)
        return
    end

    print('now start the game...')
    curr_ddz_instance = ddz_instance
    for uid,player_info in pairs(player_info_list) do
        if player_info.mingpai_status == MINGPAI_STATUS_YES then
            mingpai(uid,5)
        end    
    end
    return true
end

local function check_rob_dizhu(curr_time)
    local is_over,dizhu_uid = curr_ddz_instance:get_rob_dizhu_result()
    if is_over then
        return true,dizhu_uid
    end

    local uid,_,end_time = curr_ddz_instance:get_setting_info()
    if curr_time >= end_time then
        --现在还没人抢，就系统代劳不抢了
        rob_dizhu(uid,0,false)
    end

    return false
end

local function get_jiabeicard(uid)
    local ok,base_data = R().basesvr({key=uid}):call('.msg_handler',
        'get_base_data',uid,coins,reason.COST_ON_PAY_TICKET)
    if not ok then
        errlog(uid,'failed to pay ticket',coins,succ)
        return
    end
    
    return {
        jiabei_cards = base_data.jiabei_cards
    }
end

local function notify_rob_dizhu_over()
    local rsp = curr_ddz_instance:get_notify_dizhu_msg()
    notify_all('ddz.NTF_SETDIZHU',rsp)

    local jiabei_end_time = curr_ddz_instance:get_jiabei_end_time()
    
    --查询玩家加倍卡
    local players = {}
    for uid,fd in pairs(table_players) do
        if fd ~= ROBOT_CLIENT_FD then
            table_insert(players,{ f = get_jiabeicard,id = uid,params = {uid} })  
        end
    end
    
    local ok,results = cocall(5,table_unpack(players))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
        notify_all('ddz.NTF_JIABEI_PANEL',{end_time = jiabei_end_time})
        return
    end

    --下发否每个人加倍状态
    for uid,r in pairs(results) do
        if r and r.jiabei_cards then
            local jiabei_cards = r.jiabei_cards
            local jiabei_type = JIABEI_DISABLE
            if player_info_list[uid].coins > 8000 then
                jiabei_type = JIABEI_PUTONG
            end
            if jiabei_cards > 1 then
                jiabei_type = JIABEI_CHAOJI
            end
            if player_info_list[uid].coins > 8000 and jiabei_cards > 1 then
                jiabei_type = JIABEI_PUTONG_CHAOJI
            end

            ntf = {
                jiabei_type = jiabei_type,
                end_time = jiabei_end_time
            }

            local fd = assert(table_players[uid])
            send_to_gateway(uid,fd,'ddz.NTF_JIABEI_PANEL',ntf)
        else
            ntf = {
                jiabei_type = JIABEI_DISABLE,
                end_time = jiabei_end_time
            }

            local fd = assert(table_players[uid])
            send_to_gateway(uid,fd,'ddz.NTF_JIABEI_PANEL',ntf)
        end
    end

end

local function jiabei(uid,type)
    local player_info = assert(player_info_list[uid])
    if type == JIABEI_TYPE_PUTONG then
        if player_info.coins < 8000 then
            send_to_gateway(uid,table_players[uid],'ddz.RSP_JIABEI',{result = error_code.GOLD_IS_NOT_ENOUGH})
            return
        end
    elseif type == JIABEI_TYPE_CHAOJI then
        --TODO 消耗道具
        local ok,ret = R().basesvr({key=uid}):call('.msg_handler','reduce_jiabeicards',
            uid,1,reason.CHAOJI_JIABEI)
        if not ok then
            send_to_gateway(uid,table_players[uid],'ddz.RSP_JIABEI',{result = error_code.JIABEI_CRAD_IS_LESS})
            return
        end
    end
    
    curr_ddz_instance:jiabei(uid,type)
    notify_all('ddz.NTF_JIABEI',{uid = uid,type = type})
    if type == JIABEI_TYPE_PUTONG or type == JIABEI_TYPE_CHAOJI then
        notify_score_and_rate_detail()
    end
end

local function check_jiabei_over(curr_time)
    if curr_ddz_instance:check_all_player_jiabei() then
        return true
    end

    local jiabei_player_list = curr_ddz_instance:get_jiabei_player_list()
    local jiabei_end_time = curr_ddz_instance:get_jiabei_end_time()
    if curr_time > jiabei_end_time then
        for _,uid in pairs(ordered_players) do
            if not jiabei_player_list[uid] then
                jiabei(uid,JIABEI_TYPE_GIVEUP)
            end
        end
        return true
    end
    return false    
end

local function notify_dizhu_play()
    local dizhu_uid = curr_ddz_instance:get_dizhu_uid()
    local msg = {
        next_player_uid = dizhu_uid,
        must_play = 1,
        end_time = curr_ddz_instance:get_play_end_time(),
    }
    notify_others('ddz.NTF_PLAY',nil,msg)
end

local function check_play(curr_time)
    if curr_ddz_instance:is_game_over() then
        return true
    end

    check_trusteed_player(curr_time)

    return false
end

local function pay_lost_coins(uid,coins)
    local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler',
        'pay_lost_coins',uid,coins,reason.LOST_COINS,true)
    if not ok then
        errlog(uid,'failed to pay_lost_coins',coins)
        return
    end
    if not succ then
        errlog(uid,'failed to pay_lost_coins',coins)
        return
    end

    return {
        curr_coins = ret.curr,
        lost_coins = ret.chged,
        compensation = ret.compensation
    }
end

local function give_won_coins(uid,coins)
    local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler',
        'give_won_coins',uid,coins,reason.WIN_COINS)
    if not ok then
        errlog(uid,'failed to give_won_coins',coins,succ)
        return
    end
    if not succ then
        errlog(uid,'failed to give_won_coins',coins)
        return
    end

    return {curr_coins = ret.curr,won_coins = ret.chged}
end

local function pay_robots_coins(uid,coins)
    local player_info = assert(player_info_list[uid],'no such player info ' .. tostring(uid))
    if player_info.coins < coins then
        coins = player_info.coins
        player_info.coins = 0
    else
        player_info.coins = player_info.coins - coins
    end

    return {curr_coins = curr_coins,lost_coins = coins}
end

local function give_robots_coins(uid,coins)
    local player_info = assert(player_info_list[uid],'no such player info ' .. uid)
    player_info.coins = player_info.coins + coins
    return {curr_coins = player_info.coins,won_coins = coins}
end

local function call_take_compensation(uid)
    local ok,given,ret = R().basesvr({key=uid}):call('.msg_handler','take_compensation',uid)
    if not ok then
        errlog(uid,'failed to call_take_compensation')
        return
    end

    if not given then
        return {c = 0}
    end

    return {
        c = ret.compensation_coins,
        times = ret.compensation_times,
        curr_coins = ret.curr_coins
    }
end

local function take_compensation(compensation_list)
    if #compensation_list < 1 then
        return
    end
    
    local tasks = {}
    for _,uid in pairs(compensation_list) do
        table_insert(tasks,{ f = call_take_compensation,id = uid,params = {uid} })
    end
    
    local ok,results = cocall(5,table_unpack(tasks))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
        return
    end

    for uid,r in pairs(results) do
        if r then
            local rsp = {
                compensation_times = r.times,
                compensation_coins = r.c,
            }
            player_info_list[uid].coins = r.curr_coins
            send_to_gateway(uid,table_players[uid],'hall.NTF_COMPENSATION',rsp)
        else
            errlog(uid,'failed to check compensation...')
        end
    end
end

local function get_result_info(game_result)
    local result_info = {}
    for _,o in pairs(game_result.winners) do
        local uid = o.uid
        result_info[uid] = o
    end
    for _,o in pairs(game_result.losers) do
        local uid = o.uid
        result_info[uid] = o
    end
    return result_info
end

local function check_chun_tian()
    local chuntian_type,uid = curr_ddz_instance:get_chun_tian_type()
    if chuntian_type > 0 then
        notify_score_and_rate_detail()
    end
    return chuntian_type,uid
end

local function check_task_update(result)
    local dizhu_uid = curr_ddz_instance:get_dizhu_uid()
    for k,v in pairs(result.winners) do
        if not is_robot(v.uid) then
            if dizhu_uid ~= v.uid then
                add_task_process(v.uid,constant.TASK_FAMER_WIN)
            else
                add_task_process(v.uid,constant.TASK_DIZHU_WIN)    
            end

            if table_def.laizi_table_type_map[self_table_type] then
                add_task_process(v.uid,constant.TASK_FINISH_LAIZI)
            elseif table_def.table_type_map[self_table_type] then
                add_task_process(v.uid,constant.TASK_FINISH_STRATEGY)
            end
        end    
    end

    for k,v in pairs(result.losers) do
        if not is_robot(v.uid) then
            if table_def.laizi_table_type_map[self_table_type] then
                add_task_process(v.uid,constant.TASK_FINISH_LAIZI)
            elseif table_def.table_type_map[self_table_type] then
                add_task_process(v.uid,constant.TASK_FINISH_STRATEGY)
            end
        end
    end
end

local function audit_game_result(game_result)
    --结算
    print_r(game_result)
    local result_info = get_result_info(game_result)
    print_r("result_info",result_info)
    local roomdata = global_configs.roomdata
    local limit = roomdata[self_table_type].limit
    local robot_losers_result = {}
    local payers = {}
    local winner_coins = 0
    local real_winner_coins = 0
    local total_score = 0
    local is_beyond = false
    local winners = game_result.winners
    local losers = game_result.losers
    for _,o in pairs(winners) do
        local uid = o.uid
        local score = o.add_score
        assert(score >= 0)
        total_score = total_score + score
    end
    assert(total_score > 0,"game_result is error")
    --是否超过限制
    if total_score > limit then
        is_beyond = true
    end

    --玩家最多能赢多少钱
    assert(winners[1],"there is no winner")
    assert(losers[1],"there is no loser")
    local winner = winners[1]
    local winner_uid = winners[1].uid
    local winner_coins = winners[1].add_score
    if is_beyond then
        winner_coins = math_floor(winners[1].add_score / total_score * limit)
    end
    if winner_coins > player_info_list[winner_uid].coins then
        winner_coins = player_info_list[winner_uid].coins
    end
    if winners[2] then
        local uid = winners[2].uid
        local coins2 = winners[2].add_score
        if is_beyond then
            coins2 = limit - math_floor(winners[1].add_score / total_score * limit)
        end
        if coins2 > player_info_list[uid].coins then
            coins2 = player_info_list[uid].coins
        end
        winner_coins = winner_coins + coins2
    end

    --根据winner_coins去算出输的玩家要扣多少钱
    local loser_uid = losers[1].uid
    local lost_score = -losers[1].add_score
    assert(lost_score >= 0)
    local lost_coins = math_floor(lost_score/total_score * winner_coins)

    if is_robot(loser_uid) then
        robot_losers_result[loser_uid] = pay_robots_coins(loser_uid,lost_coins)
    else
        table_insert(payers,{ f = pay_lost_coins,id = loser_uid,params = {loser_uid,lost_coins} })
    end
    if losers[2] then
        local uid = losers[2].uid
        local lost_score = -losers[2].add_score
        local lost_coins = winner_coins - math_floor(-losers[1].add_score/total_score * winner_coins)
        if is_robot(uid) then
            robot_losers_result[uid] = pay_robots_coins(uid,lost_coins)
        else
            table_insert(payers,{ f = pay_lost_coins,id = uid,params = {uid,lost_coins} })
        end
    end

    --扣钱    
    local ok,results = cocall(5,table_unpack(payers))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
        return
    end

    dbglog('------------results of losers cocall',tostring_r(results))

    local rsp_winner = {}
    local rsp_loser = {}
    local robot_winners_result = {}
    local curr_result = {}
    local compensation_list = {}  --需要补偿的玩家
    --赢家实际上赢多少钱
    for uid,ret in pairs(results) do
        if not ret then
            errlog(uid,'failed to cocall...',tostring_r(results))
            return
        end

        real_winner_coins = real_winner_coins + ret.lost_coins

        local player_info = assert(player_info_list[uid])
        player_info.coins = ret.curr_coins
        curr_result[uid] = -ret.lost_coins
        print("loser lose coins:",uid,ret.lost_coins)
        local pochan = POCHAN_NOT
        if player_info.coins == 0 then
            pochan = POCHAN_YES
        end
        table_insert(rsp_loser,{uid = uid,add_score = -ret.lost_coins,base_score=result_info[uid].base_score,
        rate = result_info[uid].rate,pochan = pochan})
        if ret.compensation then
            table_insert(compensation_list,uid)
        end
    end

    for uid,ret in pairs(robot_losers_result) do
        real_winner_coins = real_winner_coins + ret.lost_coins
        curr_result[uid] = -ret.lost_coins
        print("loser lose coins:",uid,ret.lost_coins)
        table_insert(rsp_loser,{uid = uid,add_score = -ret.lost_coins,base_score=result_info[uid].base_score,
        rate = result_info[uid].rate,pochan = false})
    end

    local winners = game_result.winners

    local givers = {}
    local win_coins1 = math_floor(real_winner_coins * winners[1].add_score / total_score)
    if win_coins1 > player_info_list[winner_uid].coins then
        win_coins1 = player_info_list[winner_uid].coins
    end
    if not winners[2] then
        if is_robot(winner_uid) then
            robot_winners_result[winner_uid] = give_robots_coins(winner_uid,win_coins1)
        else 
            table_insert(givers,{ f = give_won_coins,id = winner_uid,params = {winner_uid,win_coins1} })  
        end
    elseif winners[2] then
        local uid = winners[2].uid
        local win_coins2 = real_winner_coins - win_coins1
        if win_coins2 > player_info_list[uid].coins then
            win_coins2 = player_info_list[uid].coins
        end
        if win_coins1 + win_coins2 ~= real_winner_coins then
            win_coins1 = real_winner_coins - win_coins2
        end

        if is_robot(winner_uid) then
            robot_winners_result[winner_uid] = give_robots_coins(winner_uid,win_coins1)
        else 
            table_insert(givers,{ f = give_won_coins,id = winner_uid,params = {winner_uid,win_coins1} })  
        end

        if is_robot(uid) then 
            robot_winners_result[uid] = give_robots_coins(uid,win_coins2)
        else
            table_insert(givers,{ f = give_won_coins,id = uid,params = {uid,win_coins2} })  
        end
    end

 
    local ok,results = cocall(3,table_unpack(givers))
    if not ok then
        errlog('failed to cocall',tostring_r(results))
    end

    dbglog('------------results of winners cocall',tostring_r(results))

    local make_rsp_winner = function(uid,ret)
        local player_info = assert(player_info_list[uid])
        local fengding = FENGDING_NOT
        if is_beyond then
            fengding = FENGDING_CHANGCI
        end    
        if ret.won_coins >= player_info.coins then
            fengding = FENGDING_JINBI   
        end
        player_info.coins = ret.curr_coins
        curr_result[uid] = ret.won_coins
        print("winner get coins:",uid,ret.won_coins)
        
        table_insert(rsp_winner,{uid = uid,add_score = ret.won_coins,base_score=result_info[uid].base_score,
        rate = result_info[uid].rate,fengding = fengding})
    end

    for uid,ret in pairs(results) do
        if ret then
            make_rsp_winner(uid,ret)
        else
            errlog(uid,'failed to cocall...',tostring_r(results))
        end
    end

    for uid,ret in pairs(robot_winners_result) do
        make_rsp_winner(uid,ret)
    end

    ---------------------------结束界面-------------------------------------
    local rsp_left_list = {}
    for uid,o in pairs(player_info_list) do
        local t = {}
        t.uid = uid
        local card_id_list = curr_ddz_instance:get_player_card_ids(uid)
        t.card_suit = card_id_list
        table_insert(rsp_left_list,t)
    end
    local chuntian_type,chuntian_uid = check_chun_tian()
    if chuntian_type > 0 then
        assert(chuntian_uid)
        if not is_robot(chuntian_uid) then
            add_task_process(chuntian_uid,constant.TASK_PLAY_CHUNTIAN)
        end    
    end

    --这里要跑一些结算的逻辑
    local score_rate_detail = curr_ddz_instance:get_score_rate_detail()
    local notification = {
        winner_uid_list = rsp_winner,
        loser_uid_list = rsp_loser,
        left_list = rsp_left_list,
        chuntian_type = chuntian_type,
    }
    notify_others('ddz.NTF_GAMEOVER',nil,notification)

    ---------任务---------------------
    check_task_update(game_result)
    -----------补助---------------------
    take_compensation(compensation_list)

    for uid,r in pairs(curr_result) do
        notify_money_changed(uid,{coins = player_info_list[uid].coins})
        notify_others('ddz.NTF_MONEY_CHANGE',nil,{uid = uid,coins = player_info_list[uid].coins})
    end

    game_over_time = util.get_now_time()
    local str_date = os.date("%Y%m%d%H%M%S")
    local table_id = self_table_id
    billlog({op = "card_record",table_gid = str_date .. "_" .. self_table_id,
            table_type = self_table_type,begin_time = game_start_time,
            end_time = game_over_time,winner_list = rsp_winner,
            loser_list = rsp_loser})
end

local function nodizhu_restart()
    for uid,status in pairs(player_status_list) do
        assert(status == PLAYER_STATUS_PLAYING)
        player_status_list[uid] = PLAYER_STATUS_READY
    end
end

local function check_close_table(curr_time)
    if keep_table then
        return
    end

    local closable = true
    --如果不满3人，则直接关闭房间
    if #ordered_players == ddz.MAX_PLAYER_NUM and 
        curr_time - start_waiting_for_ready_time < 30 then
            closable = false
    end

    if not closable then
        return
    end

    --检查还有fd的玩家
    for uid,fd in pairs(table_players) do
        if fd > 0 then
            watch_session(fd,uid,false)
        end
    end

    notify_all('ddz.NTF_BACKTO_MATCH',{})

    --这里是可以关闭了
    print('!!!now delete this table!!!!',self_table_type,self_table_id)
    
    skynet.call('.table_mgr','lua','on_table_delete',self_table_id,ordered_players)

    skynet.exit()
end
-------------------------------游戏主循环------------------------
local function update(curr_time)
    --dbglog('=============curr status',tostring(curr_status))
    if curr_status == TABLE_STATUS_REGISTERED then
        curr_status = TABLE_STATUS_WAITING_ENTER
        waiting_enter_timeout = curr_time + 3
        start_waiting_for_ready_time = curr_time
    elseif curr_status == TABLE_STATUS_WAITING_ENTER then
        if check_all_enter(curr_time) then
            curr_status = TABLE_STATUS_WAITTING_READY
        end
    elseif curr_status == TABLE_STATUS_WAITTING_READY then
        if are_all_players_ready() then
            curr_status = TABLE_STATUS_PAY_TICKET
            --去扣钱
            curr_paid_tickets = nil
            if lock_all_players() then
                --只有上锁成功了才去扣钱
                pay_all_tickets()
            else
                errlog('failed to lock_all_players!!!')
            end
        else
            check_close_table(curr_time)
        end
    elseif curr_status == TABLE_STATUS_PAY_TICKET then
        if are_all_tickets_paid() and 
            are_all_players_locked() then
            curr_status = TABLE_STATUS_CHECK_START
        else
            check_close_table(curr_time)
        end
    elseif curr_status == TABLE_STATUS_CHECK_START then
        if check_start(curr_time) then
            curr_status = TABLE_STATUS_ROB_DIZHU
            trigger_event('on_start',curr_ddz_instance)
            notify_start(curr_ddz_instance)
            game_start_time = util.get_now_time()
        end
    elseif curr_status == TABLE_STATUS_NODIZHU_RESTART then
        if check_start(curr_time) then
            curr_status = TABLE_STATUS_ROB_DIZHU
            trigger_event('on_start',curr_ddz_instance)
            notify_start(curr_ddz_instance)
        end
    elseif curr_status == TABLE_STATUS_ROB_DIZHU then
        local over,dizhu_uid = check_rob_dizhu(curr_time)
        if over then
            if dizhu_uid then
                notify_rob_dizhu_over()
                curr_status = TABLE_STATUS_JIABEI
                trigger_event('on_jiabei')
            else
                curr_status = TABLE_STATUS_NODIZHU
                nodizhu_times = nodizhu_times + 1
            end
        end
    elseif curr_status == TABLE_STATUS_JIABEI then
        if check_jiabei_over(curr_time) then
            curr_ddz_instance:start_play()
            notify_dizhu_play()
            curr_status = TABLE_STATUS_PLAYING
            trigger_event('on_start_play')
        end    
    elseif curr_status == TABLE_STATUS_PLAYING then
        if check_play(curr_time) then
            curr_status = TABLE_STATUS_GAMEOVER
        end
    elseif curr_status == TABLE_STATUS_GAMEOVER then
        local game_result = finish_game()
        if game_result then
            curr_status = TABLE_STATUS_RESTART
            local ok,ret = xpcall(audit_game_result,debug.traceback,game_result)
            if not ok then
                errlog(ret)
            end
        end
    elseif curr_status == TABLE_STATUS_RESTART then
        curr_ddz_instance = nil
        --正常跑完一局则清掉无地主记录
        nodizhu_times = 1
        set_all_unready()
        set_all_untrustee()
        set_all_unmingpai()
        unlock_all_players()
        start_waiting_for_ready_time = curr_time
        curr_status = TABLE_STATUS_WAITTING_READY
        trigger_event('on_restart')
    elseif curr_status == TABLE_STATUS_NODIZHU then
        curr_ddz_instance = nil
        nodizhu_restart()
        curr_status = TABLE_STATUS_NODIZHU_RESTART
        trigger_event('on_nodizhu_restart')
        notify_all('ddz.NTF_NODIZHU_RESTART',{})
    else
        errlog('unknown status...',curr_status)
    end
end

local function game_update()
    curr_status = TABLE_STATUS_REGISTERED
    while true do
        local curr_time = util.get_now_time()
        local ok,ret = xpcall(update,debug.traceback,curr_time)
        if not ok then 
            errlog(ret)
        end
        skynet.sleep(50)
    end
end

----------------------------------------提供服务------------------------------------
local function run_robots()
    for _,AIobj in pairs(robot_manager) do
        skynet.fork(function() AIobj:update() end)
    end
end

local function make_game_robot_config()
    local weigh_value_conf = assert(global_configs.ai_weigh_value) 
    local rob_dizhu_conf = assert(global_configs.rob_dizhu_rate)
    local jia_bei_conf  = assert(global_configs.jia_bei_rate)

    return {
        weigh_value_conf = weigh_value_conf,
        rob_dizhu_conf = rob_dizhu_conf,
        jia_bei_conf = jia_bei_conf,
    }
end

local function register_all(player_data_list)
    assert(#player_data_list <= ddz.MAX_PLAYER_NUM)

    local human_uids = {}
    for _,player_data in pairs(player_data_list) do
        local uid = player_data.uid
        table_insert(human_uids,uid)
    end
    
    if not lock_all_players_on_register(human_uids) then
        errlog('failed to lock_all_players')
        return false
    end

    local names_library = global_configs.names_library
    --检查并增加陪玩机器人
    local robots_ids = {1999999991,1999999992}
    for i=#player_data_list + 1,ddz.MAX_PLAYER_NUM do
        local uid = assert(table_remove(robots_ids))
        local player_data = {
            uid = uid,
            name = names_library[util.randint(1,#names_library)],
            coins = util.randint(9999,1999999),
            win_times = util.randint(10,1000),
            failure_times = util.randint(10,1000),
            has_card_note = false,
            sex = util.randint(1,2),
        }
        player_data.icon = tostring(player_data.sex)

        table_insert(player_data_list,player_data)
        local conf = make_game_robot_config()
        local robot_obj = game_robot.new(uid,robot_AI,skynet.self(),ROBOT_CLIENT_FD,conf)
        robot_manager[uid] = robot_obj
    end

    assert(not next(player_info_list))
    local curr_time = util.get_now_time()
    for _,player_data in pairs(player_data_list) do
        local uid = player_data.uid
        assert(not table_players[uid])
        table_players[uid] = REGISTER_CLIENT_FD
        table_insert(ordered_players,uid)
        
        player_data.position = #ordered_players
        player_data.last_chat_time = 0
        player_data.last_ping_time = curr_time

        player_info_list[uid] = player_data
        player_status_list[uid] = PLAYER_STATUS_READY   --默认进来就是准备了
        if not skynet.getenv "shenhe" then
            player_info_list[uid].mingpai_status = MINGPAI_STATUS_YES
        end
    end
    
    assert(#ordered_players == ddz.MAX_PLAYER_NUM)


    trigger_event('on_register')

    skynet.fork(game_update)

    run_robots()

    return true
end

function internal.register_all(player_data_list)
    return register_all(player_data_list)
end

function internal.get_player_num(...)
    return get_player_num()
end
---------------------------客户端请求类处理----------------------------------------
function handler.REQ_ROBDIZHU(uid,req_msg)
    if curr_status ~= TABLE_STATUS_ROB_DIZHU then
        errlog(uid,'can not rob dizhu')
        return
    end
    
    local score = req_msg.score
    if score <0 or score >3 then
        errlog('invalid score',score)
        return
    end

    local msg = { result = 0 }
    local fd = table_players[uid]
    local ret,error_code = rob_dizhu(uid,score,req_msg.is_rob == 1)
    if not ret  then
        msg.result = error_code
        send_to_gateway(uid,fd,'ddz.RSP_ROBDIZHU',msg)
        return
    end

    if req_msg.is_rob == 1 or req_msg.score > 0 then
        notify_score_and_rate_detail()
    end
    return true
end

function handler.REQ_PLAY(uid,msg)
        print_r(msg)
     if curr_status ~= TABLE_STATUS_PLAYING then
        errlog("curr_status is not playing !! ",curr_status)
        return
    end

    if not curr_ddz_instance then
        return
    end

    local fd = table_players[uid]
    local ok,rsp = play(uid,msg.card_suit or {},msg.card_suit_type,msg.card_suit_key)
    if not ok then
        print("222222222222")
        print_r(rsp)
        send_to_gateway(uid,fd,'ddz.RSP_PLAY',rsp)
        return true
    end

    --出牌成功响应
    send_to_gateway(uid,fd,'ddz.RSP_PLAY',rsp)

    local msg = {
        player_uid = uid,
        card_suit_type = rsp.card_suit_type,
        card_suit = rsp.card_suit,
        next_player_uid = rsp.next_player_uid,
        must_play = rsp.must_play,
        end_time = rsp.end_time,
        card_suit_key = rsp.card_suit_key,
        original_card_suit = rsp.original_card_suit,
    }

    notify_others('ddz.NTF_PLAY',uid,msg)
    
    return true
end

function handler.REQ_READY(uid,msg,game_session)
    --准备的时候也需要检查一下金币是否足够
    if colsing_server then
        errlog("server is closing now !!!!",curr_status)
        return 
    end

    if not can_ready(uid) then
        send_to_gateway(uid,game_session,'ddz.RSP_READY',
            {result = error_code.GOLD_IS_NOT_ENOUGH})
        return
    end
    --如果是明牌准备
    if tonumber(msg.ready) == 2 then
        player_info_list[uid].mingpai_status = MINGPAI_STATUS_YES
    end

    set_ready(uid)

    send_to_gateway(uid,game_session,'ddz.RSP_READY',{})
    
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

    send_to_gateway(uid,table_players[uid],'ddz.RSP_TRUSTEE',{state = state})

    notify_event_status(uid)

    return true
end

function handler.REQ_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if curr_time - player_info.last_chat_time < 1 then
        errlog('chatting too fast ...',uid)
        send_to_gateway(uid,table_players[uid],'ddz.RSP_CHAT',{result = error_code.REQ_CHAT_TOO_FAST})
        return
    end
    player_info.last_chat_time = curr_time

    local str_content
    if msg.str_content then
        str_content = skynet.call('.textfilter','lua','replace_sensitive',msg.str_content)
    end

    send_to_gateway(uid,table_players[uid],'ddz.RSP_CHAT',{content_id = msg.content_id,str_content = str_content})

    local ntf = {
        uid = uid,
        content_id = msg.content_id,
        str_content = str_content
    }
    notify_others('ddz.NTF_CHAT',uid,ntf)
end

function handler.REQ_VOICE_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        send_to_gateway(uid,table_players[uid],'ddz.RSP_VOICE_CHAT',{result = error_code.REQ_CHAT_TOO_FAST})
        return
    end

    player_info.last_chat_time = curr_time

    send_to_gateway(uid,table_players[uid],'ddz.RSP_VOICE_CHAT',{voice_id = msg.voice_id})

    local ntf = {
        uid = uid,
        voice_id = msg.voice_id
    }

    notify_others('ddz.NTF_VOICE_CHAT',uid,ntf)
end

function handler.REQ_INTERACT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        errlog('voice chatting too fast ...',uid)
        send_to_gateway(uid,table_players[uid],'ddz.RSP_INTERACT',{result = error_code.REQ_INTERACT_TOO_FAST})
        return
    end
    player_info.last_chat_time = curr_time

    local rsp = {recv_uid = msg.uid,context_id = msg.context_id}
    send_to_gateway(uid,table_players[uid],'ddz.RSP_INTERACT',rsp)

    local ntf = {send_uid = uid,recv_uid = msg.uid,context_id = msg.context_id}
    notify_others('ddz.NTF_INTERACT',uid,ntf)

    return true
end

local function leave(uid)
    assert(table_players[uid])

    --假如当前处于待准备中，则直接离开
    if curr_status == TABLE_STATUS_WAITTING_READY then
        --清除掉玩家
        table_players[uid] = nil
        local player_info = assert(player_info_list[uid])
        player_info_list[uid] = nil

        local del_index
        for i,_uid in ipairs(ordered_players) do
            if _uid == uid then
                del_index = i
                break
            end
        end
        assert(del_index,'no such index ' .. uid)
        table_remove(ordered_players,del_index)

        --由check close处去通知其它玩家走人
        return 0
    else
        --假如当前是处于游戏中，则将状态设置为离线状态
        assert(table_players[uid] ~= OFFLINE_CLIENT_FD)
        table_players[uid] = OFFLINE_CLIENT_FD
        return 1
    end
end

function handler.REQ_LEAVE(uid,msg,game_session)
    if table_players[uid] ~= game_session then
        send_to_gateway(uid,game_session,'ddz.RSP_LEAVE',{result = -11})
        errlog(uid,'invalid status',table_players[uid],game_session)
        return
    end

    local ret = leave(uid)

    send_to_gateway(uid,game_session,'ddz.RSP_LEAVE',{status = ret})

    watch_session(game_session,uid,false)

    skynet.send('.table_mgr','lua','leave',uid)

    return true
end

local function get_card_note_info(uid,ddz_instance)
    local other_player_cards = ddz_instance:get_other_player_cards(uid)
    local other_player_record = {}

    local records = ddz_instance:get_player_record()
    for _uid,player_record in pairs(records) do
        if uid ~= _uid then
            local record = { uid = _uid,player_records = {} }
            for _,card_record in pairs(player_record) do
                table_insert(record.player_records,{card_list = card_record})
            end

            table_insert(other_player_record,record)
        end
    end

    return {other_player_cards = other_player_cards,other_player_record = other_player_record}
end

function handler.REQ_CARD_NOTE(uid,msg)
    if not player_info_list[uid].has_card_note then
        local rsp = { result = error_code.HAS_NOT_CARD_NOTE }
        send_to_gateway(uid,table_players[uid],'ddz.RSP_CARD_NOTE',rsp)
        return
    end

    local card_note = {}
    if curr_ddz_instance then
        card_note = get_card_note_info(uid,curr_ddz_instance)
    end
    local rsp = {result = 0,card_note = card_note}
    send_to_gateway(uid,table_players[uid],'ddz.RSP_CARD_NOTE',rsp)

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
    local ret,r = enter(uid,game_session)
    if not ret then
        send_to_gateway(uid,game_session,'table.RSP_ENTER',{result = -100})
        return false
    end

    r.result = 0
    send_to_gateway(uid,game_session,'table.RSP_ENTER',r)

    local update_trustee = is_trusteed(uid)
    set_trustee(uid,false)

    if update_trustee then
        notify_event_status(uid)
    end

    watch_session(game_session,uid,true)

    return true
end

function internal.start(conf)
    self_table_id = conf.table_id
    self_table_type = conf.table_type
    this_table_gid = conf.table_gid

    dbglog(string.format('table<%d>,type(%d) got start',self_table_id,self_table_type))
    return true
end

function internal.exit()
    skynet.exit()
end

function internal.update_coins_on_table(uid,coins)
    local player_info = assert(player_info_list[uid])
    player_info.coins = coins
    notify_others('ddz.NTF_MONEY_CHANGE',uid,{uid = uid,coins = coins})
    return true
end

function handler.REQ_PLAYER_INFO(uid,msg)
    local player_uid = msg.uid
    local player_info = assert(player_info_list[player_uid])
    
    local rsp
    local win_percent = 0
    if is_robot(player_uid) then
        if player_info.win_times + player_info.failure_times > 0 then
            win_percent = math_floor(player_info.win_times / (player_info.win_times + player_info.failure_times)*100)
        end
        rsp = {
            name = player_info.name,
            coins = player_info.coins,
            total_count = player_info.win_times + player_info.failure_times,
            win_percent = win_percent,
            sex = player_info.sex,
            icon = player_info.icon
        }
    else
        local ok,base_data = R().basesvr({key=player_uid}):call('.msg_handler','get_base_data',player_uid)
        if not ok then
            errlog(uid,'failed to get_base_data info',player_uid)
        end
        if base_data.win_times + base_data.losing_times > 0 then
            win_percent = math_floor(base_data.win_times/(base_data.win_times + base_data.losing_times)*100)
        end
        rsp = {
            name = player_info.name,
            coins = base_data.coins,
            total_count = base_data.win_times + base_data.losing_times,
            win_percent = win_percent,
            sex = player_info.sex,
            icon = player_info.icon
        }
    end
    send_to_gateway(uid,table_players[uid],'ddz.RSP_PLAYER_INFO',rsp)
    return true    
end

function handler.REQ_MINGPAI(uid,msg)
    local rate = msg.rate      
    if player_info_list[uid].mingpai_status == MINGPAI_STATUS_YES then
        errlog(uid,"your status is mingpai")
        send_to_gateway(uid,table_players[uid],'ddz.RSP_MINGPAI',{result = -1})
        return false
    end
    if rate < 1 then
        errlog("params error")
        send_to_gateway(uid,table_players[uid],'ddz.RSP_MINGPAI',{result = -2})
        return false
    end
    
    if not mingpai(uid,rate) then
        send_to_gateway(uid,table_players[uid],'ddz.RSP_MINGPAI',{result = error_code.PLAYING_CANNOT_MINGPAI})
        return false
    end
    player_info_list[uid].mingpai_status = MINGPAI_STATUS_YES
    send_to_gateway(uid,table_players[uid],'ddz.RSP_MINGPAI',{result = 0})
    return true
end

function handler.REQ_JIABEI(uid,msg)
    if msg.type ~= JIABEI_TYPE_GIVEUP and msg.type ~= JIABEI_TYPE_PUTONG
       and msg.type ~= JIABEI_TYPE_CHAOJI then
       errlog("jiabei input err",msg.type)
       return
    end

    if curr_status ~= TABLE_STATUS_JIABEI then
        errlog("curr_status is not TABLE_STATUS_JIABEI!!")
        return
    end

    jiabei(uid,msg.type)
    send_to_gateway(uid,table_players[uid],'ddz.RSP_JIABEI',{result = 0})
    
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
        errlog(uid,"ctable pb decode error",pbname)
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