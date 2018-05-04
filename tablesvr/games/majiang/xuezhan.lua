local table_insert = table.insert
local table_sort = table.sort
local table_remove = table.remove
local math_floor = math.floor
local math_random = math.random

local util = require "util"
local xuezhan_checker = require "xuezhan_checker"

local MT = {}
MT.__index = MT

local REQUIRED_PLAYER_NUM = 4
local TILE_COUNT_PER_PLAYER_ON_START = 13   --玩家开始发13张牌

--抽完牌后等待的时长
local DRAW_TILE_WAITING_TIME = 100
--打完牌后等待的时长
local DISCARD_TILE_WAITING_TIME = 100
--换三张
local HUANSANZHANG_WAITING_TIME = 60
--定缺
local DINGQUE_WAITING_TIME = 100
--换三张动画时长
local HUANSANZHANG_CARTOON_TIME = 5

------------------花色定义----------------------
local FLOWER_TYPE_WAN = 1
local FLOWER_TYPE_TONG = 2
local FLOWER_TYPE_SUO = 3

local FLOWER_VALID_SET = {
    [FLOWER_TYPE_WAN] = true,
    [FLOWER_TYPE_TONG] = true,
    [FLOWER_TYPE_SUO] = true,
}

----------------------------------------------------
local YAOPAI_OP_INIT = 0  --当别人打了牌，可以要牌时初始化 
local YAOPAI_OP_PASS = 1   --不要别人的牌
local YAOPAI_OP_GANG = 2   --杠
local YAOPAI_OP_PENG = 3   --碰
local YAOPAI_OP_HU = 4      --胡
local YAOPAI_OP_TIMEOUT_PASS = 5    --超时跳过
local YAOPAI_OP_BUGANG = 6  --补杠

------------------------------换三张-------------------------
local HUANSANZHANG_CLOCKWISE = 1    --顺时针
local HUANSANZHANG_ANTICLOCKWISE = 2    --逆时针
local HUANSANZHANG_OPPOSITE = 3     --对面交换

local CHANGE_STRATEGY_DEF = {
    [HUANSANZHANG_CLOCKWISE] = {[1] = 4,[4] = 3,[3] = 2, [2] = 1},
    [HUANSANZHANG_ANTICLOCKWISE] = {[1] = 2,[2] = 3,[3] = 4, [4] = 1},
    [HUANSANZHANG_OPPOSITE] = {[1] = 3,[2] = 4,[3] = 1,[4] = 2},
}

-----------------------游戏状态定义------------------------
local GAME_STATUS_INIT = 0              --初始化状态
local GAME_STATUS_STARTED = 1           --游戏开始
local GAME_STATUS_HUANSANZHANG = 2          --牌局换三张
local GAME_STATUS_DINGQUE = 3           --游戏定缺
local GAME_STATUS_PLAYING = 4           --游戏进行
local GAME_STATUS_GAMEOVER = 5          --游戏结束

---------------------游戏子状态定义------------------------
local GAME_SUB_STATUS_INIT = 0         --初始化状态
local GAME_SUB_STATUS_AFTER_DRAW  = 1  --摸完牌后
local GAME_SUB_STATUS_AFTER_PENG = 2   --碰完牌后
local GAME_SUB_STATUS_AFTER_DISCARD = 3 --打完牌后
local GAME_SUB_STATUS_AFTER_GANG  = 4  --杠完牌后
local GAME_SUB_STATUS_AFTER_ZIMO   = 5   --胡牌之后
local GAME_SUB_STATUS_AFTER_BUGANG  = 6  --补杠牌后

-----------------------游戏杆定义--------------------------
local TYPE_GANG = 1
local TYPE_ANGANG = 2
local TYPE_BUGANG = 3

----------------------游戏加钱扣钱操作---------------------
local OP_GANG      = 1 --明杠
local OP_BY_GANG   = 2 --被明杠
local OP_BUGANG    = 3 --补杠
local OP_BY_BUGANG = 4 --被补杠
local OP_ANGANG    = 5 --暗杠
local OP_BY_ANGANG = 6 --被暗杠
local OP_ZIMO        = 7 --自摸
local OP_BY_ZIMO     = 8 --被自摸
local OP_DIANPAO     = 9 --点炮
local OP_BY_DIANPAO  = 10 --被点炮
local OP_HUJIAOZHUANGYI = 11 --呼叫转移
local OP_BY_HUJIAOZHUANGYI = 12 --被呼叫转移
local OP_TUISHUI = 13 --流局退税加分
local OP_BY_TUISHUI = 14 --流局退税减分
local OP_TINGPAI = 15 --流局听牌加分
local OP_BY_TINGPAI = 16 --流局听牌减分
local OP_HUAZHU = 17 --流局花猪加分
local OP_BY_HUAZHU = 18 --流局花猪减分

local function build_tile_map(player_tile_list)
    local tiles_map = {}
    for _,tile in ipairs(player_tile_list) do
        tiles_map[tile] = (tiles_map[tile] or 0) + 1
    end
    return tiles_map
end

local function del_from_tile_list(player_tile_list,del_map)
    local i = 1
    while i <= #player_tile_list do
        local tile = player_tile_list[i]
        local count = del_map[tile] or 0
        if count > 0 then
            table_remove(player_tile_list,i)
            del_map[tile] = count - 1
        else
            i = i + 1
        end
    end

    for _,c in pairs(del_map) do 
        assert(c == 0)
    end
end

local function reduce_tile(tiles_map,tile,num)
    local c = tiles_map[tile] or 0
    if c < num then
        return false
    end

    c = c - num
    if c < 1 then
        c = nil
    end

    tiles_map[tile] = c
    return true
end

local function add_tile(tiles_map,tile,num)
    tiles_map[tile] = (tiles_map[tile] or 0) + num
end

local function get_player_index(player_list,uid)
    for i,_uid in ipairs(player_list) do
        if uid == _uid then
            return i
        end
    end
end

