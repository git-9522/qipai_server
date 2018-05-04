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


local redis_conf = {}
local cache_connections = {}
local max_cache_connection_num
local allocated_cache_connection_num = 0

local CMD = {}

local function execute_redis_cmd(f,...)
    local ok,ret = xpcall(f,debug_traceback,...)
    while not ok do
        errlog(ret)
        skynet.sleep(100)
        print('now retry....')
        ok,ret = xpcall(f,debug_traceback,...)
    end
    return ret
end

local conn_mt = {
    __index = function(t,k)
        return function(t,...)
            return execute_redis_cmd(t.conn[k],t.conn,...)
        end
    end,
    __tostring = function(t)
        return tostring(t.conn)
    end
}

local function conn_wrapper(conn)
    return setmetatable({conn = conn}, conn_mt)
end

local function get_conn_from_pool()
    if #cache_connections > 0 then
        return table_remove(cache_connections)
    end

    while allocated_cache_connection_num >= max_cache_connection_num do
        --超上限了，唯有空转等了
        skynet.sleep(5)
        if #cache_connections > 0 then
            return table_remove(cache_connections)
        end
    end

    local ok,ret = pcall(redis.connect,redis_conf)
    while not ok do
        errlog('failed to connect redis',ret)
        skynet.sleep(100)
        ok,ret = pcall(redis.connect,redis_conf)
    end

    local conn = conn_wrapper(ret)
    allocated_cache_connection_num = allocated_cache_connection_num + 1
    return conn
end

local function putback_to_pool(conn)
    table_insert(cache_connections,conn)
end

function CMD.start()
    redis_conf.host = skynet.getenv "ontable_redis_host"
    redis_conf.port = tonumber(skynet.getenv "ontable_redis_port")
    redis_conf.db = tonumber(skynet.getenv "ontable_redis_db")

    max_cache_connection_num = tonumber(skynet.getenv "max_cache_connection_num") or 100

    -- local pre_alloc = tonumber(skynet.getenv "pre_alloc") or 2
    -- for i = 1,pre_alloc do
    --     table_insert(cache_connections,redis.connect(redis_conf))
    -- end

    allocated_cache_connection_num = 0

    skynet.retpack(true)
end

--------------------------------数据库和缓存相关[begin]--------------------------------------

---------------------------------------数据存取相关------------------------------------
local function run(f,...)
    local conn = get_conn_from_pool()
    local ok,ret = xpcall(f,debug.traceback,conn,...)
    putback_to_pool(conn)
    if not ok then errlog(ret) end
end
-----------------------------------协议-----------------------------------------
local function make_on_table_key(uid)
    return string_format('ontable_%d',uid)
end

local LOCK_TIMEOUT_INSEC = 5
local LOCK_LUA_CODE = [[
    local key = KEYS[1]
    if redis.call('get',key) then
        return 0
    end

    redis.call('setex',key,tonumber(ARGV[2]),ARGV[1])
    return 1
]]

local function lock_on_table(conn,uid)
    local key = make_on_table_key(uid)
    local rr = tonumber(conn:eval(LOCK_LUA_CODE,1,key,0,LOCK_TIMEOUT_INSEC))
    local result = false
    if rr == 1 then
        result = true
    end
    skynet.retpack(result)
end

local SET_ON_TABLE_LUA_CODE = [[
    local tonumber = tonumber
    local key = KEYS[1]
    local locked_val = tonumber(ARGV[3])
    local r = redis.call('get',key)
    if not r or tonumber(r) == locked_val then
        redis.call('setex',key,tonumber(ARGV[2]),ARGV[1])
        return 1
    end
    return 0
]]
local ONTABLE_TIMEOUT_INSEC = 7200
local function set_on_table(conn,uid,table_gid,locked_val)
    local key = make_on_table_key(uid)
    local rr = tonumber(conn:eval(SET_ON_TABLE_LUA_CODE,1,key,
        tostring(table_gid),ONTABLE_TIMEOUT_INSEC,locked_val or 0))
    local result = false
    if rr == 1 then
        result = true
    end
    print('ffffffffffffffffffffffffffff',result,uid,table_gid,tostring(rr))
    skynet.retpack(result)
end

local UNSET_ON_TABLE_LUA_CODE = [[
    local key = KEYS[1]
    local locked_val = tonumber(ARGV[1])
    local r = tonumber(redis.call('get',key))
    if r ~= locked_val then
        return 0
    end
    redis.call('del',key)
    return 1
]]
local function unset_on_table(conn,uid,table_gid)
    local key = make_on_table_key(uid)
    local rr = tonumber(conn:eval(UNSET_ON_TABLE_LUA_CODE,1,key,table_gid))
    local result = false
    if rr == 1 then
        result = true
    end
    skynet.retpack(result)
end

local function get_player_table(conn,uid)
    local key = make_on_table_key(uid)
    local r = tonumber(conn:get(key)) or 0
    skynet.retpack(r)
end
---------------------------------------------------------------------------
function CMD.lock_on_table(...) return run(lock_on_table,...) end
function CMD.set_on_table(...) return run(set_on_table,...) end
function CMD.unset_on_table(...) return run(unset_on_table,...) end
function CMD.get_player_table(...) return run(get_player_table,...) end
---------------------------------------------------------------------------


skynet.start(function()
    skynet.dispatch("lua",function(_,_,action,...)
        print('============got params ...... ',action,...)
        CMD[action](...)
    end)
end)