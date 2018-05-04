local skynet = require "skynet.manager"
local cjson = require "cjson"
local redis = require "redis"
local server_def = require "server_def"
local util = require "util"
local dbdata = require "dbdata"
local constant = require "constant"
local error_code = require "error_code"

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format
local tonumber = tonumber
local pcall = pcall
local debug_traceback = debug.traceback

local redis_pool
local sync_uids = {}

local CMD = {}


function CMD.start()
    local redis_conf = {
        host = skynet.getenv "ftable_redis_host",
        port = tonumber(skynet.getenv "ftable_redis_port"),
        db = tonumber(skynet.getenv "ftable_redis_db"),
    }

    redis_pool = require("redis_pool").new(redis_conf)

    skynet.retpack(true)
end

--------------------------------并发控制相关[begin]-------------------------------
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
    local ok,ret = xpcall(f,debug.traceback,uid,conn,...)
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

-----------------------------------协议-----------------------------------------
local function make_ftable_key(password)
    return string_format('kftable_%d',password)
end

local function get_password_from_key(key)
    return tonumber(key:sub(#'kftable_' + 1))
end

local function save_ftable_info(password,conn,table_info)
    print('saved the table info',password,tostring_r(table_info))
    local key = make_ftable_key(password)
    local value = cjson.encode(table_info)
    conn:set(key,value)
    skynet.retpack(true)
end

local function load_all_ftables(_,conn)
    local keys = conn:keys('kftable_*')
    local password_list = {}
    for _,k in pairs(keys) do
        local password = get_password_from_key(k)
        local value = conn:get(make_ftable_key(password))
        if value then
            local table_info = cjson.decode(value)
            password_list[password]  = table_info.created_time
        else
            errlog('could not find table info for password',password)
        end
    end
    skynet.retpack(password_list)
end

local function get_ftable(password,conn)
    local key = make_ftable_key(password)
    local value = conn:get(key)
    if not value then
        return skynet.retpack()
    end
    local table_info = cjson.decode(value)
    return skynet.retpack(table_info)
end

local function make_frecord_key(password)
    return string_format('frecord_%d',password)
end

local FTABLE_DETAIL_LUA = [[
    local ftable_key = KEYS[1]
    local frecord_key = KEYS[2]
    local result = redis.call('get',ftable_key)
    local len = redis.call('llen',frecord_key)
    return {result,len}
]]
local function get_ftable_detail(password,conn)
    local ftable_key = make_ftable_key(password)
    local frecord_key = make_frecord_key(password)
    local ret = conn:eval(FTABLE_DETAIL_LUA,2,ftable_key,frecord_key)
    if not ret then
        errlog(password,'invalid ftable record')
        return skynet.retpack()
    end

    assert(#ret == 2,'invalid password ' .. tostring(password))

    local table_data = ret[1]
    local curr_round = ret[2]

    local table_info = cjson.decode(table_data)
    table_info.curr_round = tonumber(curr_round)

    return skynet.retpack(table_info)
end

local function save_round_records(password,conn,conf)
    local data = cjson.encode(conf)
    print("+++++",tostring_r(data))
    local key = make_frecord_key(password)
    conn:rpush(key,data)
    skynet.retpack(true)
end

local DISMISS_LUA = [[
    local frecord_key = KEYS[1]
    local ftable_key = KEYS[2]
    local r = redis.call('lrange',frecord_key,0,-1)
    redis.call('del',frecord_key)
    local r2 = redis.call('get',ftable_key)
    redis.call('del',ftable_key)
    table.insert(r,r2)

    return r
]]

local function make_record_key(password)
    return string_format('finish_%s_%d',os.date("%Y%m%d%H%M%S"),password)
end

local function dismiss_table(password,conn)
    local frecord_key = make_frecord_key(password)
    local ftable_key = make_ftable_key(password)
    local records = conn:eval(DISMISS_LUA,2,frecord_key,ftable_key)
    if not records then
        return skynet.retpack(false)
    end
    
    local table_info = table.remove(records)
    if not table_info then
        errlog(password,'invalid records')
        return skynet.retpack(false)
    end
    table_info = cjson.decode(table_info)
    if #records < 1 then
        return skynet.retpack(true,table_info)
    end

    local record_info = cjson.decode(records[1])
    local uid_list = {}
    for _,o in pairs(record_info.round_info) do
        table_insert(uid_list,o.uid)
    end
    table_info.finish_time = util.get_now_time()
    local round_list = {} 
    for i=1,#records do
        local round_info = cjson.decode(records[i])
        table_insert(round_list,round_info)
    end
    table_info.round_list = round_list
    
    local data = cjson.encode(table_info)
    dbglog(data)

    local record_key = make_record_key(password) 
    local time_val = 3*86400
    conn:setex(record_key,time_val,data)

    table_info.round_list = nil

    table_info.record_key = record_key
    table_info.uid_list = uid_list

    return skynet.retpack(true,table_info)
end

local function get_records_from_key(_,conn,keys)
    local records = {}
    for i=1,#keys do
        local record = conn:get(keys[i])
        if record then
            table_insert(records,record)
        end
    end
    return skynet.retpack(records)
end

---------------------------------------------------------------------------
function CMD.save_ftable_info(password,...) sync_run_by_uid(password,save_ftable_info,...) end
function CMD.load_all_ftables(...) sync_run_by_uid(0,load_all_ftables,...) end
function CMD.get_ftable(password,...) sync_run_by_uid(password,get_ftable,...) end
function CMD.save_round_records(password,...) sync_run_by_uid(password,save_round_records,...) end
function CMD.dismiss_table(password,...) sync_run_by_uid(password,dismiss_table,...) end
function CMD.get_records_from_key(...)  sync_run_by_uid(0,get_records_from_key,...) end
function CMD.get_ftable_detail(password,...)  sync_run_by_uid(password,get_ftable_detail,...) end
---------------------------------------------------------------------------


skynet.start(function()
    skynet.dispatch("lua",function(_,_,action,...)
        print('============got params ...... ',action,...)
        CMD[action](...)
    end)
end)