local skynet = require "skynet"
local redis = require "redis"

local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local string_format = string.format
local xpcall = xpcall

local function execute_redis_cmd(f,...)
    local ok,ret = xpcall(f,debug.traceback,...)
    while not ok do
        errlog(ret)
        skynet.sleep(100)
        print('now retry....')
        ok,ret = xpcall(f,debug.traceback,...)
    end
    return ret
end

local CONN_MT = {
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
    return setmetatable({conn = conn}, CONN_MT)
end

local function get_conn_from_pool(self)
    local connections = self.connections
    if #connections > 0 then
        return table_remove(connections)
    end

    while self.allocated_connection_num >= self.max_connection_num do
        --超上限了，唯有空转等了
        errlog('there is no connection for reusing, waiting for one reused connection')
        skynet.sleep(5)
        if #connections > 0 then
            return table_remove(connections)
        end
    end

    local redis_conf = self.redis_conf
    local ok,ret = xpcall(redis.connect,debug.traceback,redis_conf)
    while not ok do
        errlog('failed to connect redis',ret)
        skynet.sleep(100)   --one second
        ok,ret = xpcall(redis.connect,debug.traceback,redis_conf)
    end

    local conn = conn_wrapper(ret)
    self.allocated_connection_num = self.allocated_connection_num + 1
    return conn
end

local function putback_to_pool(self,conn)
    table_insert(self.connections,conn)
end


local PMT = {}
PMT.get_conn_from_pool = get_conn_from_pool
PMT.putback_to_pool = putback_to_pool

PMT.__index = PMT

local M = {}

function M.new(conf)
    local redis_conf = {
        host = conf.host,
        port = conf.port,
        db = conf.db,
    }

    local pool = {
        redis_conf = redis_conf,
        connections = {},
        max_connection_num = conf.max_connection_num or 100,
        allocated_connection_num = 0,
    }

    return setmetatable(pool,PMT)
end

return M