local util = require "util"
local utils = require "utils"
local skynet = require "skynet"
local server_def = require "server_def"
local reason = require "reason"
local sync_run = require "sync_runner"
local table_def = require "table_def"

local table_sort = table.sort
local table_insert = table.insert
local table_remove = table.remove
local table_unpack = table.unpack
local math_random = math.random
local string_format = string.format

local TABLE_LIMIT = tonumber(skynet.getenv "table_limit") or 1000
local DEBUG = skynet.getenv "DEBUG" or false

local locked_uids = {}
local server_start_time = 0
local asyn_data_time = 0
local ftable_start_list = {}	--已经开始的房间列表
local CMD = {}

--同步当前tablesvr的桌子数
local tablesvr_table_num = {}

local fuser_handler
local ftable_handler

local USER_FTABLE_NUM_LIMIT = skynet.getenv "user_ftable_num_limit" or 10	--限制玩家开房数

local TABLE_EXPIRY_TIME = skynet.getenv "friend_table_expiry_time" or 7200	--两个小时过期
local TABLE_UNSTART_EXPIRY_TIME = skynet.getenv "friend_table_unstart_expiry_time" or 3600 --一个小时过期

local expiry_checking_list

local candidate_password_list = {}
local being_used_password_list = {}

local function gen_table_password_list()
	candidate_password_list = {}

	for i=100000,999999 do
		if not being_used_password_list[i] then
			table_insert(candidate_password_list,i)
		end
	end
end

local function create_a_password()
	local len = #candidate_password_list
	if len < 1 then
		errlog('Congratulations!!,there is no enough password for creating table...')
		return
	end

	local index = math_random(1,len)
	local password = candidate_password_list[index]
	if index ~= len then
		candidate_password_list[index] = candidate_password_list[len]
	end
	table_remove(candidate_password_list)
	assert(not being_used_password_list[password],
		string_format('password already existing <%d>',password))
	being_used_password_list[password] = 0

	return password
end

local function set_password_tgid(password,tgid)
	assert(being_used_password_list[password] == 0)
	being_used_password_list[password] = tgid
end
--密码回收
local function recycle_password(password)
	assert(being_used_password_list[password],
		string_format('password is not existing <%d>',password))
	being_used_password_list[password] = nil
	table_insert(candidate_password_list,password)
end

local function select_one_table_server()
	for tablesvr_id,table_num in pairs(tablesvr_table_num) do
		if table_num < TABLE_LIMIT then
			return tablesvr_id
		end
	end	
end

local function reduce_roomcards(uid,roomcards)
    local ok,succ,ret = R().basesvr({key=uid}):call('.msg_handler','reduce_roomcards',uid,roomcards)
    if not ok then
        errlog(uid,'failed to reduce_roomcards')
        return
    end

	if not succ then
		errlog(uid,'no enough room cards')
		return
	end

    return true
end

local function create_table_on_tablesvr(tablesvr_id,uid,table_info,password)
	table_info.expiry_time = table_info.created_time + TABLE_EXPIRY_TIME
	table_info.unstart_expiry_time = table_info.created_time  + TABLE_UNSTART_EXPIRY_TIME
	local ok,ret = R().tablesvr(tablesvr_id):call('.table_mgr',
		'create_ftable',uid,table_info,password)
	table_info.expiry_time = nil
	table_info.unstart_expiry_time = nil
	if not ok then
		errlog(uid,'failed to create_table_on_tablesvr',tablesvr_id,password)
		return
	end

	if not ret or ret < 0 then
		errlog(uid,'failed to create_table_on_tablesvr',tablesvr_id,password,ret)
		return
	end
	
	return ret
end

--[[
	ddz_table_conf = {
		table_type = msg.table_type,
        set_dizhu_way = msg.set_dizhu_way,
        max_dizhu_rate = msg.max_dizhu_rate,
        count = msg.count,
        can_watch = msg.can_watch,
        cost = cost,
	}
]]

