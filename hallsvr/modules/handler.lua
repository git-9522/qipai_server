local skynet = require 'skynet'
local pb = require 'protobuf'
local cjson = require "cjson"
local server_def = require "server_def"
local util = require "util"
local utils = require "utils"
local reason = require "reason"
local mail = require "mail"
local table_insert = table.insert
local table_sort = table.sort
local error_code = require "error_code"
local table_def = require "table_def"
local constant = require "constant"
local math_floor = math.floor
local data_access = require "data_access"

local send_to_gateway
local player
local curr_table_addr 
local global_configs

local SIGN_STATUS_UNSIGN = 0   --未签到
local SIGN_STATUS_SIGN = 1    --已签到
local select_server = require("router_selector")

local SYSTEM_SEQ_LIMIT = 2000000000

local hall_handler = {}
local lock_uids = {}
local match_lock_uids = {}
local notify_money_changed

local function check_match_table_config(table_type)
    local uid = player.uid 
    local roomdata = global_configs.roomdata
    if not roomdata[table_type] then
        return -99
    end

    --由这边先去判断下是否已经被桌定在桌子上了
    local ok,table_gid = R().exdbsvr(1):call('.tlock_mgr','get_player_table',uid)
    if not ok then
        errlog(uid,'failed to get_player_table')
        return error_code.FAILED_TO_MATCH_PLAYER
    end

    if table_gid ~= 0 then
        local tsvr_id = utils.extract_table_gid(table_gid)
        local dest = R().tablesvr(tsvr_id):dest()
        return error_code.PLAYER_IS_ON_TABLE,dest,table_gid
    end

    local ok,base_data = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
    if not ok then
        errlog(uid,'failed to get base_data',uid)
        return -1000
    end

    player.base_data = base_data
    
    --钱不够时判断金币是否达到领取救助金的条件
    if base_data.coins < 1000 then
        local got,ntf,curr_coins = data_access.take_compensation(uid)
        if got then
            base_data.coins = curr_coins
            notify_money_changed(uid,{coins = curr_coins})
            skynet.fork(function()
                send_to_gateway('hall.NTF_COMPENSATION',ntf)
            end)
        end
    end

    if base_data.coins < roomdata[table_type].min then
        return error_code.GOLD_IS_NOT_ENOUGH     
    end

    if not skynet.getenv("debug") then
        if base_data.coins > roomdata[table_type].max then
            return error_code.GOLD_OUT_OF_MAX
        end
    end

   return 0
end

local function check_create_table_config(uid,table_type,count)
    local frined_room_data = global_configs.friendroomdata

    local cost
    for _,v in pairs(frined_room_data) do
        if v.type == table_type and v.count == count then
            cost = v.cost
        end
    end
    if not cost then
        return error_code.FRIENDROOMDATA_CONFIG_ERROR
    end

    local ok,able = R().basesvr({key=uid}):call('.msg_handler','can_reduce_roomcards',uid,cost)
    if not ok then
        errlog(uid,'failed to can_reduce_roomcards',cost)
        return
    end

    if not able then
        return error_code.ROOMCARD_IS_NOT_ENOUGH
    end

    return 0,cost
end

local function notify_user_money(player)
    local user_data = player.user_data
    local ntf={
        coins = user_data.coins,
        gems = user_data.gems,
        roomcards = user_data.roomcards,
    }

    send_to_gateway('hall.NTF_USER_MONEY',ntf)
    return true
end

hall_handler.notify_user_money = notify_user_money

notify_money_changed = function(uid,chged)
    local ntf={}
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
    send_to_gateway('hall.NTF_USER_MONEY',ntf)
    return true
end
hall_handler.notify_money_changed = notify_money_changed

function hall_handler.PING(...)
    local curr_time = util.get_now_time()
    local rsp = {server_time = curr_time}
    send_to_gateway('hall.PONG',rsp)

    return true
end

function hall_handler.REQ_ROOMDATA_LIST(...)
    local roomdata = global_configs.roomdata
    local roomdata_list = {}
    for type,data in pairs(roomdata) do
        local tmp_num = math.random(100, 1000)
        local tmp_roomdata = {
            room_type  = type,
            room_name  = data.name,
            base_score = data.score,
            base_rate  = data.rate,
            min_limit  = data.min,
            max_limit  = data.max,
            cost       = data.cost,
            top_limit  = data.limit,
            play_num   = tmp_num,
        }
        table_insert(roomdata_list,tmp_roomdata)
    end

    send_to_gateway('hall.RSP_ROOMDATA_LIST',{room_data_list = roomdata_list})
    return true
end

function hall_handler.REQ_SHOP_INFO()
    local shopdata = global_configs.shop
    local rsp_shop_item_list = {}
    for shop_id,data in pairs(shopdata) do
        local price = {currency = data.price.currency,amount = data.price.amount}
        local goods = {id = data.goods.item_id,count = data.goods.item_count}
        local shop_id_data = {
            shop_id = shop_id,  
            name = data.name,
            price = price,
            goods = goods,
            givenum = data.givenum,
            givepro = data.givepro,
            index = data.index,
            icon_name = data.icon_name,
        }
        table_insert(rsp_shop_item_list,shop_id_data)
    end

    send_to_gateway('hall.RSP_SHOP_INFO',{shop_item_list = rsp_shop_item_list})
    return true
end

