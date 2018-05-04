local table_insert = table.insert
local table_sort = table.sort
local math_floor = math.floor
local table_remove = table.remove
local table_unpack = table.unpack
--TODO random函数是非线程安全的，这个方法后期要自己实现线程安全的版本
local math_random = math.random
math.randomseed(os.time())
local util = require "util"
local lz_match_cards = require "lz_match_cards"
local M = {}

local MAX_PLAYER_NUM = 3
local MAX_CARD_NUM = 54
local SETING_DIZHU_TIME = 15
local PLAY_TIME = 20
local MAX_ROB_DIZHU_TIMES = 4
local JIABEI_TIME = 6

local SET_DIZHU_WAY_ROB = 1
local SET_DIZHU_WAY_SCORE = 2

local SCORE_SELECT_ONE = 1  --1分
local SCORE_SELECT_TWO = 2  -- 2分
local SCORE_SELECT_THREE = 3 --3分

local SIGN_NONE = 0         --大小王
local SIGN_CLUB = 1         --梅花
local SIGN_DIAMOND = 2      --钻石
local SIGN_HEART = 3        --桃心
local SIGN_SPADE = 4        --黑桃

local DIZHU_CHUN_TIAN = 1
local FARMER_CHUN_TIAN = 2

local JIABEI_TYPE_GIVEUP = 0
local JIABEI_TYPE_PUTONG = 1
local JIABEI_TYPE_CHAOJI = 2

--[[
    每张卡牌分别由1-10,J,Q,K,black joker,red jocker 定义为1-15
--]]
local BLACK_JOKER_NUMBER = 14
local RED_JOKER_NUMBER = 15

local POWER_MAP = {
    [3] = 1,
    [4] = 2,
    [5] = 3,
    [6] = 4,
    [7] = 5,
    [8] = 6,
    [9] = 7,
    [10] = 8,
    [11] = 9, --J
    [12] = 10, --Q
    [13] = 11, --K
    [1] = 12,    --A

    [2] = 14,    --2

    [BLACK_JOKER_NUMBER] = 16,  --black joker
    [RED_JOKER_NUMBER] = 18,  --red joker
}