local function make_table_info(uid,created_time,password,table_conf)
	local table_info = {
		creator_uid = uid,
		created_time = created_time,
		password = password,
		curr_round = 0,
		table_type = table_conf.table_type,
		cost = table_conf.cost,
	}

	if table_def.ddz_ftable_map[table_conf.table_type] then
		table_info.set_dizhu_way = table_conf.set_dizhu_way
		table_info.max_dizhu_rate = table_conf.max_dizhu_rate
		table_info.count = table_conf.count
		table_info.can_watch = table_conf.can_watch
	end

	if table_def.xuezhan_ftable_map[table_conf.table_type] then
		table_info.total_count = table_conf.total_count
        table_info.limit_rate  = table_conf.limit_rate
		table_info.zimo_addition = table_conf.zimo_addition
        table_info.dianganghua   = table_conf.dianganghua
        table_info.exchange_three = table_conf.exchange_three
        table_info.hujiaozhuanyi = table_conf.hujiaozhuanyi
        table_info.daiyaojiu = table_conf.daiyaojiu
        table_info.duanyaojiu = table_conf.duanyaojiu
        table_info.jiangdui = table_conf.jiangdui
        table_info.mengqing = table_conf.mengqing
        table_info.tiandi_hu = table_conf.tiandi_hu
        table_info.haidilaoyue = table_conf.haidilaoyue
        table_info.base_score = table_conf.base_score
	end

	return table_info
end

local function _create_ftable(uid,tablesvr_id,table_conf,password,game_type)
	local created_time = util.get_now_time()
	local table_info = make_table_info(uid,created_time,password,table_conf)
	local table_gid = create_table_on_tablesvr(tablesvr_id,uid,table_info,password)
	if not table_gid then
		errlog(uid,'failed to create_table_on_tablesvr',tablesvr_id,password,table_gid)
		return -40
	end

	--建房成功了，开始扣房卡
	if not reduce_roomcards(uid,table_info.cost) then
		errlog(uid,'failed to reduce_roomcards',table_info.cost)
		return -30
	end

	local ok,done = R().exdbsvr(1):call(ftable_handler,'save_ftable_info',password,table_info)
	if not ok then
		errlog(uid,'failed to save_ftable_info',tablesvr_id,password,tostring_r(table_info))
		return -50
	end
	if not done then
		errlog(uid,'failed to save_ftable_info not done',password)
		return -55
	end

	--更新个人好友房创房记录
	local ok,done = R().exdbsvr(1):call(fuser_handler,'add_self_ftable',uid,password,created_time,game_type)
	if not ok then
		errlog(uid,'failed to add_self_ftable',password)
		return -60
	end
	if not done then
		errlog(uid,'failed to add_self_ftable not done',password)
		return -70
	end

	return table_gid
end

local function create_ftable(uid,table_conf)
	local tablesvr_id = select_one_table_server()
	if not tablesvr_id then
		errlog(uid,"cant find available table server on create table")
		return -10
	end

	local game_type = assert(table_def.table_game_map[table_conf.table_type],"this room in not exits in def")
	print("game_type",game_type)
	--检查下玩家的房间是否超上限
	local ok,ret = R().exdbsvr(1):call(fuser_handler,'get_user_ftable_info',uid,game_type)
	if not ok then
		errlog(uid,'failed to get_user_ftable_info')
		return -15
	end
	
	if ret.num >= USER_FTABLE_NUM_LIMIT then
		errlog(uid,"this guy've opened too much tables...",ret.num)
		return -20
	end

	if ret.locked then
		--点击太快，请重试
		errlog(uid,'the user table creation is locked')
		return -21
	end

	local password = create_a_password()
	if not password then
		errlog(uid,'no enough password')
		return -50
	end

	--创建房间
	local ok,table_gid = xpcall(_create_ftable,debug.traceback,uid,tablesvr_id,table_conf,password,game_type)
	if not ok then
		errlog(uid,'failed to _create_ftable111',uid,password,table_gid)
		recycle_password(password)
		return -60
	end

	if table_gid < 0 then
		errlog(uid,'failed to _create_ftable222',uid,password,table_gid)
		recycle_password(password)
		return -70
	end

	set_password_tgid(password,table_gid)
	expiry_checking_list[password] = util.get_now_time()

	dbglog('successful creation!!',uid,password,table_gid)

	local dest = R().tablesvr(tablesvr_id):dest()
	
	return table_gid,dest,password
