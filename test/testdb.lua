local skynet = require "skynet"
local cjson = require "cjson"

skynet.start(function()
	local data_worker = skynet.newservice('data_worker')
    skynet.call(data_worker,'lua','open',{
        redis_host = '127.0.0.1',
        redis_port = 6379,
        redis_db = 1,
        dirty_queue_db = 7,
        dirty_queue_key = 'writable_uid_queue',

        db_host = '127.0.0.1',
        db_port = 29991,
        db_name = 'ddz',
        db_coll_name = 'user'
    })

    local default = {
        name = 'helloworld',
        uid = 9999
    }
    for i = 1,10 do
    local ret = skynet.send(data_worker,'lua','fetch_or_insert',9999,cjson.encode(default))
    print(type(ret))
    print_r(ret)

    print(skynet.call(data_worker,'lua','update',9999,cjson.encode(default)))
    end
end)

