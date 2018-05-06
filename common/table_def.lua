local M = {}

---------------------------------桌子类型类型-----------------------------
local DDZ_NORMAL_TYPE_ONE    = 101  --经典新手场
local DDZ_NORMAL_TYPE_TWO    = 102  --经典初级场
local DDZ_NORMAL_TYPE_THREE  = 103  --经典中级场
local DDZ_NORMAL_TYPE_FOUR   = 104  --经典高级场

local DDZ_LAIZI_TYPE_ONE     = 111 --癞子斗地主新手场
local DDZ_LAIZI_TYPE_TWO     = 112 --癞子斗地主初级场
local DDZ_LAIZI_TYPE_THREE   = 113 --癞子斗地主中级场
local DDZ_LAIZI_TYPE_FOUR    = 114 --癞子斗地主高级场

local ZJH_TYPE_ONE           = 201 --炸金花新手场
local ZJH_TYPE_TWO           = 202 --炸金花初级场
local ZJH_TYPE_THREE         = 203 --炸金花中级场
local ZJH_TYPE_FOUR          = 204 --炸金花高级场

local FRIEND_TABLE_TYPE_NORMAL    = 10000 --经典斗地主好友房
local FRIEND_TABLE_TYPE_LAIZI     = 10001 --癞子斗地主好友房
local FRIEND_TABLE_TYPE_ZJH       = 20000 --扎金花好友房
local FRIEND_TABLE_TYPE_XUEZHAN   = 30000 --血战到底好友房
---------------------------------桌子类型类型-----------------------------

--------------------------------游戏类型--------------------------------
local GAME_TYPE_DDZ     = 1
local GAME_TYPE_ZJH     = 2
local GAME_TYPE_XUEZHAN = 3

M.GAME_TYPE_DDZ     = GAME_TYPE_DDZ
M.GAME_TYPE_ZJH     = GAME_TYPE_ZJH
M.GAME_TYPE_XUEZHAN = GAME_TYPE_XUEZHAN
-------------------------------游戏类型---------------------------------

-----------------------------------游戏服务名字---------------------------
local server_name_map = {
	[DDZ_NORMAL_TYPE_ONE]      = 'table', --经典斗地主新手场
 	[DDZ_NORMAL_TYPE_TWO]      = 'table', --经典斗地主初级场
 	[DDZ_NORMAL_TYPE_THREE]    = 'table', --经典斗地主中级场
 	[DDZ_NORMAL_TYPE_FOUR]     = 'table', --经典斗地主高级场

    [DDZ_LAIZI_TYPE_ONE]       = 'laizi_table', --癞子新手场
    [DDZ_LAIZI_TYPE_TWO]       = 'laizi_table', --癞子初级场
    [DDZ_LAIZI_TYPE_THREE]     = 'laizi_table', --癞子普通场
    [DDZ_LAIZI_TYPE_FOUR]      = 'laizi_table', --癞子中级场

    [ZJH_TYPE_ONE]             = 'zjh_table',   --扎金花新手场
    [ZJH_TYPE_TWO]             = 'zjh_table',   --扎金花初级场
    [ZJH_TYPE_THREE]           = 'zjh_table',   --扎金花中级场
    [ZJH_TYPE_FOUR]            = 'zjh_table',   --扎金花高级场

    [FRIEND_TABLE_TYPE_NORMAL] = 'friend_table', --好友经典房
    [FRIEND_TABLE_TYPE_LAIZI]  = 'friend_lztable',  --好友癞子房
    [FRIEND_TABLE_TYPE_XUEZHAN]   = 'xz_table', --血战到底好友房
}
M.server_name_map = server_name_map
-----------------------------------游戏服务名字end---------------------------

local function values_to_keys(t)
	local nt = {}
	for _,v in pairs(t) do 
		nt[v] = true
	end
	return nt
end
local table_type_list = {
	DDZ_NORMAL_TYPE_ONE,
	DDZ_NORMAL_TYPE_TWO,
	DDZ_NORMAL_TYPE_THREE,
	DDZ_NORMAL_TYPE_FOUR,

	DDZ_LAIZI_TYPE_ONE,   
 	DDZ_LAIZI_TYPE_TWO,   
 	DDZ_LAIZI_TYPE_THREE,
 	DDZ_LAIZI_TYPE_FOUR,   

	FRIEND_TABLE_TYPE_NORMAL,
	FRIEND_TABLE_TYPE_LAIZI,
}
	
M.table_type_list = table_type_list
M.table_type_map  = values_to_keys(table_type_list)

local laizi_table_type_list = {
	DDZ_LAIZI_TYPE_ONE,
	DDZ_LAIZI_TYPE_TWO,
	DDZ_LAIZI_TYPE_THREE,
	DDZ_LAIZI_TYPE_FOUR,
}
M.laizi_table_type_list = laizi_table_type_list
M.laizi_table_type_map = values_to_keys(laizi_table_type_list)

M.table_game_map = {
    [FRIEND_TABLE_TYPE_NORMAL] = GAME_TYPE_DDZ,
    [FRIEND_TABLE_TYPE_LAIZI]  = GAME_TYPE_DDZ,

    [FRIEND_TABLE_TYPE_XUEZHAN]  = GAME_TYPE_XZMJ,	
}

return M