function hall_handler.REQ_MATCH_PLAYER(msg,client_fd)
    local uid = player.uid

    local code = check_match_table_config(msg.table_type)
    if code ~= 0 then
        send_to_gateway('hall.RSP_MATCH_PLAYER',{result = code})
        return true
    end

    local user_data = {
        uid = uid,
        match_type = msg.table_type,
        begin_time = util.get_now_time(),

        name = player.user_data.name,
        coins = player.base_data.coins,
        win_times = util.randint(10,1000),
        failure_times = util.randint(10,1000),
        mingpai_status = msg.status, 
        has_card_note = false,  --计牌器默认是不可用的，等到扣房费的时候才真正去获取
        sex = player.user_data.sex,
        icon = player.user_data.icon,
    }

    local ok,waiting_time = R().matchsvr(1):call('.table_mgr','match_player',user_data)
    local result = 0
    if not ok then
        errlog(uid,'failed to match player')
        result = -1
    end

    send_to_gateway('hall.RSP_MATCH_PLAYER',{result = result,interval = waiting_time})
  
    return true
end


function hall_handler.REQ_SELF_TABLE(msg,client_fd)
    local uid = player.uid

    local ok,table_gid = R().exdbsvr(1):call('.tlock_mgr','get_player_table',uid)
    if not ok then
        errlog(uid,'failed to get_player_table')
        table_gid = 0
    end

    if table_gid == 0 then
        send_to_gateway('hall.RSP_SELF_TABLE',{})
        return true
    end

    local tsvr_id = utils.extract_table_gid(table_gid)
    local dest = R().tablesvr(tsvr_id):dest()

    local rsp = {
        dest = dest,
        table_gid = table_gid,
    }

    send_to_gateway('hall.RSP_SELF_TABLE',rsp)
    return true
end

function hall_handler.REQ_CANCEL_MATCH_PLAYER(msg,client_fd)
    local uid = player.uid
    local ok,succ = R().matchsvr(1):call('.table_mgr','cancel_matching_player',uid)
    local result = 0
    if not ok then
        errlog(uid,'failed to cancel')
        result = -2
    end
    if not succ then
        result = -1
    end

    send_to_gateway('hall.RSP_CANCEL_MATCH_PLAYER',{result = result})

    return true
end

function hall_handler.REQ_CHANGE_NAME(msg)
    local name = msg.name
    if skynet.call('.textfilter','lua','is_sensitive',name) then
        return send_to_gateway('hall.RSP_CHANGE_NAME',
            {result = error_code.INVALID_NAME})
    end

    local user_data = player.user_data
    if user_data.channel == constant.CHANNEL_WECHAT then
        return send_to_gateway('hall.RSP_CHANGE_NAME',
            {result = error_code.CAN_NOT_CHANGE_NAME})
    end

    if user_data.has_change_name ~= 0 then
        return send_to_gateway('hall.RSP_CHANGE_NAME',
            {result = error_code.HAS_CHANGED_NAME})
    end

    user_data.name = name
    user_data.has_change_name = 1
    send_to_gateway('hall.RSP_CHANGE_NAME',{
        name = name,
        can_change_name = player:can_change_name(),
    })
    return true
end

function hall_handler.REQ_CHANGE_SEX(msg)
    local uid = player.uid
    local sex = msg.sex
    if sex ~= constant.SEX_BOY and sex ~= constant.SEX_GIRL then
        errlog(uid,'invalid sex',sex)
        send_to_gateway('hall.RSP_CHANGE_SEX',{result = error_code.INVALID_SEX})
        return
    end

    local user_data = player.user_data
    user_data.sex = sex

    if user_data.icon == '' or tonumber(user_data.icon) then
        user_data.icon = tostring(sex)
    end

    send_to_gateway('hall.RSP_CHANGE_SEX',{sex = sex,icon = user_data.icon})
    return true
end

local function check_ddz_ftable_conf(table_type,create_conf,count)
    --检查斗地主好友房参数
    return true
end

local function check_xuezhan_ftable_conf(create_conf,count)
    --检查好友房参数
    return true
end

local function make_ftable_create_data(table_type,cost,ddz_create_conf,xuezhan_create_conf)
    local game_type = math_floor(table_type/100)

    if game_type == table_def.GAME_TYPE_DDZ then
        local create_data = {
            table_type = table_type,
            cost = cost,
            set_dizhu_way = ddz_create_conf.set_dizhu_way,
            max_dizhu_rate = ddz_create_conf.max_dizhu_rate,
            count = ddz_create_conf.count,
            can_watch = ddz_create_conf.can_watch,
        }
        return create_data
    elseif game_type == table_def.GAME_TYPE_XUEZHAN then
        local create_data = {
            table_type = table_type,
            cost = cost,
            total_count = xuezhan_create_conf.total_count,
            limit_rate  = xuezhan_create_conf.limit_rate,
            zimo_addition = xuezhan_create_conf.zimo_addition,
            dianganghua   = xuezhan_create_conf.dianganghua,
            exchange_three = xuezhan_create_conf.exchange_three,
            hujiaozhuanyi = xuezhan_create_conf.hujiaozhuanyi,
            daiyaojiu = xuezhan_create_conf.daiyaojiu,
            duanyaojiu = xuezhan_create_conf.duanyaojiu,
            jiangdui = xuezhan_create_conf.jiangdui,
            mengqing = xuezhan_create_conf.mengqing,
            tiandi_hu = xuezhan_create_conf.tiandi_hu,
            haidilaoyue = xuezhan_create_conf.haidilaoyue,
            base_score = 1,
        }
        return create_data
    end 
end