local function turn_to_next_index(self,curr_index)
    return (curr_index % #self.player_list) + 1
end

function MT:init()
    --生成所有的牌
    --[[
        麻将牌定义:
            11-19   万
            21-29   筒
            31-39   索
    ]]
    local tile_list = {}
    for i = 1,3 do
        for j = 1,9 do
            for k = 1,4 do
                table_insert(tile_list,i*10+j)
            end
        end
    end

    self.game_status = GAME_STATUS_INIT
    self.game_sub_status = GAME_SUB_STATUS_INIT
    self.tile_list = tile_list
    self.player_list = nil
    self.player_tiles_map = nil
    self.huansanzhang_map = nil     --换三张的记录
    self.player_dingque_map = nil   --玩家定缺
    self.player_gangpeng_map = nil  --玩家的杠碰记录
    self.player_angang_map = nil    --玩家暗杠列表
    self.player_giveup_records_map = nil    --玩家放弃的记录
    self.player_hupai_map = nil     --玩家胡牌记录
    self.banker_uid = 0             --庄家uid
    self.curr_status_end_time = nil

    self.curr_player_index = nil    --本次出牌的玩家索引
    self.curr_player_drawn_tile = nil     --本次玩家取得的牌
    self.curr_player_discarded_tile = nil  --打出的牌
    self.curr_player_end_time = nil  --本次出牌玩家的出牌结束时间
    self.curr_tile_been_taken = nil     --当前打出来的牌已经被拿走了(一炮多响会出现这种情况)
    self.curr_discarding_round = nil    --当前打牌的回合数
    self.force_next_uid = nil           --强制指定下一个取牌玩家

    self.dies = nil                 --记录的是骰子的点数
    self.record_list = nil

    self.rules = nil --规则
    self.huansanzhang_strategy = nil    --换三张策略
    self.all_discarded_tiles = nil
    self.huansanzhang_end_time = nil
    self.huansanzhang_cartoon_endtime = nil
    self.dingque_end_time = nil
    self.changed_map = nil
    self.score_detail_map = nil
    self.op_type_map = nil
    self.last_gang_map = nil
    self.player_gangpeng_info_map = nil
    self.base_score = nil   --游戏底分
    self.tmp_gameover_score_result = nil
    self.cur_round_hu_map = {}
    self.test_player_draw_tile = {}
end

--[[
    ordered_uid_list:传入有序的用户ID列表
]]
function MT:start(ordered_uid_list,defined_rules,banker_uid_)
    assert(self.game_status == GAME_STATUS_INIT)

    local player_list = {}

    local duplication_test = {}
    for _,uid in ipairs(ordered_uid_list) do
        assert(not duplication_test[uid])
        duplication_test[uid] = true
        table_insert(player_list,uid)
    end

    assert(#player_list == REQUIRED_PLAYER_NUM,string.format("player_num:%d",#player_list))

    if banker_uid_ then
        assert(duplication_test[banker_uid_])
        self.banker_uid = banker_uid_
    else
        self.banker_uid = player_list[math_random(1,#player_list)]
    end

    self.rules = defined_rules
    self.player_list = player_list
    self.huansanzhang_strategy = math_random(1,#CHANGE_STRATEGY_DEF)
    self.game_status = GAME_STATUS_STARTED
    self.base_score = defined_rules.base_score

    return true
end

--洗牌发牌
function MT:shuffle_and_deal(swap_times)
    assert(self.game_status == GAME_STATUS_STARTED)

    local tile_list = self.tile_list

    local tile_count = #tile_list
    local swap_count = swap_times or tile_count
    for i = 1,swap_count do
        local n = math_random(1,tile_count)
        local m = math_random(1,tile_count)
        if n ~= m then
            tile_list[n],tile_list[m] = tile_list[m],tile_list[n]
        end
    end
    
    --计算骰子,骰子其实仅仅供客户端做表现用
    local dies = {math_random(1,6),math_random(1,6)}
    self.dies = dies[1] * 10 + dies[2]

    assert(not self.player_tiles_map)
    local player_tiles_map = {}
    for _,uid in ipairs(self.player_list) do
        local player_tile_list = {}
        for i = 1,TILE_COUNT_PER_PLAYER_ON_START do
            local tile = table_remove(tile_list)
            table_insert(player_tile_list,tile)
        end
        assert(#player_tile_list == TILE_COUNT_PER_PLAYER_ON_START)
        
        --按照[万筒条]排序
        table_sort(player_tile_list)

        player_tiles_map[uid] = player_tile_list
    end

    --庄家多发一张
    self.curr_player_drawn_tile = table_remove(tile_list)
    table_insert(player_tiles_map[self.banker_uid],self.curr_player_drawn_tile)
    self.game_sub_status = GAME_SUB_STATUS_AFTER_DRAW

    print("rrrrrrrrrrrrrrrrrrrrrrrrrrrrrr",self.banker_uid)
    print_r(player_tiles_map)
    
    --每个人的牌已经确定了
    self.player_tiles_map = player_tiles_map

    if self.rules.huansanzhang then
        local huansanzhang_map = {}
        for _,uid in ipairs(self.player_list) do
            huansanzhang_map[uid] = {}
        end
        self.huansanzhang_map = huansanzhang_map
        self.curr_status_end_time = util.get_now_time() + HUANSANZHANG_WAITING_TIME
        self.game_status = GAME_STATUS_HUANSANZHANG
    else
        local player_dingque_map = {}
        for _,uid in ipairs(self.player_list) do
            player_dingque_map[uid] = false
        end
        self.player_dingque_map = player_dingque_map
        self.curr_status_end_time = util.get_now_time() + DINGQUE_WAITING_TIME
        self.game_status = GAME_STATUS_DINGQUE
    end
    
    return true
end

local function test_selected_tile_list(player_tile_list,selected_tile_list)
    local tiles_test = build_tile_map(player_tile_list)
    
    for _,tile in ipairs(selected_tile_list) do
        if not reduce_tile(tiles_test,tile,1) then
            return false
        end
    end

    return true
end

function MT:set_huansanzhang(uid,selected_tile_list)
    assert(self.game_status == GAME_STATUS_HUANSANZHANG)
    
    local huansanzhang_map = self.huansanzhang_map
    if not huansanzhang_map[uid] then
        return false,-100
    end

    if #huansanzhang_map[uid] > 0 then
        --已经换过三张了
        return false,-101
    end

    if #selected_tile_list ~= 3 then
        return false,-102
    end

    --检查一下玩家是不是有这三张
    local player_tile_list = self.player_tiles_map[uid]
    if not test_selected_tile_list(player_tile_list,selected_tile_list) then
        return false,-103
    end

    huansanzhang_map[uid] = selected_tile_list

    return true
end

function MT:get_auto_huansanzhang(uid)
    --已经排到序了，从右边到左边开始拿同花色的连续三张牌
    local player_tile_list = self.player_tiles_map[uid]
    local i = #player_tile_list
    while i >= 3 do
        local flower = math_floor(player_tile_list[i] / 10)
        if flower == math_floor(player_tile_list[i - 1] / 10) and
            flower == math_floor(player_tile_list[i - 2] / 10) then
            break
        end
        i = i - 1
    end

    assert(i >= 3)
    return {
        player_tile_list[i - 2],
        player_tile_list[i - 1],
        player_tile_list[i],
    }
end

--自动换三张
function MT:check_and_auto_huansanzhang(curr_time)
    assert(self.game_status == GAME_STATUS_HUANSANZHANG)
    local timeout_players = {}
    for uid,selected_tile_list in pairs(self.huansanzhang_map) do
        if #selected_tile_list ~= 3 then
            timeout_players[uid] = true
        end
    end

    if not next(timeout_players) then
        --全部选完
        return true
    end

    --还有未选的，看看时间
    if curr_time < self.curr_status_end_time then
        return false
    end

    for uid in pairs(timeout_players) do
        local result = self:get_auto_huansanzhang(uid)
        self.huansanzhang_map[uid] = result
        timeout_players[uid] = result
    end

    return true,timeout_players
end

--交换牌
local function change_tiles(self,strategy)
    local changed_map = {}
    local player_list = self.player_list
    local huansanzhang_map = self.huansanzhang_map
    for from,to in pairs(strategy) do
        local fuid,tuid = player_list[from],player_list[to]
        changed_map[tuid] = huansanzhang_map[fuid]
    end
    self.changed_map = changed_map

    local player_tiles_map = self.player_tiles_map

    for uid,lost_list in pairs(huansanzhang_map) do
        local tiles_map = build_tile_map(player_tiles_map[uid])
        for _,tile in ipairs(lost_list) do
            assert(reduce_tile(tiles_map,tile,1))
        end

        for _,tile in ipairs(changed_map[uid]) do
            add_tile(tiles_map,tile,1)
        end

        local new_player_tile_list = {}
        for tile,num in pairs(tiles_map) do
            for i = 1,num do
                table_insert(new_player_tile_list,tile)
            end
        end
        player_tiles_map[uid] = new_player_tile_list
    end

    return true
end

function MT:check_huansanzhang_over()
    assert(self.game_status == GAME_STATUS_HUANSANZHANG)
    for uid,selected_tile_list in pairs(self.huansanzhang_map) do
        if #selected_tile_list ~= 3 then
            return
        end
    end

    --换牌
    local strategy = assert(CHANGE_STRATEGY_DEF[self.huansanzhang_strategy])
    change_tiles(self,strategy)

    --下一步是定缺了
    local player_dingque_map = {}
    for _,uid in ipairs(self.player_list) do
        player_dingque_map[uid] = false
    end
    self.player_dingque_map = player_dingque_map
    self.curr_status_end_time = util.get_now_time() + DINGQUE_WAITING_TIME + HUANSANZHANG_CARTOON_TIME
    self.game_status = GAME_STATUS_DINGQUE
    local player_dingque_map = {}
    for _,uid in ipairs(self.player_list) do
        player_dingque_map[uid] = false
    end
    self.player_dingque_map = player_dingque_map
    self.huansanzhang_cartoon_endtime = util.get_now_time() + HUANSANZHANG_CARTOON_TIME

    return true
end

function MT:check_huansanzhang_cardtoon_over(curr_time)
    if curr_time >= self.huansanzhang_cartoon_endtime then
        return true
    end
    return false
end


function MT:set_dingque(uid,flower)
    assert(self.game_status == GAME_STATUS_DINGQUE)
    
    local player_dingque_map = self.player_dingque_map
    if player_dingque_map[uid] ~= false then
        return false,-200
    end

    if not FLOWER_VALID_SET[flower] then
        return false,-201
    end

    player_dingque_map[uid] = flower

    return true
end

function MT:auto_dingque(player_tile_list)
    local flower_set = {[FLOWER_TYPE_WAN] = 0,[FLOWER_TYPE_TONG] = 0,[FLOWER_TYPE_SUO] = 0}
    for _,tile in ipairs(player_tile_list) do
        local flower = math_floor(tile / 10)
        flower_set[flower] = (flower_set[flower] or 0) + 1
    end

    local min_flower,min_count = next(flower_set)
    for flower,count in pairs(flower_set) do
        if min_count > count then
            min_flower = flower
            min_count = count
        end
    end

    return min_flower
end


--自动定缺
function MT:check_and_auto_dingque(curr_time)
    assert(self.game_status == GAME_STATUS_DINGQUE)
    local timeout_players = {}
    local player_dingque_map = self.player_dingque_map
    for uid,dingque in pairs(player_dingque_map) do
        if not dingque then
            timeout_players[uid] = true
        end
    end

    if not next(timeout_players) then
        return true
    end

    if curr_time < self.curr_status_end_time then
        return false
    end

    for uid in pairs(timeout_players) do
        local result = self:auto_dingque(self.player_tiles_map[uid])
        player_dingque_map[uid] = result
        timeout_players[uid] = result
    end

    return true,timeout_players
end


function MT:check_dingque_over()
    assert(self.game_status == GAME_STATUS_DINGQUE)
    for uid,dingque in pairs(self.player_dingque_map) do
        if not dingque then
            return
        end
    end

    return true
end

function MT:get_curr_player_uid()
    return self.player_list[self.curr_player_index]
end

function MT:get_curr_player_tile()
    return self.curr_player_discarded_tile or 0
end

function MT:get_curr_player_endtime()
    return self.curr_player_end_time or 0
end

function MT:get_banker_uid()
    return self.banker_uid
end

function MT:get_player_tile_list(uid)
    local player_tile_list = assert(self.player_tiles_map[uid])
    return player_tile_list
end

function MT:get_player_tile_count(uid)
    local player_tile_list = assert(self.player_tiles_map[uid])
    return #player_tile_list
end

function MT:get_player_peng_list(uid)
    local gangpeng_map = assert(self.player_gangpeng_map[uid])
    local peng_list = {}
    for tile,count in pairs(gangpeng_map) do
        if count == 3 then
            table_insert(peng_list,tile)
        end
    end
    return peng_list
end

function MT:get_player_peng_info(uid)
    if not self.player_gangpeng_info_map then
        return 
    end

    local ret = {}
    local gangpeng_map = assert(self.player_gangpeng_info_map[uid])
    for tile,data in pairs(self.player_gangpeng_info_map[uid]) do
        if data.peng then
            table_insert(ret,{tile = tile,uid = data.penged_uid})
        end
    end

    return ret
end

function MT:get_player_gang_info(uid)
    if not self.player_gangpeng_info_map then
        return 
    end
    local ret = {}
    local gangpeng_map = assert(self.player_gangpeng_info_map[uid])
    for tile,data in pairs(gangpeng_map) do
        if data.gang then
            table_insert(ret,{tile = tile,uid = data.ganged_uid})
        end
    end

    return ret
end

function MT:get_player_gang_list(uid)
    local gangpeng_map = assert(self.player_gangpeng_map[uid])
    local gang_list = {}
    for tile,count in pairs(gangpeng_map) do
        if count == 4 then
            table_insert(gang_list,tile)
        end
    end
    return gang_list
end

function MT:get_player_angang_list(uid)
    if not self.player_angang_map then
        return 
    end

    local angang_map = assert(self.player_angang_map[uid]) 
    local angang_list = {}
    for tile,status in pairs(angang_map) do
        if status then
            table_insert(angang_list,tile)
        end
    end

    return angang_list
end

function MT:get_player_dinque(uid)
    if not self.player_dingque_map then
        return
    end

    return self.player_dingque_map[uid] or 0
end

function MT:get_player_discarded_titles(uid)
    if not self.all_discarded_tiles then
        return
    end

    local discarded_titles = assert(self.all_discarded_tiles[uid])
    return discarded_titles
end

function MT:get_player_win_title(uid)
    --TODO 还没有数据
    return 0
end

function MT:get_huangsanzhang_end_time()
    assert(self.game_status == GAME_STATUS_HUANSANZHANG)
    return self.curr_status_end_time or 0
end

function MT:get_huangsanzhang_direction()
    assert(self.game_status == GAME_STATUS_HUANSANZHANG)
    return self.huansanzhang_strategy
end

function MT:get_dingque_end_time()
    assert(self.game_status == GAME_STATUS_DINGQUE)
    return self.curr_status_end_time or 0
end

function MT:get_dies()
    return self.dies
end

function MT:get_player_changed_tiles_map()
    local changed_tiles_map = {}
    for _,uid in pairs(self.player_list) do
        local tmp = {
            tile_list = self.changed_map[uid],
            cardtoon_end_time = util.get_now_time() + HUANSANZHANG_CARTOON_TIME 
        }
        changed_tiles_map[uid] = tmp
    end

    return changed_tiles_map
end

function MT:get_player_dingque_map()
    return self.player_dingque_map
end

function MT:get_player_huansanzhang_map(uid)
    if not self.huansanzhang_map then
        return
    end
    return self.huansanzhang_map[uid]
end

function MT:is_huangsanzhang_over(curr_time)
    if curr_time > self.huansanzhang_end_time then
        return true
    end
    return false
end

function MT:is_dingque_over(curr_time)
    if curr_time > self.dingque_end_time then
        return true
    end
    return false
end

function MT:get_player_tile_info(uid)
    local player_tite_info = {}
    for _,tmp_uid in pairs(self.player_list) do
        local tmp = {
            uid = tmp_uid,
            tile_count = self:get_player_tile_count(tmp_uid),
            tile_list = self:get_player_tile_list(tmp_uid),
            peng_list = self:get_player_peng_info(tmp_uid),
            gang_list = self:get_player_gang_info(tmp_uid),
            angang_list = self:get_player_angang_list(tmp_uid),
            dingque = self:get_player_dinque(tmp_uid),
            discarded_tiles = self:get_player_discarded_titles(tmp_uid),
            win_tile = self:get_player_win_title(tmp_uid),
        }
        table_insert(player_tite_info,tmp)
    end

    return player_tite_info
end

function MT:is_dingque()
    return self.game_status == GAME_STATUS_DINGQUE
end

function MT:is_huansanzhang()
    return self.game_status == GAME_STATUS_HUANSANZHANG
end

function MT:is_playing()
    return self.game_status == GAME_STATUS_PLAYING and 
    (self.game_sub_status == GAME_SUB_STATUS_AFTER_DRAW or self.game_sub_status == GAME_SUB_STATUS_AFTER_PENG) 
end

function is_draw()
    return self.game_sub_status == GAME_SUB_STATUS_AFTER_DISCARD
end

function MT:get_game_status(uid)
    local game_status = {}
    game_status.banker_uid = self:get_banker_uid()
    game_status.cur_status = self.game_status
    game_status.player_tile_info_list = self:get_player_tile_info(uid)
    game_status.die_num = self.dies
    game_status.left_tile_count = #self.tile_list
    if self.game_status == GAME_STATUS_HUANSANZHANG then
        local data = {
            tile_list = self.huansanzhang_map[uid],
            exchange_end_time = self.curr_status_end_time,
            default_tile_list = self:get_auto_huansanzhang(uid),
        }
        game_status.huangsanzhang_data = data
    elseif self.game_status == GAME_STATUS_DINGQUE then
        local data = {
            que = self:get_player_dinque(uid),
            dingque_end_time = self.curr_status_end_time,
        }
        game_status.dingque_data = data
    elseif self.game_status == GAME_STATUS_PLAYING then
        local playing_data = {
            curr_player_uid = self:get_curr_player_uid(),
            curr_player_tile = self:get_curr_player_tile(),
            curr_end_time = self:get_curr_player_endtime(),
            option = self:get_player_op_type(uid),
        }
        game_status.playing_data = playing_data
    end
    return game_status
end

function MT:get_player_left_card_list()
    local player_left_card_list = {}
    for _,tmp_uid in pairs(self.player_list) do
        local tmp = { 
            uid = tmp_uid,
            cards = self:get_player_tile_list(tmp_uid),
        }
        table_insert(player_left_card_list,tmp)
    end

    return player_left_card_list
end

local function make_player_total_record(uid,record_list)
    local tmp = {
        uid = uid,
        total_score = 0,
        zimo_count = 0,
        jiepao_count = 0,
        dianpao_count = 0,
        angang_count = 0,
        gang_count = 0,
        dajiao_count = 0
    }

    for _,record in pairs(record_list) do
        tmp.total_score = tmp.total_score + record.score
        if record.op_type == OP_ZIMO then
            tmp.zimo_count = tmp.zimo_count + 1
        end
        if record.op_type == OP_DIANPAO then
            tmp.jiepao_count = tmp.jiepao_count + 1
        end
        if record.op_type == OP_BY_DIANPAO then
            tmp.dianpao_count = tmp.dianpao_count + 1
        end
        if record.op_type == OP_ANGANG then
            tmp.angang_count = tmp.angang_count + 1
        end
        if record.op_type == OP_GANG then
            tmp.gang_count = tmp.gang_count + 1
        end
        if record.op_type == OP_TINGPAI then
            tmp.dajiao_count = tmp.dajiao_count + 1
        end
    end

    return tmp
end

function MT:get_total_record_list()
    print_r(self.score_detail_map)
    
    local total_record_list = {}
    for uid,record_list in pairs(self.score_detail_map) do
        local tmp = make_player_total_record(uid,record_list)
        table_insert(total_record_list,tmp)
    end
    return total_record_list
end

local function get_player_add_score_detail(self,uid)
    local add_score_detail = {}
    for _,record in pairs(self.score_detail_map[uid]) do
        local tmp = { 
            op_type = record.op_type,
            score = record.score,
            hu_type = record.hu_type,
            uid_list = record.uid_list,
            addtion = record.addtion,
            fengding = record.fengding,
            fan = record.fan or 0,
        }
        table_insert(add_score_detail,tmp)
    end
    
    return add_score_detail
end

local function get_player_add_total_fan(self,uid)
    local total_fan = 0
    for _,record in pairs(self.score_detail_map[uid]) do
        total_fan = total_fan + (record.fan or 0)
    end

    return total_fan
end

local function get_total_score(records)
    local score = 0
    for _,record in pairs(records) do
        if not record then
            print("iiiiiiiiiiiiiiiiiiiiiiiiiiiiiii")
            print_r(records)
        end
        score = score + record.score
    end

    return score
end

local function get_hupai_type(self,uid)
    local hupai_result = self.player_hupai_map[uid]
    if not hupai_result then
        return 0
    end

    return hupai_result.type
end

function MT:get_player_record_list()
    print("get_player_record_list999999999")
    print_r(self.score_detail_map)

    local player_record_list = {}   
    for _,tmp_uid in pairs(self.player_list) do
        local tmp = { 
            uid = tmp_uid,
            add_score = get_total_score(self.score_detail_map[tmp_uid]),
            add_score_detail = get_player_add_score_detail(self,tmp_uid),
            add_fan = get_player_add_total_fan(self,tmp_uid),
        }
        table_insert(player_record_list,tmp)
    end

    return player_record_list
end

function MT:get_game_over_score_result()
    assert(self.game_status == GAME_STATUS_GAMEOVER)

    for uid, _ in pairs(self.tmp_gameover_score_result) do
        if not next(self.tmp_gameover_score_result[uid]) then
            self.tmp_gameover_score_result[uid] = nil
        end
    end
    return self.tmp_gameover_score_result
end

function MT:get_no_hupai_list(excepted_uid)
    local no_hupai_list = {}
    for _,uid in pairs(self.player_list) do
        if not self.player_hupai_map[uid] and uid ~= excepted_uid then
            table_insert(no_hupai_list,uid)
        end
    end

    return no_hupai_list
end

local function make_gang_score(self,gang_type,uid,ganged_uid)
    local tmp_score_map = {}
    if gang_type == TYPE_GANG then
        tmp_score_map[uid] = { {op_type = OP_GANG,score = self.base_score,uid_list = {ganged_uid}} }
        tmp_score_map[ganged_uid] = { {op_type = OP_BY_GANG,score = -self.base_score,uid_list = {uid}} }
    elseif gang_type == TYPE_BUGANG then
        tmp_score_map[uid] = { {op_type = OP_BUGANG,score = self.base_score,uid_list = {ganged_uid}} }
        tmp_score_map[ganged_uid] = { {op_type = OP_BY_BUGANG,score = -self.base_score,uid_list = {uid}} }
    elseif gang_type == TYPE_ANGANG then
        local tmp = {op_type = OP_BY_ANGANG,score = -2 * self.base_score,uid_list = {uid}}
        local no_hupai_list = self:get_no_hupai_list(uid)
        for _,tmp_uid in pairs(no_hupai_list) do
            tmp_score_map[tmp_uid] = {tmp}
        end
        tmp = {op_type = OP_ANGANG,score = #no_hupai_list * 2 * self.base_score,uid_list = no_hupai_list}
        tmp_score_map[uid] = {tmp}
    else
        errlog("make_gang_score type err ",gang_type)
    end

    for uid,record_list in pairs(tmp_score_map) do
        for _,record in pairs(record_list) do
            table_insert(self.score_detail_map[uid],record)
        end
    end
    return tmp_score_map
end

-- hupai_result = {
--         zimo = true,
--         uid = uid,
--         hupai_result = max_fan_result,
--         tile = self.curr_player_drawn_tile,  --胡的牌
-- }

--  hupai_result =
--  {
--     fangpao = curr_uid,
--     uid = uid,
--     hupai_result = max_fan_result,
--     tile = curr_tile
-- }

local function is_duanyaojiu(self,player_tile_list,gangpeng_map)
    if not self.rules.duanyaojiu then
        return false
    end

    for _,tile in pairs(player_tile_list) do
        if tile % 10 == 1 or tile % 10 == 9 then
            return false
        end 
    end
    for tile,_ in pairs(gangpeng_map) do
        if tile % 10 == 1 or tile % 10 == 9 then
            return false
        end 
    end

    return true
end

local function is_mengqing(self,gangpeng_map,angang_map)
    if not self.rules.mengqing then
        return false
    end

    for tile,count in pairs(gangpeng_map) do
        if count == 3 then --有碰牌
            return false
        end

        if count == 4 and not angang_map[tile] then --有明杠
            return false
        end
    end
    return true
end

local function is_haidilaoyue(self,zimo)
    if not self.rules.haidilaoyue then
        return false
    end
    if #self.tile_list >= 1 then
        return false
    end
    if not zimo then
        return false
    end

    return true
end

local function is_tianhu(self,uid)
    if not self.rules.tiandi_hu then
        return false
    end

    if uid ~= self.banker_uid then
        return false
    end

    if next(self.all_discarded_tiles[uid]) then
        return false
    end

    if next(self.player_gangpeng_map[uid]) then
        return false
    end

    return true
end

local function is_dihu(self,uid)
    if not self.rules.tiandi_hu then
        return false
    end

    if uid == self.banker_uid then
        return false
    end
    if next(self.all_discarded_tiles[uid]) then
        return false
    end

    if next(self.player_gangpeng_map[uid]) then
        return false
    end

    return true
end

local function is_dianganghua(self,uid)
    print_r(self.last_gang_map)
    
    if not self.last_gang_map[uid] then
        return false
    end
    if self.last_gang_map[uid].ganged_uid == uid then
        return false
    end
    if self.last_gang_map[uid].round ~= self.curr_discarding_round then
        return false
    end

    return true
end

local function is_gangshangpao(self,fangpao_uid)
    print("11is_gangshangpao11 111111111111111111",fangpao_uid)
    if not fangpao_uid then
        return false
    end
    if not self.last_gang_map[fangpao_uid] then
        return false
    end
    if self.last_gang_map[fangpao_uid].round + 1 ~= self.curr_discarding_round then
        return false
    end

    return true
end

local function is_gangshanghua(self,uid)
    print("zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz",uid,self.curr_discarding_round)
    print_r(self.last_gang_map)

    if self.last_gang_map[uid] and self.last_gang_map[uid].round == self.curr_discarding_round then
        return true
    end

    return false
end

local function is_qianggang(self,uid,tile)
    print("is_qianggang1111111111111111111")
    print_r(self.player_giveup_records_map)

    local player_giveup_records_map = self.player_giveup_records_map[uid]
    local record = player_giveup_records_map[tile]
    if record and record.qiang_gang then
        return true
    end
    return false
end

local function is_hujiaozhuanyi(self,result)
    if not self.rules.hujiaozhuanyi then
        return false
    end
    if not result.fangpao then
        return false
    end
    if not self.last_gang_map[result.fangpao] then
        return false
    end
    if self.last_gang_map[result.fangpao].round + 1 ~= self.curr_discarding_round then
        return false
    end

    return true
end

-- local OP_GANG      = 1
-- local OP_BY_GANG   = 2
-- local OP_BUGANG    = 3
-- local OP_BY_BUGANG = 4
-- local OP_ANGANG    = 5
-- local OP_BY_ANGANG = 6
-- local OP_ZIMO        = 7
-- local OP_BY_ZIMO     = 8
-- local OP_DIANPAO     = 9
-- local OP_BY_DIANPAO  = 10

local function get_player_yuqian(self,uid)
    local player_score_detail_list = assert(self.score_detail_map[uid]) 
    local yuqian = 0
    for _,record in pairs(player_score_detail_list) do
        if record.op_type == OP_GANG or record.op_type == OP_BUGANG or 
           record.op_type == OP_ANGANG then
           yuqian = yuqian + record.score
        end
    end

    return yuqian
end

local function get_gen_count(self,uid,hupai_result)
    if  hupai_result.type == xuezhan_checker.HU_QIDUI or
        hupai_result.type == xuezhan_checker.HU_LONGQIDUI or
        hupai_result.type == xuezhan_checker.HU_QINGQIDUI or 
        hupai_result.type == xuezhan_checker.HU_QINGLONGQIDUI then
        return 0
    end

    local gen_count = 0 
    local player_tile_list = assert(self.player_tiles_map[uid])
    local tile_map = build_tile_map(player_tile_list)
    for tile,count in pairs(tile_map) do
        if count >= 4 then
            gen_count = gen_count  + 1
        end
    end
    for tile,count in pairs(self.player_gangpeng_map[uid]) do
        if count >= 4 then
            gen_count = gen_count  + 1
        end
    end
    
    return gen_count
end

local function calculate_hupai_score(self,result,player_tile_list,gangpeng_map,angang_map)
    local hupai_result = assert(result.hupai_result) 
    local uid = assert(result.uid)
    local fan = hupai_result.fan
    local score = 0
    local addtion_type_map = {}
    if result.zimo and self.rules.zimo_addition == 1 then  --自摸加底
        print("player zimo_addition 111",uid)
        score = score + self.base_score
        addtion_type_map.zimo_addition = 1
    elseif result.zimo and self.rules.zimo_addition == 2 then --自摸加倍
        print("player zimo_addition 222",uid)
        fan = fan + 1
        addtion_type_map.zimo_addition = 2
    end
    --断吆九(中张)
    if is_duanyaojiu(self,player_tile_list,gangpeng_map) then
        print("player is_duanyaojiu 333",uid)
        fan = fan + 1
        addtion_type_map.duanyaojiu = true
    end
    --门清
    if is_mengqing(self,gangpeng_map,angang_map) then
        print("player is_mengqing 444",uid)
        fan = fan + 1
        addtion_type_map.mengqing = true
    end
    --海底捞月
    if is_haidilaoyue(self,result.zimo) then
        print("player is_haidilaoyue 555",uid)
        fan = fan + 1
        addtion_type_map.haidilaoyue = true
    end
    --天地胡
    if is_tianhu(self,uid) then
        print("player is_tianhu 666",uid)
        fan = fan + 6
        addtion_type_map.tiandihu = 1
    elseif is_dihu(self,uid) then
        print("player is_tianhu 777",uid)
        fan = fan + 6
        addtion_type_map.tiandihu = 2
    end
    --杠上炮
    if is_gangshangpao(self,result.fangpao) then
        print("player is_gangshangpao 888",uid)
        fan = fan + 1
        addtion_type_map.gangshangpao = true
    end
    --杠上花
    if is_gangshanghua(self,uid) then
        print("player is_gangshanghua 101010",uid)
        fan = fan + 1
        addtion_type_map.dianganghua = true
    end
    --抢杠
    if is_qianggang(self,uid,result.tile) then
        print("player is qiang_gang+++++++++++++ 101010",uid)
        fan = fan + 1
        addtion_type_map.qianggang = true
    end
    --根
    local gen_count = get_gen_count(self,uid,hupai_result)
    if gen_count > 0 then
        print("player is_gangshangpao 999",gen_count)
        fan = fan + gen_count
        addtion_type_map.gen_count = gen_count
    end

    local fengding = false 
    if fan >= self.rules.limit_rate then
        fengding = true
        fan = self.rules.limit_rate
    end
    score = self.base_score * math.floor(2^(fan - 1)) + score

    return fan,score,addtion_type_map,fengding
end

local function mark_huanjiaozhuangyi(self,uid)
    assert(self.score_detail_map[uid])

    for _,record in pairs(self.score_detail_map[uid]) do
        if record.op_type == OP_GANG or record.op_type == OP_BUGANG or record.op_type == OP_ANGANG then
            record.zhuangyi = true
        end
    end
end

local function make_hu_score(self,hupai_result,player_tile_list,gangpeng_map)
    local result = hupai_result.hupai_result
    local uid = hupai_result.uid
    local angang_map = assert(self.player_angang_map[uid]) 
    local fan,score,addtion_type_map,fengding = calculate_hupai_score(self,hupai_result,player_tile_list,gangpeng_map,angang_map)

    print("7777777777777777777777777777",uid)
    print_r(addtion_type_map)
    print_r(self.score_detail_map[uid])
    local score_result = {}
    if hupai_result.zimo then
        print("make_hu_score1111111111111111111111111111111111")
        print_r(self.rules)
        if is_dianganghua(self,uid) and self.rules.dianganghua == 2 then --点杠花当点炮
            local ganged_uid = assert(self.last_gang_map[uid].ganged_uid) 
             print("make_hu_score222222222222222222222222222222222222222",ganged_uid)
            local tmp1 = {
                op_type = OP_ZIMO,
                hu_type = result.type,
                score = score,
                uid_list = {ganged_uid},
                addtion = addtion_type_map,
                fengding = fengding,
                fan = fan or 0,
            }
            table_insert(self.score_detail_map[uid],tmp1)

            local tmp2 = {
                op_type = OP_BY_ZIMO,
                hu_type = result.type,
                score = -score,
                uid_list = {uid},
                addtion = addtion_type_map,
                fan = fan or 0,
            }
            table_insert(self.score_detail_map[ganged_uid],tmp2)

            return {[uid] = {tmp1},[ganged_uid] = {tmp2}}
        end

        local no_hupai_list = self:get_no_hupai_list(uid)
        local tmp1 = {
            op_type = OP_BY_ZIMO,
            hu_type = result.type,
            score = -score,
            uid_list = {uid},
            addtion = addtion_type_map ,
            fan = fan or 0
        }
        for _,tmp_uid in pairs(no_hupai_list) do
            table_insert(self.score_detail_map[tmp_uid],tmp1)
            score_result[tmp_uid] = {tmp1}
        end    

        local tmp2 = {
            op_type = OP_ZIMO,
            hu_type = result.type,
            score = #no_hupai_list*score,
            uid_list = no_hupai_list,
            addtion = addtion_type_map,
            fengding = fengding,
            fan = fan or 0,
        }
        table_insert(self.score_detail_map[uid],tmp2)
        score_result[uid] = {tmp2}
    elseif hupai_result.fangpao then
        --呼叫转移
        score_result = {[uid] = {},[hupai_result.fangpao] = {}}
        if is_hujiaozhuanyi(self,hupai_result) then
            local yuqian = get_player_yuqian(self,hupai_result.fangpao)
            local tmp1 = {op_type = OP_BY_HUJIAOZHUANGYI, score = -yuqian,uid_list = {uid}}
            table_insert(self.score_detail_map[hupai_result.fangpao],tmp1)

            local tmp2 = {op_type = OP_HUJIAOZHUANGYI, score = yuqian,uid_list = {hupai_result.fangpao}}
            table_insert(self.score_detail_map[uid],tmp2)

            table_insert(score_result[hupai_result.fangpao],tmp1)
            table_insert(score_result[uid],tmp2)

            mark_huanjiaozhuangyi(self,hupai_result.fangpao)
        end

        local tmp1 = {
            op_type = OP_DIANPAO,
            hu_type = result.type,
            score = score,
            uid_list = {hupai_result.fangpao},
            addtion = addtion_type_map,
            fengding = fengding,
            fan = fan or 0,
        }
        table_insert(self.score_detail_map[uid],tmp1)

        local tmp2 = {
            op_type = OP_BY_DIANPAO,
            hu_type = result.type,
            score = -score,
            uid_list = {uid},
            addtion = addtion_type_map,
            fan = fan or 0
        }
        table_insert(self.score_detail_map[hupai_result.fangpao],tmp2)

        table_insert(score_result[uid],tmp1)
        table_insert(score_result[hupai_result.fangpao],tmp2)
    end

    print("22222222222222222222222222222222")
    print_r(self.score_detail_map[uid])
    return score_result
end

local function make_player_op_type(self,ret_uid_map)
    for uid,result in pairs(ret_uid_map) do
        self.op_type_map[uid] = result
    end

    print("make_player_op_type7")
    print_r(self.op_type_map)
end

local function clean_player_op_type(self,uid)
    assert(self.op_type_map[uid])
    self.op_type_map[uid] = {}
end

function MT:get_player_op_type(uid)
    assert(self.op_type_map[uid])

    return {
        peng = self.op_type_map[uid].peng,
        gang = self.op_type_map[uid].gang or self.op_type_map[uid].bugang or self.op_type_map[uid].angang,
        hu = self.op_type_map[uid].hu,
    }
end

local function copy_table(t)
    local new_t = {}
    for k,v in pairs(t) do
        new_t[k] = v
    end
    return new_t
end

local function check_others_when_discarding(self,curr_uid,curr_tile)
    local player_giveup_records_map = self.player_giveup_records_map
    local player_dingque_map = self.player_dingque_map
    local player_gangpeng_map = self.player_gangpeng_map
    local player_hupai_map = self.player_hupai_map
    local curr_discarding_round = assert(self.curr_discarding_round)

    --检查玩家是否要过这张牌了，如果要过则其无法操作该牌
    local ret_uid_map = {}
    
    for uid,player_tile_list in pairs(self.player_tiles_map) do
        if uid == curr_uid then
            goto continue
        end

        if player_hupai_map[uid] then
            --玩家已经胡牌了，无需判断
            goto continue
        end

        --打出的牌是缺牌不能要
        if math_floor(curr_tile/10) == player_dingque_map[uid] then
            goto continue
        end

        local records = player_giveup_records_map[uid]
        if records[curr_tile] then
            --同一张牌有记录，这次肯定不能再继续了
            goto continue
        end

        local r = {}

        --记录下还未操作过
        local tiles_map = build_tile_map(player_tile_list)
        --看看能否碰,可以的话要记录下来
        local tile_count = tiles_map[curr_tile] or 0
        if tile_count >= 2 then
            r.peng = true
        end

        if tile_count >= 3 and #self.tile_list > 0 then
            r.gang = true
        end

        --并没有放弃过胡,则可以看看能否胡
        local test_player_tile_list = copy_table(player_tile_list)
        table_insert(test_player_tile_list,curr_tile)

        --检查是否能胡？
        local result_list = xuezhan_checker.check_hupai(test_player_tile_list,
            player_dingque_map[uid],player_gangpeng_map[uid],self.rules)

        print('ffffffffffffff',uid,tostring_r(result_list))
        if result_list and #result_list > 0 then
            --可以胡,需要记录番数
            local parsed_result_list = xuezhan_checker.parse_hupai_list(result_list,
                player_gangpeng_map[uid],self.rules)
            
            local max_fan
            for _,parsed_result in ipairs(parsed_result_list) do
                if not max_fan or max_fan < parsed_result.fan then
                    max_fan = parsed_result.fan
                end
            end

            --这里要记住可胡时候的最大番，不然下次没法比较下一张能胡的牌
            if records.max_fan then
                if assert(max_fan) > records.max_fan then
                    records.max_fan = max_fan
                    r.hu = true
                end
            else
                r.hu = true
                records.max_fan = max_fan
            end
        end

        if next(r) then
            r.op = YAOPAI_OP_INIT
            r.round = curr_discarding_round

            records[curr_tile] = r
            ret_uid_map[uid] = r
        end

        ::continue::
    end
    make_player_op_type(self,ret_uid_map)

    return ret_uid_map
end

local function exchange_next_set_draw_tile(self,tile)
    print("exchange_next_set_draw_tile+++++++++++++",tile)
    print_r(self.tile_list)
    for index,tmp_tile in pairs(self.tile_list) do
        if tmp_tile == tile then
            local len = #self.tile_list
            self.tile_list[index],self.tile_list[len] = self.tile_list[len],self.tile_list[index]
        end
    end
end

--检查庄主是否可以胡，暗杠
local function check_banker_start_status(self,uid)
    local ret = { uid = uid }

    local player_tile_list = assert(self.player_tiles_map[uid]) 
    local gangpeng_map = assert(self.player_gangpeng_map[uid])
    --检查是否能胡？
    local result_list = xuezhan_checker.check_hupai(player_tile_list,
        self.player_dingque_map[uid],gangpeng_map)
    if result_list and #result_list > 0 then
        --可以胡
        ret.hu = true
    end

    --判断下自己是否还有暗杠
    local tiles_map = build_tile_map(player_tile_list)
    for tile,count in pairs(tiles_map) do
        if count >= 4 and math_floor(tile/10) ~= self.player_dingque_map[uid] then
            ret.angang = true
        end
    end

    return ret
end

--摸一张牌
local function draw_one_tile(self,uid)
    --决定下一个玩家
    if self.force_next_uid then
        assert(not uid)
        uid = self.force_next_uid
        self.force_next_uid = nil
    end

    local curr_player_index
    if uid then
        curr_player_index = get_player_index(self.player_list,uid)
        self.curr_player_index = curr_player_index
    else
        --找出还没胡的那个人
        repeat
            curr_player_index = turn_to_next_index(self,self.curr_player_index)
            self.curr_player_index = curr_player_index
            uid = self.player_list[curr_player_index]
        until not self.player_hupai_map[uid]
    end

    --取一个牌
    local new_tile
    if self.test_player_draw_tile[uid] then
        exchange_next_set_draw_tile(self,self.test_player_draw_tile[uid])
        self.test_player_draw_tile[uid] = nil
    end
    new_tile = assert(table_remove(self.tile_list))

    --判断下自己是否可以杠或者胡
    local player_tile_list = self.player_tiles_map[uid]
    table_insert(player_tile_list,new_tile)

    self.curr_player_drawn_tile = new_tile
    self.curr_player_end_time = util.get_now_time() + DRAW_TILE_WAITING_TIME
    self.curr_player_discarded_tile = nil

    --自己抽了牌，则需要删除之前各种弃牌的记录
    local player_giveup_records_map = self.player_giveup_records_map
    if next(player_giveup_records_map[uid]) then
        player_giveup_records_map[uid] = {}
    end

    local ret = {
        uid = uid,
        tile = new_tile,
    }

    local gangpeng_map = assert(self.player_gangpeng_map[uid])
    --检查是否能胡？
    local result_list = xuezhan_checker.check_hupai(player_tile_list,
        self.player_dingque_map[uid],gangpeng_map)
    if result_list and #result_list > 0 then
        --可以胡
        print("huhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhuhu+++++++++")
        ret.hu = true
        local r = {hu = true,op = YAOPAI_OP_INIT,round = self.curr_discarding_round}
        self.player_giveup_records_map[uid][new_tile] = r
    end

    local tiles_map = build_tile_map(player_tile_list)
    local tile_count = assert(tiles_map[new_tile])
    if gangpeng_map[new_tile] and gangpeng_map[new_tile] >= 3 
       and #self.tile_list > 0 then
        print("mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmm",new_tile)
        ret.bugang = true
        local r = {bugang = true,op = YAOPAI_OP_INIT,round = self.curr_discarding_round}
        self.player_giveup_records_map[uid][new_tile] = r
    end

    --判断下自己是否还有暗杠
    local angang = {}
    for tile,count in pairs(tiles_map) do
        if count >= 4 and math_floor(tile/10) ~= self.player_dingque_map[uid] then
            table_insert(angang,tile)
        end
    end

    if #angang > 0 and #self.tile_list > 0 then
        ret.angang = angang
    end

    if ret.angang then
        print("angang999999999999++++++++++++++++++")
        print_r(player_tile_list)
    end

    self.game_sub_status = GAME_SUB_STATUS_AFTER_DRAW
    make_player_op_type(self,{[uid] = ret})

    return ret
end

--设置下一张摸到的牌
function MT:set_next_draw_tile(uid,tile)
    print("set_next_draw_tile++++++++++++++++",tile)
    print_r(self.tile_list)

    for index,tmp_tile in pairs(self.tile_list) do
        if tmp_tile == tile then
            self.test_player_draw_tile[uid] = tile
            return true
        end
    end
    return -1000
end

function MT:get_curr_player_drawn_tile()
    return self.curr_player_drawn_tile or 0
end

function MT:is_player_can_win(uid)
    local record = self.player_giveup_records_map[uid][self.curr_player_drawn_tile]
    print("is_player_can_win333333333333333",self.curr_player_drawn_tile,self.curr_discarding_round)
    print_r(self.player_giveup_records_map)

    if not record then
        return false
    end

    if not record.hu or record.round ~= self.curr_discarding_round then
        return false
    end

    return true
end

local function do_discard(self,uid,tile)
    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,300
    end

    print_r(self.player_hupai_map)

    if self.player_hupai_map[uid] then
        --玩家已经胡过牌了
        return false,310
    end

    --当前是不是轮到自己出牌
    local curr_uid = assert(self:get_curr_player_uid())
    if curr_uid ~= uid then
        return false,302
    end 

    --是不是已经出过牌了
    if self.curr_player_discarded_tile then
        return false,303
    end

    local tiles_map = build_tile_map(player_tile_list)
    local tile_count = tiles_map[tile]
    if not tile_count then
        --并无此牌
        return false,301
    end

    --删除此牌，然后看下其它人是否能胡
    del_from_tile_list(player_tile_list,{[tile] = 1})

    table_insert(self.all_discarded_tiles[uid],tile)

    self.curr_player_discarded_tile = tile
    self.curr_tile_been_taken = nil
    self.curr_discarding_round = self.curr_discarding_round + 1

    --判断下有没有人能碰或胡，有的话则延长时间
    local curr_time = util.get_now_time()
    local ret_uid_map = check_others_when_discarding(self,uid,tile)

    print_r(ret_uid_map)

    if next(ret_uid_map) then
        --其它人可以要这张牌，则延长时间
        self.curr_player_end_time = curr_time + DISCARD_TILE_WAITING_TIME
    else
        self.curr_player_end_time = curr_time   --不用等了
    end
    self.game_sub_status = GAME_SUB_STATUS_AFTER_DISCARD
    clean_player_op_type(self,uid)

    return true,{
        uid = uid,
        tile = tile,
        op_map = ret_uid_map,
    }
end

--出牌
function MT:do_discard(uid,tile)
    assert(self.game_status == GAME_STATUS_PLAYING)
    return do_discard(self,uid,tile)
end

local function check_others_when_bugang(self,curr_uid,curr_tile)
    local player_dingque_map = self.player_dingque_map
    local player_gangpeng_map = self.player_gangpeng_map
    local player_hupai_map = self.player_hupai_map

    --检查玩家是否要过这张牌了，如果要过则其无法操作该牌
    local ret_uid_map = {}
    
    for uid,player_tile_list in pairs(self.player_tiles_map) do
        if uid == curr_uid then
            goto continue
        end

        if player_hupai_map[uid] then
            --玩家已经胡牌了，无需判断
            goto continue
        end

        --打出的牌是缺牌不能要
        if math_floor(curr_tile/10) == player_dingque_map[uid] then
            goto continue
        end

        --检查是否可以胡
        local r = {}
        local test_player_tile_list = copy_table(player_tile_list)
        table_insert(test_player_tile_list,curr_tile)

        local result_list = xuezhan_checker.check_hupai(test_player_tile_list,
            player_dingque_map[uid],player_gangpeng_map[uid],self.rules)

        print('ffffffffffffff',uid,tostring_r(result_list))
        if result_list and #result_list > 0 then
            r.hu = true
            r.qiang_gang = true
        end

        if next(r) then
            ret_uid_map[uid] = r
        end

        ::continue::
    end

    return ret_uid_map
end

--补杠
local function do_bugang(self,curr_uid,curr_tile)
    print("777777777777777777777777777777777777777777",curr_uid,curr_tile)
    print_r(self.all_discarded_tiles[curr_uid])
    assert(curr_tile == table_remove(self.all_discarded_tiles[curr_uid]))

    self.player_gangpeng_map[curr_uid][curr_tile] = 4
    local tmp_uid = assert(self.player_gangpeng_info_map[curr_uid][curr_tile].penged_uid) 
    self.player_gangpeng_info_map[curr_uid][curr_tile] = {gang = true,ganged_uid = tmp_uid}
    local t = {round = assert(self.curr_discarding_round),ganged_uid = curr_uid,type = TYPE_BUGANG}
    self.last_gang_map[curr_uid] = t

    return make_gang_score(self,TYPE_BUGANG,curr_uid,tmp_uid)
end

--杠其它人
local function do_gang_other(self,uid)
    local player_gangpeng_map = self.player_gangpeng_map
    local curr_uid = assert(self:get_curr_player_uid())
    local curr_tile = assert(self.curr_player_discarded_tile)

    assert(uid ~= curr_uid)

    --杠其它人的，必然是已经有记录了
    local records = assert(self.player_giveup_records_map[uid])
    if not records[curr_tile] then
        return {ok = false,result = 411}
    end

    if records[curr_tile].op ~= YAOPAI_OP_GANG or 
        not records[curr_tile].gang then
        return {ok = false,result = 412}
    end

    --杠其它人
    local player_tile_list = assert(self.player_tiles_map[uid])
    local tiles_map = build_tile_map(player_tile_list)
    assert(tiles_map[curr_tile] == 3)

    local gangpeng_map = player_gangpeng_map[uid]
    assert(not gangpeng_map[curr_tile])

    --从牌堆里删除该牌
    assert(curr_tile == table_remove(self.all_discarded_tiles[curr_uid]))

    --删除记录，放入杠中
    del_from_tile_list(player_tile_list,{[curr_tile] = 3})
    gangpeng_map[curr_tile] = 4

    records[curr_tile] = nil
    if records.max_fan then
        records.max_fan = nil
    end

    assert(not self.force_next_uid)
    self.force_next_uid = uid
    self.game_sub_status = GAME_SUB_STATUS_AFTER_GANG
    local score_result = make_gang_score(self,TYPE_GANG,uid,curr_uid)
    self.last_gang_map[uid] = {round = assert(self.curr_discarding_round),ganged_uid = curr_uid,type = TYPE_GANG}
    self.player_gangpeng_info_map[uid][curr_tile] = {gang = true,ganged_uid = curr_uid}

    return {ok = true,result = curr_tile,ganged_uid = curr_uid,score_result = score_result}
end

function MT:do_gang(uid,gang_tile)
    assert(self.game_status == GAME_STATUS_PLAYING)

    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,400
    end

    if self.player_hupai_map[uid] then
        --玩家已经胡过牌了
        return false,410
    end

    local player_gangpeng_map = self.player_gangpeng_map
    local player_angang_map = self.player_angang_map
    local curr_uid = assert(self:get_curr_player_uid())

    local gang_type = 0
    local score_result
    local player_hu_op_map = {}

    --当前是玩家自己摸的牌
    if uid == curr_uid then
        local curr_tile = self.curr_player_drawn_tile
        if not curr_tile then
            --当前没有摸牌，很有可能是因为碰了别人的牌，现在轮到自己打
            return false,408
        end
        local gangpeng_map = player_gangpeng_map[uid]
        local tile_count = gangpeng_map[curr_tile] 
        
        if tile_count then
            --补杠
            if tile_count + 1 ~= 4 then
                return false,401
            end
            --补杠的时候，必然是已经有记录了
            local records = assert(self.player_giveup_records_map[uid])
            if not records[curr_tile] then
                return false,408
            end
            if records[curr_tile].op ~= YAOPAI_OP_INIT or not records[curr_tile].bugang then
                --可能是已经操作过了
                return false,409
            end

            self.curr_player_discarded_tile = curr_tile
            del_from_tile_list(player_tile_list,{[curr_tile] = 1})
            table_insert(self.all_discarded_tiles[curr_uid],curr_tile)

            print("ttttttttttttttttttttttttttttttttttttttttt")
            print_r(self.all_discarded_tiles[curr_uid])

            local curr_time = util.get_now_time()
            self.curr_player_end_time = curr_time
            player_hu_op_map = check_others_when_bugang(self,curr_uid,curr_tile)
            print_r("KKKKKKKKKKKKKKKKKKKKKKKKKKKKKK")
            print_r(player_hu_op_map)

            if next(player_hu_op_map) then
                for uid,_ in pairs(player_hu_op_map) do
                    local r = {hu = true,op = YAOPAI_OP_INIT,round = self.curr_discarding_round,qiang_gang = true}
                    self.player_giveup_records_map[uid][curr_tile] = r
                end 
                --其它人可以要这张牌，则延长时间
                self.curr_player_end_time = curr_time + DISCARD_TILE_WAITING_TIME
            end

            records[curr_tile].op = YAOPAI_OP_BUGANG
            self.game_sub_status = GAME_SUB_STATUS_AFTER_BUGANG
            gang_type = TYPE_BUGANG
            gang_tile = curr_tile
        else
            --暗杠
            local tiles_map = build_tile_map(player_tile_list)
            if tiles_map[gang_tile] ~= 4 then
                return false,402
            end

            if math_floor(gang_tile/10) == self.player_dingque_map[uid] then
                return false,403
            end

            assert(not player_angang_map[uid][gang_tile])
            --删除三个牌
            del_from_tile_list(player_tile_list,{[gang_tile] = 4})
            player_angang_map[uid][gang_tile] = true
            gangpeng_map[gang_tile] = 4
            gang_type = TYPE_ANGANG
            self.game_sub_status = GAME_SUB_STATUS_AFTER_GANG
            score_result = make_gang_score(self,TYPE_ANGANG,curr_uid)
            self.last_gang_map[uid] = {round = assert(self.curr_discarding_round),ganged_uid = curr_uid,type = TYPE_ANGANG}
        end

        assert(not self.force_next_uid)
        self.force_next_uid = uid
        
        return true,gang_type,gang_tile,score_result,player_hu_op_map
    else
        local curr_tile = self.curr_player_discarded_tile
        --杠其它人的，必然是已经有记录了
        local records = assert(self.player_giveup_records_map[uid])
        if not records[curr_tile] then
            return false,411
        end

        if records[curr_tile].op ~= YAOPAI_OP_INIT or
            not records[curr_tile].gang then
            --可能是已经操作过了
            return false,412
        end

        --这里不实际去杠，仅仅做记录,还要等裁决
        records[curr_tile].op = YAOPAI_OP_GANG
    end
    clean_player_op_type(self,uid)

    return true
end

local function do_peng(self,uid)
    local player_gangpeng_map = self.player_gangpeng_map
    local curr_uid = assert(self:get_curr_player_uid())
    local curr_tile = assert(self.curr_player_discarded_tile)

    assert(uid ~= curr_uid)

    --杠其它人的，必然是已经有记录了
    local records = assert(self.player_giveup_records_map[uid])
    if not records[curr_tile] then
        return {ok = false,result = 411}
    end

    if records[curr_tile].op ~= YAOPAI_OP_PENG or 
        not records[curr_tile].peng then
        return {ok = false,result = 511}
    end

    --碰其它人
    local player_tile_list = assert(self.player_tiles_map[uid])
    local tiles_map = build_tile_map(player_tile_list)
    assert(tiles_map[curr_tile] >= 2)

    local gangpeng_map = player_gangpeng_map[uid]
    assert(not gangpeng_map[curr_tile])

    --从牌堆里删除该牌
    assert(curr_tile == table_remove(self.all_discarded_tiles[curr_uid]))

    --删除记录，放入杠中
    del_from_tile_list(player_tile_list,{[curr_tile] = 2})
    gangpeng_map[curr_tile] = 3

    records[curr_tile] = nil
    if records.max_fan then 
        records.max_fan = nil
    end

    -- 碰了之后需要打出牌
    self.curr_player_index = get_player_index(self.player_list,uid)
    self.curr_player_drawn_tile = nil
    self.curr_player_discarded_tile = nil   --还未打牌，因此置为nil
    self.curr_player_end_time = util.get_now_time() + DRAW_TILE_WAITING_TIME
    print("888888888888888888888888888888888888")
    self.game_sub_status = GAME_SUB_STATUS_AFTER_PENG
    clean_player_op_type(self,uid)
    self.player_gangpeng_info_map[uid][curr_tile] = {peng = true,penged_uid = curr_uid}

    return {ok = true,result = curr_tile,penged_uid = curr_uid}
end

function MT:do_peng(uid)
    assert(self.game_status == GAME_STATUS_PLAYING)

    local player_gangpeng_map = self.player_gangpeng_map
    local curr_uid = assert(self:get_curr_player_uid())
    local curr_tile = self.curr_player_discarded_tile

    if uid == curr_uid then
        --不能碰自己牌
        return false,501
    end
    
    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,509
    end

    if self.player_hupai_map[uid] then
        --玩家已经胡过牌了
        return false,510
    end

    --碰其它人的，必然是已经有记录了
    local records = assert(self.player_giveup_records_map[uid])
    if not records[curr_tile] then
        return false,511
    end

    if records[curr_tile].op ~= YAOPAI_OP_INIT or
        not records[curr_tile].peng then
        --可能是已经操作过了
        return false,512
    end
    
    records[curr_tile].op = YAOPAI_OP_PENG

    return true
end

local function get_can_hu_num(self)
    local curr_tile = self.curr_player_discarded_tile
    if not curr_tile then
        return
    end

    local count 
    for uid,records in pairs(self.player_giveup_records_map) do
        if records[curr_tile] and records[curr_tile].hu then
            count = (count or 0) + 1
        end
    end
    return count
end

local function do_hu(self,uid)
    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,500
    end

    local player_hupai_map = self.player_hupai_map
    if player_hupai_map[uid] then
        --玩家已经胡过牌了
        return false,510
    end

    local gangpeng_map = assert(self.player_gangpeng_map[uid])
    local dingque = assert(self.player_dingque_map[uid])
    local curr_uid = assert(self:get_curr_player_uid())
    
    local max_fan
    local max_fan_result

    local hupai_result
    local score_result
    local yipaoduoxiang
    if uid == curr_uid then
        if not self.curr_player_drawn_tile then
            return false,519
        end
        --检查是否能胡？
        local result_list = xuezhan_checker.check_hupai(player_tile_list,
            dingque,gangpeng_map)
        if not result_list or #result_list < 1 then
            return false,511
        end

        --可以胡,需要记录番数
        local parsed_result_list = xuezhan_checker.parse_hupai_list(result_list,
            gangpeng_map,self.rules)
        for _,parsed_result in ipairs(parsed_result_list) do
            if not max_fan or max_fan < parsed_result.fan then
                max_fan = parsed_result.fan
                max_fan_result = parsed_result
            end
        end

        assert(max_fan_result)

        hupai_result = {
            zimo = true,
            uid = uid,
            hupai_result = max_fan_result,
            tile = self.curr_player_drawn_tile,  --胡的牌
        }
        score_result = make_hu_score(self,hupai_result,player_tile_list,gangpeng_map)

        self.game_sub_status = GAME_SUB_STATUS_AFTER_ZIMO
    else
        local curr_tile = assert(self.curr_player_discarded_tile)
        local records = assert(self.player_giveup_records_map[uid])
        if not records[curr_tile] then
            --如果可以胡的话，应该一早就算出来的了
            return false,505
        end 

        if records[curr_tile].op ~= YAOPAI_OP_INIT or 
            not records[curr_tile].hu then
            return false,506
        end

        --先看下自己能拿什么胡先
        local test_player_tile_list = copy_table(player_tile_list)
        table_insert(test_player_tile_list,curr_tile)
        
        --检查是否能胡？
        local result_list = xuezhan_checker.check_hupai(test_player_tile_list,
            dingque,gangpeng_map)

        if not result_list or #result_list < 1 then
            return false,501
        end

        --可以胡,需要记录番数
        local parsed_result_list = xuezhan_checker.parse_hupai_list(result_list,
            gangpeng_map,self.rules)
        for _,parsed_result in ipairs(parsed_result_list) do
            if not max_fan or max_fan < parsed_result.fan then
                max_fan = parsed_result.fan
                max_fan_result = parsed_result
            end
        end

        assert(max_fan_result)
        records[curr_tile].op = YAOPAI_OP_HU

        --需要删除最后一张牌
        if not self.curr_tile_been_taken then
            self.curr_tile_been_taken = true
            print("nnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnnn",curr_uid)
            assert(curr_tile == table_remove(self.all_discarded_tiles[curr_uid]))
        end

        hupai_result = {
            fangpao = curr_uid,
            uid = uid,
            hupai_result = max_fan_result,
            tile = curr_tile
        }
        score_result = make_hu_score(self,hupai_result,player_tile_list,gangpeng_map)

        if (self.cur_round_hu_map[self.curr_discarding_round] or 0) >= 2 then
            yipaoduoxiang = true
        end
        self.cur_round_hu_map[self.curr_discarding_round] = (self.cur_round_hu_map[self.curr_discarding_round] or 0) + 1
    end

    --至此可以判定玩家胡牌
    player_hupai_map[uid] = assert(hupai_result)
    
    --下一家,必须找出还未胡牌的
    local curr_player_index = get_player_index(self.player_list,uid)
    local next_uid
    repeat
        curr_player_index = turn_to_next_index(self,curr_player_index)
        next_uid = self.player_list[curr_player_index]
    until not self.player_hupai_map[next_uid]
    self.force_next_uid = next_uid
    clean_player_op_type(self,uid)

    return true,{ hupai_result = hupai_result,score_result = score_result ,yipaoduoxiang = yipaoduoxiang}
end

function MT:do_hu(uid)
    assert(self.game_status == GAME_STATUS_PLAYING)
    return do_hu(self,uid)
end

--跳过当前的牌
local function do_pass(self,uid)
    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,600
    end

    local curr_uid = assert(self:get_curr_player_uid())

    --当前是玩家自己摸的牌,不允许过
    if uid == curr_uid then
        return false,601
    end

    local curr_tile = assert(self.curr_player_discarded_tile)
    local records = assert(self.player_giveup_records_map[uid])
    if not records[curr_tile] then
        --如果可以操作的话，在出牌者出牌的时候就算出来的了
        return false,605
    end

    if records[curr_tile].op ~= YAOPAI_OP_INIT then
        return false,606
    end
    records[curr_tile].op = YAOPAI_OP_PASS
    clean_player_op_type(self,uid)

    return true
end

--过牌<<不胡，不碰，不杠>>
function MT:do_pass(uid)
    assert(self.game_status == GAME_STATUS_PLAYING)
    if not self.curr_player_discarded_tile then
         return true
    end

    return do_pass(self,uid)
end

function MT:auto_select_discarded_tile(uid)
    local player_tile_list = self.player_tiles_map[uid]
    if not player_tile_list then
        return false,300
    end

    assert(not self.player_hupai_map[uid])
    local dingque = assert(self.player_dingque_map[uid])
    table_sort(player_tile_list)

    --先选缺牌，如果没有则再选最右牌
    local discarded_tile
    for i = #player_tile_list,1,-1 do
        local tile = player_tile_list[i]
        if math_floor(tile / 10) == dingque then
            discarded_tile = tile
            break
        end
    end

    if not discarded_tile then
        discarded_tile = assert(player_tile_list[#player_tile_list])
    end

    return true,discarded_tile
end

local function do_tuishui(self,uid)
    local tuishui_map = {}
    for _,tmp in pairs(self.score_detail_map[uid]) do
        if (tmp.op_type == OP_GANG or tmp.op_type == OP_BUGANG or tmp.op_type == OP_ANGANG) and not tmp.zhuangyi then
            for _,tmp_uid in pairs(tmp.uid_list) do
                tuishui_map[tmp_uid] = ( tuishui_map[tmp_uid] or 0 ) + tmp.score / #tmp.uid_list
            end
        end
    end

    local tuishui_uid_list = {}
    local yuqian = 0
    for tmp_uid,score in pairs(tuishui_map) do
        local t = { op_type = OP_TUISHUI,score = score,uid_list = {uid}}
        table_insert(self.score_detail_map[tmp_uid],t)
        table_insert(self.tmp_gameover_score_result[tmp_uid],t)

        table_insert(tuishui_uid_list,tmp_uid)
        yuqian = yuqian + score
    end
    if yuqian > 0 then
        local t = { op_type = OP_BY_TUISHUI,score = -yuqian,uid_list = tuishui_uid_list }
        table_insert(self.score_detail_map[uid],t)
        table_insert(self.tmp_gameover_score_result[uid],t)
    end

    print("ddddddddddddddddddddddddddddddddddddd")
    print_r(self.tmp_gameover_score_result)
end

local function check_tuishui(self)
    local no_hupai_list = self:get_no_hupai_list()
    for _,uid in pairs(no_hupai_list) do
        local tile_list = assert(self.player_tiles_map[uid]) 
        local que = assert(self.player_dingque_map[uid])
        local gangpeng_map = assert(self.player_gangpeng_map[uid]) 
        local result_list = xuezhan_checker.check_tingpai(tile_list,que,gangpeng_map)
        if not result_list or not next(result_list) then --没有听牌
            do_tuishui(self,uid)
        end
    end
end

local function is_huazhu(self,uid)
    local tmp_map = {}
    local player_tile_list = assert(self.player_tiles_map[uid])
    for _,tile in pairs(player_tile_list) do
        tmp_map[math.floor(tile / 10)] = true
    end
    local count = 0
    for _,_ in pairs(tmp_map) do
        count = count + 1
    end
    if count >= 3 then
        return true
    end
end

local function do_huazhu_punishment(self,huazhu_list,no_huazhu_list)
    if not next(huazhu_list) or not next(no_huazhu_list) then
        return
    end

    for _,uid in pairs(huazhu_list) do
        local fan = self.rules.limit_rate or 6
        local total_score = self.base_score * math_floor(2^(fan - 1))
        local t = { op_type = OP_BY_HUAZHU,score = -total_score * #no_huazhu_list,uid_list = no_huazhu_list,fan = fan}
        table_insert(self.score_detail_map[uid],t)
        table_insert(self.tmp_gameover_score_result[uid],t)
        for _,tmp_uid in pairs(no_huazhu_list) do
            local t = { op_type = OP_HUAZHU,score = total_score,uid_list = {uid},fengding = true,fan = fan}
            table_insert(self.score_detail_map[tmp_uid],t)
            table_insert(self.tmp_gameover_score_result[tmp_uid],t)
        end
    end

    print_r(self.tmp_gameover_score_result)
end

local function check_huazhu(self)
    if not self:is_liuju() then
        return
    end

    local huazhu_list = {}
    local no_huazhu_list = {}
    local no_hupai_list = self:get_no_hupai_list()
    for _,uid in pairs(no_hupai_list) do
        if is_huazhu(self,uid) then
            table_insert(huazhu_list,uid)
        else
            table_insert(no_huazhu_list,uid)
        end
    end

    print("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
    print_r(huazhu_list)
    print_r(no_huazhu_list)

    do_huazhu_punishment(self,huazhu_list,no_huazhu_list)
end

local function is_tingpai(self,uid)
    local tile_list = assert(self.player_tiles_map[uid]) 
    local que = assert(self.player_dingque_map[uid])
    local gangpeng_map = assert(self.player_gangpeng_map[uid]) 
    local result_list = xuezhan_checker.check_tingpai(tile_list,que,gangpeng_map)
    if result_list and next(result_list) then
        return true
    end
    return false
end

local function calculate_max_fan_when_tingpai(self,uid)
    local tile_list = assert(self.player_tiles_map[uid]) 
    local que = assert(self.player_dingque_map[uid])
    local gangpeng_map = assert(self.player_gangpeng_map[uid]) 
    local result_list = assert(xuezhan_checker.check_tingpai(tile_list,que,gangpeng_map))
    assert(result_list)
    print("calculate_max_fan_when_tingpai11111",uid)
    print_r(result_list)
    local tmp_result_list = {}
    for _,result in pairs(result_list) do
        table_insert(tmp_result_list,result:sub(1,result:find('-') - 1))
    end
    print_r(tmp_result_list)
    result_list = tmp_result_list

    local parsed_result_list = xuezhan_checker.parse_hupai_list(result_list,gangpeng_map,self.rules)
    print("calculate_max_fan_when_tingpai22222",uid)
    print_r(parsed_result_list)
    
    local max_fan
    for _,parsed_result in ipairs(parsed_result_list) do
        local fan = get_gen_count(self,uid,parsed_result) + parsed_result.fan
        if not max_fan or max_fan < fan then
            max_fan = fan
        end
    end

    return max_fan
end

local function do_no_tingpai_punishment(self,tingpai_list,no_tingpai_list)
    if not next(tingpai_list) or not next(no_tingpai_list) then
        return
    end

    for _,tmp_uid in pairs(tingpai_list) do
        local max_fan = calculate_max_fan_when_tingpai(self,tmp_uid)
        local fengding = false
        if max_fan >= self.rules.limit_rate then
            fengding = true
            max_fan = self.rules.limit_rate
        end

        for _,uid in pairs(no_tingpai_list) do
            local score = self.base_score * math_floor(2^(max_fan - 1)) 
            local t = { op_type = OP_TINGPAI,score = score,uid_list = {uid},fengding = fengding,fan = max_fan}
            table_insert(self.score_detail_map[tmp_uid],t)
            table_insert(self.tmp_gameover_score_result[tmp_uid],t)

            local t = { op_type = OP_BY_TINGPAI,score = -score,uid_list = { tmp_uid },fan = max_fan}
            table_insert(self.score_detail_map[uid],t)
            table_insert(self.tmp_gameover_score_result[uid],t)
        end
    end

    print_r(self.tmp_gameover_score_result)
end

local function check_tingpai(self)
    if not self:is_liuju() then
        return
    end

    local tingpai_list = {}
    local no_tingpai_list = {}
    local no_hupai_list = self:get_no_hupai_list()
    for _,uid in pairs(no_hupai_list) do
        if is_tingpai(self,uid) then
            table_insert(tingpai_list,uid)
        elseif not is_huazhu(self,uid) then
            table_insert(no_tingpai_list,uid)
        end
    end
    print("ccccccccccccccccccccccccccccccccc")
    print_r(tingpai_list)
    print_r(no_tingpai_list)

    do_no_tingpai_punishment(self,tingpai_list,no_tingpai_list)
end

local function game_over(self)
    assert(self.game_status == GAME_STATUS_PLAYING)

    self.game_status = GAME_STATUS_GAMEOVER

    --检查退税
    check_tuishui(self)
    --查花猪
    check_huazhu(self)
    --查叫
    check_tingpai(self)
end

local function switch_next_player(self)
    assert(self.game_status == GAME_STATUS_PLAYING)
    if #self.tile_list < 1 then
        --没牌了，游戏结束
        game_over(self)
        return
    end

    --是不是只剩下一家胡了
    local hu_count = 0
    for _ in pairs(self.player_hupai_map) do
        hu_count = hu_count + 1
    end

    if hu_count >= REQUIRED_PLAYER_NUM - 1 then
        game_over(self)
        return
    end
    
    --下一家
    return assert(draw_one_tile(self))
end

--[[
    有人胡了   【有人选择了胡】 则把杠碰玩家状态取消掉
    没人胡     【1、有人可以胡但是全选了不胡。2、没有任何人可以胡】 
]]
local function check_and_auto_handle(self,curr_time)
    local player_giveup_records_map = self.player_giveup_records_map
    local player_hupai_map = self.player_hupai_map

    local curr_tile = assert(self.curr_player_discarded_tile)
    local curr_discarding_round = assert(self.curr_discarding_round)
    
    local auto = {}
    --玩家出过牌了，则判断其它人是否需要操作
    local curr_uid = assert(self:get_curr_player_uid())
    local op_timeout = (curr_time >= self.curr_player_end_time)

    print("check_and_auto_handle++++++++++++++++++++",op_timeout,curr_uid,curr_time,self.curr_player_end_time)

    local hupai_map = {}
    local hupai_count = 0
    local gangpeng_record
    local auto_hupai_list = {}

    local round_over = true
    print_r(player_giveup_records_map)

    for uid,records in pairs(player_giveup_records_map) do
        print("111111111111111111111111111111111",uid,curr_discarding_round,curr_tile)
        local r = records[curr_tile]
        if not r then
            goto continue
        end

        if  not r.bugang and uid == curr_uid then
            goto continue
        end

        if r.round ~= curr_discarding_round then
            goto continue
        end

        print("444444444444444444444444444444444444")
        local op = r.op
        if r.hu and op == YAOPAI_OP_INIT and op_timeout then
            --超时默认帮其胡
            op = YAOPAI_OP_HU
            table_insert(auto_hupai_list,uid)
        end

        if (r.gang or r.peng or r.bugang) and op == YAOPAI_OP_INIT and op_timeout then
            --超时默认过牌
            op = YAOPAI_OP_TIMEOUT_PASS
        end

        if r.hu and op == YAOPAI_OP_INIT then
            --可以胡但还未操作
            hupai_map[uid] = op
        elseif op == YAOPAI_OP_HU then
            --已经确定是胡了，无论是系统还是自己手动
            hupai_map[uid] = op
            hupai_count = hupai_count + 1
        end

        if r.gang or r.peng or r.bugang then
            assert(not gangpeng_record)
            gangpeng_record = {[uid] = op}
        end
        print("55555555555555555555555555555555555555555",op)
        if op == YAOPAI_OP_INIT then
            round_over = false
        end

        ::continue::
    end

    --自动胡牌
    for _,uid in ipairs(auto_hupai_list) do
        local _,ret = assert(do_hu(self,uid))
        auto[uid] = {hu = ret}
    end

    if hupai_count > 0 and gangpeng_record then
        --有人胡牌则放弃碰与杠了,无论玩家选的要与否
        local uid,op = next(gangpeng_record)
        --可能是一个既可胡又可碰的玩家
        if hupai_map[uid] then
            --该玩家既可胡又可碰
            local r = player_giveup_records_map[uid][curr_tile]
            assert(r.gang or r.peng)
            r.gang = nil
            r.peng = nil
            r.bugang = nil
            --应该取消PASS比较合适
        else
            auto[uid] = {gangpeng = YAOPAI_OP_PASS}
            player_giveup_records_map[uid][curr_tile] = nil
        end
    elseif not next(hupai_map) and gangpeng_record then
        --没人可胡，并有杠碰
        local uid,op = next(gangpeng_record)
        if op == YAOPAI_OP_GANG then
            local ret = assert(do_gang_other(self,uid))
            auto[uid] = {gangpeng = YAOPAI_OP_GANG, ret = ret}
            player_giveup_records_map[uid] = {}
        elseif op == YAOPAI_OP_BUGANG then
            local score_result = assert(do_bugang(self,uid,curr_tile))
            auto[uid] = {gangpeng = YAOPAI_OP_BUGANG, ret = score_result}
            player_giveup_records_map[uid] = {}
        elseif op == YAOPAI_OP_PENG then
            local ret = assert(do_peng(self,uid))
            auto[uid] = {gangpeng = YAOPAI_OP_PENG, ret = ret}
            player_giveup_records_map[uid] = {}
        elseif op == YAOPAI_OP_TIMEOUT_PASS then
            local _,ret = assert(do_pass(self,uid))
            auto[uid] = {gangpeng = YAOPAI_OP_PASS}
        end
    end

    for uid,op in pairs(hupai_map) do
        --[[
            已经胡牌的人，则删除掉记录,
            之所以不在胡牌的时候直接删除是因为需要取消杠碰的玩家
        ]]
        if op == YAOPAI_OP_HU then
            player_giveup_records_map[uid][curr_tile] = nil
        end
    end

    return round_over,auto
end

function MT:check_playing(curr_time)
    --检查玩家是否已经出过牌了

    print("cur game sub status ++++++++++++++++++++++++",self.game_sub_status)
    if self.game_sub_status == GAME_SUB_STATUS_AFTER_DRAW or 
       self.game_sub_status == GAME_SUB_STATUS_AFTER_PENG then
        print("6666666666666666666666++++++++++++++",curr_time,self.curr_player_end_time)
        if curr_time < self.curr_player_end_time then
            return false
        end

        local uid = assert(self:get_curr_player_uid())
        print('get_curr_player_uid',uid)
        --玩家未出过牌且超时了，则需要帮玩家出牌
        local _,tile = assert(self:auto_select_discarded_tile(uid))
        local _,ret = assert(do_discard(self,uid,tile))
        return true,{discard = ret}
    end

    local result = {}
    local round_over = true
    local auto
    if self.game_sub_status == GAME_SUB_STATUS_AFTER_DISCARD or 
       self.game_sub_status == GAME_SUB_STATUS_AFTER_BUGANG then
        round_over,auto = check_and_auto_handle(self,curr_time)
        print("77777777777777777777+++++++++++++++++",round_over)
        print_r(auto)
    end

    if auto and next(auto) then
        --自动操作
        --assert(next(auto))
        result.auto = auto
    end

    if (round_over and self.game_sub_status == GAME_SUB_STATUS_AFTER_DISCARD) or 
        (round_over and self.game_sub_status == GAME_SUB_STATUS_AFTER_BUGANG) or
        self.game_sub_status == GAME_SUB_STATUS_AFTER_GANG  or 
        self.game_sub_status == GAME_SUB_STATUS_AFTER_ZIMO  then
        assert(round_over)
        result.drawing = switch_next_player(self)
    end

    return true,result
end

function MT:start_play()
    assert(self.game_status == GAME_STATUS_DINGQUE)

    local player_gangpeng_map = {}
    local player_giveup_records_map = {}
    local player_angang_map = {}
    local all_discarded_tiles = {}
    local score_detail_map = {}
    local op_type_map = {}
    local last_gang_map = {}
    local player_gangpeng_info_map = {}
    local tmp_gameover_score_result = {}
    for _,uid in pairs(self.player_list) do
        player_gangpeng_map[uid] = {}
        player_giveup_records_map[uid] = {}
        player_angang_map[uid] = {}
        all_discarded_tiles[uid] = {}
        score_detail_map[uid] = {}
        op_type_map[uid] = {}
        player_gangpeng_info_map[uid] = {}
        tmp_gameover_score_result[uid] = {}
    end
    self.player_gangpeng_map = player_gangpeng_map
    self.player_giveup_records_map = player_giveup_records_map
    self.player_angang_map = player_angang_map
    self.all_discarded_tiles = all_discarded_tiles
    self.score_detail_map = score_detail_map
    self.op_type_map = op_type_map
    self.last_gang_map = last_gang_map
    self.player_gangpeng_info_map = player_gangpeng_info_map
    self.tmp_gameover_score_result = tmp_gameover_score_result
    self.player_hupai_map = {}
    self.curr_discarding_round = 0
    self.curr_status_end_time = nil

    self.game_status = GAME_STATUS_PLAYING

    self.curr_player_index = get_player_index(self.player_list,self.banker_uid)
    self.curr_player_end_time = util.get_now_time() + DRAW_TILE_WAITING_TIME
    self.curr_player_discarded_tile = nil
    
    --开始抽第一张牌
    local ret = assert(check_banker_start_status(self,self.banker_uid))
    return true,ret
end

function MT:is_game_over()
    return self.game_status == GAME_STATUS_GAMEOVER
end

function MT:is_liuju()
    if self.game_status ~= GAME_STATUS_GAMEOVER then
        return false
    end
    local no_hupai_list = self:get_no_hupai_list()
    if #no_hupai_list <= 1 then
        return false
    end

    return true
end

function MT:get_game_type()
    return 2
end
-------------------------exported----------
local M = {}
function M.new()
    local o = {}
    return setmetatable(o, MT)
end


-------------------------test----------------------------------
function M.test_set(k,v)
    if k == 'DRAW_TILE_WAITING_TIME' then DRAW_TILE_WAITING_TIME = tonumber(v) or DRAW_TILE_WAITING_TIME end
    if k == 'DISCARD_TILE_WAITING_TIME' then DISCARD_TILE_WAITING_TIME = tonumber(v) or DISCARD_TILE_WAITING_TIME end
    if k == 'HUANSANZHANG_WAITING_TIME' then HUANSANZHANG_WAITING_TIME = tonumber(v) or HUANSANZHANG_WAITING_TIME end
    if k == 'DINGQUE_WAITING_TIME' then DINGQUE_WAITING_TIME = tonumber(v) or DINGQUE_WAITING_TIME end

end

M.REQUIRED_PLAYER_NUM = REQUIRED_PLAYER_NUM
M.HUANSANZHANG_CARTOON_TIME = HUANSANZHANG_CARTOON_TIMEP
M.TYPE_GANG = TYPE_GANG
M.TYPE_ANGANG = TYPE_ANGANG
M.TYPE_BUGANG = TYPE_BUGANG
M.YAOPAI_OP_GANG = YAOPAI_OP_GANG
M.YAOPAI_OP_PENG = YAOPAI_OP_PENG
M.YAOPAI_OP_BUGANG = YAOPAI_OP_BUGANG
M.OP_ZIMO = OP_ZIMO
M.OP_DIANPAO =  OP_DIANPAO
M.OP_BY_DIANPAO = OP_BY_DIANPAO
M.OP_ANGANG = OP_ANGANG
M.OP_GANG = OP_GANG
M.OP_TINGPAI = OP_TINGPAI
M.DINGQUE_WAITING_TIME = DINGQUE_WAITING_TIME
M.HUANSANZHANG_WAITING_TIME = HUANSANZHANG_WAITING_TIME
M.GAME_SUB_STATUS_AFTER_DRAW = GAME_SUB_STATUS_AFTER_DRAW

return M