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
--------------------抢地主方式---------------------
local SET_DIZHU_WAY_ROB = 1
local SET_DIZHU_WAY_SCORE = 2

--------------是否封顶-------------------
local FENGDING_NOT = 0
local FENGDING_YES = 1
-------------------加倍方式-------------------
local JIABEI_TYPE_GIVEUP = 0
local JIABEI_TYPE_PUTONG = 1
local JIABEI_TYPE_CHAOJI = 2
-------------------管理---------------------

local curr_ddz_instance

local handler = {}
local internal = {}

local REGISTER_CLIENT_FD = 0
local ROBOT_CLIENT_FD = -1
local OFFLINE_CLIENT_FD = -2

-------------------托管管理------------------------
local trusteed_players = {}
local TIMEOUT_TIMES_TO_TRUSTEE = 2

--------------------明牌管理-----------------------
local mingpai_players = {}
local MINGPAI_STATUS_NO = 1
local MINGPAI_STATUS_YES = 2

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
local TABLE_STATUS_CHECK_START = 5
local TABLE_STATUS_ROB_DIZHU = 6
local TABLE_STATUS_PLAYING = 7
local TABLE_STATUS_GAMEOVER = 8
local TABLE_STATUS_RESTART = 9
local TABLE_STATUS_NODIZHU = 10  --选不出地主，重新开始
local TABLE_STATUS_NODIZHU_RESTART = 11
local TABLE_STATUS_JIABEI = 12

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

-----------------------游戏状态------------------------
return function(params)
local ddz = params.ddz
local trustee_AI = params.trustee_AI

local tablesvr_id = tonumber(skynet.getenv "server_id")
local self_table_type,self_table_id,self_password 

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

local function notify_player_leave(uid,status)
    notify_others('ddz.NTF_PLAYER_LEAVE',uid,{
        uid = uid,
        status = status
    })
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

local function get_round_serial()
    local rsp_round_serial = {}
    for i=1,#record_list do
        local round_info = {}
        round_info.round = i
        local player_list = {}
        for _,o in pairs(record_list[i]) do
            table_insert(player_list,{uid = o.uid,add_score = o.score})
        end
        round_info.player_list = player_list
        table_insert(rsp_round_serial,round_info)
    end
    return rsp_round_serial
end

local function get_rank_list()
    local rsp_rank_list = {} 
    for _,_uid in pairs(ordered_players) do
        local one_player_info = {}
        one_player_info.uid = _uid
        one_player_info.round_times = #record_list
        local win_times = 0
        local score = 0
        for i=1,#record_list do
            local round_result = record_list[i]
            if round_result then
                for j=1,#round_result do
                    round_info = round_result[j]
                    if round_info.uid == _uid then
                        if round_info.score > 0 then
                            win_times = win_times + 1
                        end
                        score = score + round_info.score
                        break
                    end
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

    local rank_list = get_rank_list()
    for _,uid in ipairs(ordered_players) do
        local r = {}
        local player_info

        local cards_ids = players_card_id_list[uid]
        player_info = assert(player_info_list[uid])
        local r = {
            uid = uid,
            name = player_info.name,
            cards_count = #cards_ids,
            position = player_info.position,
            state = get_player_state(uid),
            coins = player_info.coins,
            icon = player_info.icon,
            sex = player_info.sex,
            f_curr_score = get_player_score(uid,rank_list),
            player_ip = player_info.player_ip,
        }
        if player_info.mingpai_status == MINGPAI_STATUS_YES then
            r.cards_count = -1
            r.card_id_list = assert(players_card_id_list[uid])
        end
    

        table_insert(players_info_list,r)
    end

    local rsp_list = {}
    for position,uid in ipairs(ordered_players) do
        local rsp = copy(common)
        local tmp_list = {}
        for _,v in ipairs(players_info_list) do
            table_insert(tmp_list,copy(v))
        end
        
        print('ffffffffffff',tostring_r(tmp_list),tostring_r(ordered_players))
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

