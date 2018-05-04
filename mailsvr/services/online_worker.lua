local skynet = require "skynet"
local cjson = require "cjson"
local redis = require "redis"

local playing_number = 0
local online_number = 0

local function load_hall_config(conf_path)
	assert(conf_path,'invalid router configuration path')
	local conf = assert(loadfile(conf_path)())
	local hallsvr_config = assert(conf.hallsvr)
	local tablesvr_config = assert(conf.tablesvr)
	local hall_map = {}
	for _,hallsvr_id in pairs(hallsvr_config) do
		hall_map[hallsvr_id] = true
	end
	local table_map = {}
	for _,tablesvr_id in pairs(tablesvr_config) do
		table_map[tablesvr_id] = true
	end
	return {hall_map = hall_map,table_map = table_map}
end

local function execute_redis_cmd(...)
    local ok,ret = pcall(...)
    while not ok do
        skynet.error(ret)
        print(ret)
        skynet.sleep(100)
        print('now retry....')
        ok,ret = pcall(...)
    end
    return ret
end

local function log_online_and_playing_number(router_config)
	online_number = 0
	for hallsvr_id,_ in pairs(router_config.hall_map) do
		local ok,count = R().hallsvr(hallsvr_id):call('.msg_handler','get_agent_count')
		if not ok then
			errlog('failed to query_online_player_count',hallsvr_id)
			count = 0
		end
		online_number = online_number + count 
	end

	playing_number = 0
	for tablesvr_id,_ in pairs(router_config.table_map) do
		local ok,count = R().tablesvr(tablesvr_id):call('.table_mgr','get_playing_player_count')
		if not ok then
			errlog('failed to query_playing_player_count',tablesvr_id)
			count = 0
		end
		playing_number = playing_number + count
	end

	billlog({
		op = "online_and_playing_number",
		online_number = online_number,
		playing_number = playing_number
	})
end

local function routine_check_online_and_palying_player(router_config)
    while true do
        local ok,ret = pcall(log_online_and_playing_number,router_config)
        if not ok then
            errlog(ret)
        end
        skynet.sleep(10 * 100)
    end
end

local function routine_save_online_data_on_redis(redis_conn)
    while true do
        local data = cjson.encode({online_num = online_number,playing_num = playing_number})
        execute_redis_cmd(redis_conn.set,redis_conn,'online_data',data)
        --print("22222222222222222222")
        skynet.sleep(10 * 100)
    end
end

local CMD = {}

local function init()
	local router_config = load_hall_config(skynet.getenv "router_path")
	skynet.fork(routine_check_online_and_palying_player,router_config)

	local redis_conf = {}
	redis_conf.host = skynet.getenv "log_redis_host"
    redis_conf.port = tonumber(skynet.getenv "log_redis_port")
    redis_conf.db   = tonumber(skynet.getenv "log_redis_db")

	local redis_conn = redis.connect(redis_conf)
	skynet.fork(routine_save_online_data_on_redis,redis_conn)
end

function CMD.start()
	init()
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)
end)
