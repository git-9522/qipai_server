local skynet = require "skynet.manager"
local cjson = require "cjson"
local server_def = require "server_def"
local util = require "util"
local dbdata = require "dbdata"
local constant = require "constant"
local error_code = require "error_code"

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format

--[[
该模块主要管理游戏的基础数据,
做的事情就是从mongodb读出数据，写到redis中并返回给其它服务,
持久化的工作可通过消息队列的方式让外部程序去写
--]]

local select_server = require("router_selector")

local sync_uids = {}

local CMD = {}

local compensation_cond = constant.BASE_COMPENSATION_COND
local compensation_coins = constant.BASE_COMPENSATION_COINS
local compensation_times_limit = constant.BASE_COMPENSATION_TIMES_LIMIT

local init_coins = tonumber(skynet.getenv "init_coins") or 555
local init_gems = tonumber(skynet.getenv "init_gems") or 99999
local init_roomcards = tonumber(skynet.getenv "init_roomcards") or 99


local dirty_queue_db
local dirty_queue_key
local redis_pool

local mongo_conf
local mongo_pool

function CMD.open(conf)
    local redis_conf = {
        host = assert(conf.redis_host),
        port = assert(conf.redis_port),
        db = assert(conf.redis_db),
    }
    
    dirty_queue_db = assert(conf.dirty_queue_db)
    dirty_queue_key = assert(conf.dirty_queue_key)
    redis_pool = require("redis_pool").new(redis_conf)

    mongo_conf = {
        host = assert(conf.db_host),
        port = assert(conf.db_port),
        username = conf.db_username,
        password = conf.db_password,
        db_name = assert(conf.db_name),
        coll_name = assert(conf.db_coll_name),
    }
    mongo_pool = require("mongo_pool").new(mongo_conf)

    skynet.retpack(true)
end

--------------------------------数据库和缓存相关[begin]--------------------------------------
local function select_from_mongodb(uid)
    local client = mongo_pool:get_conn_from_pool()
    local db_name = mongo_conf.db_name
    local coll_name = mongo_conf.coll_name
    local ok,ret = xpcall(function()
        return client[db_name][coll_name]:findOne({_id = uid})
    end,debug.traceback)
    mongo_pool:putback_to_pool(client)
    if not ok then
        errlog(uid,ret)
        return
    end

    return ret
end
--------------------------------数据库和缓存相关[end]--------------------------------------

-----------------------------------数据存取相关--------------------------------
--先把数据写入,再做一个写标记，切记不可调换。用脚本同时可保证数据写入的原子性
local update_redis_script = [[
    redis.call('set',KEYS[1],ARGV[1])
    redis.call('select',KEYS[2])
    redis.call('hincrby',KEYS[3],ARGV[2],ARGV[3])
]]

local fix_base_data_for_miss_field

local function create_default_base_data(uid)
    local new_data = {uid = uid}
    fix_base_data_for_miss_field(new_data)
    return new_data
end

local function save_data_to_cache(uid,conn,data)
    local key = string_format('base_%d',uid)
    local data_str = cjson.encode(data)
    conn:eval(update_redis_script,3,key,dirty_queue_db,
        dirty_queue_key,data_str,uid,1)
    dbglog(uid,'save data to cache',data_str)
end

local function ensure_data_in_cache(uid,conn)
    local key = string_format('base_%d',uid)
    local data = conn:get(key)
    dbglog(uid,"-----ensure_data_in_cache-----",data)
    if data then
        data = cjson.decode(data)
        if fix_base_data_for_miss_field(data) then
            save_data_to_cache(uid,conn,data)
        end
    else
        --缓存没命中，在数据库里？我们需要到mongodb上找去
        data = select_from_mongodb(uid)
        if not data then
            --数据库也没有，这是一个新玩家，我们用默认的数据吧
            data = create_default_base_data(uid)
            save_data_to_cache(uid,conn,data)
        else
            fix_base_data_for_miss_field(data)
            --写到缓存中去吧
            save_data_to_cache(uid,conn,data)
        end  
    end

    return dbdata.new_from('data',data)
end

---------------------------------------数据存取相关------------------------------------

--------------------------------并发控制相关[begin]-------------------------------
local function wrapper_f(f,uid,conn,...)
    local data = assert(ensure_data_in_cache(uid,conn),
        string_format('could not fetch data <%s>',tostring(uid)))
    local ret = {f(uid,data,...)}
    if data:is_dirty() then
        save_data_to_cache(uid,conn,data:deep_copy())
    end

    if #ret > 0 then
        skynet.retpack(table_unpack(ret))
    end