-----------创建好友房
local room_handler = {}
function room_handler.REQ_CREATE_FRIEND_TABLE(msg,client_fd)
    local uid = player.uid
    local table_type = msg.table_type
    local game_type = math_floor(table_type/10000)
    local count = 0

    if game_type == table_def.GAME_TYPE_DDZ then
        if not check_ddz_ftable_conf(table_type,msg.ddz_create_conf) then
            send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{result = error_code.INPUT_ERROR})
            return
        end
        count = msg.ddz_create_conf.count
    elseif game_type == table_def.GAME_TYPE_XUEZHAN then
        if not check_xuezhan_ftable_conf(msg.xuezhan_create_conf) then
            send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{result = error_code.INPUT_ERROR})
            return
        end
        count = msg.xuezhan_create_conf.total_count
    else
        errlog("unkown table type!!!!",table_type)
        return
    end

    local err_code,cost = check_create_table_config(uid,msg.table_type,count)
    if err_code > 0 then
        return send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{result = err_code})  
    end

    --扣房卡
    assert(cost >= 0)
    local create_data = make_ftable_create_data(table_type,cost,msg.ddz_create_conf,msg.xuezhan_create_conf)
    if not create_data then
        errlog("make_ftable_create_data errlog",table_type)
        return
    end

    local ok,table_gid,dest,password = R().fmatchsvr(1):call('.table_mgr','create_friend_table',uid,create_data)
    print("11111111111111111111111111111111",ok,table_gid,dest,password)
    if not ok then
        errlog(uid,'failed to create friend table',table_gid,dest)
        return send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{result = -1})
    end

    dbglog('result of create_friend_table',ok,table_gid,dest)
    if table_gid < 0 or not dest then
        errlog(uid,'failed to create friend table',table_gid,dest)
        return send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{result = -2})
    end

    --查看下房卡数量
    local ok,base_data = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
    if ok then
        notify_money_changed(uid,{roomcards = base_data.roomcards})
    end

    return send_to_gateway('room.RSP_CREATE_FRIEND_TABLE',{dest = dest,table_gid = table_gid,password = password})
end

function room_handler.REQ_FRIEND_TABLE_INFO(msg,client_fd)
    local uid = player.uid
    local ok,ret = R().fmatchsvr(1):call('.table_mgr','get_friend_table_info',uid,msg.password)
    if not ok then
        errlog(uid,'failed to get_friend_table_info fmatchsvr',msg.password)
        send_to_gateway('room.RSP_FRIEND_TABLE_INFO',{result = error_code.CANNOT_ENTER_TEMOPORARILY})
        return
    end

    if not ret then
        send_to_gateway('room.RSP_FRIEND_TABLE_INFO',{result = error_code.NO_SUCH_FRIEND_TABLE})
        return
    end

    send_to_gateway('room.RSP_FRIEND_TABLE_INFO',{
        dest = ret.dest,
        table_gid = ret.table_gid
    })
    
    return true
end

local function get_today_score(uid,game_type)
    local ok,keys = R().exdbsvr(1):call('.msg_handler','get_all_frecord_key',uid,game_type)
    if not ok then
        errlog('failed to query frecord key',uid)
        return
    end
    if not keys then
        errlog('failed to get record key',uid)
        return
    end

    local ok,ret = R().exdbsvr(1):call('.ftable_handler','get_records_from_key',keys)
    if not ok then
        errlog(uid,'failed to get records')
        return
    end

    local score = 0
    local curr_time = util.get_now_time()
    for i=#ret,1,-1 do
        local record_info = cjson.decode(ret[i])
        if not util.is_same_sunup_day(curr_time,record_info.created_time) then
            break
        end

        for k,v in pairs(record_info.round_list) do
            for _,o in pairs(v.round_info) do
                if uid == o.uid then
                    score = score + o.score
                end
            end
        end
    end
    return score
end

-----查看好友面板
function room_handler.REQ_FRIEND_TABLE_PANEL(msg,client_fd)
    local uid = player.uid
    local ok,friend_tables = R().fmatchsvr(1):call('.table_mgr','get_created_friend_tables',uid,msg.game_type)
    if not ok then
        errlog(uid,'failed to get_created_friend_tables',table_gid)
        return send_to_gateway('room.RSP_FRIEND_TABLE_PANEL',{result = -1})
    end

    dbglog(tostring_r(friend_tables))

    table.sort(friend_tables, function(a,b) return a.enter_time > b.enter_time end)

    --计算今日积分
    local ok,today_score = pcall(get_today_score,uid,msg.game_type)
    if not ok then
        errlog(uid,'get score failed')
        today_score = 0
    end

    local rsp_friend_tables = {}
    for _,o in ipairs(friend_tables) do
        table_insert(rsp_friend_tables,{password = o.password,table_type = o.table_type,
        icons = o.icons,player_num = o.player_num,zimo_addition = o.zimo_addition,total_count = o.total_count})
    end

    local rsp = {
        friend_tables = rsp_friend_tables,
        today_score = today_score,
        game_type = msg.game_type
    }

    return send_to_gateway('room.RSP_FRIEND_TABLE_PANEL',rsp)
end

