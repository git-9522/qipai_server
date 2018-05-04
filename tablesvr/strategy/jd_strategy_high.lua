local lz_remind = require "lz_remind"
local util = require "util"

local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort

local assert = assert
local pairs = pairs
local ipairs = ipairs

local table_concat = table.concat
local string_format = string.format
local tostring = tostring

local function get_now_ustime()
    local time4,time5 = util.get_now_time() 
    return time4 * 1000000 + time5
end

local function draw_indent(indent)
    local s = {}
    for i = 1,indent do
        table_insert(s,'  ')
    end

    return table_concat(s,'')
end

local function _tostring_r(data,depth)
    if depth >= 6 then return '...' end
    if type(data) == 'table' then
        local s = {'{\n'}
        for k,v in pairs(data) do
            table_insert(s,string_format('%s%s:%s,\n',draw_indent(depth+1),tostring(k),_tostring_r(v,depth+1)))
        end
        table_insert(s,draw_indent(depth) .. '}\n')
        return table_concat(s,'')
    elseif type(data) == 'string' then
        return string_format('"%s"',tostring(data))
    else
        return tostring(data)
    end
end

local function tostring_r(data)
    return _tostring_r(data,0)
end

local CARD_SUIT_TYPE_INVALID = 0         --无效牌型
local CARD_SUIT_TYPE_WANGZHA = 1         --王炸
local CARD_SUIT_TYPE_ZHADAN = 2          --炸弹
local CARD_SUIT_TYPE_DANPAI = 3          --单牌
local CARD_SUIT_TYPE_DUIPAI = 4          --对牌
local CARD_SUIT_TYPE_SANZANGPAI = 5      --三张牌
local CARD_SUIT_TYPE_SANDAIYI = 6        --三带一
local CARD_SUIT_TYPE_DANSHUN = 7         --单顺
local CARD_SUIT_TYPE_SHUANGSHUN = 8      --双顺
local CARD_SUIT_TYPE_FEIJI = 9           --飞机
local CARD_SUIT_TYPE_FEIJIDAICIBANG = 10 --飞机带翅膀
local CARD_SUIT_TYPE_SIDAIER = 11        --四带二
local CARD_SUIT_TYPE_RUANZHA = 12        --软炸
local CARD_SUIT_TYPE_SANDAIYIDUI = 13    --三带一对
local CARD_SUIT_TYPE_SIDAILIANGDUI = 14  --四带两对

--[[
    每张卡牌分别由1-10,J,Q,K,black joker,red jocker 定义为1-15
--]]
local CARD_TWO_NUMBER = 2
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

local MARK_TYPE_WANGZHA = 1
local MARK_TYPE_ZHANDAN  = 2
local MARK_TYPE_DANPAI_RJOKER = 3
local MARK_TYPE_DANPAI_BJOKER = 4
local MARK_TYPE_DANPAI_TWO = 5

local MARK_TYPE_SCORE_MAP = {
    [MARK_TYPE_WANGZHA] = 8,--王炸8分
    [MARK_TYPE_ZHANDAN]  = 6,--炸弹6分
    [MARK_TYPE_DANPAI_RJOKER] = 4, --单牌大王4分
    [MARK_TYPE_DANPAI_BJOKER] = 3, --单牌小王3分
    [MARK_TYPE_DANPAI_TWO] = 2, --一张单牌二 2分
}

local REMAIN_CARD_COUNT_ONE = 1 --报单
local REMAIN_CARD_COUNT_TWO = 2 --报双

local self_card_type_list
local make_card_type

--配置
local WEIGH_VALUE_CONF --权重配置
local ROB_DIZHU_CONF --抢地主配置
local JIABEI_CONF

local san_zhang_priority_list 
local dan_shun_priority_list 
local shuang_shun_priority_list

-----------------------------------------common-----------------------------------------------
local function alloc_tmp_card_type_list()
    local  tmp_card_type_list = {
        [CARD_SUIT_TYPE_WANGZHA]    = {},
        [CARD_SUIT_TYPE_ZHADAN]     = {},
        [CARD_SUIT_TYPE_FEIJI]      = {},
        [CARD_SUIT_TYPE_SANZANGPAI] = {},
        [CARD_SUIT_TYPE_SHUANGSHUN] = {},
        [CARD_SUIT_TYPE_DANSHUN]    = {},
        [CARD_SUIT_TYPE_DUIPAI]     = {},
        [CARD_SUIT_TYPE_DANPAI]     = {},
   } 

   return tmp_card_type_list
end

local function extract_card_number(card_id)
    return card_id % 100
end

local function translate_to_count_number(card_suit)
    local card_number_set = {}
    for _,card_id in pairs(card_suit) do
        local number = extract_card_number(card_id)
        card_number_set[number] = (card_number_set[number] or 0) + 1
    end

    local count_number_map = {}
    for number,count in pairs(card_number_set) do
        local t = count_number_map[count]
        if not t then 
            t = {}
            count_number_map[count] = t
        end
        table_insert(t,number)
    end

    return count_number_map,card_number_set
end

local function process_card_id_list(card_id_list)
    local card_number_set = {}
    local real_card_number_set = {}
    for _,card_id in pairs(card_id_list) do
        local number = extract_card_number(card_id)
        card_number_set[number] = (card_number_set[number] or 0) + 1

        local t = real_card_number_set[number]
        if not t then t = {} real_card_number_set[number] = t end
        table_insert(t,card_id)
    end

    local card_count = 0
    local count_number_map = {}
    for number,count in pairs(card_number_set) do
        local t = count_number_map[count]
        if not t then 
            t = {}
            count_number_map[count] = t
        end
        table_insert(t,number)
        card_count = card_count + count
    end

    return card_number_set,real_card_number_set,count_number_map
end

local function full_result_cards(ret,real_card_number_set)
    local cards = {}
    for number,count in pairs(ret) do
        local card_id_list = assert(real_card_number_set[number])
        for i = 1,count do
            table_insert(cards,assert(card_id_list[i]))
        end
    end
    return cards
end

local function wipe_dai_pai_count(total_count,card_type_list)
    local dui_pai_count = #card_type_list[CARD_SUIT_TYPE_DUIPAI]
    local dan_pai_count = #card_type_list[CARD_SUIT_TYPE_DANPAI]
    for _,_ in pairs(card_type_list[CARD_SUIT_TYPE_ZHADAN]) do
        if dan_pai_count >= 2 then --四带两个单
            dan_pai_count = dan_pai_count - 2
            total_count = total_count - 2
            goto continue
        end
        if dui_pai_count >= 2 then --四带两个对
           dui_pai_count = dui_pai_count - 2
           total_count = total_count - 2
           goto continue
        end
        if dui_pai_count == 1 then --四带一对
            dui_pai_count = dui_pai_count - 1
            total_count = total_count - 1
            goto continue
        end

        ::continue::
    end

    local san_zhang_count = #card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,feiji in pairs(card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        san_zhang_count = san_zhang_count + #feiji
    end

    return total_count - math.min(san_zhang_count,dui_pai_count + dan_pai_count)
end

--得到手数
local function get_card_handle_count(total_card_type_list)
    local count = 0

    for _,card_type_list in pairs(total_card_type_list) do
        count = (count or 0) + #card_type_list
    end

    return wipe_dai_pai_count(count,total_card_type_list)
end

local function get_shun_zi_card_and_key(card_type,card_number)
    local card_count = 0
    if card_type == CARD_SUIT_TYPE_DANSHUN then
        card_count = 1
    elseif card_type == CARD_SUIT_TYPE_SHUANGSHUN then
        card_count = 2
    elseif card_type == CARD_SUIT_TYPE_FEIJI then
        card_count = 3
    else
        errlog("get shun_zi_count card type err!!!",card_type)
    end

    local ret = {}
    for _,number in pairs(card_number) do
        ret[number] = card_count
    end
    return ret,card_number[#card_number]
end

local function make_card_record(card_type,card_number)
    if card_type == CARD_SUIT_TYPE_DANPAI then
        return {[card_number] = 1},card_number
    elseif card_type == CARD_SUIT_TYPE_DUIPAI then
        return {[card_number] = 2},card_number
    elseif card_type == CARD_SUIT_TYPE_SANZANGPAI then
        return {[card_number] = 3},card_number
    elseif card_type == CARD_SUIT_TYPE_DANSHUN or 
           card_type == CARD_SUIT_TYPE_SHUANGSHUN or 
           card_type == CARD_SUIT_TYPE_FEIJI then
        return get_shun_zi_card_and_key(card_type,card_number)
    elseif card_type == CARD_SUIT_TYPE_ZHADAN then
        return {[card_number] = 4},card_number
    elseif card_type == CARD_SUIT_TYPE_WANGZHA then
        return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1},RED_JOKER_NUMBER
    else
        errlog("make_card_record card_type err",card_type)
    end
end

local function get_absolute_handle_count(uid,ddz_instance,total_card_type_list)
   local start_time = get_now_ustime()

   local dizhu_uid = ddz_instance:get_dizhu_uid()
   local compare_card1_ids = {}
   local compare_card2_ids = {}

   if uid == dizhu_uid then
        local farmer1_uid,famer2_uid = ddz_instance:get_farmer_uids()
        compare_card1_ids = ddz_instance:get_player_card_ids(farmer1_uid)
        compare_card2_ids = ddz_instance:get_player_card_ids(famer2_uid)
   else
        compare_card1_ids = ddz_instance:get_player_card_ids(dizhu_uid) 
   end

   local absolute_handle_count = 0
   local cards_id_list = ddz_instance:get_player_card_ids(uid)
   local _,real_card_number_set = process_card_id_list(cards_id_list)
   local one_card_type_no_absolute 
   for card_type,card_type_list in pairs(total_card_type_list) do
       for _,card_number in pairs(card_type_list) do
           local ret,key = make_card_record(card_type,card_number)
           if ret then
              local card_suit = full_result_cards(ret,real_card_number_set)
              if not lz_remind.can_greater_than(compare_card1_ids,card_suit,card_type,key) and
                 not lz_remind.can_greater_than(compare_card2_ids,card_suit,card_type,key) then
                 absolute_handle_count = absolute_handle_count + 1
              else
                 one_card_type_no_absolute = card_type
              end
           else
              errlog("make_card_record err",card_type)
           end
       end
   end

   --print("get_absolute_handle_count1231231231231231312",get_now_ustime() - start_time)
   return absolute_handle_count,one_card_type_no_absolute
