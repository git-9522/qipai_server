local skynet = require "skynet"
local mongo = require "mongo"

local table_insert = table.insert
local table_remove = table.remove
local xpcall = xpcall

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

    local mongo_conf = self.mongo_conf
    local ok,ret = xpcall(mongo.client,debug.traceback,mongo_conf)
    while not ok do
        errlog('failed to connect mongo',ret)
        skynet.sleep(100)   --one second
        ok,ret = xpcall(mongo.client,debug.traceback,mongo_conf)
    end

    self.allocated_connection_num = self.allocated_connection_num + 1
    return ret
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
    local mongo_conf = {
        host = conf.host,
        port = conf.port,
        username = conf.username,
        password = conf.password,
    }

    local pool = {
        mongo_conf = mongo_conf,
        connections = {},
        max_connection_num = conf.max_connection_num or 100,
        allocated_connection_num = 0,
    }

    return setmetatable(pool,PMT)
end

return M