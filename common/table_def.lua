local M = {}

local MAX_DIZHU_RATE_SELECT_ONE = 32
local MAX_DIZHU_RATE_SELECT_TWO = 64
local MAX_DIZHU_RATE_SELECT_THRE = 128

local FRIENT_TABLE_COUNT_SELECT_ONE = 6
local FRIENT_TABLE_COUNT_SELECT_TWO = 9
local FRIENT_TABLE_COUNT_SELECT_THREE = 15

local NORMAL_TABLE_TYPE_NEW = 1  --经典新手场
local NORMAL_TABLE_TYPE_BASE = 2  --经典初级场
local NORMAL_TABLE_TYPE_LOW = 3 --经典普通场
local NORMAL_TABLE_TYPE_MIN = 4  --经典中级场
local NORMAL_TABLE_TYPE_HIGHT = 5  --经典高级场
local NORMAL_TABLE_TYPE_ZHIZUN = 6   --经典至尊场至尊

local LAIZI_TABLE_TYPE_NEW = 101 --癞子新手场
local LAIZI_TABLE_TYPE_BASE = 102 --癞子初级场
local LAIZI_TABLE_TYPE_LOW = 103 --癞子普通场
local LAIZI_TABLE_TYPE_MIN = 104 --癞子中级场
local LAIZI_TABLE_TYPE_HIGHT = 105 --癞子高级场
local LAIZI_TABLE_TYPE_ZHIZUN = 106 --癞子至尊场

local FRIEND_TABLE_TYPE_NORMAL = 201 --好友经典房
local FRIEND_TABLE_TYPE_LAIZI = 202  --好友癞子房

local FRIEND_TABLE_TYPE_XUEZHAN   = 10001 --血战到底好友房

local SET_DIZHU_WAY_ROB = 1
local SET_DIZHU_WAY_SCORE = 2

local GAME_TYPE_DDZ = 1
local GAME_TYPE_XZMJ = 2

M.set_dizhu_way = {
	[SET_DIZHU_WAY_ROB] = true,
	[SET_DIZHU_WAY_SCORE] = true,
}


local ddz_ftable_map = {
	[FRIEND_TABLE_TYPE_NORMAL] = true,
	[FRIEND_TABLE_TYPE_LAIZI] = true,
}

M.ddz_ftable_map = ddz_ftable_map

local xuezhan_ftable_map = {
	[FRIEND_TABLE_TYPE_XUEZHAN] = true,
}
M.xuezhan_ftable_map = xuezhan_ftable_map

local server_name_map = {
	[NORMAL_TABLE_TYPE_NEW]    = 'table',  --经典新手场
 	[NORMAL_TABLE_TYPE_BASE]   = 'table',  --经典初级场
 	[NORMAL_TABLE_TYPE_LOW]    = 'table', --经典普通场
 	[NORMAL_TABLE_TYPE_MIN]    = 'table',  --经典中级场
 	[NORMAL_TABLE_TYPE_HIGHT]  = 'table',  --经典高级场
 	[NORMAL_TABLE_TYPE_ZHIZUN] = 'table',   --经典至尊场至尊

    [LAIZI_TABLE_TYPE_NEW]    = 'laizi_table', --癞子新手场
    [LAIZI_TABLE_TYPE_BASE]   = 'laizi_table', --癞子初级场
    [LAIZI_TABLE_TYPE_LOW]    = 'laizi_table', --癞子普通场
    [LAIZI_TABLE_TYPE_MIN]    = 'laizi_table', --癞子中级场
    [LAIZI_TABLE_TYPE_HIGHT]  = 'laizi_table', --癞子高级场
    [LAIZI_TABLE_TYPE_ZHIZUN] = 'laizi_table', --癞子至尊场

    [FRIEND_TABLE_TYPE_NORMAL] = 'friend_table', --好友经典房
    [FRIEND_TABLE_TYPE_LAIZI]  = 'friend_lztable',  --好友癞子房

    [FRIEND_TABLE_TYPE_XUEZHAN]   = 'xz_table', --血战到底好友房
}

M.server_name_map = server_name_map

M.max_dizhu_rate = {
	[MAX_DIZHU_RATE_SELECT_ONE] = true,
	[MAX_DIZHU_RATE_SELECT_TWO] = true,
	[MAX_DIZHU_RATE_SELECT_THRE] = true,
}