end

local function player_can_must_win(uid,ddz_instance,card_type_list)
    local start_time = get_now_ustime()

    local handle_count = get_card_handle_count(card_type_list)
    local absolute_handle_count,card_type_finaly_play = get_absolute_handle_count(uid,ddz_instance,card_type_list)
    if absolute_handle_count >= handle_count - 1 then
        return true,card_type_finaly_play
    end

    --print("player_can_must_win10101010110101010===",get_now_ustime() - start_time)
    return false
end

local function rival_can_must_win(self)
   local dizhu_uid = self.ddz_instance:get_dizhu_uid()
   if self.uid == dizhu_uid then
        local farmer1_uid,famer2_uid = self.ddz_instance:get_farmer_uids()

        local farmer1_card_type_list = assert(make_card_type(farmer1_uid,self.ddz_instance)) 
        if player_can_must_win(farmer1_uid,self.ddz_instance,farmer1_card_type_list) then
            return true
        end

        local farmer2_card_type_list = assert(make_card_type(famer2_uid,self.ddz_instance)) 
        if player_can_must_win(famer2_uid,self.ddz_instance,farmer2_card_type_list) then
            return true
        end 
        return false
   else
        local dizhu_card_type_list = assert(make_card_type(dizhu_uid,self.ddz_instance)) 
        return player_can_must_win(dizhu_uid,self.ddz_instance,dizhu_card_type_list)
   end
end

--自己达到必赢条件
local function self_can_must_win(self)
    return player_can_must_win(self.uid,self.ddz_instance,self_card_type_list)
end

local function get_player_da_pai_count(ddz_instance,uid)
    local da_pai_count = 0
    local card_id_list = ddz_instance:get_player_card_ids(uid)
    local _,real_card_num_set = process_card_id_list(card_id_list)
    local pai_A = 12
    for number,cards in pairs(real_card_num_set) do
        if POWER_MAP[number] >= pai_A then
            da_pai_count = da_pai_count + #cards
        end
    end
    return da_pai_count
end

local function self_da_pai_more_than_rival(self)
    local self_da_pai_count = get_player_da_pai_count(self.ddz_instance,self.uid)
    local rival_da_pai_count = 0
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    if self.uid == dizhu_uid then
        local farmer1_uid,farmer2_uid = self.ddz_instance:get_farmer_uids()
        local count1 = get_player_da_pai_count(self.ddz_instance,farmer1_uid)
        local count2 = get_player_da_pai_count(self.ddz_instance,farmer2_uid)
        rival_da_pai_count = count1 + count2
    else
        rival_da_pai_count = get_player_da_pai_count(self.ddz_instance,dizhu_uid)
    end

    return self_da_pai_count > rival_da_pai_count 
end

--得到权值
local function get_card_weigh_value(total_card_type_list)
    local weigh_value = 0
    for card_type,card_type_list in pairs(total_card_type_list) do
        for _,card_numbers in pairs(card_type_list) do
           if type(card_numbers) == 'table' then
                local beyond_len = #card_numbers - WEIGH_VALUE_CONF[card_type].base_len
                local add = beyond_len * WEIGH_VALUE_CONF[card_type].add
                weigh_value = weigh_value + WEIGH_VALUE_CONF[card_type].base + add
           else
                weigh_value = weigh_value + WEIGH_VALUE_CONF[card_type].base
           end
        end
    end

    return weigh_value
end

local function next_is_dizhu(self)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local next_position_uid = self.ddz_instance:get_next_position_uid(self.uid)
    if next_position_uid == dizhu_uid then
        return true
    end
    return false
end

local function rival_is_remain_one(self)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local is_dizhu = dizhu_uid == self.uid
    local rival_min_count = self.ddz_instance:get_rival_min_card_count(is_dizhu)
    if rival_min_count == REMAIN_CARD_COUNT_ONE then
        return true
    end
    return false
end

local function rival_is_remain_two(self)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local is_dizhu = dizhu_uid == self.uid
    local rival_min_count = self.ddz_instance:get_rival_min_card_count(is_dizhu)
    if rival_min_count == REMAIN_CARD_COUNT_TWO then
        return true
    end
    return false
end

local function player_is_teammate(self,uid)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    if self.uid == dizhu_uid and uid ~= dizhu_uid then
        return false
    end
    if self.uid ~= dizhu_uid and uid == dizhu_uid then
        return false
    end
    return true
end

local function rival_is_remain_one_handle(self,last_uid)
    --对手出的牌并且只剩一手牌
    local card_type_list = assert(make_card_type(last_uid,self.ddz_instance))
    local handle_count = get_card_handle_count(card_type_list)
    if handle_count == 1 then
        return true
    end
    return false
end

local function can_seprate_dan_shun(self,dan_shun,number,last_uid)
    if player_is_teammate(self,last_uid) then
        return false
    end

    local max_num = dan_shun[#dan_shun]
    if max_num == number and #dan_shun >= 6 then
        return true
    end
    if POWER_MAP[max_num] - POWER_MAP[number] <= 1 and #dan_shun >= 7 then
        return true
    end
    local cards_id_list = self.ddz_instance:get_player_card_ids(last_uid)
    local card_type_list = assert(make_card_type(last_uid,self.ddz_instance))
    if get_card_handle_count(card_type_list) <= 1 then
        return true
    end

    return false
end

-----------------------------------------common-----------------------------------------------

-----------------------------------------check_rob_dizhu_begin--------------------------------------
local function get_wangzha_score(card_num_set)
    if card_num_set[BLACK_JOKER_NUMBER] and card_num_set[RED_JOKER_NUMBER] then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_WANGZHA]
    end
    return 0
end

local function get_zhadan_score(count_num_map)
   local zhadan_list = count_num_map[4] or {}
   return #zhadan_list * MARK_TYPE_SCORE_MAP[MARK_TYPE_ZHANDAN]
end

local function get_danpai_joker_score(card_num_set)
    if card_num_set[RED_JOKER_NUMBER] and not card_num_set[BLACK_JOKER_NUMBER] then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_DANPAI_RJOKER]
    end
    if card_num_set[BLACK_JOKER_NUMBER] and not card_num_set[RED_JOKER_NUMBER] then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_DANPAI_BJOKER]
    end
    return 0
end

local function get_danpai_two_score(real_card_number_set)
    local list_two = real_card_number_set[2] or {}
    if #list_two >= 4 then return 0 end
    return #list_two * MARK_TYPE_SCORE_MAP[MARK_TYPE_DANPAI_TWO]
end

local function get_cards_total_score(card_num_set,real_card_num_set,count_num_map)
    local total_score = 0
    total_score = total_score + get_wangzha_score(card_num_set)
    total_score = total_score + get_zhadan_score(count_num_map)
    total_score = total_score + get_danpai_joker_score(card_num_set)
    total_score = total_score + get_danpai_two_score(real_card_num_set)

    return total_score
end

local function get_probabilaty_by_score(self,total_score)
    local cur_probability = 0
    for _,tb in pairs(self.conf.rob_dizhu_conf) do
        if total_score >= tb.score then
            cur_probability = tb.probability
        end
    end
   
    return cur_probability
end

local function is_need_rob_dizhu(self)
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)
    local total_score = get_cards_total_score(card_num_set,real_card_num_set,count_num_map)
    local probability = get_probabilaty_by_score(self,total_score)

    if math.random(1, 100) <= probability then
        return true
    end
    return false
end

-----------------------------------------check_rob_dizhu_end--------------------------------------

-----------------------------------------check_jiabei_begin---------------------------------------
local function get_probabilaty_by_handle_count(handle_count)
    local cur_probability = 0
    for _,tb in pairs(JIABEI_CONF) do
        if handle_count <= tb.count then
            cur_probability = tb.probability
        end
    end
   
    return cur_probability
end

local function is_need_jiabei(uid,ddz_instance)
    local handle_count = get_card_handle_count(self_card_type_list)
    local probability  = get_probabilaty_by_handle_count(handle_count)
    if math.random(1, 100) <= probability then
        return true
    end
    return false
end

local function make_farmer_role(self)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    if self.uid == dizhu_uid then
        return
    end

    --满足必赢条件
    if self_can_must_win(self) then
        self.is_main_role = true
        return
    end
    local self_handle_count = get_card_handle_count(self_card_type_list)
    if self_handle_count <= 3 then
        self.is_main_role = true
        return
    end

    local another_framer_uid 
    local farmer1_uid,farmer2_uid = self.ddz_instance:get_farmer_uids()
    if self.uid == farmer1_uid then
        another_framer_uid = farmer2_uid
    else
        another_framer_uid = farmer1_uid
    end
    local another_card_type_list = assert(make_card_type(another_framer_uid,self.ddz_instance)) 

    local self_weigh_value = get_card_weigh_value(self_card_type_list)
    local another_weigh_value = get_card_weigh_value(another_card_type_list)
    if self_weigh_value >= another_weigh_value then
        self.is_main_role = true
        return
    end
    local another_handle_count = get_card_handle_count(another_card_type_list)
    if self_handle_count < another_handle_count then
        self.is_main_role = true
        return
    end

    self.is_main_role = false
end
-----------------------------------------check_jiabei_end-----------------------------------------

-----------------------------------------make_card_type_begin-------------------------------------
local function make_wangzha(real_card_num_set,card_type_list)
    if real_card_num_set[BLACK_JOKER_NUMBER] and real_card_num_set[RED_JOKER_NUMBER] then
        table_insert(card_type_list[CARD_SUIT_TYPE_WANGZHA],{BLACK_JOKER_NUMBER,RED_JOKER_NUMBER})
        real_card_num_set[BLACK_JOKER_NUMBER] = nil
        real_card_num_set[RED_JOKER_NUMBER]   = nil
    end
end