local function notify_player_enter(uid)
    local player_info = assert(player_info_list[uid])
    local rank_list = get_rank_list()
    local player = {
        uid = uid,
        name = player_info.name,
        position = player_info.position,
        coins = player_info.coins,
        icon = player_info.icon,
        sex = player_info.sex,
        state = get_player_state(uid),
        f_curr_score = get_player_score(uid,rank_list),
        player_ip = player_info.player_ip,
    }

    notify_others('ddz.NTF_PLAYER_ENTER',uid,{player = player})
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

local function get_all_human_uids()
    local uids = {}
    for uid,fd in pairs(table_players) do
        if not is_robot(uid) then
            table_insert(uids,uid)
        end
    end
    return uids
end

local function unlock_all_players()
    local uids = get_all_human_uids()
    for _,uid in pairs(uids) do
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

local function get_player_enter_data(uid)
     --先拉取玩家信息
    local ok,base_data = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
    if not ok then
        errlog(uid,'failed to get base_data',uid)
        return
    end
    print_r(base_data)
    local ok,enter_data = R().hallsvr({key=uid}):call('.msg_handler','get_enter_data',uid)
    if not ok then
        errlog(uid,'failed to get enter_data')
        enter_data = {}
    end
    print_r(enter_data)
    local str_ip = enter_data.player_ip
    local player_data = {
        uid = base_data.uid,
        name = enter_data.name or '',
        coins = base_data.coins,
        win_times = base_data.win_times,
        failure_times = base_data.losing_times,
        icon = enter_data.icon or '',
        sex = enter_data.sex or 1,
        player_ip = str_ip:sub(1,str_ip:find(':') - 1),
    }

    return player_data    
end

local function get_table_conf()
    local conf = {}
    conf.total_round = table_info.count
    conf.limit = table_info.max_dizhu_rate
    conf.curr_round = curr_round
    conf.password = self_password
    return conf
end

local function enter(uid,client_fd)
    print('now enter ========================',uid,client_fd)
    if table_players[uid] then
        local data = get_player_enter_data(uid)
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
        if num >= ddz.MAX_PLAYER_NUM then
            errlog(uid,'that player num is enough')
            return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
        end

        if not lock_one_player(uid,this_table_gid) then
            errlog(uid,'failed to lock player,you may have been in other table')
            return false,error_code.CANNOT_ENTER_FTABLE_LOCKED
        end

        local data = get_player_enter_data(uid)
        if not data then
            errlog(uid,'failed to get_player_enter_data')
            return false,error_code.CANNOT_ENTER_TEMOPORARILY
        end

        --有空位的话直接坐到位置上
        local position = 1
        while ordered_players[position] do
            position = position + 1
        end
        if position > ddz.MAX_PLAYER_NUM then
            unlock_one_player(uid,this_table_gid)
            errlog(uid,'that player num is enough three people',position)
            return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
        end


        data.position = position
        ordered_players[position] = uid
        player_info_list[uid] = data
        player_status_list[uid] = PLAYER_STATUS_NOREADY
    else
        errlog(uid,'that player have not been registed yet')
        return false,error_code.FULL_PLAYERS_IN_FRIEND_ROOM
    end
    --通知其它玩家当前玩家进来
    notify_player_enter(uid)
    
    table_players[uid] = client_fd

    local enter_info = {}
    enter_info.f_table_conf = get_table_conf()
    enter_info.creator_uid = creator_uid
    local rank_list = get_rank_list()
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
                    state = get_player_state(_uid),
                    f_curr_score = get_player_score(_uid,rank_list),
                    player_ip = player_info.player_ip,
            })
        end 

        enter_info.waiting_table_status = {
            players_info_list = players_info_list,
        }
        enter_info.game_status = 0
    else
        local rsp_list = get_response_list(curr_ddz_instance)
        enter_info.game_status = 1
        enter_info.table_status = assert(rsp_list[uid])
        enter_info.last_card_records = curr_ddz_instance:get_last_round_records()

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

    return true,{table_type = self_table_type, game_type = 1,ddz_enter_info = enter_info}