local function get_frecord_list(record_data)
    local rsp_record = {}
    for i=#record_data,1,-1 do
        local one_record = {}
        local record_info = cjson.decode(record_data[i])
        one_record.time = record_info.created_time
        one_record.table_type = record_info.table_type
        one_record.password = record_info.password
        local detail_list = {}
        local player_list = {}
        for _,o in ipairs(record_info.round_list) do
            local one_round_info = {}
            one_round_info.round = o.curr_round
            local result_list = {}
            for k,v in pairs(o.round_info) do
                table_insert(result_list,{uid = v.uid,addscore = v.score})
                local t = player_list[v.uid]
                if not t then
                    t = {}
                    t.name = v.name
                    t.icon = v.icon
                    t.score_list = {}
                    player_list[v.uid] = t
                end
                table_insert(t.score_list,v.score)
            end
            one_round_info.result_list = result_list
            table_insert(detail_list,one_round_info)
        end
        one_record.detail_list = detail_list
        local total_list = {}
        for uid,o in pairs(player_list) do
            local one_player_info = {}
            one_player_info.uid = uid
            one_player_info.name = o.name
            one_player_info.icon = o.icon
            one_player_info.count = #record_info.round_list
            local win_times = 0
            local addscore = 0
            for i=1,#o.score_list do
                if o.score_list[i] > 0 then
                    win_times = win_times + 1
                end
                addscore = addscore + o.score_list[i]
            end
            one_player_info.win_times = win_times
            one_player_info.addscore = addscore
            table_insert(total_list,one_player_info)
        end
        
        one_record.total_list = total_list

        table_insert(rsp_record,one_record)
    end
    return rsp_record
end

function room_handler.REQ_FRECORD_LIST(msg)
    local ok,keys = R().exdbsvr(1):call('.msg_handler','get_all_frecord_key',player.uid,msg.game_type)
    if not ok then
        errlog('failed to query frecord key',player.uid)
        send_to_gateway('room.RSP_FRECORD_LIST',{ result = -1 })
        return
    end
    if not keys then
        errlog('failed to get record key',player.uid)
        send_to_gateway('room.RSP_FRECORD_LIST',{ result = -2 })
        return
    end
    print_r(keys)

    local ok,ret = R().exdbsvr(1):call('.ftable_handler','get_records_from_key',keys)
    if not ok then
        errlog(uid,'failed to get records')
        send_to_gateway('room.RSP_FRECORD_LIST',{ result = -3 })
        return
    end

    local ok,rsp_frecord = pcall(get_frecord_list,ret)
    if not ok then
        errlog(uid,'get_frecord_list',rsp_frecord)
        send_to_gateway('room.RSP_FRECORD_LIST',{ result = -1000 })
        return 
    end

    send_to_gateway('room.RSP_FRECORD_LIST',{frecord_list = rsp_frecord,game_type = msg.game_type})

    return true
end

local function check_update_on_table(uid,base_data)
    local ok,table_gid = R().exdbsvr(1):call('.tlock_mgr','get_player_table',uid)
    if not ok then
        errlog(uid,'failed to get_player_table')
        table_gid = 0
    end

    if table_gid ~= 0 then
        local tsvr_id = utils.extract_table_gid(table_gid)
        dest = R().tablesvr(tsvr_id):send('.table_mgr','update_coins_on_table',uid,table_gid,base_data.coins)
    end
    return true
end

local BASE_DATA_MAP = {
    [constant.ITEM_COIN_ID] = true,
    [constant.ITEM_GEM_ID] = true,
    [constant.ITEM_ROOMCARD_ID] = true,
    [constant.ITEM_CNOTE_ONE_ID] = true,
    [constant.ITEM_CNOTE_TWO_ID] = true,
    [constant.ITEM_CNOTE_THREE_ID] = true,
    [constant.ITEM_JIABEICARD_ID] = true,
}
function hall_handler.REQ_BUY(msg,client_fd)
    local uid = player.uid
    local goods_id = msg.goods_id
    local goods_conf = global_configs.shop[goods_id]
    if not goods_conf then
        errlog(uid,'could not find goods',goods_id)
        return send_to_gateway('hall.RSP_BUY',{result = -1})
    end

    local base_req = {}

    --检查够不够扣
    local price = goods_conf.price

    local currency = price.currency
    if BASE_DATA_MAP[currency] then
        base_req.cost_item = {
            item_id = currency,
            item_num = price.amount
        }
    else
        errlog(uid,'invalid currency',goods_id,currency)
        return
    end

    local goods = goods_conf.goods
    if BASE_DATA_MAP[goods.item_id] then
        base_req.bought_item = {
            item_id = goods.item_id,
            item_num = goods.item_count
        }
    else
        --检查下是否是普通道具
        errlog(uid,'invalid goods.item_id',goods_id,goods.item_id)
        return
    end

    local ok,succ,ret = R().basesvr(1):call('.msg_handler','buy',uid,base_req,reason.BUY_FROM_SHOP)
    if not ok then
        errlog(uid,'failed to buy ok',goods_id)
        return send_to_gateway('hall.RSP_BUY',{result = -3})
    end

    if not succ then
        errlog(uid,'failed to buy succ',goods_id,ret)
        return send_to_gateway('hall.RSP_BUY',{result = ret})
    end
    
    player:billlog('buy',{goods_id = goods_id,item_id = goods.item_id,
            count = goods.item_count,currency = price.currency,amount = price.amount})

    local base_data = ret
    notify_money_changed(uid,{
        coins = base_data.coins,
        gems = base_data.gems,
        roomcards = base_data.roomcards
    })

    --检查是否需要更新到桌子
    if goods.item_id == constant.ITEM_COIN_ID then
        skynet.send('.msg_handler','lua','toagent',uid,'add_task_process',constant.TASK_BUY_COINS)
        check_update_on_table(uid,base_data)
    end    

    return send_to_gateway('hall.RSP_BUY',{
            goods_id = goods_id,
            item_id = goods.item_id,
            item_count = goods.item_count
        })
end