local function make_zhadan(real_card_num_set,card_type_list)
    for _,card_id_list in pairs(real_card_num_set) do
        if card_id_list == 4 then
            table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],number)
            real_card_num_set[number] = nil
        end
    end
    local tmp_list = card_type_list[CARD_SUIT_TYPE_ZHADAN]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_dan_shun(real_card_number_set,card_type_list)
    local start_time = get_now_ustime()

    local tmp_dan_shun_list = {}
    local dan_shun = {}
    local dan_shun_count = 0
    local power = 1
    --选取最小五连
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end

        if real_card_number_set[number] then
            table_insert(dan_shun,number)
            dan_shun_count = dan_shun_count + 1 
        elseif dan_shun_count < 5 then
            dan_shun = {}
            dan_shun_count = 0
        end
        power = power + 1

        if dan_shun_count >= 5 then
            table_insert(tmp_dan_shun_list,dan_shun)

            for _,number in pairs(dan_shun) do
                table_remove(real_card_number_set[number],1)
                if #real_card_number_set[number] <= 0 then
                    real_card_number_set[number] = nil
                end
            end
            dan_shun = {}
            dan_shun_count = 0
            power = 1
        end
    end
    --拓展五连
    for number,_ in pairs(real_card_number_set) do
        local power = POWER_MAP[number]
        for _,dan_shun in pairs(tmp_dan_shun_list) do
            local max_num = dan_shun[#dan_shun]
            local last_power = POWER_MAP[max_num]
            if last_power + 1 == power then
                table_insert(dan_shun,number)
                table_remove(real_card_number_set[number],1)
                if #real_card_number_set[number] <= 0 then
                    real_card_number_set[number] = nil
                end
                break
            end
        end
    end
    --合并顺子
    local index = 1
    for i=1,#tmp_dan_shun_list do
        local pre_list = tmp_dan_shun_list[i]
        local j = i+1
        while tmp_dan_shun_list[j] do
            local next_list = tmp_dan_shun_list[j]
            local pre_number = pre_list[#pre_list]
            local pre_power = POWER_MAP[pre_number]
            local next_number = next_list[1]
            local next_power = POWER_MAP[next_number]
            if pre_power + 1 == next_power then
                for _,number in pairs(next_list) do
                    table_insert(tmp_dan_shun_list[i],number)
                end
                table_remove(tmp_dan_shun_list,j)
            else
                j = j + 1
            end
        end
    end

    if next(tmp_dan_shun_list) then
        card_type_list[CARD_SUIT_TYPE_DANSHUN] = tmp_dan_shun_list
    end

    --print("make_dan_shun2222222",get_now_ustime() - start_time)
end

local function make_zhadan(real_card_num_set,card_type_list)
    local start_time = get_now_ustime()

    for number,cards_id_list in pairs(real_card_num_set) do
        if #cards_id_list == 4 then
            table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],number)
            real_card_num_set[number] = nil
        end
    end

    --print("make_zhadan66666666666",get_now_ustime() - start_time)
end

local function make_dan_pai(real_card_num_set,card_type_list)
    local start_time = get_now_ustime()

    for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 1 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DANPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)

   --print("make_dan_pai888888888888",get_now_ustime() - start_time)
end

local function make_dui_pai(real_card_num_set,card_type_list)
   local start_time = get_now_ustime()

   for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 2 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DUIPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)

   --print("make_dui_pai77777777777777",get_now_ustime() - start_time)
end

local function make_san_zhang_pai(real_card_num_set,card_type_list)
    local start_time = get_now_ustime()

    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],number)
            real_card_num_set[number] = nil
        end
    end

    local tmp_list = card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)

    --print("make_san_zhang_pai+++++",get_now_ustime() - start_time)
end

local function make_feiji(real_card_number_set,card_type_list)
    local start_time = get_now_ustime()

    local tmp_list = {}
    for number,cards_id_list in pairs(real_card_number_set) do
        if #cards_id_list == 3 then
            table_insert(tmp_list,number)
        end
    end
    if #tmp_list < 2 then return end
         
    local power_list = {}
    for _,number in pairs(tmp_list) do
        table_insert(power_list,POWER_MAP[number])
    end
    table_sort(power_list)

    local last_power = power_list[1]
    local continuous = {CONTINUOUS_CARD_MAP[last_power]}
    for i = 2,#power_list do
        local power = power_list[i]
        if power == last_power + 1 then
            last_power = power
            table_insert(continuous,CONTINUOUS_CARD_MAP[power])

            goto continue
        end
        if #continuous >= 2 then
            for _,number in pairs(continuous) do
                real_card_number_set[number] = nil
            end
            table_insert(card_type_list[CARD_SUIT_TYPE_FEIJI],continuous)
        end
        if #continuous > 0 then
            continuous = {}
        end
        last_power = power
        table_insert(continuous,CONTINUOUS_CARD_MAP[power])

        ::continue::
    end

    if #continuous >= 2 then
        for _,number in pairs(continuous) do
            real_card_number_set[number] = nil
        end
        table_insert(card_type_list[CARD_SUIT_TYPE_FEIJI],continuous)
    end

    --print("make_feiji44444",get_now_ustime() - start_time)
end

local function is_equal_dan_shun(dan_shun1,dan_shun2)
    if #dan_shun1 ~= #dan_shun2 then
        return false
    end

    local tmp_map = {}
    for _,number in pairs(dan_shun2) do
        tmp_map[number] = true
    end
    for _,num in pairs(dan_shun1) do
        if not tmp_map[num] then
            return false
        end
    end

    return true
end

local function make_shuang_shun(real_card_number_set,card_type_list)
    local start_time = get_now_ustime()

    --在单顺中组建双顺
    local type_list = card_type_list[CARD_SUIT_TYPE_DANSHUN]

    local i = 1
    while type_list[i] and type_list[i+1] do
        if is_equal_dan_shun(type_list[i],type_list[i+1]) then
            table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],type_list[i])
            for j=1,2 do
                table_remove(type_list,i)
            end
        else
            i = i + 1
        end
    end
    --在剩余牌中组建双顺
    local power = 1
    local tmp_list = {}
    local tmp_count = 0
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end
        local card_id_list = real_card_number_set[number]
        if card_id_list and #card_id_list >= 2 then
            table_insert(tmp_list,number)
            tmp_count = tmp_count + 1
        elseif tmp_count >= 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],tmp_list)
            for _,number in pairs(tmp_list) do
                for count=1,2 do
                    table_remove(real_card_number_set[number],1)
                end
                if #real_card_number_set[number] <= 0 then
                    real_card_number_set[number] = nil
                end
            end

            tmp_list = {}
            tmp_count = 0
        elseif tmp_count > 0 then
            tmp_list = {}
            tmp_count = 0
        end
        power = power + 1
    end

    --print("make_shuang_shun33333",get_now_ustime() - start_time)
end

local function select_card_type_list(uid,ddz_instance)
    local handle_count_one = get_card_handle_count(dan_shun_priority_list)
    local absolute_count_one = get_absolute_handle_count(uid,ddz_instance,dan_shun_priority_list)
    local weigh_value_one = get_card_weigh_value(dan_shun_priority_list)
    if absolute_count_one >= handle_count_one - 1 then --满足必赢条件
        return dan_shun_priority_list
    end

    local handle_count_two = get_card_handle_count(shuang_shun_priority_list)
    local absolute_count_two = get_absolute_handle_count(uid,ddz_instance,shuang_shun_priority_list)
    local weigh_value_two = get_card_weigh_value(shuang_shun_priority_list)
    if absolute_count_two >= handle_count_two - 1 then --满足必赢条件
        return shuang_shun_priority_list
    end

    local handle_count_three = get_card_handle_count(san_zhang_priority_list)
    local absolute_count_three = get_absolute_handle_count(uid,ddz_instance,san_zhang_priority_list)
    local weigh_value_three = get_card_weigh_value(san_zhang_priority_list)
    if absolute_count_three >= handle_count_three - 1 then --满足必赢条件
        return san_zhang_priority_list
    end

    local tmp_handle_count = weigh_value_one
    local tmp_card_list = dan_shun_priority_list
    local tmp_absolute_count = absolute_count_one
    local tmp_weigh_value = weigh_value_one

    if tmp_handle_count < handle_count_two then
        tmp_handle_count = handle_count_two
        tmp_card_list = shuang_shun_priority_list
        tmp_absolute_count = absolute_count_two
        tmp_weigh_value = weigh_value_two
    elseif tmp_handle_count == handle_count_two and tmp_absolute_count > absolute_count_two then
        tmp_card_list = shuang_shun_priority_list
        tmp_absolute_count = absolute_count_two
        tmp_weigh_value = weigh_value_two
    elseif tmp_handle_count == handle_count_two and tmp_absolute_count == absolute_count_two and
           tmp_weigh_value < weigh_value_two then
        tmp_card_list = shuang_shun_priority_list
        tmp_weigh_value = weigh_value_two
    end

    if tmp_handle_count < handle_count_three then
        tmp_handle_count = handle_count_three
        tmp_card_list = san_zhang_priority_list
        tmp_absolute_count = absolute_count_tree
        tmp_weigh_value = weigh_value_tree
    elseif tmp_handle_count == handle_count_three and tmp_absolute_count > absolute_count_three then
        tmp_card_list = san_zhang_priority_list
        tmp_absolute_count = absolute_count_three
        tmp_weigh_value = weigh_value_three
    elseif tmp_handle_count == handle_count_three and tmp_absolute_count == absolute_count_three and
           tmp_weigh_value < weigh_value_three then
        tmp_card_list = san_zhang_priority_list
        tmp_weigh_value = weigh_value_three
    end

    return tmp_card_list
end

--三条,顺子,连对
local function make_san_zhang_priority_card_type(cards_id_list)
    local _,real_card_num_set = process_card_id_list(cards_id_list)

    make_wangzha(real_card_num_set,san_zhang_priority_list)
    make_zhadan(real_card_num_set,san_zhang_priority_list)
    make_feiji(real_card_num_set,san_zhang_priority_list)
    make_san_zhang_pai(real_card_num_set,san_zhang_priority_list)
    make_dan_shun(real_card_num_set,san_zhang_priority_list)
    make_shuang_shun(real_card_num_set,san_zhang_priority_list)
    make_dui_pai(real_card_num_set,san_zhang_priority_list)
    make_dan_pai(real_card_num_set,san_zhang_priority_list)
end

--三张,连对,顺子
local function make_shuang_shun_priority_card_type(cards_id_list)
    local _,real_card_num_set = process_card_id_list(cards_id_list)

    make_wangzha(real_card_num_set,shuang_shun_priority_list)
    make_zhadan(real_card_num_set,shuang_shun_priority_list)
    make_feiji(real_card_num_set,shuang_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,shuang_shun_priority_list)
    make_dan_shun(real_card_num_set,shuang_shun_priority_list)
    make_shuang_shun(real_card_num_set,shuang_shun_priority_list)
    make_dui_pai(real_card_num_set,shuang_shun_priority_list)
    make_dan_pai(real_card_num_set,shuang_shun_priority_list)