end

-----------------------------创建好友房------------------------------
function CMD.create_friend_table(uid,table_conf)
	dbglog('ffffffffffffffffffff',uid,tostring_r(table_conf))
	if locked_uids[uid] then
		errlog(uid,'this guy is creating the friend table now')
		return -999
	end

	locked_uids[uid] = true
	local ok,table_gid,dest,password = xpcall(create_ftable,debug.traceback,uid,table_conf)
	locked_uids[uid] = nil

	if not ok then
		errlog(uid,'failed to create friend table',table_gid)
		return -998
	end

	if table_gid < 0 then
		errlog(uid,'failed to create friend table',table_gid)
		return -1000
	end

	return table_gid,dest,password
end

function CMD.report_ftable_stats(server_id,friend_tables_p2t_map,curr_table_num)
	tablesvr_table_num[server_id] = curr_table_num
	if friend_tables_p2t_map then
		for password,table_id in pairs(friend_tables_p2t_map) do
			if being_used_password_list[password] == 0 then
				being_used_password_list[password] = utils.make_table_gid(server_id,table_id)
			else
				errlog('failed to sync friend tables',server_id,password,table_id,
					tostring(being_used_password_list[password]))
			end
		end
	end
end

function CMD.get_created_friend_tables(uid,game_type)
	local ok,ret = R().exdbsvr(1):call(fuser_handler,'get_entered_ftables',uid,game_type)
	if not ok then
		errlog(uid,'failed to get_entered_ftables')
		return {}
	end

	local pt_map = {}
	for i = 1,#ret,2 do
		pt_map[tonumber(ret[i])] = tonumber(ret[i + 1])
	end
	local removed_tables = {}
	local valid_tables = {}
	local curr_time = util.get_now_time()
	for password,enter_time in pairs(pt_map) do
		if not being_used_password_list[password] or 
			curr_time - enter_time >= TABLE_EXPIRY_TIME then
			--不存在的或很久远的桌子了，则删除记录之
			table_insert(removed_tables,password)
		else
			valid_tables[password] = enter_time
		end
	end

	--需要删除掉不存在的房号
	if #removed_tables > 0 then
		R().exdbsvr(1):send(fuser_handler,'del_records',uid,removed_tables,game_type)
	end

	local table_info_list
	local bret 
	for _,_ in pairs(valid_tables) do
		bret = true
		break
	end
	--拉取桌子实时信息(头像等信息)
	if bret then
		local ok,data = R().tablesvr(tablesvr_id):call('.table_mgr','get_ftable_info',valid_tables)
		print_r(data)
		if ok and data then
			table_info_list = data
		end
	end	

	local ret = {}
	for password,enter_time in pairs(valid_tables) do
		local table_gid = being_used_password_list[password]
		local tablesvr_id,table_id = utils.extract_table_gid(table_gid)
		
		local rsp_table = {}
		--获取房间基本信息
		local ok,table_info = R().exdbsvr(1):call(ftable_handler,'get_ftable',password)
		if not ok then
			errlog(uid,'can not get friend table',password)
			return false
		end
		rsp_table.table_type = table_info.table_type
		rsp_table.total_count = table_info.total_count or table_info.count
		rsp_table.password = password
		rsp_table.enter_time = enter_time
		if table_info_list and table_info_list[password] then
			rsp_table.icons = table_info_list[password].icons or {}
			rsp_table.player_number = table_info_list[password].player_number or 0
			rsp_table.zimo_addition = table_info_list[password].zimo_addition or 0
		end
		table_insert(ret,rsp_table)
	end
	
	print_r(ret)
	--取得详细的数据,由hallsvr自行排序
	return ret
