local util = require "util"
local socket = require "socket"
local skynet = require "skynet.manager"
local server_def = require "server_def"
local error_code = require "error_code"

local table_sort = table.sort
local table_insert = table.insert
local table_remove = table.remove

local MATCH_INTERVAL = 30
local TABLE_LIMIT = tonumber(skynet.getenv "table_limit") or 1000
local MAX_MATCH_TIME = tonumber(skynet.getenv "max_match_time") or 10
local DEBUG = skynet.getenv "DEBUG" or false

local MAX_PLAYER_NUM = 3
local server_start_time = 0
local asyn_data_time = 0

local CMD 					= {}
local match_data_list       = {}
local matched_list          = {}
local player_match_type_map = {}
local player_table_map      = {}
local table_players_map     = {}
local tablesvr_table_num    = {}
local closing_tablesvr_map  = {}

--------------------关注该session的连接情况----------------
local function watch_session(game_session,uid,observing)
    local gateway_id = game_session >> 31
    local request
    if observing then
        request = 'observe_fd'
    else
        request = 'unobserve_fd'
    end

    R().gateway(gateway_id):send('.watchdog','common',request,R().get_source(),
		game_session,uid,'.table_mgr')
end

local function send_data_to_player(uid,...)
	R().hallsvr{key=uid}:send('.msg_handler','toagent',uid,...)
end

function CMD.report_table_stats(server_id,curr_table_num,closing)
	tablesvr_table_num[server_id] = curr_table_num
	closing_tablesvr_map[server_id] = closing
end

local function match_sort(a,b)
	return a.coins < b.coins
end

local function cancel(uid)
	local table_type = player_match_type_map[uid]
	if not table_type then
		errlog("player is already in match  list!!!",uid)
		--玩家不在记录里，可能已经取消过了
		return true
	end
	
	local match_list = assert(match_data_list[table_type])
	for i,user_data in pairs(match_list) do
		if user_data.uid == uid then
			table_remove(match_list,i)
			player_match_type_map[uid] = nil
			dbglog("delete player from match_list sucess!!!")
			return true
		end
	end

	return false
end

function CMD.cancel_matching_player(uid)
	local result = cancel(uid)
	return skynet.retpack(result)
end

local function _match_player(user_data)
	local uid = user_data.uid
	--玩家在桌子上打牌
	local table_gid = player_table_map[user_data.uid]
	if table_gid then
		dbglog(uid,'this player is already in matching')
		return false
	end

	--玩家已经在匹配队列里面
	if player_match_type_map[uid] then
		dbglog(uid,"player is already in match  list!!!")
		return false
	end

	if not match_data_list[user_data.match_type] then
		match_data_list[user_data.match_type] = {}
	end

	table_insert(match_data_list[user_data.match_type],user_data)
	--TODO 是否可以定时排序？？？？
	table_sort(match_data_list[user_data.match_type],match_sort)

	player_match_type_map[uid] = user_data.match_type

	--增加网关关注事件
	return true
end

function CMD.match_player(user_data)
	local ok = _match_player(user_data)
	return skynet.retpack(MATCH_INTERVAL)
end

local function select_one_table_server()
	local candidate_svr_id,least_table_num = next(tablesvr_table_num)
	--策略是选一个最少桌子数的tablesvr
	for tablesvr_id,table_num in pairs(tablesvr_table_num) do
		if table_num < TABLE_LIMIT and not closing_tablesvr_map[tablesvr_id] then
			if table_num < least_table_num then
				least_table_num = table_num
				candidate_svr_id = tablesvr_id
			end
		end
	end	

	return candidate_svr_id
end

local function match_player_on_a_table(end_index,match_type_list,table_type)
	local real_end_index
	for i=1,end_index,MAX_PLAYER_NUM do
		local tablesvr_id = select_one_table_server()
		if not tablesvr_id then
			errlog("cant find available table server")
			break
		end

		local tmp_table = {match_type_list[i],match_type_list[i+1],match_type_list[i+2]}
		local matched_gid = tablesvr_id << 32 | table_type
		table_insert(matched_list,{gid = matched_gid,users_data = tmp_table})
	
		real_end_index = i + 2
	end

	if not real_end_index then
		dbglog('there is not any handled players')
		return
	end

	--考虑到人数不足的情况
	if real_end_index > end_index then
		real_end_index = end_index
	end

	dbglog('ffffffffffffff',real_end_index,tostring_r(match_type_list))
	for i=1,real_end_index do
		local m = assert(match_type_list[i])
		player_match_type_map[m.uid] = nil
	end

	for i = 1,real_end_index do
		table_remove(match_type_list,1)
	end