end

--顺子,三条,连对
local function make_dan_shun_priority_card_type(cards_id_list)
    local _,real_card_num_set = process_card_id_list(cards_id_list)

    make_wangzha(real_card_num_set,dan_shun_priority_list)
    make_zhadan(real_card_num_set,dan_shun_priority_list)
    make_feiji(real_card_num_set,dan_shun_priority_list)
    make_dan_shun(real_card_num_set,dan_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,dan_shun_priority_list)
    make_shuang_shun(real_card_num_set,dan_shun_priority_list)
    make_dui_pai(real_card_num_set,dan_shun_priority_list)
    make_dan_pai(real_card_num_set,dan_shun_priority_list)
end

local function clear_card_type_list()
    san_zhang_priority_list = alloc_tmp_card_type_list()
    dan_shun_priority_list =  alloc_tmp_card_type_list()
    shuang_shun_priority_list = alloc_tmp_card_type_list()
end

make_card_type = function(uid,ddz_instance)
    clear_card_type_list()

    local cards_id_list = ddz_instance:get_player_card_ids(uid)
    make_san_zhang_priority_card_type(cards_id_list)
    make_shuang_shun_priority_card_type(cards_id_list)
    make_dan_shun_priority_card_type(cards_id_list)

    return select_card_type_list(uid,ddz_instance)
end

-----------------------------------------make_card_type_end-------------------------------------

local function get_san_zhang_pai_count()
    local count = #self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,fei_ji_list in pairs(self_card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        count = count + #fei_ji_list
    end

    return count
end

local function get_dan_shuang_pai_count()
   assert(self_card_type_list)

   return #self_card_type_list[CARD_SUIT_TYPE_DANPAI] + #self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
end

local function check_si_dai_er(self,card_type)
    if #self_card_type_list[CARD_SUIT_TYPE_ZHADAN] <= 0 then
        print("check_si_dai_er1111111111111111111111111111",self.uid)
        return false
    end
    if card_type == CARD_SUIT_TYPE_SIDAIER and 
       #self_card_type_list[CARD_SUIT_TYPE_DANPAI] < 2 then
        print("check_si_dai_er22222222222222222222222222222",self.uid)
        return false
    end
    if card_type == CARD_SUIT_TYPE_SIDAILIANGDUI and 
       #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] < 2 then
       print("check_si_dai_er3333333333333333333333333333333",self.uid)
       return false
    end
    if not self_can_must_win(self) then
        print("check_si_dai_er3333333333333333333333333333333",self.uid)
        return false
    end
    --敌方剩余一张单牌时，如果自己手中小于敌方剩余单牌的数量小于等于2,则不出4带2单牌。
    if card_type == CARD_SUIT_TYPE_SIDAIER  and rival_is_remain_one(self) then
        local pai_id = assert(self.ddz_instance:get_rival_the_remain_one_pai(self.uid))
        local pai_number = extract_card_number(pai_id)
        local count = 0
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
            if POWER_MAP[number] < POWER_MAP[pai_number] then
                count = count + 1
            end
        end
        if count < 2 then
            return false
        end
    end
    print("check_si_dai_er4444444444444444444444444444444444444",self.uid)
    return true
end

local function check_by_card_type(self,card_type,min_num_map)
    if card_type == CARD_SUIT_TYPE_DANPAI then
        local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        if #dan_pai_list <= 0 then
            return false
        end
        local san_zhang_count = get_san_zhang_pai_count()
        local dan_dui_pai_count = get_dan_shuang_pai_count()
        if san_zhang_count > 0 and dan_dui_pai_count - 2 <  san_zhang_count then
            return false
        end 
        if not min_num_map then
            return true
        end
        for _,number in pairs(dan_pai_list) do
            if min_num_map[number] then
                return true
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_DUIPAI then
        local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
        if #dui_pai_list <= 0 then
            return false
        end
        --对2不满足必应条件的时候先不出
        if #dui_pai_list == 1 and dui_pai_list[1] == 2 and not self_can_must_win(self) then
            return false
        end
        
        local san_zhang_count = get_san_zhang_pai_count()
        local dan_dui_pai_count = get_dan_shuang_pai_count()
        if san_zhang_count > 0 and dan_dui_pai_count - 2 <  san_zhang_count then
            return false
        end 
        if not min_num_map then
            return true
        end
        for _,number in pairs(dui_pai_list) do
            if min_num_map[number] then
                return true
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_SANZANGPAI then
        local sanzhang_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        if #sanzhang_list <= 0 then
            return false
        end
        --当手数大于4，判断出J或以上的连对，优先出其他牌型(下家是地主时)
        if next_is_dizhu(self) and get_card_handle_count(self_card_type_list) >= 4 then
            local min_num = assert(sanzhang_list[1]) 
            local pai_J = 9
            if POWER_MAP[min_num] >= pai_J then
                return false
            end
        end
        return true
    elseif card_type == CARD_SUIT_TYPE_DANSHUN then
        local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
        if #dan_shun_list <= 0 then
            return false
        end
        if not min_num_map then
            return true
        end
        for _,dan_shun in pairs(dan_shun_list) do
            for _,number in pairs(dan_shun) do
                if min_num_map[number] then
                    return true
                end
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_SHUANGSHUN then
        local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
        if #shuang_shun_list <= 0 then
            return false
        end
        --当手数大于4，判断出J或以上的连对，优先出其他牌型(下家是地主时)
        if next_is_dizhu(self) and get_card_handle_count(self_card_type_list) >= 4 then
            local min_num = assert(shuang_shun_list[1][1]) 
            local pai_J = 9
            if POWER_MAP[min_num] >= pai_J then
                return false
            end
        end
        if not min_num_map then
            return true
        end
        for _,shuang_shun in pairs(shuang_shun_list) do
            for _,number in pairs(shuang_shun) do
                if min_num_map[number] then
                    return true
                end
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_FEIJI or card_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        if #feiji_list <= 0 then
            return false
        end
        --当手数大于4，判断出Q或以上的飞机，优先出其他牌型(下家是地主时)
        if next_is_dizhu(self) and get_card_handle_count(self_card_type_list) >= 4 then
            local min_feiji_num = assert(feiji_list[1][1]) 
            local pai_Q = 10
            if POWER_MAP[min_feiji_num] >= pai_Q then
                return false
            end
        end

        return true
    elseif card_type == CARD_SUIT_TYPE_SIDAIER or card_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
        return check_si_dai_er(self,card_type)
    elseif card_type == CARD_SUIT_TYPE_ZHADAN then
        if #self_card_type_list[CARD_SUIT_TYPE_ZHADAN] <= 0 then
            return false
        end
        --if get_card_handle_count(self_card_type_list) >= 3 then
        --    return false
        --end
    elseif card_type == CARD_SUIT_TYPE_WANGZHA then
        if #self_card_type_list[CARD_SUIT_TYPE_WANGZHA] <= 0 then
            return false
        end
        if get_card_handle_count(self_card_type_list) >= 3 then
            return false
        end
    else
        errlog("unknwon card type on check_card_type!!!",card_type)
    end

    return true
end

local function get_min_dan_pai_from_card_type()
   local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
   if not next(dan_pai_list) then
       return
   end

   local min_dan_pai = dan_pai_list[1]
   for _,number in pairs(dan_pai_list) do

      if POWER_MAP[min_dan_pai] > POWER_MAP[number] then
         min_dan_pai = number
      end
   end
   return min_dan_pai
end

local function get_min_dui_pai_from_card_type()
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    local min_dui_pai_num = dui_pai_list[1]
    if min_dui_pai_num then
       for _,number in pairs(dui_pai_list) do
          if POWER_MAP[min_dui_pai_num] > POWER_MAP[number] then
             min_dui_pai_num = number
          end
       end
   end
   return min_dui_pai_num
end

local function get_san_zhang_pai_xiao_pai()
   local min_dan_pai_num = get_min_dan_pai_from_card_type()
   local min_dui_pai_num = get_min_dui_pai_from_card_type()
   
   --大于两手牌的时候 不能带大于等于二的牌,写死算了
   local now_count = get_card_handle_count(self_card_type_list)
   if now_count >= 2 and min_dan_pai_num and POWER_MAP[min_dan_pai_num] >= 14 then
      dan_pai_num = nil
   end
   if now_count >= 2 and min_dui_pai_num and POWER_MAP[min_dui_pai_num] >= 14 then
      dui_pai_num = nil
   end
   return min_dan_pai_num,min_dui_pai_num
end

local function get_feiji_xiao_pai(card_list)
   local t_xiao_pai = {}
   local xiao_pai_count = #card_list
   local handle_count = get_card_handle_count(self_card_type_list)
   local pai_2 = 14
   --不够单牌的时候拆6连单顺以上的底牌
   local xiao_dan_pai_list = {}
   for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
       if handle_count > 2 and POWER_MAP[number] >= pai_2 then
           goto continue
       end
       table_insert(xiao_dan_pai_list,number)

       ::continue::
   end
   for _,dan_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_DANSHUN]) do
       if #dan_shun >= 6 then
           table_insert(xiao_dan_pai_list,dan_shun[1])
       end
   end
   if #xiao_dan_pai_list >= xiao_pai_count then
       for i=1,xiao_pai_count do
           t_xiao_pai[xiao_dan_pai_list[i]] = 1
       end
       return t_xiao_pai
   end

    --不够对子的时候拆4连对以上的底对
    local xiao_dui_pai_list = {}
    for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
       if handle_count > 2 and POWER_MAP[number] >= pai_2 then
           goto continue
       end
       table_insert(xiao_dui_pai_list,number)

       ::continue::
    end

    if #xiao_dui_pai_list >= xiao_pai_count then
       for i=1,xiao_pai_count do
           t_xiao_pai[xiao_dui_pai_list[i]] = 2
       end
       return t_xiao_pai
    end

    return {}
end

local function copy_from_table(tab)
    local t = {}
    for k,v in pairs(tab) do
        t[k] = v
    end
    return t
end