M.count_select = {
	[FRIENT_TABLE_COUNT_SELECT_ONE] = true,
	[FRIENT_TABLE_COUNT_SELECT_TWO] = true,
	[FRIENT_TABLE_COUNT_SELECT_THREE] = true,
}

local function values_to_keys(t)
	local nt = {}
	for _,v in pairs(t) do 
		nt[v] = true
	end
	return nt
end
local table_type_list = {
	NORMAL_TABLE_TYPE_NEW,
	NORMAL_TABLE_TYPE_BASE,
	NORMAL_TABLE_TYPE_LOW,
	NORMAL_TABLE_TYPE_MIN,
	NORMAL_TABLE_TYPE_HIGHT,
	NORMAL_TABLE_TYPE_ZHIZUN,

	LAIZI_TABLE_TYPE_NEW,
	LAIZI_TABLE_TYPE_BASE,
	LAIZI_TABLE_TYPE_LOW,
	LAIZI_TABLE_TYPE_MIN,
	LAIZI_TABLE_TYPE_HIGHT,
	LAIZI_TABLE_TYPE_ZHIZUN,

	FRIEND_TABLE_TYPE_NORMAL,
	FRIEND_TABLE_TYPE_LAIZI,
}

M.table_type_list = table_type_list
M.table_type_map = values_to_keys(table_type_list)

local friend_table_type_list = {
	FRIEND_TABLE_TYPE_NORMAL,
	FRIEND_TABLE_TYPE_LAIZI
}
M.friend_table_type_list = friend_table_type_list
M.friend_table_type_map = values_to_keys(friend_table_type_list)

local friend_lztable_type_list = {
	FRIEND_TABLE_TYPE_LAIZI,
}
M.friend_lztable_type_list = friend_lztable_type_list
M.friend_lztable_type_map = values_to_keys(friend_lztable_type_list)

local laizi_table_type_list = {
	LAIZI_TABLE_TYPE_NEW,
	LAIZI_TABLE_TYPE_BASE,
	LAIZI_TABLE_TYPE_LOW,
	LAIZI_TABLE_TYPE_MIN,
	LAIZI_TABLE_TYPE_HIGHT,
	LAIZI_TABLE_TYPE_ZHIZUN,
}
M.laizi_table_type_list = laizi_table_type_list
M.laizi_table_type_map = values_to_keys(laizi_table_type_list)

local XUEZHAN_FTABLE_COUNT_SELECT_ONE = 4
local XUEZHAN_FTABLE_COUNT_SELECT_TWO = 8
M.xuezhan_count_map = {
	[XUEZHAN_FTABLE_COUNT_SELECT_ONE] = true,
	[XUEZHAN_FTABLE_COUNT_SELECT_TWO] = true,
}

local XUEZHAN_LIMIT_RATE_SELECT_ONE = 2
local XUEZHAN_LIMIT_RATE_SELECT_TWO = 3
local XUEZHAN_LIMIT_RATE_SELECT_THREE = 4
M.xuezhan_limit_rate_map = {
	[XUEZHAN_LIMIT_RATE_SELECT_ONE] = true,
	[XUEZHAN_LIMIT_RATE_SELECT_ONE] = true,
	[XUEZHAN_LIMIT_RATE_SELECT_THREE] = true,
}

local XEUZHAN_ZIMO_SELECT_ONE = 1
local XEUZHAN_ZIMO_SELECT_TWO = 2
M.xuezhan_zimo_map = {
	[XEUZHAN_ZIMO_SELECT_ONE] = true,
	[XEUZHAN_ZIMO_SELECT_TWO] = true,
}

local XEUZHAN_DIANGANGHUA_ADDTION_SELECT_ONE = 1
local XEUZHAN_DIANGANGHUA_ADDTION_SELECT_TWO = 2
M.dianganghua_map = {
	[XEUZHAN_DIANGANGHUA_ADDTION_SELECT_ONE] = true,
	[XEUZHAN_DIANGANGHUA_ADDTION_SELECT_ONE] = true,
}

local XUEZHAN_PLAY_SELECT_MAX_COUNT = 4
M.XUEZHAN_PLAY_SELECT_MAX_COUNT = XUEZHAN_PLAY_SELECT_MAX_COUNT

M.table_game_map = {
    [FRIEND_TABLE_TYPE_NORMAL] = GAME_TYPE_DDZ,
    [FRIEND_TABLE_TYPE_LAIZI]  = GAME_TYPE_DDZ,

    [FRIEND_TABLE_TYPE_XUEZHAN]  = GAME_TYPE_XZMJ,	
}

return M