end

local function finish_game()
    local ok,result = curr_ddz_instance:get_game_result()
    if not ok then
        return
    end

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
    if card_suit_type == ddz.CARD_SUIT_TYPE_WANGZHA or 
        card_suit_type == ddz.CARD_SUIT_TYPE_ZHADAN or 
        card_suit_type == ddz.CARD_SUIT_TYPE_RUANZHA then
        notify_score_and_rate_detail()
    end

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

local function are_all_players_ready()
    local player_num = get_player_num()
    if player_num < ddz.MAX_PLAYER_NUM then
        return false
    end
    
    local count = 0
    for _,status in pairs(player_status_list) do
        if status ~= PLAYER_STATUS_READY then
            return false
        end
        count = count + 1
    end
    if count ~= ddz.MAX_PLAYER_NUM then
        return false
    end

    return true
end

local function can_start()
    if curr_ddz_instance then
        return false,-1
    end

    local sitdown_num = get_player_num()
    if sitdown_num < ddz.MAX_PLAYER_NUM then
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
    
    ddz_instance:setingdizhu_status(table_info.set_dizhu_way)

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
        local  msg = {table_status = rsp_list[uid],set_dizhu_status = set_status,score_rate_detail = detail,fround = curr_round}
        send_to_gateway(uid,fd,'ddz.NTF_START',msg)
    end 
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

local function notify_rob_dizhu_over()
    local rsp = curr_ddz_instance:get_notify_dizhu_msg()
    notify_all('ddz.NTF_SETDIZHU',rsp)

    local jiabei_end_time = curr_ddz_instance:get_jiabei_end_time()
    notify_all('ddz.NTF_JIABEI_PANEL',{end_time = jiabei_end_time})
end

local function jiabei(uid,type)
    local player_info = assert(player_info_list[uid])
    
    if type == JIABEI_TYPE_CHAOJI then
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

local function get_result_info(game_result)
    local rand_info = {}
    local total_score = 0
    
    local fengding = FENGDING_NOT
    local winners = game_result.winners
    local losers = game_result.losers
    local limit = table_info.max_dizhu_rate
    for _,o in pairs(winners) do
        total_score = total_score + o.add_score
    end
    assert(total_score > 0)
    local real_score = total_score
    if limit < total_score then
        real_score = limit
        fengding = FENGDING_YES
    end

    winners[1].add_score = math_floor(winners[1].add_score/total_score*real_score)
    table_insert(rand_info,{uid = winners[1].uid,score = winners[1].add_score})
    winners[1].fengding = fengding
    if winners[2] then
        winners[2].add_score = real_score - winners[1].add_score
        table_insert(rand_info,{uid = winners[2].uid,score = winners[2].add_score})
        winners[2].fengding = fengding
    end

    losers[1].add_score = math_floor(losers[1].add_score/total_score*real_score)
    table_insert(rand_info,{uid = losers[1].uid,score = losers[1].add_score})
    if losers[2] then
        losers[2].add_score = -(real_score + losers[1].add_score)
        table_insert(rand_info,{uid = losers[2].uid,score = losers[2].add_score})
    end
    return rand_info
end

local function check_chun_tian()
    local chuntian_type = curr_ddz_instance:get_chun_tian_type()
    if chuntian_type > 0 then
        notify_score_and_rate_detail()
    end
    return chuntian_type
end