local function get_sidaier_xiao_pai(card_suit_type)
    local t_xiao_pai = {}
    if card_suit_type == CARD_SUIT_TYPE_SIDAIER and 
       #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        local dan_pai_list = copy_from_table(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        table_sort(dan_pai_list,function(a,b) return (POWER_MAP[a]<POWER_MAP[b]) end)
         for i=1,2 do
             local number = dan_pai_list[i]
             t_xiao_pai[number] = 1
         end
    end

    if card_suit_type == CARD_SUIT_TYPE_SIDAIER and
       #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 then
        local dui_pai_list = copy_from_table(self_card_type_list[CARD_SUIT_TYPE_DUIPAI])
        table_sort(dui_pai_list,function(a,b) return (POWER_MAP[a]<POWER_MAP[b]) end)
        for i=1,2 do
           local number = dui_pai_list[i]
           t_xiao_pai[number] = 2
        end
    end
    return t_xiao_pai
end

local function get_second_min_number(num_list)
    assert(#num_list >= 2)
    local min_num = num_list[1]
    local second_min_num = num_list[2]
    if second_min_num < min_num then
        min_num = num_list[2]
        second_min_num = num_list[1]
    end
    for i=3,#num_list do
        if num_list[i] < second_min_num then
            if num_list[i] < min_num then
                second_min_num = min_num
                min_num = num_list[i]
            else
               second_min_num = num_list[i]
            end
        end
    end
    return second_min_num
end

local function get_max_two_number(num_list)
    assert(#num_list >= 2)
    local max_num = num_list[1]
    local second_max_num = num_list[2]
    if POWER_MAP[second_max_num] > POWER_MAP[max_num] then
        max_num = num_list[2]
        second_max_num = num_list[1]
    end
    for i=3,#num_list do
        if POWER_MAP[num_list[i]] > POWER_MAP[second_max_num] then
            if POWER_MAP[num_list[i]] > POWER_MAP[max_num] then
                second_max_num = max_num
                max_num = num_list[i]
            else
               second_max_num = num_list[i]
            end
        end
    end
    return max_num,second_max_num
end

local function select_dan_pai(self)
    if next_is_dizhu(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        --从权值第二大的单牌从大到小出
        local max_num,second_max_num = get_max_two_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        print("max_num,second_max_num",max_num,second_max_num)
        if rival_is_remain_one(self) then
            return {[max_num] = 1}
        else
            return {[second_max_num] = 1}
        end
    end
    if rival_is_remain_one(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        --当敌方报单的时候,必须出单牌时,出第二小的单牌
        local second_min_num = get_second_min_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        return {[second_min_num] = 1}
    end

    if self_can_must_win(self) and get_card_handle_count(self_card_type_list) <=2 then
        local tmp_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        table_sort(tmp_list,function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
    end
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_DANPAI][1])
    return {[number] = 1}
end

local function select_dui_pai(self)
    if get_card_handle_count(self_card_type_list) <=2 and self_can_must_win(self) then
        local tmp_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
        table_sort(tmp_list,function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
    end

    local number = assert(self_card_type_list[CARD_SUIT_TYPE_DUIPAI][1]) 
    if rival_is_remain_two(self) then
        --如果敌方报双,必须出单牌的时,拆开出单牌
        return {[number] = 1}
    end
    --下家是地主
    if next_is_dizhu(self) and #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 then 
        if get_card_handle_count(self_card_type_list) > 3 then
            local second_min_num = get_second_min_number(self_card_type_list[CARD_SUIT_TYPE_DUIPAI])
            return {[second_min_num] = 2}
        end
    end
    return {[number] = 2}
end

local function select_san_zhang_pai(self)
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI][1]) 
    local dan_pai_num,dui_pai_num = get_san_zhang_pai_xiao_pai()
    if dan_pai_num then
        return {[number] = 3,[dan_pai_num] = 1} --三带一
    elseif dui_pai_num then
        return {[number] = 3,[dui_pai_num] = 2} --三带二
    else
        return {[number] = 3} --三条
    end 
end

local function select_dan_shun(self)
    local ret = {}
    local card_list = assert(self_card_type_list[CARD_SUIT_TYPE_DANSHUN][1]) 
    for _,number in pairs(card_list) do
        ret[number] = 1
    end
    return ret
end

local function select_shuang_shun(self)
    local ret = {}
    local card_list = assert(self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN][1]) 
    for _,number in pairs(card_list) do
        ret[number] = 2
    end
    return ret
end

local function select_feiji(self)
    local ret = {}
    local card_list = assert(self_card_type_list[CARD_SUIT_TYPE_FEIJI][1]) 
    for _,number in pairs(card_list) do
        ret[number] = 3
    end
    local xiao_pai_table = get_feiji_xiao_pai(card_list)
    for number,count in pairs(xiao_pai_table) do
        ret[number] = count
    end
    return ret
end

local function select_si_dai_er(self,card_suit_type)
    local ret = {}
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_ZHADAN][1])
    ret[number] = 4
    local xiao_pai_table = get_sidaier_xiao_pai(card_suit_type)
    if not next(xiao_pai_table) then
        print("select_si_dai_er 555555555555555555555555555555555",self.uid)
        return 
    end
    print("select_si_dai_er 66666666666666666666666666666666",tostring_r(xiao_pai_table))
    for number,count in pairs(xiao_pai_table) do
        ret[number] = count
    end
    return ret
end

local function select_zha_dan(self)
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_ZHADAN][1]) 
    return {[number] = 4}
end

local function select_wang_zha(self)
    assert(self_card_type_list[CARD_SUIT_TYPE_WANGZHA][1])
    return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
end

local function select_by_card_type(self,card_suit_type)
    if card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return select_dan_pai(self)
    elseif card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return select_dui_pai(self)
    elseif card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        return select_san_zhang_pai(self)
    elseif card_suit_type == CARD_SUIT_TYPE_DANSHUN then
        return select_dan_shun(self)
    elseif card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
        return select_shuang_shun(self)
    elseif card_suit_type == CARD_SUIT_TYPE_FEIJIDAICIBANG or 
           card_suit_type == CARD_SUIT_TYPE_FEIJI then
        return select_feiji(self)
    elseif card_suit_type == CARD_SUIT_TYPE_SIDAIER or 
           card_suit_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
        return select_si_dai_er(self,card_suit_type)
    elseif card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        print("11111")
        return select_zha_dan(self)
    elseif card_suit_type == CARD_SUIT_TYPE_WANGZHA then
        return select_wang_zha(self)
    else
        errlog("unknwon card type on select_by_card_type!!!",card_suit_type)
    end
end

local function check_zhadan_wangzha(card_suit_key)
    local zhadan_list = self_card_type_list[CARD_SUIT_TYPE_ZHADAN]
    if zhadan_list then
        for _,number in pairs(zhadan_list) do
            if card_suit_key then
                if POWER_MAP[card_suit_key] < POWER_MAP[number] then
                    return {[number] = 4}
                end
            else
                return {[number] = 4}
            end
        end
    end
    --如果有王炸也行
    local wang_zha = self_card_type_list[CARD_SUIT_TYPE_WANGZHA]
    if next(wang_zha) then
        return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
    end

    return
end