end

local function sync_run_by_uid(uid,f,...)
    local waiting_list = sync_uids[uid]
    if waiting_list == nil then
        sync_uids[uid] = true
    else
        if waiting_list == true then
            waiting_list = {}
            sync_uids[uid] = waiting_list
        end
        local co = coroutine.running()
        table_insert(waiting_list,co)
        skynet.wait(co) --等待唤醒
    end

    local conn = redis_pool:get_conn_from_pool()
    local ok,ret = xpcall(wrapper_f,debug.traceback,f,uid,conn,...)
    redis_pool:putback_to_pool(conn)

    if not ok then errlog(ret) end

    --再接着调度
    local waiting_list = sync_uids[uid]
    if waiting_list == true or #waiting_list == 0 then
        sync_uids[uid] = nil
        return
    end

    local co = table_remove(waiting_list,1)
    skynet.wakeup(co)
end
--------------------------------并发控制相关[end]-------------------------------
fix_base_data_for_miss_field = function(data)
    local changed = false
    if not data.coins then
        data.coins = init_coins
        changed = true
    end
    if not data.gems then
        data.gems = init_gems
        changed = true
    end
    if not data.max_gems then
        data.max_gems = data.gems
        changed = true
    end
    if not data.roomcards then
        data.roomcards = init_roomcards
        changed = true
    end
    if not data.win_times then
        data.win_times = 0
        changed = true
    end
    if not data.losing_times then
        data.losing_times = 0
        changed = true
    end
    if not data.created_time then
        data.created_time = util.get_now_time()
        changed = true
    end
    if not data.compensation_times then
        data.compensation_times = 0
        changed = true
    end
    if not data.last_cross_day_time then
        data.last_cross_day_time = 0
        changed = true
    end
    if not data.jiabei_cards then
        data.jiabei_cards = 0
        changed = true
    end
    if not data.card_note_count then
        data.card_note_count = 1
        changed = true
    end
    if not data.card_note_end_time then
        data.card_note_end_time = 0
        changed = true
    end
    if not data.coins_locked then
        data.coins_locked = 0
        changed = true
    end
    return changed
end

local function check_cross_day(uid,data)
    local curr_time = util.get_now_time()
    if util.is_same_sunup_day(data.last_cross_day_time,curr_time) then
        return
    end
    
    data.last_cross_day_time = curr_time

    data.compensation_times = 0
end
-----------------------------------协议-----------------------------------------
local function get_base_data(uid,data)
    return data
end

-------------------补助金------------------------
local function can_take_compensation(uid,data)
    --检查下跨天
    check_cross_day(uid,data)

    if data.compensation_times >= compensation_times_limit then
        return false
    end
    
    if data.coins >= compensation_cond then
        return false
    end

    return true
end


local function add_coins(uid,data,coins,reason)
    data.coins = data.coins + coins

    billlog({op="addcoins",uid = uid,curr = data.coins,value = coins,r = reason})

    return true,{
        curr = data.coins,
        chged = coins,
    }
end

local function reduce_coins(uid,data,coins,reason,clear)
    local lost_coins = coins
    local diff = data.coins - lost_coins
    if diff < 0 then
        if not clear then
            return false
        end
        lost_coins = data.coins
    end

    data.coins = data.coins - lost_coins

    local compensation = can_take_compensation(uid,data)

    billlog({op="reducecoins",uid = uid,curr = data.coins,value = lost_coins,intent = coins,r = reason})

    return true,{
        curr = data.coins,
        chged = lost_coins,
        compensation = compensation
    }
end

local function pay_one_ticket(uid,data,coins,reason,clear)
    local ret,t = reduce_coins(uid,data,coins,reason,clear)
    if not ret then
        return false
    end

    t.has_card_note = false
    local now = util.get_now_time()
    if data.card_note_end_time >= now then
        t.has_card_note = true
        return true,t
    end

    if data.card_note_count > 0 then
        data.card_note_count = data.card_note_count - 1
        t.has_card_note = true
    end

    --买了门票后就锁住钱
    data.coins_locked = now + 7200

    return true,t
end

local function can_reduce_coins(uid,data,coins)
    local able = false
    if data.coins >= coins then
        able = true
    end

   return able
end

local function add_gems(uid,data,gems,reason)
    data.gems = data.gems + gems
    data.max_gems = data.max_gems + gems

    billlog({op="addgems",uid = uid,curr = data.gems,value = gems,r = reason})

    return true,{
        curr = data.gems,
        chged = gems
    }