end

local function _get_friend_table_info(uid,password)
	local table_gid = being_used_password_list[password]
	if not table_gid then
		--没有该好友房了，有可能是被删除了
		errlog(uid,'this password does not exist',password)
		return false
	end

	--先看下有没有记录在哪个桌子服务器，如果有记录，则确保桌子存在
	if table_gid ~= 0 then
		local tablesvr_id = utils.extract_table_gid(table_gid)
		local ok,key = R().tablesvr(tablesvr_id):call('.table_mgr','touch_table',table_gid)
		if not ok then
			errlog(uid,password,'failed to touch table',table_gid,tablesvr_id)
			table_gid = 0
		elseif not key then
			dbglog(uid,password,'this table does not exist now.')
			table_gid = 0
		elseif key ~= password then
			--假如一些复杂的原因，那个桌子服的tgid虽然存在，但不是关联着我们这个桌子
			errlog(uid,'unmatch table',key,password)
			table_gid = 0
		else
			--桌子还存在，则直接返回
			return {
				dest = R().tablesvr(tablesvr_id):dest(),
				table_gid = table_gid,
			}
		end
	end
	local ok,table_info = R().exdbsvr(1):call(ftable_handler,'get_ftable_detail',password)
	if not ok then
		errlog(uid,'can not get friend table',password)
		return false
	end

	if not table_info then
		errlog(uid,'failed to get friend table info',password)
		return false
	end
	
	--假如这个房间已经开过局了，则不能重新分配，并且强制其过期
	if table_info.curr_round ~= 0 then
		errlog(uid,'this room must not destroy now...',password)
		local t = assert(expiry_checking_list[password],'invalid expiry record ' .. password)
		expiry_checking_list[password] = t - TABLE_EXPIRY_TIME
		return false
	end

	local tablesvr_id = select_one_table_server()
	if not tablesvr_id then
		errlog(uid,"cant find available table server on create table")
		return false
	end
	
	local table_gid = create_table_on_tablesvr(tablesvr_id,uid,table_info,password)
	if not table_gid then
		errlog(uid,'failed to create_table_on_tablesvr',tablesvr_id,password)
		return false
	end

	being_used_password_list[password] = table_gid

	return {
		dest = R().tablesvr(tablesvr_id):dest(),
		table_gid = table_gid,
	}
end

local function safe_return(ok,...)
	if not ok then
		errlog('failed to get_friend_table_info',...)
		return skynet.retpack(false)
	end
	return skynet.retpack(...)
end

function CMD.get_friend_table_info(uid,password)
	sync_run(password,safe_return,
		xpcall(_get_friend_table_info,debug.traceback,uid,password))
	return --外部就不retpack了
end

local function _dismiss_friend_table(password)
	dbglog('now dismiss_friend_table',password)
	recycle_password(password)
	
    local ok,succ,table_info = R().exdbsvr(1):call('.ftable_handler','dismiss_table',password)
    if not ok then
        errlog(uid,"failed to dismiss_table",password)
		return false
    end

	if not succ then
		errlog(uid,"failed to dismiss_table and it is not success",password)
		return false
	end

	local creator_uid = table_info.creator_uid
	local game_type = assert(table_def.table_game_map[table_info.table_type])

    R().exdbsvr(1):send('.fuser_handler','del_self_ftable',creator_uid,password,game_type)

	if table_info.record_key then
		local record_key = table_info.record_key
		--如果有过该记录
		local uid_list = assert(table_info.uid_list)
		local game_type = assert(table_def.table_game_map[table_info.table_type])
		for _,uid in ipairs(uid_list) do
			R().exdbsvr(1):send('.msg_handler','save_frecord',uid,record_key,game_type)
		end
	else
		--从来没有玩过，因此没有记录,所以需要退房卡
		dbglog(creator_uid,'this is an unused friend table,refund room cards',password,
			table_info.cost)
		local ok,succ,ret = R().basesvr{key=creator_uid}:call('.msg_handler','add_roomcards',
			creator_uid,table_info.cost,reason.FRIEND_TABLE_RETURN)
		if ok and succ then
			--通知客户端退回了房卡
			R().hallsvr{key=creator_uid}:send('.msg_handler','toagent',creator_uid,
				'notify_money_changed',{roomcards = ret.curr})
		else
			errlog(creator_uid,'failed to add room cards',password,table_info.cost)
		end
	end

	return true