local function check_dan_pai(self,last_card_suit_key,only_check_dan_pai)
    --大小王压2
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list) 
    if last_card_suit_key == CARD_TWO_NUMBER then
        if real_card_number_set[BLACK_JOKER_NUMBER] and real_card_number_set[RED_JOKER_NUMBER] and self_can_must_win(self) then
            return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
        elseif real_card_number_set[BLACK_JOKER_NUMBER] then --小王压2
            return {[BLACK_JOKER_NUMBER] = 1}
        elseif real_card_number_set[RED_JOKER_NUMBER] and self_da_pai_more_than_rival(self) then --大王压2
            return {[RED_JOKER_NUMBER] = 1}
        end
    end

    if last_card_suit_key == BLACK_JOKER_NUMBER then    --大王压小王
        if real_card_number_set[RED_JOKER_NUMBER] then
            return {[RED_JOKER_NUMBER] = 1}
        end
    end
    --找单牌
    local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
    for _,number in pairs(dan_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            if rival_can_must_win(self) or self_can_must_win(self) then
                return {[number] = 1}
            end
            if number == BLACK_JOKER_NUMBER or number == RED_JOKER_NUMBER then
                break
            end
            return {[number] = 1}
        end
    end
    if only_check_dan_pai then return end
    --拆2
    if real_card_number_set[CARD_TWO_NUMBER] and 
        #real_card_number_set[CARD_TWO_NUMBER] < 4 and 
       POWER_MAP[CARD_TWO_NUMBER] > POWER_MAP[last_card_suit_key] then
       return {[CARD_TWO_NUMBER] = 1}
    end
    --拆对牌
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    for _,number in pairs(dui_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            return {[number] = 1}
        end
    end
    --拆6连顺以上的顶牌
    local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
    for _,dan_shun in pairs(dan_shun_list) do
        if #dan_shun >= 6 and POWER_MAP[last_card_suit_key] < POWER_MAP[dan_shun[#dan_shun]] then
            return {[dan_shun[#dan_shun]] = 1}
        end
    end
    --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            return {[number] = 1}
        end
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        for _,number in pairs(feiji) do
           if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
               return {[number] = 1}
           end
        end 
    end
    --拆5连顺
    for _,dan_shun in pairs(dan_shun_list) do
        if #dan_shun == 5 then
            for _,number in pairs(dan_shun) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    return {[number] = 1}
                end
            end
        end
    end
    --拆连对
    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        for _,number in pairs(shuang_shun) do
            if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                return {[number] = 1}
            end
        end
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_dui_pai(self,last_card_suit_key,last_uid,only_check_dui_pai)
    --找对牌
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    if next_is_dizhu(self) and not self.is_main_role then
        --如果自己是配角，跟大于等于地主手中第二大的对子
        local dizhu_uid = self.ddz_instance:get_dizhu_uid()
        local dizhu_card_type_list = assert(make_card_type(dizhu_uid,self.ddz_instance)) 

        if #dizhu_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 
           and #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 1 then
            local _,second_max_num = get_max_two_number(dizhu_card_type_list[CARD_SUIT_TYPE_DUIPAI])
            local max_num = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][1]
            if #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 then
                max_num,_ = get_max_two_number(self_card_type_list[CARD_SUIT_TYPE_DUIPAI])
            end
            if POWER_MAP[max_num] > POWER_MAP[last_card_suit_key] then
                if POWER_MAP[max_num] >= POWER_MAP[second_max_num] then
                    for _,number in pairs(dui_pai_list) do
                        if POWER_MAP[number] > POWER_MAP[last_card_suit_key] and
                           POWER_MAP[number] >= POWER_MAP[second_max_num] then
                           return {[number] = 2}
                        end
                    end
                else
                    return {[max_num] = 2}
                end
            end
        end
    end

    for _,number in pairs(dui_pai_list) do
        if not (self_can_must_win(self) or rival_can_must_win(self)) and number == CARD_TWO_NUMBER then
            goto continue
        end
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then 
            return {[number] = 2}
        end
        ::continue::
    end
    if only_check_dui_pai then return end

    --拆4连对的顶对
    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        if #shuang_shun >= 4 then
            if POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun[#shuang_shun]] then
                return {[shuang_shun[#shuang_shun]] = 2}
            end
        end
    end
    --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            return {[number] = 2}
        end
    end
    --拆3连对
    for _,shuang_shun in pairs(shuang_shun_list) do
        for _,number in pairs(shuang_shun) do
            if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                return {[number] = 2}
            end
        end
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        for _,number in pairs(feiji) do
            if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                return {[number] = 2}
            end
        end 
    end
    print("111111111111111111")
    --拆单顺
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list) 
    local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
    for _,dan_shun in pairs(dan_shun_list) do
        for _,number in pairs(dan_shun) do
            print("22222222222222",number)
            if real_card_number_set[number] and #real_card_number_set[number] >= 2 and
               POWER_MAP[last_card_suit_key] < POWER_MAP[number] and
               can_seprate_dan_shun(self,dan_shun,number,last_uid) then
               return {[number] = 2}
            end
        end
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_xiao_pai_power(number)
    local handle_count = get_card_handle_count(self_card_type_list)
    if handle_count > 2 and POWER_MAP[number] >= POWER_MAP[CARD_TWO_NUMBER] then
        return false
    end
    return true
end

local function get_xiao_pai(except_map,xiaopai_type,xiaopai_count)
    local xiao_pai_list = {}
    local remain_count = xiaopai_count

    if xiaopai_type == 1 then --单牌
        local tmp_dan_pai_list = {}
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
            table_insert(tmp_dan_pai_list,number)
        end
        --找6连顺以上的底牌
        for _,dan_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_DANSHUN]) do
            if #dan_shun >= 6 then
                table_insert(tmp_dan_pai_list,dan_shun[1])
            end
        end
        --拆三条中的牌
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]) do
            table_insert(tmp_dan_pai_list,number)
        end
        --拆飞机
        for _,feiji in pairs(self_card_type_list[CARD_SUIT_TYPE_FEIJI]) do
            table_insert(tmp_dan_pai_list,number) 
        end
        --拆5连顺的底牌
        for _,dan_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_DANSHUN]) do
            if #dan_shun == 5 then
               table_insert(tmp_dan_pai_list,dan_shun[1]) 
            end
        end
        --拆连对
        for _,shuang_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]) do
            table_insert(tmp_dan_pai_list,shuang_shun[1])    
        end
        --寻找小牌
        for _,number in pairs(tmp_dan_pai_list) do
            if not except_map[number] and check_xiao_pai_power(number) and remain_count > 0 then
                table_insert(xiao_pai_list,number)
                remain_count = remain_count - 1
            end
        end
    elseif xiaopai_type ==  2 then  --对牌
        --找对牌
        local tmp_dui_pai_list = {}
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
            table_insert(tmp_dui_pai_list,number)
        end
        --拆4连对的底对
        for _,shuang_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]) do
            if #shuang_shun >= 4 then
                table_insert(tmp_dui_pai_list,shuang_shun[1])
            end
        end
        --拆三条中的牌
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]) do
            table_insert(tmp_dui_pai_list,number)  
        end
        --拆3连对底对
        for _,shuang_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]) do
            if #shuang_shun == 3 then
                table_insert(tmp_dui_pai_list,shuang_shun[1])
            end
        end
        --拆飞机底对
        for _,feiji in pairs(self_card_type_list[CARD_SUIT_TYPE_FEIJI]) do
            table_insert(tmp_dui_pai_list,feiji[1])
        end
        --寻找小牌
        for _,number in pairs(tmp_dui_pai_list) do
            if not except_map[number] and check_xiao_pai_power(number) and remain_count > 0 then
                table_insert(xiao_pai_list,number)
                table_insert(xiao_pai_list,number)
                remain_count = remain_count - 1
            end
        end
    else
       errlog("unknwon xiaopai_count!!!!")
    end

    if remain_count <= 0 then
        return xiao_pai_list
    end
end