end

local function reduce_gems(uid,data,gems,reason)
    if data.gems < gems then
        return false
    end

    data.gems = data.gems - gems

    billlog({op="reducegems",uid = uid,curr = data.gems,value = gems,r = reason})

    return true,{
        curr = data.gems,
        chged = gems
    }
end

local function can_reduce_gems(uid,data,gems)
    local able = false
    if data.gems >= gems then
        able = true
    end

    return able
end

local function add_roomcards(uid,data,roomcards,reason)
    data.roomcards = data.roomcards + roomcards

    billlog({op="addroomcards",uid = uid,curr = data.roomcards,value = roomcards,r = reason})

    return true,{
        curr = data.roomcards,
        chged = roomcards
    }
end

local function reduce_roomcards(uid,data,roomcards,reason)
    if data.roomcards < roomcards then
        return false
    end

    data.roomcards = data.roomcards - roomcards

    billlog({op="reduceroomcards",uid = uid,curr = data.roomcards,value = roomcards,r = reason})

    return true,{
        curr = data.roomcards,
        chged = roomcards
    }
end

local function can_reduce_roomcards(uid,data,roomcards)
    local able = false
    if data.roomcards >= roomcards then
        able = true
    end

    return able
end

local function add_jiabeicards(uid,data,item_id,count,reason)
    data.jiabei_cards = data.jiabei_cards + count

    billlog({op="add_item",uid = uid,cur = data.jiabei_cards,
        item_id,item_num = count,r = reason})

    return true,{
        curr = data.jiabei_cards,
        chged = count
    }
end

local function reduce_jiabeicards(uid,data,item_id,count,reason)
    if data.jiabei_cards < count then
        return false
    end
    data.jiabei_cards = data.jiabei_cards - count

    billlog({op="reduce_item",uid = uid,curr = data.jiabei_cards,
        item_id = item_id,item_num = count,r = reason})
    
    return true,{
        curr = data.jiabei_cards,
        chged = count
    }
end

local function can_reduce_jiabeicards(uid,data,count)
    local able = false
    if data.jiabei_cards >= count then
        able = true
    end

    return able
end

local function add_card_note_count(uid,data,item_id,item_num,reason)
    data.card_note_count = data.card_note_count + item_num

    billlog({op="add_item",uid = uid,cur = data.card_note_count,
        item_id = item_id,item_num = item_num,r = reason})

    return true,{
        curr = data.card_note_count,
        chged = item_num
    }
end

local function add_card_note_time(uid,data,item_id,item_num,reason)
    local add_second = 0
    if item_id == constant.ITEM_CNOTE_TWO_ID then --1天记牌器
        add_second = item_num * 24 * 60 * 60
    elseif item_id == constant.ITEM_CNOTE_THREE_ID then --7天记牌器
        add_second = item_num * 7 * 24 * 60 * 60
    else
        errlog(uid,'unknown itemid',item_id)
        return false
    end

    local now = util.get_now_time()
    data.card_note_end_time = math.max(data.card_note_end_time,now)
    data.card_note_end_time = data.card_note_end_time + add_second

    local day = math.ceil(data.card_note_end_time / (24 * 60 * 60)) 
    billlog({op="add_item",uid = uid,cur = day,item_id = item_id,item_num = item_num,r = reason})

    return true,{
        curr = data.card_note_end_time,
        chged = add_second
    }
end

local function take_compensation(uid,data)
    billlog({op="bankrupt",uid = uid})

    local ret = can_take_compensation(uid,data)
    if not ret then
        return false
    end
    
    data.compensation_times = data.compensation_times + 1
    data.coins = data.coins + compensation_coins

    return true,{
        curr_coins = data.coins,
        compensation_times = data.compensation_times,
        compensation_coins = compensation_coins,
    }
end