local function audit_game_result(game_result)
    ---------------------------结算界面-------------------------------------
    local rsp_left_list = {}
    for uid,o in pairs(player_info_list) do
        local t = {}
        t.uid = uid
        local card_id_list = curr_ddz_instance:get_player_card_ids(uid)
        t.card_suit = card_id_list
        table_insert(rsp_left_list,t)
    end
    local chuntian_type = check_chun_tian()
    local winners = game_result.winners
    local losers = game_result.losers
    

    local rand_info = get_result_info(game_result)
    assert(not record_list[curr_round])
    record_list[curr_round] = rand_info
    local rank_list = get_rank_list()
    --获取当前积分
    for _,obj in pairs(winners) do
        obj.f_curr_score = get_player_score(obj.uid,rank_list) 
    end
    for _,obj in pairs(losers) do
        obj.f_curr_score = get_player_score(obj.uid,rank_list)
    end

    local notification = {
        winner_uid_list = winners,
        loser_uid_list = losers,
        left_list = rsp_left_list,
        chuntian_type = chuntian_type,
    }
    notify_others('ddz.NTF_GAMEOVER',nil,notification)
    
    local save_info = {}
    for k,v in pairs(rand_info) do
        local _uid = v.uid
        local _name = assert(player_info_list[_uid].name)
        local _icon = assert(player_info_list[_uid].icon)
        table_insert(save_info,{uid = _uid,name = _name,icon = _icon,score = v.score})
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
    billlog({op = "fcard_record",table_gid = str_date .. "_" .. self_table_id,
            table_type = self_table_type,begin_time = game_start_time,
            end_time = util.get_now_time(),curr_round = curr_round,password = self_password,
            winner_list = winners,loser_list = losers})
    
    return true
end

local function nodizhu_restart()
    for uid,status in pairs(player_status_list) do
        assert(status == PLAYER_STATUS_PLAYING)
        player_status_list[uid] = PLAYER_STATUS_READY
    end
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
            notify_others('ddz.NTF_TOUPIAO',uid,ntf)
        end
    end

    return true
end

--return[over,dismiss result]
local function check_toupiao_result()
    local agree_number = 0
    local pending
    local total_player_num = 0
    for _,r in pairs(agree_dissovle_map) do
        if r == DISS_TOUPIAO_RESULT_AGREE then
            agree_number = agree_number + 1
        elseif r == DISS_TOUPIAO_RESULT_INIT then
            pending = true
        end

        total_player_num = total_player_num + 1
    end

    if agree_number >= math.floor(total_player_num * 2 / 3) then
        return true,true
    end

    if pending then
        return false
    end

    return true,false
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

local function dissmiss_table(dismiss_reason)
    for uid,fd in pairs(table_players) do
        if fd > 0 then
            watch_session(fd,uid,false)
        end
    end
    --玩家解除桌子锁定
    unlock_all_players()

    local ntf1 = {rank_list = get_rank_list(),round_list=get_round_serial()}
    local ntf2 = {reason = dismiss_reason}

    notify_all('ddz.NTF_ROUND_OVER',ntf1)
    notify_all('ddz.NTF_FTABLE_DISS',ntf2)
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
                notify_all('ddz.NTF_FTABLE_DISS',{result = error_code.FTABLE_DISS_FAIL})
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

