local skynet = require "skynet.manager"
local cjson = require "cjson"
local table_insert = table.insert
local table_remove = table.remove
local string_format = string.format

--[[
该模块做的事情就是从mongodb读出数据，写到redis中并返回给其它服务,
持久化的工作可通过消息队列的方式让外部程序去写
--]]
local sync_uids = {}

local CMD = {}

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

local function sync_run_by_uid(uid,f)
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

    local ok,err = xpcall(f,debug.traceback)
    if not ok then errlog(err) end

    --再接着调度
    local waiting_list = sync_uids[uid]
    if waiting_list == true or #waiting_list == 0 then
        sync_uids[uid] = nil
        return
    end    

    local co = table_remove(waiting_list,1)
    skynet.wakeup(co)
end

--先把数据写入,再做一个写标记，切记不可调换。用脚本同时可保证数据写入的原子性
local update_redis_script = [[
    redis.call('set',KEYS[1],ARGV[1])
    redis.call('select',KEYS[2])
    redis.call('hincrby',KEYS[3],ARGV[2],ARGV[3])
]]

local function fetch_or_insert(uid,default_data)
    sync_run_by_uid(uid,function()
        --先查redis,假如redis没有数据，再去mongodb查
        local conn = redis_pool:get_conn_from_pool()
        local key = string_format('data_%d',uid)
        local data = conn:get(key)
        if data then
            data = cjson.decode(data)
        else
            --缓存没命中，在数据库里？我们需要到mongodb上找去
            data = select_from_mongodb(uid)
            dbglog('ffffffffffffffffffffffffff data from mongodb',data)
            local str_data
            if not data then
                --数据库也没有，这是一个新玩家，我们用默认的数据吧
                data = cjson.decode(default_data)
                str_data = default_data
                conn:eval(update_redis_script,3,key,dirty_queue_db,
                    dirty_queue_key,str_data,uid,1)
            else
                str_data = cjson.encode(data)
                --必须写到缓存中去
                conn:set(key,str_data)
            end
        end

        redis_pool:putback_to_pool(conn)
        --先返回给对端会话
        skynet.retpack(data)
    end)
end

CMD.fetch_or_insert = fetch_or_insert

function CMD.update(uid,data)
    sync_run_by_uid(uid,function()
        --先查redis,假如redis没有数据，再去mongodb查
        local conn = redis_pool:get_conn_from_pool()
        local key = string_format('data_%d',uid)

        --再做一个写标记，切记不可调换
        conn:eval(update_redis_script,3,key,dirty_queue_db,
            dirty_queue_key,data,uid,1)

        redis_pool:putback_to_pool(conn)
        --先返回给对端会话
        skynet.retpack(true)
    end)
end

skynet.start(function()
    skynet.dispatch("lua",function(session,addr,action,...)
        print('got params ...',action,...)
        CMD[action](...)
    end)
end)