local function get_san_zhang_pai(self,last_card_suit_key,last_uid)
    local ret = {}
    local tmp_san_zhang_list = {}
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]) do
        table_insert(tmp_san_zhang_list,number)
    end
    for _,feiji in pairs(self_card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        for _,number in pairs(feiji) do
            table_insert(tmp_san_zhang_list,number)
        end
    end
    for _,dan_shun in pairs(self_card_type_list[CARD_SUIT_TYPE_DANSHUN]) do
        for _,number in pairs(dan_shun) do
            if #real_card_number_set[number] >= 3 and can_seprate_dan_shun(self,dan_shun,number,last_uid) then
                table_insert(tmp_san_zhang_list,number)
            end
        end
    end
    for _,number in pairs(tmp_san_zhang_list) do
        if POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
            if number == CARD_TWO_NUMBER then --3条2
               if self_can_must_win(self) or rival_can_must_win(self) then
                    ret[number] = 3
                    break
               end
            else
                ret[number] = 3
                break
            end
        end
    end
    return ret
end

local function check_san_zhang_pai(self,last_card_suit_key,last_uid)
    local ret = get_san_zhang_pai(self,last_card_suit_key,last_uid)
    if next(ret) then
        return ret
    end
    --return check_zhadan_wangzha() --炸弹
end

local function check_san_dai_yi(self,last_card_suit_key,last_uid)
    local ret = get_san_zhang_pai(self,last_card_suit_key,last_uid)
    if next(ret) then --寻找小牌
        local xiao_pai_list = get_xiao_pai(ret,1,1)
        if not xiao_pai_list then
            return
        end
        for _,number in pairs(xiao_pai_list) do
            if not ret[number] then
                ret[number] = 1
            else
                ret[number] = ret[number] + 1
            end
        end
        return ret
    end
    --return check_zhadan_wangzha() --炸弹
end

local function check_san_dai_yi_dui(self,last_card_suit_key,last_uid)
    local ret = get_san_zhang_pai(self,last_card_suit_key,last_uid)
    if next(ret) then --寻找小牌
        local xiao_pai_list = get_xiao_pai(ret,2,1)
        if not xiao_pai_list then
            return
        end
        for _,number in pairs(xiao_pai_list) do
            if not ret[number] then
                ret[number] = 1
            else
                ret[number] = ret[number] + 1
            end
        end
        return ret
    end
    --return check_zhadan_wangzha() --炸弹
end

local function check_dan_shun(last_card_suit_key,shun_zi_count)
    local card_type_list = {
       self_card_type_list[CARD_SUIT_TYPE_DANSHUN],
       self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],
       self_card_type_list[CARD_SUIT_TYPE_FEIJI],
    }
    --先找相同张数的单顺,双顺,飞机
    for _,card_type_table in pairs(card_type_list) do
        for _,shun_zi in pairs(card_type_table) do
            local max_num = shun_zi[#shun_zi]
            if #shun_zi == shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
                local ret = {}
                for _,number in pairs(shun_zi) do
                    ret[number] = 1
                end
                return ret
            end
        end
    end
    --特殊处理不同张数的单顺
    for _,shun_zi in pairs(self_card_type_list[CARD_SUIT_TYPE_DANSHUN]) do
        local max_num = shun_zi[#shun_zi]
        local cut_len = #shun_zi - shun_zi_count
        if (cut_len >= 1 and cut_len <= 2 or cut_len >= 5) and 
           POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then 
            local ret = {}
            local power = POWER_MAP[max_num]
            for i = 1,shun_zi_count do
                local number = assert(CONTINUOUS_CARD_MAP[power])
                power = power - 1
                ret[number] = 1
            end
            return ret
        end
    end
    local tmp_card_type_list = {
       self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],
       self_card_type_list[CARD_SUIT_TYPE_FEIJI],
    }
    --再找不同张数的单顺,双顺,飞机
    for _,card_type_table in pairs(tmp_card_type_list) do
        for _,shun_zi in pairs(card_type_table) do
            local max_num = shun_zi[#shun_zi]
            local cut_len = #shun_zi - shun_zi_count
            if cut_len > 0 and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
                local ret = {}
                local power = POWER_MAP[max_num]
                for i = 1,shun_zi_count do
                    local number = assert(CONTINUOUS_CARD_MAP[power])
                    power = power - 1
                    ret[number] = 1
                end
                return ret
            end
        end
    end

    --return check_zhadan_wangzha()
end

local function check_shuang_shun(last_card_suit_key,shun_zi_count)
    --拆相同张数的双顺
    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        local max_num = shuang_shun[#shuang_shun]
        if #shuang_shun == shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            for _,number in pairs(shuang_shun) do
                ret[number] = 2
            end
            return ret
        end
    end
    --拆不同张数的双顺
    for _,shuang_shun in pairs(shuang_shun_list) do
        local max_num = shuang_shun[#shuang_shun]
        if #shuang_shun > shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            local power = POWER_MAP[max_num]
            for i = 1,shun_zi_count do
                local number = assert(CONTINUOUS_CARD_MAP[power])
                power = power - 1
                ret[number] = 2
            end
            return ret
        end
    end
    --拆不同张数的飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local max_num = feiji[#feiji]
        if #feiji > shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            local power = POWER_MAP[max_num]
            for i = 1,shun_zi_count do
                local number = assert(CONTINUOUS_CARD_MAP[power])
                power = power - 1
                ret[number] = 2
            end
            return ret
        end
    end 
    --拆相同张数的飞机
    for _,feiji in pairs(feiji_list) do
        local max_num = feiji[#feiji]
        if #feiji == shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            for _,number in pairs(feiji) do
                ret[number] = 2
            end
            return ret
        end
    end 

    --return check_zhadan_wangzha()
end

local function check_feiji(last_card_suit_key,last_card_suit)
    local rival_count_number_map = translate_to_count_number(last_card_suit)
    local sanzhang_list = assert(rival_count_number_map[3])
    local feiji_len = #sanzhang_list

    --拆相同张数的飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local max_num = feiji[#feiji]
        if #feiji == feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            for _,number in pairs(feiji) do
                ret[number] = 3
            end
            return ret
        end
    end 
    --拆不同张数的飞机
    for _,feiji in pairs(feiji_list) do
        local max_num = feiji[#feiji]
        if #feiji > feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            local ret = {}
            local power = POWER_MAP[max_num]
            for i = 1,feiji_len do
                local number = assert(CONTINUOUS_CARD_MAP[power])
                power = power - 1
                ret[number] = 3
            end
            return ret
        end
    end 

    --return check_zhadan_wangzha()
end

local function check_feiji_and_wing(last_card_suit_key,last_card_suit)
    local rival_count_number_map = translate_to_count_number(last_card_suit)
    local sanzhang_list = assert(rival_count_number_map[3])
    local feiji_len = #sanzhang_list

    --拆相同张数的飞机
    local ret = {}
    local found = false
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local max_num = feiji[#feiji]
        if #feiji == feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
            for _,number in pairs(feiji) do
                ret[number] = 3
                found = true
            end
        end
    end 
    --拆不同张数的飞机
    if not found then
        for _,feiji in pairs(feiji_list) do
            local max_num = feiji[#feiji]
            if #feiji > feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
                local power = POWER_MAP[max_num]
                for i = 1,feiji_len do
                    local number = assert(CONTINUOUS_CARD_MAP[power])
                    power = power - 1
                    ret[number] = 3
                    found = true
                end
            end
        end 
    end

    if found then
        local xiaopai_type = 1
        if not rival_count_number_map[1] then
            xiaopai_type = 2
        end
        assert(#rival_count_number_map[xiaopai_type] == feiji_len)
        local xiao_pai_list = get_xiao_pai(ret,xiaopai_type,feiji_len)
        if not xiao_pai_list then
            return
        end
        for _,number in pairs(xiao_pai_list) do
            if not ret[number] then
                ret[number] = 1
            else
                ret[number] = ret[number] + 1
            end
        end
        return ret
    end
    
    --return check_zhadan_wangzha()
end

local function get_number_list(cards_id_list)
    assert(#cards_id_list > 0)

    local tmp_number_list = {}
    for _,card_id in pairs(cards_id_list) do
        local number = extract_card_number(card_id)
        table_insert(tmp_number_list,number)
    end
    return tmp_number_list
end

local function get_min_dan_pai(cards_id_list)
    assert(#cards_id_list > 0)

    local tmp_number_set = {}
    for _,card_id in pairs(cards_id_list) do
        local number = extract_card_number(card_id)
        tmp_number_set[number] = (tmp_number_set[number] or 0) + 1
    end
    
    --去掉炸弹
    local card_number_set = {}
    for number,count in pairs(tmp_number_set) do
        if count ~= 4 then
            card_number_set[number] = count
        end
    end

    local min_number = extract_card_number(cards_id_list[1])
    local min_power = POWER_MAP[min_number]
    for number,_ in pairs(card_number_set) do
        if min_power > POWER_MAP[number] then
            min_power = POWER_MAP[number]
            min_number = number
        end
    end

    return {[min_number] = 1} 
end

local function get_max_type_from_all_card(card_type,real_card_num_set)
    local card_num
    if card_type == CARD_SUIT_TYPE_DANPAI then
        card_num = 1
    elseif card_type == CARD_SUIT_TYPE_DUIPAI then
        card_num = 2
    end
    if not card_num then
        return
    end

    local card_list = {}
    for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list >= card_num then
          table_insert(card_list,number)
       end
   end

   table_sort(card_list,function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
   return card_list
end

local function get_max_cards_greater_than_key(last_record,cards_id_list)   
    local _,real_card_num_set = process_card_id_list(cards_id_list)
    local card_type_list = get_max_type_from_all_card(last_record.card_suit_type,real_card_num_set)
    --print_r(card_type_list)
    if not card_type_list or not next(card_type_list) then
        return
    end

    local max_card_num = card_type_list[1]
    
    if POWER_MAP[max_card_num] <= POWER_MAP[last_record.key] then
        return
    end

    if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return {[max_card_num] = 1}
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return {[max_card_num] = 2}
    end
end

local function player_can_play(self,last_record,uid)
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key
    local last_card_suit = last_record.card_suit
    local player_cards_id = self.ddz_instance:get_player_card_ids(uid)
    
    return lz_remind.can_greater_than(player_cards_id,last_card_suit,last_card_suit_type,last_card_suit_key)
end

local function on_teammate_play(self,last_record)
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key
    local last_card_suit = last_record.card_suit

    local card_type_list = assert(make_card_type(last_record.uid,self.ddz_instance))
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    if not player_can_play(self,last_record,dizhu_uid) and player_can_must_win(last_record.uid,self.ddz_instance,card_type_list) then
        print("on_teammate_play player_can_must_win")
        return
    end

    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        if next_is_dizhu(self) and not self.is_main_role and 
           #self_card_type_list[CARD_SUIT_TYPE_DANPAI] > 0 then
            local dizhu_card_list = assert(make_card_type(dizhu_uid,self.ddz_instance))
            if #dizhu_card_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
                local _,second_max_num = get_max_two_number(dizhu_card_list[CARD_SUIT_TYPE_DANPAI])
                local len = #self_card_type_list[CARD_SUIT_TYPE_DANPAI]
                local self_max_num = self_card_type_list[CARD_SUIT_TYPE_DANPAI][len]
                if POWER_MAP[self_max_num] > POWER_MAP[last_card_suit_key] then
                    if POWER_MAP[self_max_num] < POWER_MAP[second_max_num] then
                        return {[self_max_num] = 1}
                    else
                        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
                            if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and 
                               POWER_MAP[number] > POWER_MAP[second_max_num] and 
                               POWER_MAP[number] > POWER_MAP[last_card_suit_key] then                  
                               return {[number] = 1}
                            end
                        end
                    end
                end
            end
        end

        --大于等于A的时候,必须满足必赢条件
        local pai_A = 12
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_A then
            return
        end
        return check_dan_pai(self,last_card_suit_key,true)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        --大于等于QQ的时候,必须满足必赢条件
        local pai_Q = 10 
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_Q then
            return
        end
        return check_dui_pai(self,last_card_suit_key,last_record.uid,true)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        local pai_J = 9
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_J then
            return
        end 
        return check_san_zhang_pai(self,last_card_suit_key,last_record.uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        local pai_J = 9
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_J then
            return
        end 
        return check_san_dai_yi(self,last_card_suit_key,last_record.uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        local pai_J = 9
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_J then
            return
        end 
        return check_san_dai_yi_dui(self,last_card_suit_key,last_record.uid)
    end
end

local function next_player_is_teammate(self)
    if self.uid == self.ddz_instance:get_dizhu_uid() then
        return false
    end
    if next_is_dizhu(self) then
        return false
    end
    return true
end

local function select_numbers(self,last_record)
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key
    local last_card_suit = last_record.card_suit
    local last_uid = last_record.uid

    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        local next_player_card_count = self.ddz_instance:get_next_player_card_count(self.uid)
        local next_uid = self.ddz_instance:get_next_position_uid(self.uid)
        if next_player_card_count == REMAIN_CARD_COUNT_ONE and
            next_player_is_teammate(self) and
            player_can_play(self,last_record,next_uid) then
            return
        else
            return check_dan_pai(self,last_card_suit_key)
        end    
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return check_dui_pai(self,last_card_suit_key,last_uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        return check_san_zhang_pai(self,last_card_suit_key,last_uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        return check_san_dai_yi(self,last_card_suit_key,last_uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        return check_san_dai_yi_dui(self,last_card_suit_key,last_uid)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DANSHUN then
        return check_dan_shun(last_card_suit_key,#last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
        return check_shuang_shun(last_card_suit_key,#last_card_suit / 2)
    elseif last_card_suit_type == CARD_SUIT_TYPE_FEIJI then
        return check_feiji(last_card_suit_key,last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
        return check_feiji_and_wing(last_card_suit_key,last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SIDAIER then
        return check_zhadan_wangzha()
    elseif last_card_suit_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
        return check_zhadan_wangzha()
    elseif last_card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        return check_zhadan_wangzha(last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_WANGZHA then
        print("****************************************")
        return
    else
        error('unknwon card suit type ...',last_card_suit_type)
    end
end

local function delay_card_type_dan_pai(candidate_type)
    for index,card_type in pairs(candidate_type) do
        if card_type == CARD_SUIT_TYPE_DANPAI then
            table_remove(candidate_type,index)
            break
        end
    end
    table_insert(candidate_type,CARD_SUIT_TYPE_DANPAI)
    table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
end

local function delay_card_type_dui_pai(candidate_type)
    for index,card_type in pairs(candidate_type) do
        if card_type == CARD_SUIT_TYPE_DUIPAI then
            table_remove(candidate_type,index)
            break
        end
    end
    table_insert(candidate_type,CARD_SUIT_TYPE_DUIPAI)
    --如果没有单牌，将对牌拆为单牌
    if #self_card_type_list[CARD_SUIT_TYPE_DANPAI] == 0 then
        for _,number in pairs(self_card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
            table_insert(self_card_type_list[CARD_SUIT_TYPE_DANPAI],number)
        end
        self_card_type_list[CARD_SUIT_TYPE_DUIPAI] = {}
    end
end

local function delay_card_type(candidate_type,card_type)
    for index,new_card_type in pairs(candidate_type) do
        if new_card_type == card_type then
            table_remove(candidate_type,index)
            break
        end
    end
    print("++++++++++++++++++",card_type)
    table_insert(candidate_type,card_type)
    if card_type == CARD_SUIT_TYPE_DANPAI or card_type == CARD_SUIT_TYPE_DUIPAI then
        table_sort(self_card_type_list[card_type],function(a,b) return (a>b) end)
    end    
end

local function select_card_on_must_play(self,candidate_type,check_min)
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    local min_num_map
    if check_min then
        min_num_map = get_min_dan_pai(cards_id_list)
    end
    for _,card_suit_type in pairs(candidate_type) do
        if check_by_card_type(self,card_suit_type,min_num_map) then
            local ret = select_by_card_type(self,card_suit_type)
            if ret then 
                return full_result_cards(ret,real_card_number_set)
            else
                print("select card_faild!!! type is ",card_suit_type)
            end
        end
    end
end

local function on_play_pre_is_teammate(self,last_record)
    local ret = on_teammate_play(self,last_record)
    if not ret then 
        return {} --不出
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    return full_result_cards(ret,real_card_number_set)
end

local function on_play_next_is_teammate(self,candidate_type)
    local next_player_card_count = self.ddz_instance:get_next_player_card_count(self.uid)
    if next_player_card_count == REMAIN_CARD_COUNT_ONE then --队友报单
        local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
        local _,real_card_number_set = process_card_id_list(cards_id_list)
        local ret = get_min_dan_pai(cards_id_list)
        if ret then 
            return full_result_cards(ret,real_card_number_set)     
        else
            errlog("on_play_next_is_teammate select card_faild!!!")
            return 
        end
    end

    local check_min = true
    if rival_is_remain_one(self) or self_can_must_win(self) then
        check_min = false
    end
    return select_card_on_must_play(self,candidate_type,check_min)
end

local function pre_player_is_teammate(self,last_record)
    local ddz_instance = assert(self.ddz_instance)
    local dizhu_uid = ddz_instance:get_dizhu_uid()
    if self.uid == dizhu_uid and last_record.uid ~= dizhu_uid then
        return false
    end
    if self.uid ~= dizhu_uid and last_record.uid == dizhu_uid then
        return false
    end

    return true
end

local function rival_is_remain_dui_pai(self)
    if not rival_is_remain_two(self) then
        return false
    end
    if self.uid == self.ddz_instance:get_dizhu_uid() then
        local farmer1_uid,famer2_uid = self.ddz_instance:get_farmer_uids()
        local cards1_id_list = self.ddz_instance:get_player_card_ids(farmer1_uid)
        local cards2_id_list = self.ddz_instance:get_player_card_ids(famer2_uid)
        assert(#cards1_id_list == 2 or #cards2_id_list == 2)
        if #cards1_id_list == 2 then
            return extract_card_number(cards1_id_list[1]) == extract_card_number(cards1_id_list[2])
        else
            return extract_card_number(cards2_id_list[1]) == extract_card_number(cards2_id_list[2])
        end
    else
        local dizhu_uid = self.ddz_instance:get_dizhu_uid()
        local cards_id_list = self.ddz_instance:get_player_card_ids(dizhu_uid)
        assert(#cards_id_list == 2)
        return extract_card_number(cards_id_list[1]) == extract_card_number(cards_id_list[2])
    end   
end

local function on_play_pre_is_rival(self,last_record)
    local ret = select_numbers(self,last_record)
    --print_r(last_record)
    if not ret then 
        if rival_is_remain_one_handle(self,last_record.uid) and 
        last_record.card_suit_type ~= CARD_SUIT_TYPE_ZHADAN and 
        last_record.card_suit_type ~= CARD_SUIT_TYPE_WANGZHA then
            ret = check_zhadan_wangzha()
        end
        if not ret then
            return {} --不出 
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    return full_result_cards(ret,real_card_number_set)
end

local function on_play_next_is_rival(self,candidate_type_list,can_must_win)
    --[[if next_is_dizhu(self) and not can_must_win then
        local candidate_type_list = {
            CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,CARD_SUIT_TYPE_DANSHUN,
            CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_SANZANGPAI,CARD_SUIT_TYPE_DUIPAI,
            CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_SIDAIER,CARD_SUIT_TYPE_SIDAILIANGDUI,
            CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
        }
        return select_card_on_must_play(self,candidate_type_list,false)
    end]]

    local check_min = true
    if can_must_win or rival_is_remain_one(self) or rival_is_remain_two(self) then
        check_min = false
    end

    return select_card_on_must_play(self,candidate_type_list,check_min)
end

local function check_next_rival_on_remain_one(self,last_record)
    if last_record.card_suit_type ~= CARD_SUIT_TYPE_DANPAI 
        or next_player_is_teammate(self) then
       return
    end
    if not rival_is_remain_one(self) then
        return
    end
    
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    local ret = get_max_dan_pai(cards_id_list,last_record.key)
    if not ret then 
        return   
    end

    return full_result_cards(ret,real_card_number_set)
end

local function check_next_rival_remain_report(self,last_record)
    if next_player_is_teammate(self) then
        return
    end
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local ret 
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local next_uid = self.ddz_instance:get_next_position_uid(self.uid)
    local next_is_rival = false
    if self.uid == dizhu_uid or next_uid == dizhu_uid then
        next_is_rival = true
    end
    print("111111111111111111111111")
    if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI and 
        rival_is_remain_one(self) and 
        next_is_rival and
        player_can_play(self,last_record,next_uid) then
       --敌方报单的时候,出最大的单牌
        ret = get_max_cards_greater_than_key(last_record,cards_id_list)
    end
    if last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI and
       rival_is_remain_dui_pai(self) and
       player_can_play(self,last_record,next_uid) and
       next_is_rival then
       --敌方是对牌的时候出对牌
       ret = get_max_cards_greater_than_key(last_record,cards_id_list)
    end
    if ret then 
        local _,real_card_number_set = process_card_id_list(cards_id_list)
        return full_result_cards(ret,real_card_number_set) 
    end 
end

local function on_must_play(self)
    --[[local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    if #cards_id_list == 2 and #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] == 1 then
        local card_number = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][1]
        local ret = {}
        ret[card_number] = 2
        local _,real_card_number_set = process_card_id_list(cards_id_list)
        return full_result_cards(ret,real_card_number_set)
    end]]

    local candidate_type_list = {
        CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_DUIPAI,CARD_SUIT_TYPE_DANSHUN,
        CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_SANZANGPAI,
        CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,
        CARD_SUIT_TYPE_SIDAIER,CARD_SUIT_TYPE_SIDAILIANGDUI,
        CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
    }

    local can_must_win,card_type_finaly_play = self_can_must_win(self)
    if can_must_win then
        print("======================can_must_win")
        candidate_type_list = {
            CARD_SUIT_TYPE_DANSHUN,CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_SANZANGPAI,
            CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,CARD_SUIT_TYPE_SIDAIER,
            CARD_SUIT_TYPE_SIDAILIANGDUI,CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_DUIPAI,
            CARD_SUIT_TYPE_WANGZHA,CARD_SUIT_TYPE_ZHADAN,
        }
        if rival_is_remain_one(self) then
            delay_card_type_dan_pai(candidate_type_list)
        end
        if card_type_finaly_play then
            print("===========================",card_type_finaly_play)
            delay_card_type(candidate_type_list,card_type_finaly_play)
        end
        return select_card_on_must_play(self,candidate_type_list,false)
    end

    if rival_is_remain_one(self) then
        delay_card_type_dan_pai(candidate_type_list)
    end
    if rival_is_remain_two(self) then
        delay_card_type_dui_pai(candidate_type_list)
    end

    if next_player_is_teammate(self) then  
        --如果下家是队友
        return on_play_next_is_teammate(self,candidate_type_list)
    else  --如果下家是敌对                      
        return on_play_next_is_rival(self,candidate_type_list,can_must_win)  
    end
end

local function on_play_follow(self,last_record)
    local ret = select_numbers(self,last_record)
    if not ret then
        if last_record.card_suit_type ~= CARD_SUIT_TYPE_ZHADAN and 
        last_record.card_suit_type ~= CARD_SUIT_TYPE_WANGZHA then
            ret = check_zhadan_wangzha()
        end
        if not ret then
            return {}
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    return full_result_cards(ret,real_card_number_set)
end

local function on_not_must_play(self,last_record)
    --处理敌方报单,报双的情况
    local cards = check_next_rival_remain_report(self,last_record)
    if cards then 
        return cards
    end

    local can_must_win,card_type = self_can_must_win(self)
    if can_must_win then
        local player_cards_id = self.ddz_instance:get_player_card_ids(self.uid)
        if lz_remind.can_greater_than(player_cards_id,last_record.card_suit,last_record.card_suit_type,last_record.key) then
            if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI then
                table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
            elseif last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI then
                table_sort(self_card_type_list[CARD_SUIT_TYPE_DUIPAI],function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)    
            end
            return on_play_follow(self,last_record)
        end
    end
    --如果满足必赢条件则跟牌
    --if self_can_must_win(self) then
    --   return on_play_follow(self,last_record)
    --end

    --print("xxxxxxxxxxxxxxxxxxxxxxxxxx",tostring_r(self_card_type_list))
    if pre_player_is_teammate(self,last_record) then
         --如果上家是队友
        return on_play_pre_is_teammate(self,last_record)
    else --如果上家是敌对
        return on_play_pre_is_rival(self,last_record)
    end
end

local M = {}

function M.analyse_rob_dizhu(self)
    local ddz_instance = assert(self.ddz_instance)
    if not self.is_rob then
        self.is_rob = is_need_rob_dizhu(self)
    end

    return {score = 0,is_rob = self.is_rob and 1 or 0}
end

function M.analyse_jiabei(self)
    print("sss",self.uid)
    WEIGH_VALUE_CONF = assert(self.conf.weigh_value_conf)
    JIABEI_CONF = assert(self.conf.jia_bei_conf)

    local ddz_instance = assert(self.ddz_instance)
    self_card_type_list = assert(make_card_type(self.uid,ddz_instance)) 
    make_farmer_role(self)

    local is_jiabei = is_need_jiabei(self.uid,self.ddz_instance)
    return { type = is_jiabei and 1 or 0}
end

function M.analyse_play(self)
    local ddz_instance = assert(self.ddz_instance)
    local last_record = ddz_instance:get_last_card_suit_ex()
    local must_play = false
    if not last_record or last_record.uid == self.uid then
        must_play = true
    end

    --确定牌型
    self_card_type_list = assert(make_card_type(self.uid,ddz_instance)) 
    --print_r(self_card_type_list)
    local result_card_id_list
    if must_play then
        result_card_id_list = on_must_play(self) or {}
    else
        result_card_id_list = on_not_must_play(self,last_record) or {}
    end

    return {card_suit = result_card_id_list}
end

return M