-------------------------------游戏主循环------------------------
local function update(curr_time)
    --print('=============curr status',tostring(curr_status))

    if curr_status == TABLE_STATUS_WAITTING_READY then
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
            
            curr_status = TABLE_STATUS_ROB_DIZHU
            notify_start(curr_ddz_instance)
            game_start_time = util.get_now_time()
        end
    elseif curr_status == TABLE_STATUS_NODIZHU_RESTART then
        if check_start(curr_time) then
            curr_status = TABLE_STATUS_ROB_DIZHU
            notify_start(curr_ddz_instance)
        end
    elseif curr_status == TABLE_STATUS_ROB_DIZHU then
        local over,dizhu_uid = check_rob_dizhu(curr_time)
        if over then
            if dizhu_uid then
                notify_rob_dizhu_over()
                curr_status = TABLE_STATUS_JIABEI
            else
                --随机一个地主吧
                curr_status = TABLE_STATUS_NODIZHU
                nodizhu_times = nodizhu_times + 1
            end
        end
     elseif curr_status == TABLE_STATUS_JIABEI then
        if check_jiabei_over(curr_time) then
            curr_ddz_instance:start_play()
            notify_dizhu_play()
            curr_status = TABLE_STATUS_PLAYING
        end
    elseif curr_status == TABLE_STATUS_PLAYING then
        if check_play(curr_time) then
            curr_status = TABLE_STATUS_GAMEOVER
        end
    elseif curr_status == TABLE_STATUS_GAMEOVER then
        local game_result = finish_game()
        if game_result then
            local ok,ret = xpcall(audit_game_result,debug.traceback,game_result)
            if not ok then
                errlog(ret)
            end
        end
        if curr_round >= table_info.count then
            is_round_over = true
        end 
        curr_status = TABLE_STATUS_RESTART
    elseif curr_status == TABLE_STATUS_RESTART then
        curr_ddz_instance = nil
        --正常跑完一局则清掉无地主记录
        nodizhu_times = 1
        set_all_unready()
        set_all_untrustee()
        set_all_unmingpai()
        curr_status = TABLE_STATUS_WAITTING_READY
    elseif curr_status == TABLE_STATUS_NODIZHU then
        curr_ddz_instance = nil
        nodizhu_restart()
        curr_status = TABLE_STATUS_NODIZHU_RESTART
        notify_all('ddz.NTF_NODIZHU_RESTART',{})
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

    if curr_status ~= TABLE_STATUS_WAITTING_READY then
        errlog("curr_status is not waiting ready !! ",curr_status)
        return
    end

    --如果是明牌准备
    if tonumber(msg.ready) == 2 then
        player_info_list[uid].mingpai_status = MINGPAI_STATUS_YES
    end

    set_ready(uid,msg.ready > 0)

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
end

function handler.REQ_CARD_NOTE(uid,msg)
    local card_note = {}
    if curr_ddz_instance then
        card_note = get_card_note_info(uid,curr_ddz_instance)
    end
    send_to_gateway(uid,table_players[uid],'ddz.RSP_CARD_NOTE',{card_note = card_note})

    return true
end

function handler.REQ_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
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
        str_content = str_content,
    }

    notify_others('ddz.NTF_CHAT',uid,ntf)
end

function handler.REQ_VOICE_CHAT(uid,msg)
    local player_info = assert(player_info_list[uid])
    local curr_time = util.get_now_time()

    if player_info.last_chat_time and curr_time - player_info.last_chat_time < 1 then
        errlog('voice chatting too fast ...',uid)
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

function handler.REQ_STAND(uid,msg)
    send_to_gateway(uid,table_players[uid],'ddz.RSP_STAND',{})

    return true
end

function handler.REQ_SITDOWN(uid,msg)
    send_to_gateway(uid,table_players[uid],'ddz.RSP_SITDOWN',{})

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
         --清除掉玩家
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
        send_to_gateway(uid,game_session,'ddz.RSP_LEAVE',{result = -11})
        errlog(uid,'invalid status',table_players[uid],game_session)
        return
    end

    if curr_round > 0 then
        send_to_gateway(uid,game_session,'ddz.RSP_LEAVE',{result = error_code.ALREADY_START})
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
    local card_note = {}
    if curr_ddz_instance then
        card_note = get_card_note_info(uid,curr_ddz_instance)
    end
    
    send_to_gateway(uid,table_players[uid],'ddz.RSP_CARD_NOTE',{card_note = card_note})

    return true
end