local function can_reduce_item(uid,data,item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return can_reduce_coins(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return can_reduce_gems(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return can_reduce_roomcards(uid,data,item_num,reason) 
    elseif item_id == constant.ITEM_JIABEICARD_ID then
        return can_reduce_jiabeicards(uid,data,item_num,reason)   
    end

    return false
end


local function add_item(uid,data,item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return add_coins(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return add_gems(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return add_roomcards(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_CNOTE_ONE_ID then
        return add_card_note_count(uid,data,item_id,item_num,reason)
    elseif item_id == constant.ITEM_CNOTE_TWO_ID or 
           item_id == constant.ITEM_CNOTE_THREE_ID  then
        return add_card_note_time(uid,data,item_id,item_num,reason)
    elseif item_id == constant.ITEM_JIABEICARD_ID then
        return add_jiabeicards(uid,data,item_id,item_num,reason)
    end

    return false
end

local function reduce_item(uid,data,item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return reduce_coins(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return reduce_gems(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return reduce_roomcards(uid,data,item_num,reason)
    elseif item_id == constant.ITEM_JIABEICARD_ID then
        return reduce_jiabeicards(uid,data,item_id,item_num,reason)
    end
    
    return false
end

local function buy(uid,data,req,reason)
    local cost_item = req.cost_item

    if cost_item.item_id == constant.ITEM_COIN_ID then
        local curr_time = util.get_now_time()
        if curr_time < data.coins_locked then
            return false,error_code.CANNOT_BUY_DURING_PLAYING
        end
    end
    if not can_reduce_item(uid,data,cost_item.item_id,cost_item.item_num,reason)
    then
        return false,error_code.NOT_ENOUGH_GEMS
    end

    if not reduce_item(uid,data,cost_item.item_id,cost_item.item_num,reason) then
        return false,-2
    end

    local bought_item = req.bought_item
    --不一定是买这边的道具
    local bought_id
    local bought_num
    if bought_item then
        add_item(uid,data,bought_item.item_id,bought_item.item_num,reason)
        bought_id = bought_item.item_id
        bought_num = bought_item.item_num
    end

    billlog({
        op="basebuy",uid = uid,cost_id = cost_item.item_id,
        cost_num = cost_item.item_num,bought_id = bought_id,
        bought_num = bought_num
    })

    return true,data
end

local function pay_lost_coins(uid,data,coins,reason,clear)
    local ret,t = reduce_coins(uid,data,coins,reason,clear)
    if ret then
        data.losing_times = data.losing_times + 1
    end

    data.coins_locked = 0

    return ret,t
end

local function give_won_coins(uid,data,coins,reason)
    local ret,t = add_coins(uid,data,coins,reason)
    data.win_times = data.win_times + 1
    data.coins_locked = 0

    return ret,t
end

---------------------------------------------------------------------------
function CMD.get_base_data(uid) sync_run_by_uid(uid,get_base_data) end

function CMD.add_coins(uid,...) sync_run_by_uid(uid,add_coins,...) end
function CMD.reduce_coins(uid,...) sync_run_by_uid(uid,reduce_coins,...) end
function CMD.can_reduce_coins(uid,...) sync_run_by_uid(uid,can_reduce_coins,...) end

function CMD.add_gems(uid,...) sync_run_by_uid(uid,add_gems,...) end
function CMD.reduce_gems(uid,...) sync_run_by_uid(uid,reduce_gems,...) end
function CMD.can_reduce_gems(uid,...) sync_run_by_uid(uid,can_reduce_gems,...) end

function CMD.add_roomcards(uid,...) sync_run_by_uid(uid,add_roomcards,...) end
function CMD.reduce_roomcards(uid,...) sync_run_by_uid(uid,reduce_roomcards,...) end
function CMD.can_reduce_roomcards(uid,...) sync_run_by_uid(uid,can_reduce_roomcards,...) end

function CMD.add_jiabeicards(uid,...) sync_run_by_uid(uid,add_jiabeicards,...) end
function CMD.reduce_jiabeicards(uid,...) sync_run_by_uid(uid,reduce_jiabeicards,...) end
function CMD.can_reduce_jiabeicards(uid,...) sync_run_by_uid(uid,can_reduce_jiabeicards,...) end

function CMD.take_compensation(uid,...) sync_run_by_uid(uid,take_compensation,...) end

function CMD.can_reduce_item(uid,...) sync_run_by_uid(uid,can_reduce_item,...) end
function CMD.add_item(uid,...) sync_run_by_uid(uid,add_item,...) end
function CMD.reduce_item(uid,...) sync_run_by_uid(uid,reduce_item,...) end

function CMD.pay_one_ticket(uid,...) sync_run_by_uid(uid,pay_one_ticket,...) end

function CMD.buy(uid,...) sync_run_by_uid(uid,buy,...) end

function CMD.pay_lost_coins(uid,...) sync_run_by_uid(uid,pay_lost_coins,...) end
function CMD.give_won_coins(uid,...) sync_run_by_uid(uid,give_won_coins,...) end
---------------------------------------------------------------------------


skynet.start(function()
    skynet.dispatch("lua",function(session,addr,action,...)
        print('============got params ...... ',action,...)
        CMD[action](...)
    end)
end)