local function full_item_list(base_data)
    local rsp_item_list = {}
    --房卡    
    if base_data.roomcards > 0 then
        local item = {id = constant.ITEM_ROOMCARD_ID,count = base_data.roomcards}
        table_insert(rsp_item_list,item)
    end
    --记牌器(次数)
    if base_data.card_note_count > 0 then
        local item2 = {id = constant.ITEM_CNOTE_ONE_ID,count = base_data.card_note_count}
        table_insert(rsp_item_list,item2)
    end
    --记牌器(天数)
    local interval = base_data.card_note_end_time - util.get_now_time()
    local day = math.ceil(math.max(interval,0) / (24 * 60 * 60)) 
    if day > 0 then
        local item3 = {id = constant.ITEM_CNOTE_TWO_ID,count = day}
        table_insert(rsp_item_list,item3)
    end
    --超级加倍卡
    if base_data.jiabei_cards > 0 then
        local item4 = {id = constant.ITEM_JIABEICARD_ID,count = base_data.jiabei_cards}
        table_insert(rsp_item_list,item4)
    end

    return rsp_item_list
end

function hall_handler.REQ_ITEM_LIST(msg)
    local uid = player.uid
    local user_data = player.user_data
    local ok,base_data = R().basesvr{key=uid}:call('.msg_handler','get_base_data',uid)
    if not ok then
        errlog(uid,'failed to get_base_data info',uid)
        return false
    end

    send_to_gateway('hall.RSP_ITEM_LIST',{item_list = full_item_list(base_data)})
    return true
end

function hall_handler.REQ_PERSONAL_INFO(msg)
    local uid = player.uid
    local ok,base_data = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
    if not ok then
        errlog(uid,'failed to get personal info',uid)
        return false
    end
    local win_percent = 0
    local total_count = base_data.win_times + base_data.losing_times
    if total_count > 0 then
        win_percent = math_floor(base_data.win_times/total_count*100)
    end

    rsp = {
        uid = uid,
        name = player.user_data.name,
        sex = player.user_data.sex,
        coins = base_data.coins,
        gems = base_data.gems,
        total_count = total_count,
        win_percent = win_percent,
        icon = player.user_data.icon
    }
    send_to_gateway('hall.RSP_PERSONAL_INFO',rsp)

    return true
end

--------------------------------------GM命令--------------------------------
function hall_handler.REQ_GM(msg)
    if not skynet.getenv("debug") then
        return
    end
    local cmd_string = msg.cmd
    local user_data = player.user_data
    local command = utils.str_split(cmd_string," ")
    local cmd = command[1]
    local params = {}
    for i = 2,#command do
        table_insert(params,command[i])
    end
    print_r(params)

    local reason = reason.GM
    local uid = player.uid
    if cmd == "addcoins" then
        local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler','add_coins',uid,params[1],reason)
        notify_money_changed(uid,{coins = ret.curr})
        --notify_user_money(player)
    elseif cmd == "addgems" then
        local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler','add_gems',
        uid,params[1],reason)
        notify_money_changed(uid,{gems = ret.curr})
    elseif cmd == "addroomcards" then
        local ok,succ,curr_roomcards = R().basesvr({key=uid}):call('.msg_handler','add_roomcards',
        uid,params[1],reason)
        notify_money_changed(uid,{roomcards = curr_roomcards})
    elseif cmd == "addtaskprocess" then
        player:add_task_process(params[1],global_configs.daily_task)
    elseif cmd == "testmail" then
        local attach_list1 = {}
        attach_list1[10001] = 1
        attach_list1[10002] = 2
        player:add_mail(102,10,nil,attach_list1)
    elseif cmd == "reducecoins" then
        local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler','reduce_coins',
        uid,params[1],reason)
        notify_money_changed(uid,{coins = ret.curr})     
    else
        errlog(uid,"invalid cmd")
        return false    
    end    
    send_to_gateway('hall.RSP_GM',{result = 0})
    return true
end
------------------------------------------------------------------------
local function add_award(uid,award_list,reason)
    local chged = {}
    for index,award_info in ipairs(award_list) do
        local award_id = tonumber(award_info.id)
        local count = tonumber(award_info.count)
        local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler','add_item',uid,award_id,count,reason)
        if not ok then
            return
        end
        if award_id == constant.ITEM_COIN_ID then
            chged.coins = ret.curr
        elseif award_id == constant.ITEM_GEM_ID then
            chged.gems = ret.curr
        elseif award_id == constant.ITEM_ROOMCARD_ID then
            chged.roomcards = ret.curr
        end        
    end
    return chged
end



local daily_handler = {}

function daily_handler.REQ_SIGNIN(msg)
    local uid = player.uid
    local user_data = player.user_data

    --获取系统时间
    local time_secs = util.get_now_time()
    local sign_info = user_data.sign_info
    local last_sign_time = sign_info.last_sign_time
    --今日是否已经签到
    if util.is_same_day(time_secs,last_sign_time) then
        errlog("today you are already signin",last_sign_time)
        send_to_gateway('daily.RSP_SIGNIN',{result = error_code.TODAY_IS_ALREADY_SIGN})
        return
    end

    --连续签到天数+1
    local sign_count = sign_info.sign_count
    if sign_count < constant.MAX_SIGN_COUNT then
        sign_count = sign_count + 1
    end

    sign_info.sign_count = sign_count
    sign_info.last_sign_time = time_secs
 
    local daily_signing = global_configs.daily_signing
    if not daily_signing then
        errlog("failed to get daily_signing",uid)
        send_to_gateway('daily.RSP_SIGNIN',{result = -2})
        return
    end
    local rsp_award_list = {}
    for id,award_info in ipairs(daily_signing[sign_count].awards_list) do
        local one_award = {}
        one_award.id = award_info.id
        one_award.count = award_info.count
        table_insert(rsp_award_list,one_award)
    end

    -- 发放奖励
    if #rsp_award_list > 0 then
        local award_reason = reason.SIGN_IN
        local chged = add_award(uid,rsp_award_list,award_reason)
        if not chged then
            errlog("failed to add_award",tostring_r(rsp_award_list))
            send_to_gateway('daily.RSP_SIGNIN',{result = -3})
            return
        end
        notify_money_changed(uid,chged)
    end

    local rsp = {
        sign_count = sign_count,
        award_list = rsp_award_list,
    }
    send_to_gateway('daily.RSP_SIGNIN',rsp)

    return true