--请求解散
function handler.REQ_DISMISS_TOUPIAO(uid,msg)
    if curr_round <= 0 and uid ~= creator_uid then
        errlog("you are not creator_uid, cant dissovle")
        --TODO 你不是房主，不能发起投票
        send_to_gateway(uid,table_players[uid],'ddz.RSP_DISMISS_TOUPIAO',{result = error_code.PERMISSION_DENIDE})
        return
    end
    
    if agree_dissovle_map then
        errlog(uid,"there is another dismiss toupiao...")
        --TODO 已经有一场投票了
        send_to_gateway(uid,table_players[uid],'ddz.RSP_DISMISS_TOUPIAO',{result = error_code.ARLEADY_AGREE})
        return
    end

    if not table_players[uid] then
        errlog(uid,"you are not a player")
        --TODO 响应玩家
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
        notify_all('ddz.NTF_TOUPIAO_PANEL',ntf)
    else
        --未开过局,房主解散,默认所有的成员都同意
        assert(uid == creator_uid)
        for _uid in pairs(table_players) do
            agree_dissovle_map[_uid] = DISS_TOUPIAO_RESULT_AGREE
        end
    end

    send_to_gateway(uid,table_players[uid],'ddz.RSP_DISMISS_TOUPIAO',{})

    return true
end

--其它人投票
function handler.REQ_TOUPIAO(uid,msg)
    if not agree_dissovle_map then
        errlog(uid,'there have not a toupiao')
        send_to_gateway(uid,table_players[uid],'ddz.RSP_TOUPIAO',{result = error_code.PERMISSION_DENIDE})
        return
    end
    
    if agree_dissovle_map[uid] ~= DISS_TOUPIAO_RESULT_INIT then
        errlog(uid,"you has agree dissovle!! on REQ_TOUPIAO")
        send_to_gateway(uid,table_players[uid],'ddz.RSP_TOUPIAO',{result = error_code.ARLEADY_AGREE})
        return
    end

    local attitude = DISS_TOUPIAO_RESULT_REFUSE
    if msg.is_agree == 1 then
        attitude = DISS_TOUPIAO_RESULT_AGREE
    end

    agree_dissovle_map[uid] = attitude

    local rsp = {result = 0,is_agree = msg.is_agree}
    send_to_gateway(uid,table_players[uid],'ddz.RSP_TOUPIAO',rsp)

    --通知其他玩家
    local ntf = {uid = uid,is_agree = msg.is_agree}
    notify_others('ddz.NTF_TOUPIAO',uid,ntf)

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

    local update_trustee = is_trusteed(uid)
    set_trustee(uid,false)

    if update_trustee then
        notify_event_status(uid)
    end

    watch_session(game_session,uid,true)

    --进房了就要去记录一下进房记录
    R().exdbsvr(1):call('.fuser_handler','add_self_ftable',
        uid,self_password,util.get_now_time())

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
        eerrlog('invalid curr_round',self_password)
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
    local icon_list = {}
    for _,data in pairs(player_info_list) do
        print_r(data)
        table_insert(icon_list,data.icon)
    end
    table_data.icons = icon_list
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
        player_ip = player_info.player_ip,
    }

    send_to_gateway(uid,table_players[uid],'ddz.RSP_PLAYER_INFO',rsp)
    return true
end

function handler.REQ_MINGPAI(uid,msg)
    local rate = msg.rate      
    if player_info_list[uid].mingpai_status == MINGPAI_STATUS_YES  then
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

function handler.REQ_ROUND_RANK(uid,msg)
    local rsp_rank_list = get_rank_list()
    local rsp = {
        rank_list = rsp_rank_list
    }
    send_to_gateway(uid,table_players[uid],'ddz.RSP_ROUND_RANK',rsp)
    return true
end

function handler.REQ_ROUND_SERIAL(uid,msg)
    local rsp_round_serial = get_round_serial()
    
    local rsp = {
        round_list = rsp_round_serial
    }
    send_to_gateway(uid,table_players[uid],'ddz.RSP_ROUND_SERIAL',rsp)
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
        errlog(uid,"cftable pb decode error",pbname)
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