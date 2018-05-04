local skynet = require "skynet.manager"
local cjson = require "cjson"
local redis = require "redis"
local server_def = require "server_def"
local util = require "util"
local dbdata = require "dbdata"
local constant = require "constant"
local error_code = require "error_code"

local redis_pool

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format

local redis_conf = {}
local cache_connections = {}
local max_cache_connection_num
local allocated_cache_connection_num = 0
local sync_uids = {}

local CMD = {}

function CMD.open(conf)
    local redis_conf = {
        host = assert(conf.redis_host),
        port = assert(conf.redis_port),
        db = assert(conf.redis_db)
    }

    redis_pool = require("redis_pool").new(redis_conf)

    skynet.retpack(true)
end

--------------------------------数据库和缓存相关[begin]--------------------------------------


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
local function make_user_key(uid,game_type)
    return string_format('fuser_self_%d_%d',game_type,uid)
end

local function get_user_ftable_info(uid,conn,game_type)
    local key = make_user_key(uid,game_type)
    local num = conn:hlen(key)
    skynet.retpack({num = num})
end

local function make_user_entered_key(uid,game_type)
    return string_format('fuser_entered_%d_%d',game_type,uid)
end

local function lock_for_creating(uid,conn,criteria)

end

local function unlock_and_add_ftable(uid,conn,password)

end

local function add_self_ftable(uid,conn,password,update_time,game_type)
    dbglog(uid,'add_self_ftable ====',password,update_time)
    local key = make_user_key(uid,game_type)
    conn:hset(key,password,update_time)

    local key = make_user_entered_key(uid,game_type)
    conn:hset(key,password,update_time)

    skynet.retpack(true)
end

local function update_entered_ftable(uid,conn,password,update_time,game_type)
    dbglog(uid,'update_entered_ftable ====',password,update_time)
    local key = make_user_entered_key(uid,game_type)
    conn:hset(key,password,update_time)
    skynet.retpack(true)
end

local function get_entered_ftables(uid,conn,game_type)
    dbglog(uid,'get_entered_ftables ====')
    local key = make_user_entered_key(uid,game_type)
    local ret = conn:hgetall(key)
    skynet.retpack(ret)
end

local function del_records(uid,conn,subkeys,game_type)
    dbglog(uid,'del_records ====',table.concat(subkeys, ", "))
    local key = make_user_entered_key(uid,game_type)
    conn:hdel(key,table_unpack(subkeys))
    skynet.retpack(true)
end

local function del_self_ftable(uid,conn,password,game_type)
    dbglog(uid,'del_self_ftable ====',password,update_time)
    local key = make_user_key(uid,game_type)
    conn:hdel(key,password)
    skynet.retpack(true)
end
---------------------------------------------------------------------------
function CMD.get_user_ftable_info(uid,...) sync_run_by_uid(uid,get_user_ftable_info,...) end
function CMD.lock_for_creating(uid,...) sync_run_by_uid(uid,lock_for_creating,...) end
function CMD.unlock_and_add_ftable(uid,...) sync_run_by_uid(uid,unlock_and_add_ftable,...) end
function CMD.add_self_ftable(uid,...) sync_run_by_uid(uid,add_self_ftable,...) end
function CMD.update_entered_ftable(uid,...) sync_run_by_uid(uid,update_entered_ftable,...) end
function CMD.get_entered_ftables(uid,...) sync_run_by_uid(uid,get_entered_ftables,...) end
function CMD.del_records(uid,...) sync_run_by_uid(uid,del_records,...) end
function CMD.del_self_ftable(uid,...) sync_run_by_uid(uid,del_self_ftable,...) end
---------------------------------------------------------------------------

skynet.start(function()
    skynet.dispatch("lua",function(session,addr,action,...)
        print('============got params ...... ',action,...)
        CMD[action](...)
    end)
end)