end

function daily_handler.REQ_SPECIAL_SIGNAWARD(msg)
    local uid = player.uid
    local user_data = player.user_data

    --获取系统时间
    local time_secs = util.get_now_time()
    local sign_info = user_data.sign_info
 
    local daily_signing = global_configs.daily_signing
    if not daily_signing then
        send_to_gateway('daily.RSP_SPECIAL_SIGNAWARD',{result = error_code.INPUT_ERROR})
        return
    end

    local sign_count = sign_info.sign_count or 0
    if sign_count < constant.MAX_SIGN_COUNT then
        send_to_gateway('daily.RSP_SPECIAL_SIGNAWARD',{result = error_code.CANNOT_TAKE})
        return
    end

    if sign_info.special_award == constant.HAS_TAKEN then
        send_to_gateway('daily.RSP_SPECIAL_SIGNAWARD',{result = error_code.ALREADY_TAKE})
        return
    end

    local rsp_award_list = {}
    for id,award_info in ipairs(daily_signing[constant.LIMIT_AWARD_COUNT].awards_list) do
        local one_award = {}
        one_award.id = award_info.id
        one_award.count = award_info.count
        table_insert(rsp_award_list,one_award)
    end

    sign_info.special_award = constant.HAS_TAKEN

    -- 发放奖励
    if #rsp_award_list > 0 then
        local award_reason = reason.SIGN_IN
        local chged = add_award(uid,rsp_award_list,award_reason)
        if not chged then
            errlog("failed to add_award",tostring_r(rsp_award_list))
            send_to_gateway('daily.RSP_SPECIAL_SIGNAWARD',{result = -3})
            return
        end
        notify_money_changed(uid,chged)
    end

    local rsp = {
        award_list = rsp_award_list,
    }
    send_to_gateway('daily.RSP_SPECIAL_SIGNAWARD',rsp)

    return true
end


function daily_handler.REQ_SIGNIN_PANEL(msg)
    local uid = player.uid
    local user_data = player.user_data
    local sign_info = user_data.sign_info
    local time_secs = util.get_now_time()
    local last_sign_time = sign_info.last_sign_time
    local today_sign = 0

    --今日是否已经签到
    if util.is_same_day(time_secs,last_sign_time) then
        today_sign = 1
    elseif not util.is_same_day(time_secs - 24*3600,last_sign_time) then
        sign_info.sign_count = 0    
    end

    local sign_count = sign_info.sign_count

    local daily_signing = global_configs.daily_signing
    if not daily_signing then
        errlog("failed to get daily_signing",uid)
        send_to_gateway('daily.RSP_SIGNIN_PANEL',{result = -1})
        return
    end

    local new_award_list = {}

    --读取配置
    for k,v in ipairs(daily_signing) do
        local one_day_award = {}
        one_day_award.day = k
        local award_list = {}
        for i=1,#v.awards_list do
            local one_award = {}
            one_award.id = v.awards_list[i].id
            one_award.count = v.awards_list[i].count
            table_insert(award_list,one_award)
        end
        one_day_award.award_list = award_list
        table_insert(new_award_list,one_day_award)
    end
--    print_r(new_award_list)

    local rsp = {
        today_sign = today_sign,
        sign_count = sign_count,
        day_award_list = new_award_list,
    }
    send_to_gateway('daily.RSP_SIGNIN_PANEL',rsp)
    return true
end