end

local function match_player(table_type,match_type_list)
	--大于三人的时候,三人凑一桌
	if #match_type_list  >= MAX_PLAYER_NUM then
		local end_index = math.floor(#match_type_list / MAX_PLAYER_NUM) * MAX_PLAYER_NUM
		match_player_on_a_table(end_index,match_type_list,table_type)
	end

	--少于三人的情况,有人超过等待时间,就凑一桌
	assert(#match_type_list >= 0 and #match_type_list < MAX_PLAYER_NUM)

	local time_out = false
	local now = util.get_now_time()
	for _,v in pairs(match_type_list) do
		if now - v.begin_time >= MAX_MATCH_TIME then
			time_out = true
		end
	end
	if time_out then
		match_player_on_a_table(#match_type_list,match_type_list,table_type)
	end
end

local function register_player_on_table(tablesvr_id,table_data,users_data)
	--TODO 这里先去临时锁住每一个玩家,以免坑了tablesvr,
	--要保证这里能tablesvr的都是已经不在其它桌子上的，例如好友房

	dbglog('==================================',tostring_r(users_data))
	local dest = R().tablesvr(tablesvr_id):dest()
	local ok,result = R().dest(dest):call('.table_mgr','register_all',table_data,users_data)
	if not ok then
		errlog(uid,'failed to register player on table ',ok,result,tostring_r(users_data))
    	return
	end

	tablesvr_table_num[tablesvr_id] = assert(tablesvr_table_num[tablesvr_id],'invalid tablesvr ' .. tablesvr_id) + 1

	if result <= 0 then
		--匹配失败，不响应给玩家
		errlog(uid,'failed to register players on table',result,tostring_r(users_data))
		return
	end

	--记录玩家的桌子信息,桌子的玩家信息
	for _,user_data in pairs(users_data) do
		local uid = user_data.uid
		send_data_to_player(uid,"report_player_matched",dest,result)
	end
	
	return true
end

local function safe_register(...)
	--注册玩家
	local ok,ret = xpcall(register_player_on_table,debug.traceback,...)
	if not ok then
		errlog(uid,'failed to register_player_on_table',ret)
	end
end

local function handle_matched_player()
	if DEBUG and next(matched_list) then
		print_r(matched_list)
	end

	local match_data = table_remove(matched_list,1)
	while match_data do
		local tablesvr_id = match_data.gid >> 32
		local table_data = {
			table_type = match_data.gid & 0xffffffff,
	    }

		skynet.fork(safe_register,tablesvr_id,table_data,match_data.users_data)

		match_data = table_remove(matched_list,1)
	end
end

local function match_runable()
	while true do
        for table_type,match_type_list in pairs(match_data_list) do
        	match_player(table_type,match_type_list)
        end

        handle_matched_player()

        skynet.sleep(100) 
    end
end

local function asyn_data_runable()
	local phase_swith_time = tonumber(skynet.getenv "phase_swith_time")
	local last_sync_time = 0
	while true do
		local now = util.get_now_time()
		local interval = now - last_sync_time
		local phase = now - server_start_time

		if (phase <= phase_swith_time and interval >= 5) or
			phase > phase_swith_time and interval >= 60 then
			last_sync_time = now
			R().tablesvr():broadcast('.table_mgr','get_table_stats',R().get_source(),
				'.table_mgr',server_start_time)
		end

		skynet.sleep(500) --5 seconds
	end
end

function CMD.start()
	server_start_time = util.get_now_time()

	skynet.fork(asyn_data_runable)
	skynet.fork(match_runable)

	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua",function(_,_,cmd, ...)
		print("seq,cmd, ...===========",cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)
end)