end

function CMD.dismiss_friend_table(password,table_gid)
	if not expiry_checking_list[password] then
		errlog('no such password',password)
		return false
	end

	local tgid = being_used_password_list[password]
	if tgid ~= table_gid then
		errlog('unmatched table gid',password,tgid,table_gid)
		return false
	end

	expiry_checking_list[password] = nil
	return _dismiss_friend_table(password)
end

function CMD.ftable_start(password)
	if not expiry_checking_list[password] then
		errlog('no such password',password)
		return false
	end

	ftable_start_list[password] = true
	return true
end

local function asyn_data_runable()
	 local phase_swith_time = tonumber(skynet.getenv "phase_swith_time")
	 local last_sync_time = 0
	 while true do
	 	local now = util.get_now_time()
        local interval = now - last_sync_time
        local phase = now - server_start_time

        if (phase <= phase_swith_time and interval >= 5) or
			(phase > phase_swith_time and interval >= 60) then
            last_sync_time = now
			R().tablesvr():broadcast('.table_mgr','get_ftable_stats',
				R().get_source(),'.table_mgr',server_start_time)
        end

        skynet.sleep(500) --5 seconds
    end
end

local function load_all_ftables()
	print('load_all_tables-------------- begin...')

	local ok,password_list
	while not ok do
		ok,password_list = R().exdbsvr(1):call(ftable_handler,'load_all_ftables')
		if not ok then
			errlog('failed to load_all_ftables ---------------')
		end
	end

	print('load_all_tables-------------- password_list...',#password_list)
	for password in pairs(password_list) do
		assert(not being_used_password_list[password])
		being_used_password_list[password] = 0
	end

	assert(expiry_checking_list == nil)
	expiry_checking_list = password_list

	gen_table_password_list()

	print('load_all_tables--------------end ... available passwords number is',
		#candidate_password_list)
end

local function check_expiry_passwords(curr_time)
	for password,created_time in pairs(expiry_checking_list) do
		if not ftable_start_list[password] and 
			curr_time - created_time >= TABLE_UNSTART_EXPIRY_TIME + 10 then
				expiry_checking_list[password] = nil
				skynet.fork(_dismiss_friend_table,password)
				dbglog('expiry password',password)
		elseif ftable_start_list[password] and 
			curr_time - created_time >= TABLE_EXPIRY_TIME + 10 then
				expiry_checking_list[password] = nil
				skynet.fork(_dismiss_friend_table,password)
				dbglog('expiry password',password)
		end	
	end
end

local function routine_check()
	while true do
		local curr_time = util.get_now_time()
		local ok,ret = xpcall(check_expiry_passwords,debug.traceback,curr_time)
		if not ok then
			errlog(ret)
		end
		skynet.sleep(100)
	end
end

function CMD.start()
	fuser_handler = '.fuser_handler'
	ftable_handler = '.ftable_handler'

	load_all_ftables()

	server_start_time = util.get_now_time()

	skynet.fork(asyn_data_runable)
	skynet.fork(routine_check)

	skynet.dispatch("lua",function(_,_,cmd,...)
		print("===========",cmd,...)
		local f = assert(CMD[cmd])
		local r = {f(...)}
		if #r > 0 then
			skynet.retpack(table_unpack(r))
		end
	end)
	
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		assert(cmd == 'start')
		CMD[cmd](...)
	end)
end)