local function get_task_cycle_list()

    local uid = player.uid
    local user_data = player.user_data
    local task_info = user_data.task_info
    local daily_task_list = task_info.daily_task_list
    local task_config = global_configs.task
    if not task_config then
        errlog("failed to get daily_task",uid)
        return
    end

    local rsp_cycle_list = {}
    local get_award_list = function(award_list)
        local new_award_list = {}
        for k,v in pairs(award_list) do
            local one_award = {}
            one_award.id = v.id
            one_award.count = v.count
            table_insert(new_award_list,one_award)
        end
        return new_award_list
    end

    --按类型发，每种类型发送一个任务，当任务已完成则查配置里面是否还有下一个任务
    for cycle,cycle_info in pairs(task_info) do
        local task_list = {}
        for task_type,task_obj in pairs(cycle_info) do
            local task = task_obj[#task_obj]
            if not task then
                errlog("task is not exist",task_type,uid)
                break
            end
            local status = tonumber(task.status)
            if status == constant.TASK_STATUS_UNFINISH or status == constant.TASK_STATUS_FINISHED then
                local one_task = {}
                local _task = task_config[task.task_id]
                one_task.task_id = task.task_id
                one_task.process = task.process
                one_task.process_limit = _task.process
                one_task.task_name = _task.task_name
                one_task.award_list = get_award_list(_task.award_list)
                one_task.guidance = _task.guidance
                table_insert(task_list, one_task)
            elseif status == constant.TASK_STATUS_TAKEN then    --最后一个任务如果已经被领取，查找配置是否还存在这一系列的任务
                next_id = task_config[task.task_id].next_id
                if next_id then
                    local next_task = task_config[next_id]
                    if next_task then
                        local one_task = {}
                        one_task.task_id = next_id
                        one_task.process = 0
                        one_task.process_limit = next_task.process
                        one_task.task_name = next_task.task_name
                        one_task.award_list = get_award_list(next_task.award_list)
                        one_task.guidance = next_task.guidance
                        table_insert(task_list, one_task)
                    end
                end
            end    
        end
        table_sort(task_list,function(a,b) return a.task_id < b.task_id end)
        table_insert(rsp_cycle_list,{cycle_type = cycle,task_list = task_list})
    end
    return rsp_cycle_list
    
end

--请求当前任务
function daily_handler.REQ_CURR_TASK(msg)
    local rsp_cycle_list = get_task_cycle_list()
    local rsp = {
        cycle_list = rsp_cycle_list
    }
    send_to_gateway('daily.RSP_CURR_TASK',rsp)
    return true
end

local function notify_curr_task()
    local rsp_cycle_list = get_task_cycle_list()
    send_to_gateway('daily.NTF_CURR_TASK',{cycle_list = rsp_cycle_list})
    return true
end

daily_handler.notify_curr_task = notify_curr_task

--领取任务奖励
function daily_handler.REQ_TAKE_TASK_AWARD(msg)
    local uid = player.uid
    local task_id = msg.task_id
    local task_config = global_configs.task
    local task_conf = task_config[task_id]
    assert(task_conf,'cannot find task in config')
    local cycle = task_conf.cycle
    local task_type = task_conf.task_type

    local user_data = player.user_data
    local task_info = user_data.task_info
    local cycle_task_list = task_info[cycle]
    local type_task_list = cycle_task_list[tostring(task_type)]

    local task = nil
    for _,task_obj in ipairs(type_task_list) do
        if task_id == task_obj.task_id then                     
            task = task_obj
            break
        end
    end
    if not task then
        errlog("this task not exit",task_id)
        send_to_gateway('daily.RSP_TAKE_TASK_AWARD',{result = error_code.TASK_IS_NOT_EXIST})
        return
    end
    
    if task.status ~= constant.TASK_STATUS_FINISHED then
        errlog("you're not finish this task",uid,task.process,task_conf.process)
        send_to_gateway('daily.RSP_TAKE_TASK_AWARD',{result = error_code.CANNOT_TAKE})
        return
    end

    local award_list = {}
    for k,v in ipairs(task_conf.award_list) do
        local one_award = {}
        one_award.id = v.id
        one_award.count = v.count
        table_insert(award_list,one_award)
    end

    --状态置为已领取
    task.status = constant.TASK_STATUS_TAKEN

    -- 发放奖励
    if #award_list > 0 then
        local award_reason = reason.TAKE_TASK_AWARD
        local chged = add_award(uid,award_list,award_reason)
        if not chged then
            errlog("failed to add_award",tostring_r(award_list),reason)
            send_to_gateway('daily.RSP_SIGNIN',{result = -3})
            return
        end
        notify_money_changed(uid,chged)
    end

    notify_curr_task()

    local rsp = {
        award_list = award_list,
        task_id = task_id
    }
    send_to_gateway('daily.RSP_TAKE_TASK_AWARD',rsp)
    return true
end

function daily_handler.notify_task_change(task_id,process)
    local ntf = {
        task_id = task_id,
        process = process
    }
    send_to_gateway('daily.NTF_TASK_CHANGE',ntf)
end


local mail_handler = {}
local function fill_rsp_attach_list(rsp_attach_list,attach_list)
    if attach_list then
        for _,attach_info in pairs(attach_list) do
            local one_attach = {}
            one_attach.id = attach_info.id
            one_attach.count = attach_info.count
            table_insert(rsp_attach_list, one_attach)
        end
    end
end

function mail_handler.REQ_MAIL_LIST(msg)
    --添加一封邮件
    --[[local attach_list1 = {}
    attach_list1[10001] = 1
    attach_list1[10002] = 2
    player:add_mail(102,10,nil,attach_list1)]]

    local uid = player.uid
    local user_data = player.user_data
    local mail_info = user_data.mail_info
    local mail_list = mail_info.mail_list

    local mail_template = global_configs.mail_template
    
    local rsp_mail_list = {}
    local time_secs = util.get_now_time()
    --加载系统普通邮件
    for seq,mail_obj in pairs(mail_list) do
        if time_secs - mail_obj.send_time > 30 * 86400 then
            mail_list:delete_from_hash(seq)
        else
            local one_mail = {}
            one_mail.mail_seq = mail_obj.mail_seq
            local title,content = mail.get_sender_content(uid,mail_obj,mail_template)
            one_mail.title = title
            one_mail.content = content
            one_mail.send_time = mail_obj.send_time

            local attach_list = {}
            fill_rsp_attach_list(attach_list,mail_obj.attach_list)
            one_mail.attach_list = attach_list
            table_insert(rsp_mail_list, one_mail)
        end
    end

    local ok,platform_mail_list = R().mailsvr(1):call('.msg_handler','select_mail_list',uid)
    if ok then
        for seq,mail_obj in pairs(platform_mail_list) do
            table_insert(rsp_mail_list,mail_obj)
        end
    end
	
    local rsp = {
        mail_list = rsp_mail_list
    }
    send_to_gateway('mail.RSP_MAIL_LIST',rsp)
    return true
end

function mail_handler.REQ_TAKE_ATTACH(msg)
    local uid = player.uid
    local user_data = player.user_data
    local mail_seq = msg.mail_seq

    local mail_info = user_data.mail_info
    local mail_list = mail_info.mail_list

    local rsp_attach_list = {}
    if mail_seq <= SYSTEM_SEQ_LIMIT then
        local mail_obj = mail_list[tostring(mail_seq)]
        if not mail_obj then
            errlog(uid,"mail is not exist",mail_seq)
            return
        end
        local attach_list = mail_obj.attach_list
        if not attach_list then
            errlog("attach is nil",uid)
            return
        end
        fill_rsp_attach_list(rsp_attach_list,attach_list)

        --删除邮件
        mail_list:delete_from_hash(tostring(mail_seq))
    elseif mail_seq > SYSTEM_SEQ_LIMIT then
    --如果是平台邮件需要到邮件服务器去处理
        --local ok,ret,attach_list = skynet.call('.forwarder','lua','TOMAILSVR','take_attach',uid,mail_seq)
        local ok,attach_list = R().mailsvr(1):call('.msg_handler','take_attach',uid,mail_seq)
        if not ok then
            errlog(uid,'failed to fetch user data',ret)
            return
        end
        fill_rsp_attach_list(rsp_attach_list,attach_list)
    end

    -- 发放奖励
    if #rsp_attach_list > 0 then
        local award_reason = reason.TAKE_MAIL_ATTACH
        local chged = add_award(uid,rsp_attach_list,award_reason)
        if not chged then
            errlog("failed to add_award",tostring_r(rsp_attach_list))
            send_to_gateway('daily.RSP_SIGNIN',{result = -3})
            return
        end
        notify_money_changed(uid,chged)
    end

    local rsp = {
        attach_list = rsp_attach_list,
        mail_seq = mail_seq
    }    
    send_to_gateway('mail.RSP_TAKE_ATTACH',rsp)
    return true
end

function mail_handler.REQ_DEL_MAIL(msg)
    local uid = player.uid
    local user_data = player.user_data
    local mail_seq = msg.mail_seq

    local mail_info = user_data.mail_info
    local mail_list = mail_info.mail_list

    if mail_seq <= SYSTEM_SEQ_LIMIT then
        if not mail_list[tostring(mail_seq)] then
            errlog("this mail is not exit",uid)
            return 
        end
        mail_list:delete_from_hash(tostring(mail_seq))
    elseif mail_seq > SYSTEM_SEQ_LIMIT then
    --如果是平台邮件需要到邮件服务器去处理    
        --local ok,ret,seq = skynet.call('.forwarder','lua','TOMAILSVR','del_mail',uid,mail_seq)
        local ok,seq = R().mailsvr(1):call('.msg_handler','del_mail',uid,mail_seq)
        if not ok then
            errlog(uid,'failed to del_mail',ret)
            return
        end
    end
    local rsp = {
        mail_seq = mail_seq
    }
    send_to_gateway("mail.RSP_DEL_MAIL",rsp)
    return true
end

function mail_handler.REQ_ALL_MAIL_ATTACH(msg)
    local uid = player.uid
    local user_data = player.user_data
    
    local mail_info = user_data.mail_info
    local mail_list = mail_info.mail_list
    local rsp_attach_list = {}
    --先领取系统内有附件的邮件
    for seq,mail_obj in pairs(mail_list) do
        if mail_obj.attach_list then
            local mail_attach_info = {}
            mail_attach_info.mail_seq = seq
            local one_attach_list = {}
            fill_rsp_attach_list(one_attach_list,mail_obj.attach_list)
            mail_attach_info.attach_list = one_attach_list
            table_insert(rsp_attach_list,mail_attach_info)
            --领完附件即删除
            mail_list:delete_from_hash(tostring(seq))
        end
    end
    --领取平台上有附件的邮件
    --local ok,ret,platform_attach_list = skynet.call('.forwarder','lua','TOMAILSVR','take_all_attach',uid)
    local ok,platform_attach_list = R().mailsvr(1):call('.msg_handler','take_all_attach',uid)
    if ok then
        for k,v in pairs(platform_attach_list) do 
            table_insert(rsp_attach_list,v)
        end
    end

    -- 发放奖励
    local rsp_chged = {}
    for _,obj in pairs(rsp_attach_list) do
        local award_reason = reason.TAKE_MAIL_ATTACH
        local chged = add_award(uid,obj.attach_list,award_reason)
        if not chged then
            errlog("failed to add_award",tostring_r(obj.attach_list))
            send_to_gateway('daily.RSP_SIGNIN',{result = -3})
            return
        end
        rsp_chged.coins = chged.coins or rsp_chged.coins
        rsp_chged.gems = chged.gems or rsp_chged.gems
        rsp_chged.roomcards = chged.roomcards or rsp_chged.roomcards 
    end
    notify_money_changed(uid,rsp_chged)
    local rsp = {
        mail_attach_list = rsp_attach_list
    }
    send_to_gateway("mail.RSP_ALL_MAIL_ATTACH",rsp)
    return true
end

function mail_handler.notify_new_mail(count)
    local ntf = {
        count = count
    }
    send_to_gateway("mail.NTF_NEW_MAIL",ntf)
end

function room_handler.REQ_ENTER(msg)
    local uid = player.uid
    local table_type = msg.table_type

    local code,dest,table_gid = check_match_table_config(table_type)
    
    if code ~= 0 then
        send_to_gateway('room.RSP_ENTER',{result = code,
            dest = dest, table_gid = table_gid})
        return 
    end

    send_to_gateway("room.RSP_ENTER",{result = 0})
    return true
end
--------------------------------------------------------------------
local M = {
    login = {},
    table = table_handler,
    daily = daily_handler,
    mail  = mail_handler,
    hall  = hall_handler,
    room  = room_handler,
}

function M._init_(player_,send_to_gateway_,global_configs_)
    player = player_
    send_to_gateway = send_to_gateway_
    global_configs = global_configs_
end

return M
