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

local table_type_map = {}
table_type_map[DDZ_NORMAL_TYPE_ONE]   = true
table_type_map[DDZ_NORMAL_TYPE_TWO]   = true
table_type_map[DDZ_NORMAL_TYPE_THREE] = true
table_type_map[DDZ_NORMAL_TYPE_FOUR]  = true

table_type_map[DDZ_LAIZI_TYPE_ONE]    = true
table_type_map[DDZ_LAIZI_TYPE_TWO]    = true
table_type_map[DDZ_LAIZI_TYPE_THREE]  = true
table_type_map[DDZ_LAIZI_TYPE_FOUR]   = true

table_type_map[ZJH_TYPE_ONE]          = true
table_type_map[ZJH_TYPE_TWO]          = true
table_type_map[ZJH_TYPE_THREE]        = true
table_type_map[ZJH_TYPE_FOUR]         = true

table_type_map[FRIEND_TABLE_TYPE_NORMAL]      = true
table_type_map[FRIEND_TABLE_TYPE_LAIZI]       = true
table_type_map[FRIEND_TABLE_TYPE_ZJH]         = true
table_type_map[FRIEND_TABLE_TYPE_XUEZHAN]     = true

M.table_type_map = table_type_map

local laizi_table_type_map = {}
laizi_table_type_map[DDZ_LAIZI_TYPE_ONE] = true
laizi_table_type_map[DDZ_LAIZI_TYPE_TWO] = true
laizi_table_type_map[DDZ_LAIZI_TYPE_THREE] = true
laizi_table_type_map[DDZ_LAIZI_TYPE_FOUR] = true

M.laizi_table_type_map = laizi_table_type_map
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
local server_name_map = {}
server_name_map[DDZ_NORMAL_TYPE_ONE]   = 'table' --经典斗地主新手场
server_name_map[DDZ_NORMAL_TYPE_TWO]   = 'table' --经典斗地主初级场
server_name_map[DDZ_NORMAL_TYPE_THREE] = 'table' --经典斗地主中级场
server_name_map[DDZ_NORMAL_TYPE_FOUR]  = 'table' --经典斗地主高级场

server_name_map[DDZ_LAIZI_TYPE_ONE]    = 'laizi_table' --癞子斗地主新手场
server_name_map[DDZ_LAIZI_TYPE_TWO]    = 'laizi_table' --癞子斗地主初级场
server_name_map[DDZ_LAIZI_TYPE_THREE]  = 'laizi_table' --癞子斗地主普通场
server_name_map[DDZ_LAIZI_TYPE_FOUR]   = 'laizi_table' --癞子斗地主中级场

server_name_map[ZJH_TYPE_ONE]          = 'zjh_table' --扎金花新手场
server_name_map[ZJH_TYPE_TWO]          = 'zjh_table' --扎金花初级场
server_name_map[ZJH_TYPE_THREE]        = 'zjh_table' --扎金花中级场
server_name_map[ZJH_TYPE_FOUR]         = 'zjh_table' --扎金花高级场

server_name_map[FRIEND_TABLE_TYPE_NORMAL]     = 'friend_table'   --经典斗地主好友房
server_name_map[FRIEND_TABLE_TYPE_LAIZI]      = 'friend_lztable' --癞子斗地主好友房
server_name_map[FRIEND_TABLE_TYPE_ZJH]        = 'zmj_ftable'     --扎金花好友房
server_name_map[FRIEND_TABLE_TYPE_XUEZHAN]    = 'xz_ftable'      --血战好友房

M.server_name_map = server_name_map
-----------------------------------游戏服务名字--------------------------

return M