assert(#POWER_MAP == 15)

local CONTINUOUS_CARD_MAP = {}
for k,v in ipairs(POWER_MAP) do CONTINUOUS_CARD_MAP[v] = k end

local GAME_STATUS_INIT = 0          --初始化状态
local GAME_STATUS_STARTED = 1       --游戏已经开始
local GAME_STATUS_SETING_DIZHU = 2  --抢地主状态
local GAME_STATUS_JIABEI = 3        --加倍状态
local GAME_STATUS_PLAYING = 4       --玩牌状态
local GAME_STATUS_OVER = 5          --结束状态
local GAME_STATUS_NODIZHU_OVER = 6  --没有地主重新开始

local C = {

}

local function make_card_id(sign,number)
    return sign * 100 + number
end

local function extract_card_number(card_id)
    return card_id % 100
end

local function get_player_index(player_list,uid)
    for i,_uid in ipairs(player_list) do
        if uid == _uid then
            return i
        end
    end
end

function C:init()
    --生成所有的牌
    local cards = {}
    for i = 1,13 do
        for j = 1,4 do
            table_insert(cards,make_card_id(j,i))
        end
    end

    table_insert(cards,make_card_id(SIGN_NONE,14))
    table_insert(cards,make_card_id(SIGN_NONE,15))

    self.game_status = GAME_STATUS_INIT
    self.cards = cards
    self.player_cards_map = nil
    self.record_list = {}   --台面上的出牌记录
    self.dizhu_uid = 0         --地主uid
    self.dizhu_cards = {}   --地主多的那三张牌,需要表现
    self.next_player_index = 0      --下一个出牌的玩家
    self.play_end_time = 0  --下一个出牌玩家的出牌结束时间
    self.player_list = {}
    self.setting_uid = 0  --抢地主玩家uid
    self.setting_pos = 0  --抢地主玩家位置、
    self.cur_count = 0
    self.setting_end_time = 0
    self.base_score = 1   --底分
    self.rate = 1--倍数
    self.player_rob_score = {} --玩家抢地主分数
    self.give_up_dizhu_list = {} -- 放弃抢地主玩家list
    self.rob_dizhu_list = {}    --抢地主玩家list
    self.rob_dizhu_history_list = {}    --抢地主历史
    self.laizi = 0
    self.set_dizhu_way = 0 --抢地主的方式 1抢地主 2叫分
    self.chun_tian_type = 0  --0无 1地主春天 2农民春天
    self.player_rate_list = {}  --玩家加倍倍数
    self.dipai_rate = 1
    self.mingpai_rate = 1
    self.rob_rate = 1
    self.zhadan_rate = 1
    self.chuntian_rate = 1 
    self.jiabei_end_time = 0 
    self.frist_ming_pai_uid = 0  --第一个明牌的
end

function C:enter(uid)
    local player_list = self.player_list
    if get_player_index(player_list,uid) then
        --已经在牌局上了
        return true
    end

    if #player_list >= MAX_PLAYER_NUM then
        return false
    end

    table_insert(player_list,uid)
    return true
end

function C:check_and_start()
    local player_list = self.player_list
    if #player_list < MAX_PLAYER_NUM then
        return false
    end
    assert(self.game_status == GAME_STATUS_INIT and #player_list == MAX_PLAYER_NUM)
    
    self.game_status = GAME_STATUS_STARTED

    local player_cards_map = {}
    for _,uid in pairs(player_list) do
        player_cards_map[uid] = {}
    end

    self.player_cards_map = player_cards_map

    return true
end

function C:shuffle(swap_times)
    assert(self.game_status == GAME_STATUS_STARTED)
    local cards = self.cards
    
    local card_count = #cards
    swap_times = card_count or swap_times
    for i = 1,swap_times do
        local n = math_random(1,card_count)
        local m = math_random(1,card_count)
        if n ~= m then
            cards[n],cards[m] = cards[m],cards[n]
        end
    end
end

--发牌
function C:deal()
    assert(self.game_status == GAME_STATUS_STARTED)
    local cards = self.cards
    local player_cards_map = self.player_cards_map
    assert(cards and player_cards_map)

    for i = 1,51,3 do
        local j = 0
        for _,card_id_set in pairs(player_cards_map) do
            card_id_set[cards[i + j]] = true
            j = j + 1
        end
    end

    self.dizhu_cards = {cards[52],cards[53],cards[54]}
end

local function get_dipai_rate(dizhu_cards)
    local card1,card2,card3 = table_unpack(dizhu_cards)
    assert(card1)
    assert(card2)
    assert(card3)
    local dipai_card = {}
    local power = {}
    for _,card_id in pairs(dizhu_cards) do
        local id = extract_card_number(card_id)
        local count = dipai_card[id] or 0
        count = count + 1
        dipai_card[id] = count
        table_insert(power,POWER_MAP[id])
    end
    if dipai_card[14] and dipai_card[15] then
        return 4
    end

    --有一张大王或小王
    if dipai_card[14] or dipai_card[15] then
        return 2
    end

    --3张一样
    for k,v in pairs(dipai_card) do
        if v == 3 then
            return 4
        end
    end

    --同花
    local huase = math_floor(card1 / 100)
    if math_floor(card2 / 100) == huase and math_floor(card3 / 100) == huase then
        return 3
    end
    --顺子
    table_sort(power)
    if power[1] + 1 == power[2] and power[2] + 1 == power[3] then
        return 3
    end
    return 1
end

--从地主开始出牌
function C:start_play()
    assert(self.game_status == GAME_STATUS_JIABEI)
    self.game_status = GAME_STATUS_PLAYING
    self.next_player_index = assert(get_player_index(self.player_list,self.dizhu_uid))
    self.play_end_time = util.get_now_time() + PLAY_TIME
end

function C:set_dizhu(uid)
    local dizhu_card_id_set = self.player_cards_map[uid]
    print("dizhu_card_id_set+++++++++++",dizhu_card_id_set,uid,self.dizhu_uid)
    assert(dizhu_card_id_set and (self.dizhu_uid == 0))

    self.jiabei_end_time = util.get_now_time() + JIABEI_TIME
    self.dizhu_uid = uid
    -- self.next_player_index = assert(get_player_index(self.player_list,uid))
    -- self.play_end_time = util.get_now_time() + PLAY_TIME
    --另外三张牌给地主
    for _,index in pairs(self.dizhu_cards) do
        assert(dizhu_card_id_set[index] == nil)
        dizhu_card_id_set[index] = true
    end

    self.dipai_rate = get_dipai_rate(self.dizhu_cards)

    --选癞子
    if self.laizi == 0 then
        local n = math_random(1,13)     
        self.laizi = n
    end

    self.setting_uid = 0
    self.setting_end_time = 0
    self.setting_pos = 0
    --self.game_status = GAME_STATUS_PLAYING
    self.game_status = GAME_STATUS_JIABEI
    print("laizi is ",self.laizi)
end

local function set_nodizhu(self)
    assert(self.game_status == GAME_STATUS_SETING_DIZHU)
    
    self.setting_uid = 0
    self.setting_end_time = 0
    self.setting_pos = 0
    self.game_status = GAME_STATUS_NODIZHU_OVER
end

local CARD_SUIT_TYPE_INVALID = 0        --无效牌型
local CARD_SUIT_TYPE_WANGZHA = 1        --王炸
local CARD_SUIT_TYPE_ZHADAN = 2         --炸弹
local CARD_SUIT_TYPE_DANPAI = 3         --单牌
local CARD_SUIT_TYPE_DUIPAI = 4         --对牌
local CARD_SUIT_TYPE_SANZANGPAI = 5     --三张牌
local CARD_SUIT_TYPE_SANDAIYI = 6       --三带一
local CARD_SUIT_TYPE_DANSHUN = 7        --单顺
local CARD_SUIT_TYPE_SHUANGSHUN = 8     --双顺
local CARD_SUIT_TYPE_FEIJI = 9       --飞机 
local CARD_SUIT_TYPE_FEIJIDAICIBANG = 10          --飞机带翅膀
local CARD_SUIT_TYPE_SIDAIER = 11       --四带二
local CARD_SUIT_TYPE_RUANZHA = 12    --软炸
local CARD_SUIT_TYPE_SANDAIYIDUI = 13   --三带一对
local CARD_SUIT_TYPE_SIDAILIANGDUI = 14 --四带两对


local function compare_power(self,last_record,card_suit_type,key,card_suit)
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key

    if last_card_suit_type == CARD_SUIT_TYPE_WANGZHA then
        return false 
    elseif last_card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        if card_suit_type == CARD_SUIT_TYPE_WANGZHA then
            return true
        end

        if card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            if last_card_suit_key == self.laizi then
                return false
            elseif key == self.laizi then
                return true    
            end
            return POWER_MAP[key] > POWER_MAP[last_card_suit_key]
        end

        return false
    elseif last_card_suit_type == CARD_SUIT_TYPE_RUANZHA then
        if card_suit_type == CARD_SUIT_TYPE_WANGZHA or card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            return true
        end    

        if card_suit_type == CARD_SUIT_TYPE_RUANZHA then
            return POWER_MAP[key] > POWER_MAP[last_card_suit_key]
        end

        return false
    end

    if card_suit_type == CARD_SUIT_TYPE_WANGZHA or card_suit_type == CARD_SUIT_TYPE_ZHADAN or 
    card_suit_type == CARD_SUIT_TYPE_RUANZHA then
        --王炸跟炸弹秒杀一切
        return true
    end

    --否则必须牌型相同
    if card_suit_type ~= last_card_suit_type or #last_record.card_suit ~= #card_suit then
        return false
    end

    return POWER_MAP[key] > POWER_MAP[last_card_suit_key]
end
M.compare_power = compare_power

--是否办到自己的
function C:is_my_turn(uid)
    return self.next_player_index == get_player_index(self.player_list,uid)
end

function C:turn_next_player()
    local next_player_index = self.next_player_index + 1
    if next_player_index > #self.player_list then
        next_player_index = next_player_index % #self.player_list
    end
    self.next_player_index = next_player_index
    self.play_end_time = util.get_now_time() + PLAY_TIME
end

function C:is_must_play(uid)
    local last_record = self.record_list[#self.record_list]
    if not last_record or last_record.uid == uid then
        return true
    end

    return false
end

--不出牌
function C:donot_play(uid)
    if self.game_status ~= GAME_STATUS_PLAYING then
        return false,-1
    end

    if not self:is_my_turn(uid) then
        return false,-2
    end

    local card_id_set = self.player_cards_map[uid]
	if not card_id_set then
		return false,-3
	end

    local last_record = self.record_list[#self.record_list]
    if not last_record then
        --第一个出牌的一定要出
        return false,-4
    end

    if last_record and last_record.uid == uid then
        --上一个是自己的话，不允许不出
        return false,-5
    end

    self:turn_next_player()
    
    
    return true
end

local function check_card_suit(card_suit_types_table,card_suit_type,key) 
    print("++++++++++++++++++++++++++++++",card_suit_type,key)
    local result = false
    for i=1,#card_suit_types_table do
        for type,k in pairs(card_suit_types_table[i]) do
            if type == card_suit_type and k == key then
                result = true
                break
            end
        end
    end
    return result
end

function C:check_and_play(uid,card_suit,card_suit_type,key)
    if self.game_status ~= GAME_STATUS_PLAYING then
        return false,-200
    end

    if not self:is_my_turn(uid) then
        return false,-100
    end
    
    local card_id_set = self.player_cards_map[uid]
	if not card_id_set then
		return false,-1
	end

    local card_number_set = {}

	local test = {}

    --is that card suit in my card
    for _,card_id in pairs(card_suit) do
		if not card_id_set[card_id] then
            print("my_card:",tostring_r(card_id_set))
			return false,-2
		end

		if test[card_id] then
			return false,-3
		end

		test[card_id] = true

		local number = extract_card_number(card_id)
		card_number_set[number] = (card_number_set[number] or 0) + 1
    end
    --print("+++++++++++++++++++++++number:")
    for card,count in pairs(card_number_set) do
        print(card,count)
    end

    local card_suit_types_table = lz_match_cards.get_card_suit_type(card_number_set,self:get_laizi_id())
    --print("+++++++++++++++++++++",tostring_r(card_suit_types_table),card_suit_type,key)
    if not card_suit_types_table or not check_card_suit(card_suit_types_table,card_suit_type,key) then
        print("fffffffffffffff",tostring_r(card_suit_types_table),card_suit_type,key)
        return false,-4
    end

    if #self.record_list > 0 then
        --考虑到上一个出牌者是自己的情况
        local last_record = self.record_list[#self.record_list]
        if last_record.uid ~= uid and not compare_power(self,last_record,card_suit_type,key,card_suit) then
            return false,-5   --牌型不够大
        end
    end

    --为了防止直接修改到参数，这里重新创建一个table
    local sorted_card_suit = {}
    for _,card_id in pairs(card_suit) do
        table_insert(sorted_card_suit,card_id)
    end
    table_sort(sorted_card_suit)
    
    return true,{
        uid = uid,
        card_suit_type = card_suit_type,
        key = key,
        card_suit = sorted_card_suit
    }
end

function C:check_chun_tian()
    assert(self.game_status == GAME_STATUS_OVER)
    assert(#self.record_list >= 1)
    assert(self.record_list[1].uid == self.dizhu_uid)

    local is_dizhu_chun_tian = true
    local is_farmer_chun_tian = true

    for index,record in pairs (self.record_list) do
        if index <= 1 then
            goto continue
        end
        if record.uid ~= self.dizhu_uid then
            is_dizhu_chun_tian = false
        else
            is_farmer_chun_tian = false
        end

        ::continue::
    end

    if is_dizhu_chun_tian then
        self.chun_tian_type = DIZHU_CHUN_TIAN
        return
    end

    if is_farmer_chun_tian then
        self.chun_tian_type = FARMER_CHUN_TIAN
    end
end

function C:check_add_rate(suit_type)
    if suit_type == CARD_SUIT_TYPE_WANGZHA or suit_type == CARD_SUIT_TYPE_ZHADAN or suit_type == CARD_SUIT_TYPE_RUANZHA then
        self.zhadan_rate = self.zhadan_rate * 2
    end

    if self.chun_tian_type == DIZHU_CHUN_TIAN or self.chun_tian_type == FARMER_CHUN_TIAN then
        self.chuntian_rate = self.chuntian_rate * 2
    end
end

function C:play(uid,card_suit,card_suit_type,key)
    local ok,result = self:check_and_play(uid,card_suit,card_suit_type,key)
    if not ok then
        return false,result
    end

    --标记已出的牌
    local card_id_set = assert(self.player_cards_map[uid])
    for _,card_id in ipairs(card_suit) do
        assert(card_id_set[card_id])
        card_id_set[card_id] = false
    end

    --这里可以出牌
    table_insert(self.record_list,result)

    --检查牌局是否结束
    local left_card_count = 0
    for _,valid in pairs(card_id_set) do
        if valid then
            left_card_count = left_card_count + 1
        end
    end

    local over = false
    --切换下一个玩家
    if left_card_count > 0 then
        self:turn_next_player()
    else
        self.game_status = GAME_STATUS_OVER
        over = true

        self:check_chun_tian()
    end

    local new_card_suit = {}
    local all_cards = lz_match_cards.match_cards(card_suit,self.laizi)
    --print("+++++++++++++++++",tostring_r(all_cards))
    if all_cards then
        for k,card_info in pairs(all_cards) do
            if card_info.type == card_suit_type and card_info.key == key then
                new_card_suit = card_info.card
            end
        end
    end

    --检查加倍
    self:check_add_rate(card_suit_type)

    return true,{
        card_suit_type = card_suit_type,
        card_suit = new_card_suit,
        card_suit_key = key,
        over = over,
        original_card_suit = card_suit,
        }
end

function C:get_dizhu_card_ids()
    if self.game_status <= GAME_STATUS_SETING_DIZHU then
        return {}
    end
    return self.dizhu_cards
end

function C:get_dizhu_uid()
    return self.dizhu_uid
end

function C:get_farmer_uids()
    local farmer_uids = {}
    for _,uid in pairs(self.player_list) do
        if self.dizhu_uid > 0 and self.dizhu_uid ~= uid then
            table_insert(farmer_uids,uid)
        end
    end
    assert(#farmer_uids == 2)
    return farmer_uids[1],farmer_uids[2]
end


function C:get_chun_tian_type()
    return self.chun_tian_type,self.record_list[#self.record_list].uid
end

function C:get_rival_the_remain_one_pai(uid)
    if uid == self.dizhu_uid then
        for i,_uid in ipairs(self.player_list) do
            if _uid ~= uid then
                local card_ids = self:get_player_card_ids(_uid)
                if #card_ids == REMAIN_CARD_COUNT_ONE then
                    return card_ids[1]
                end
            end
        end
    else --如果是农民
        local card_ids = self:get_player_card_ids(self.dizhu_uid)
        assert(#card_ids == REMAIN_CARD_COUNT_ONE)
        return card_ids[1]
    end
end

function C:get_next_player_uid()
    return self.player_list[self.next_player_index] or 0
end

function C:get_play_end_time()
    return self.play_end_time
end

function C:get_last_card_suit()
    if #self.record_list < 1 then
        return
    end

    local last_record = self.record_list[#self.record_list]
    return last_record.card_suit_type,last_record.card_suit,last_record.key
end

function C:get_last_card_suit_ex()
    if #self.record_list < 1 then
        return
    end

    return self.record_list[#self.record_list]
end

function C:is_game_over()
    return self.game_status == GAME_STATUS_OVER
end

function C:get_all_cards()
    return self.cards
end

function C:get_card_record_list()
    return self.record_list
end

function C:is_rob_dizhu()
    return self.game_status == GAME_STATUS_SETING_DIZHU
end

function C:is_playing()
    return self.game_status == GAME_STATUS_PLAYING
end

function C:is_jiabei()
    return self.game_status == GAME_STATUS_JIABEI
end

function C:get_game_result()
    if not self:is_game_over() then
        return false
    end

    assert(#self.record_list > 0)
    --公共倍数=基础倍数*抢地主倍数*明牌倍数*炸弹倍数*春天倍数*地主加倍
    local dizhu_jiabei = self.player_rate_list[self.dizhu_uid] or 1
    local rate = self.rate * self.rob_rate * self.mingpai_rate * self.dipai_rate * self.zhadan_rate * self.chuntian_rate * dizhu_jiabei

    local last_record = self.record_list[#self.record_list]
    local winner_uid = last_record.uid
    local dizhu_rate = 0
    if winner_uid == self.dizhu_uid then
        local losers = {}
        for _uid,_ in pairs(self.player_cards_map) do
            if _uid ~= winner_uid then
                local self_rate = self.player_rate_list[_uid] or 1
                table_insert(losers,{uid = _uid,add_score = -(self.base_score * rate * self_rate),base_score = self.base_score,rate = rate * self_rate })
                dizhu_rate = dizhu_rate + self_rate
            end
        end
        local dizhu_record = {{uid = winner_uid,add_score = self.base_score * rate * dizhu_rate,base_score = self.base_score,rate = rate * dizhu_rate}}
        return true,{winners = dizhu_record,losers = losers}
    else
        local winners = {}
        for _uid,_ in pairs(self.player_cards_map) do
            if _uid ~= self.dizhu_uid then
                local self_rate = self.player_rate_list[_uid] or 1
                table_insert(winners,{uid = _uid,add_score = self.base_score * rate *self_rate,base_score = self.base_score,rate = rate * self_rate })
                dizhu_rate = dizhu_rate + self_rate
            end
        end
        local dizhu_record2 = {{uid = self.dizhu_uid,add_score = -(self.base_score * rate * dizhu_rate),base_score = self.base_score,rate = rate * dizhu_rate}}
        return true,{winners = winners,losers = dizhu_record2}
    end
end

function C:get_player_card_ids(uid)
    local card_id_set = self.player_cards_map[uid]
    if not card_id_set then
        return nil,string.format('There is no such uid(%d) in this game',uid)
    end

    local cards_id_list = {}
    for card_id,valid in pairs(card_id_set) do
        if valid then
            table_insert(cards_id_list,card_id)
        end
    end

    return cards_id_list
end

function C:get_laizi_id()
    return self.laizi
end

function C:rand_seting_dizhu_player()
    assert(self.game_status == GAME_STATUS_SETING_DIZHU)
    if self.frist_ming_pai_uid > 0 then
        local postion = get_player_index(player_list,self.frist_ming_pai_uid)
        return postion,self.frist_ming_pai_uid
    end
    local index = math_random(1,#self.player_list)
    return index,self.player_list[index]
end


function C:setingdizhu_status(way)
    assert(self.game_status == GAME_STATUS_STARTED)
    self.game_status = GAME_STATUS_SETING_DIZHU
    self.setting_pos,self.setting_uid = self:rand_seting_dizhu_player()
    self.cur_count = 1
    self.setting_end_time = util.get_now_time() + SETING_DIZHU_TIME + 3.5
    self.set_dizhu_way = way
end

function C:set_base_score(score)
    self.base_score  = score
end

function C:set_rate(rate)
    self.rate = rate
end

function C:get_setting_info()
    return self.setting_uid,self.cur_count,self.setting_end_time,self.set_dizhu_way
end

function C:get_setting_uid()
    return self.setting_uid
end

function C:get_rob_count()
    return #self.rob_dizhu_list
end

function C:get_rob_dizhu_history_list()
    return self.rob_dizhu_history_list
end

function C:get_base_score_and_rate()
    return self.base_score,self.rate
end

function C:get_cur_setting_count()
    return self.cur_count
end

function C:get_score_rate_detail(uid)
    local dizhu_rate = self.player_rate_list[self.dizhu_uid] or 1
    local nongmin_rate = 0
    if uid == self.dizhu_uid then
        for _uid,_ in pairs(self.player_cards_map) do
            if self.dizhu_uid ~= 0 and _uid ~= self.dizhu_uid then
                local self_rate = self.player_rate_list[_uid] or 1
                nongmin_rate = self_rate + nongmin_rate
            end
        end
        if nongmin_rate == 0 then
            nongmin_rate = 2
        end
    else
        nongmin_rate = self.player_rate_list[uid] or 1
    end    


    local detail = {
        base_score = self.base_score,
        original_rate = self.rate,
        mingpai_rate = self.mingpai_rate,
        rob_rate = self.rob_rate,
        dipai_rate = self.dipai_rate,
        zhadan_rate = self.zhadan_rate,
        chuntian_rate = self.chuntian_rate,
        dizhu_rate = dizhu_rate,
        nongmin_rate = nongmin_rate,
        common_rate = self.rate * self.rob_rate * self.mingpai_rate * self.dipai_rate * self.zhadan_rate * self.chuntian_rate,
        total_rate = self.rate * self.rob_rate * self.mingpai_rate * self.dipai_rate * self.zhadan_rate * self.chuntian_rate * dizhu_rate * nongmin_rate,
    }
    return detail
end

function C:select_dizhu()
    local max_score = 0
    local dizhu_uid
    for _uid,score in pairs(self.player_rob_score) do
        if score > max_score then
            max_score = score
            dizhu_uid = _uid
        end
    end

    if not dizhu_uid and self.frist_ming_pai_uid > 0 then
        dizhu_uid = self.frist_ming_pai_uid
    end
    return dizhu_uid
end

function C:turn_next_rob_player()
    self.setting_pos = self.setting_pos % #self.player_list + 1
    if self.cur_count >= MAX_PLAYER_NUM then
        if #self.rob_dizhu_list >= 2 then
            self.setting_pos = get_player_index(self.player_list,self.rob_dizhu_list[1])
        end
    end

    self.setting_uid = self.player_list[self.setting_pos]
    self.setting_end_time = util.get_now_time() + SETING_DIZHU_TIME
end

local function is_rob_dizhu_over(self)
    if self.set_dizhu_way == SET_DIZHU_WAY_ROB then
        --抢了4次
        if self.cur_count >= MAX_ROB_DIZHU_TIMES then
            return true
        end
        --三个人放弃
        if #self.give_up_dizhu_list >= MAX_PLAYER_NUM then
            return true
        end
        --三人只有一个人叫地主
        if self.cur_count == MAX_PLAYER_NUM and #self.rob_dizhu_list == 1 then
            return true
        end
    elseif self.set_dizhu_way == SET_DIZHU_WAY_SCORE then
        if self.rob_rate >= SCORE_SELECT_THREE or self.cur_count >= MAX_PLAYER_NUM then
            return true
        end
    end
    
    return false
end

function C:get_rob_dizhu_result()
    if self.game_status == GAME_STATUS_JIABEI then
        return true,assert(self.dizhu_uid)
    end

    if self.game_status == GAME_STATUS_NODIZHU_OVER then
        return true
    end

    assert(self.game_status == GAME_STATUS_SETING_DIZHU)
    return false
end

function C:rob_dizhu(uid,score,is_rob,forced)
    assert(self.game_status == GAME_STATUS_SETING_DIZHU)
    assert(uid == self.setting_uid)

    if self.set_dizhu_way == SET_DIZHU_WAY_ROB then
        if is_rob then
            table_insert(self.rob_dizhu_list,uid)
            self.player_rob_score[uid] = #self.rob_dizhu_list
            if #self.rob_dizhu_list > 1 then
                self.rob_rate = 1 << (#self.rob_dizhu_list - 1)
            end 
        else
            table_insert(self.give_up_dizhu_list,uid)
        end
    elseif self.set_dizhu_way == SET_DIZHU_WAY_SCORE then
        if score > 0 then
            self.rob_rate = score 
            self.player_rob_score[uid] = score
            table_insert(self.rob_dizhu_list,uid) 
        else
            table_insert(self.give_up_dizhu_list,uid)
        end
    end

    table_insert(self.rob_dizhu_history_list,{uid = uid,is_rob = is_rob,score = score})

    local is_over = is_rob_dizhu_over(self)
    if is_over then
        local dizhu_uid = self:select_dizhu()
        if dizhu_uid then
            billlog({op="robdizhu",count=#self.rob_dizhu_list})
            print("++++++++++++",dizhu_uid)
            self:set_dizhu(dizhu_uid)
            return true,dizhu_uid
        elseif forced then
            local dizhu_idx = assert(util.randint(1,#self.player_list))
            dizhu_uid = self.player_list[dizhu_idx]
            billlog({op="robdizhu",count=#self.rob_dizhu_list,forced = true})
            self:set_dizhu(dizhu_uid)
            return true,dizhu_uid    
        else
            set_nodizhu(self)
            return true
        end     
    end

    self:turn_next_rob_player()
    self.cur_count = self.cur_count + 1

    return false
end

function C:get_player_record()
    local result = {}
    for _,v in pairs (self.record_list) do
        if not result[v.uid] then
            result[v.uid] = {}
        end

        table.insert(result[v.uid],v.card_suit)
    end
    return result
end

function C:get_other_player_cards(uid)
    local result = {}
    for _uid,card_ids in pairs(self.player_cards_map) do
       if uid ~= _uid then
          for card_id,valid in pairs(card_ids) do
              if valid then
                table_insert(result,card_id)
              end 
          end
       end
    end
    return result
end

function C:get_last_record()
    return self.record_list[#self.record_list]
end



function C:get_last_round_records()
    local last_round_records = {}

    for _,v in pairs(self.record_list) do
        table_insert(last_round_records,{ uid = v.uid,card_list = v.card_suit })
        if #last_round_records > MAX_PLAYER_NUM then
            table_remove(last_round_records,1)
        end
    end

    return last_round_records
end

function C:get_rival_min_card_count(is_dizhu)
    if not is_dizhu then
        local card_ids = self:get_player_card_ids(self.dizhu_uid)
        return #card_ids
    end

    local min_count = 100
    for i,_uid in ipairs(self.player_list) do
        if _uid == self.dizhu_uid then
            goto continue
        end
        local card_ids = self:get_player_card_ids(_uid)
        if min_count > #card_ids then
            min_count = #card_ids
        end

        ::continue::
    end

    return min_count
end

function C:get_teammate_min_card_count(except_uid)
    for _,_uid in ipairs(self.player_list) do
        if _uid ~= self.dizhu_uid and _uid ~= except_uid then
             local card_ids = self:get_player_card_ids(_uid)
            return #card_ids
        end
    end
end

function C:get_next_position_uid(uid)
    local cur_position = get_player_index(self.player_list,uid)
    local next_postion = cur_position % #self.player_list + 1
    local next_postion_uid = self.player_list[next_postion]

    return next_postion_uid
end

function C:get_next_pos_player_card_count(uid)
    local next_postion_uid = self:get_next_position_uid(uid)
    local card_ids = {}
    if next_postion_uid then
        card_ids = self:get_player_card_ids(next_postion_uid)
    end

    return #card_ids
end

function C:get_notify_dizhu_msg()
    assert(self.game_status == GAME_STATUS_JIABEI)
    --assert(self.game_status == GAME_STATUS_PLAYING)
    return {
        dizhu_uid = self.dizhu_uid,
        laizi_id = self.laizi,
        dizhu_card_id_list = self.dizhu_cards,
    }
end

function C:set_mingpai(uid,rate)
    if rate > self.mingpai_rate then
        self.mingpai_rate = rate 
    end   
    if self.frist_ming_pai_uid > 0 then
        return
    end
    self.frist_ming_pai_uid = uid
end


function C:check_all_player_jiabei()
    local jiabei_number = 0
    for _,_ in pairs(self.player_rate_list) do
        jiabei_number = jiabei_number + 1
    end

    return jiabei_number >= MAX_PLAYER_NUM
end

function C:get_jiabei_player_list()
    return self.player_rate_list
end

function C:jiabei(uid,type)
    --assert(self.game_status == GAME_STATUS_PLAYING)
    assert(self.game_status == GAME_STATUS_JIABEI)
    assert(self.player_rate_list[uid] == nil)
    if type == JIABEI_TYPE_GIVEUP then
        self.player_rate_list[uid] = 1
    elseif type == JIABEI_TYPE_PUTONG then
        self.player_rate_list[uid] = 2
    elseif type == JIABEI_TYPE_CHAOJI then
        self.player_rate_list[uid] = 4
    end        
end

function C:get_jiabei_end_time()
    return self.jiabei_end_time
end

function C:get_game_type()
    return 1
end

M.MAX_PLAYER_NUM         = MAX_PLAYER_NUM
M.SET_DIZHU_WAY_ROB      = SET_DIZHU_WAY_ROB
M.SET_DIZHU_WAY_SCORE    = SET_DIZHU_WAY_SCORE
M.CARD_SUIT_TYPE_WANGZHA = CARD_SUIT_TYPE_WANGZHA
M.CARD_SUIT_TYPE_ZHADAN  = CARD_SUIT_TYPE_ZHADAN
M.DIZHU_CHUN_TIAN        = DIZHU_CHUN_TIAN
M.FARMER_CHUN_TIAN       = FARMER_CHUN_TIAN
M.CARD_SUIT_TYPE_RUANZHA = CARD_SUIT_TYPE_RUANZHA
M.CARD_SUIT_TYPE_FEIJIDAICIBANG = CARD_SUIT_TYPE_FEIJIDAICIBANG
M.CARD_SUIT_TYPE_FEIJI = CARD_SUIT_TYPE_FEIJI

function M.new()
    local o = {}
    return setmetatable(o,{__index = C})
end

return M