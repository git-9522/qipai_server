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
local CARD_NUMBER_A = 1
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
local make_card_tmp_list
local make_card_sucess
local make_card_type

--配置
local WEIGH_VALUE_CONF 
local ROB_DIZHU_CONF

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

local function get_absolute_handle_count(uid,ddz_instance,total_card_type_list)
   local absolute_handle_count = 0
   for card_type,card_type_list in pairs(total_card_type_list) do
        for _,card_number in pairs(card_type_list) do
           if card_type == CARD_SUIT_TYPE_DANPAI and card_number == RED_JOKER_NUMBER then
                absolute_handle_count = absolute_handle_count + 1
           elseif (card_type == CARD_SUIT_TYPE_DUIPAI or card_type == CARD_SUIT_TYPE_SANZANGPAI)
                and card_number == CARD_TWO_NUMBER then
                absolute_handle_count = absolute_handle_count + 1
           elseif (card_type == CARD_SUIT_TYPE_DANSHUN or card_type == CARD_SUIT_TYPE_SHUANGSHUN
                or card_type == CARD_SUIT_TYPE_FEIJI) and card_number[#card_number] == CARD_NUMBER_A then
                absolute_handle_count = absolute_handle_count + 1
           elseif card_type == CARD_SUIT_TYPE_ZHADAN or card_type == CARD_SUIT_TYPE_WANGZHA then
                absolute_handle_count = absolute_handle_count + 1
           end
        end
    end

    return absolute_handle_count
end

local function player_can_must_win(uid,ddz_instance,card_type_list)
    local handle_count = get_card_handle_count(card_type_list)
    local absolute_handle_count = get_absolute_handle_count(uid,ddz_instance,card_type_list)
    if absolute_handle_count >= handle_count - 1 then
        return true
    end
    return false
end

--自己达到必赢条件
local function self_can_must_win(self)
    return player_can_must_win(self.uid,self.ddz_instance,self_card_type_list)
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
-----------------------------------------check_jiabei_end-----------------------------------------

-----------------------------------------make_card_type_begin-------------------------------------
local function make_wangzha(real_card_num_set,card_type_list)
    if real_card_num_set[BLACK_JOKER_NUMBER] and real_card_num_set[RED_JOKER_NUMBER] then
        table_insert(card_type_list[CARD_SUIT_TYPE_WANGZHA],{BLACK_JOKER_NUMBER,RED_JOKER_NUMBER})
        real_card_num_set[BLACK_JOKER_NUMBER] = nil
        real_card_num_set[RED_JOKER_NUMBER]   = nil
    end
end

local function make_one_card_card_type(real_card_num_set,card_number,card_type_list)
   if not real_card_num_set[card_number] then
        return
   end

   local len = #real_card_num_set[card_number]
   if len == 1 then
      table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],card_number)
   elseif len == 2 then
      table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],card_number)
   elseif len == 3 then
      table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],card_number)
   elseif len == 4 then
      table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],card_number)
   else
      errlog("make_one_card_card_type len err",card_number,len)
   end
   real_card_num_set[card_number] = nil
end

local function make_dan_shun(real_card_number_set,card_type_list,except_map)
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

        if real_card_number_set[number] and not except_map[number] then
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
end

local function make_zhadan(real_card_num_set,card_type_list)
    for number,cards_id_list in pairs(real_card_num_set) do
        if #cards_id_list == 4 then
            table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],number)
            real_card_num_set[number] = nil
        end
    end
end

local function make_dan_pai(real_card_num_set,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 1 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DANPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_dui_pai(real_card_num_set,card_type_list)
   for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 2 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DUIPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_san_zhang_pai(real_card_num_set,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],number)
            real_card_num_set[number] = nil
        end
    end

    local tmp_list = card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_feiji(real_card_number_set,card_type_list)
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
end

local function select_card_type_list(uid,ddz_instance,tmp_card_type_list)
    assert(make_card_tmp_list)

    if player_can_must_win(uid,ddz_instance,tmp_card_type_list) then
        make_card_tmp_list = tmp_card_type_list
        make_card_sucess = true
        return
    end

    local tmp_handle_count = get_card_handle_count(tmp_card_type_list)
    local tmp_absolute_count = get_absolute_handle_count(uid,ddz_instance,tmp_card_type_list)
    local tmp_weigh_value = get_card_weigh_value(tmp_card_type_list)

    local cur_handle_count = get_card_handle_count(make_card_tmp_list)
    local cur_absolute_count = get_absolute_handle_count(uid,ddz_instance,make_card_tmp_list)
    local cur_weigh_value = get_card_weigh_value(make_card_tmp_list)

    if tmp_handle_count < cur_handle_count then
        make_card_tmp_list = tmp_card_type_list
    end
    if tmp_handle_count == cur_handle_count and tmp_absolute_count > cur_absolute_count then
        make_card_tmp_list = tmp_card_type_list
    end
    if tmp_handle_count == cur_handle_count and tmp_absolute_count == cur_absolute_count 
       and tmp_weigh_value > cur_weigh_value then
        make_card_tmp_list = tmp_card_type_list
    end
end

local function get_disorder_card(real_card_number_set)
    local disorder_number_map = {}
    if real_card_number_set[BLACK_JOKER_NUMBER] then
        disorder_number_map[BLACK_JOKER_NUMBER] = true
    end
    if real_card_number_set[RED_JOKER_NUMBER] then
        disorder_number_map[RED_JOKER_NUMBER] = true
    end
    if real_card_number_set[CARD_TWO_NUMBER] then
        disorder_number_map[CARD_TWO_NUMBER] = true
    end

    local lian_pai_list = {}
    local lian_pai = {}
    local power = 1
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end

        if real_card_number_set[number] then
            table_insert(lian_pai,number)
        else
            table_insert(lian_pai_list,lian_pai)
            lian_pai = {}
        end
        power = power + 1
    end 
    if next(lian_pai) then
        table_insert(lian_pai_list,lian_pai)
    end

    for _,lian_pai in pairs(lian_pai_list) do
        if #lian_pai == 1 then
            disorder_number_map[lian_pai[1]] = true
        end
    end
    return disorder_number_map
end

local function get_all_zd_sz_dz(real_card_number_set,except_map)
    local zd_sz_dz_list = {}
    for number,num_cards in pairs(real_card_number_set) do
        if not except_map[number] and #num_cards >= 2 then
            table_insert(zd_sz_dz_list,number)
        end
    end
    return zd_sz_dz_list
end

local function combine_zd_sz_dz_list(zd_sz_dz_list)
    local zd_sz_dz_combine_list = {}
    local len = #zd_sz_dz_list
    for i=1,len do
        for j=i+1,len do
            local tmp_map = {[zd_sz_dz_list[i]] = true,[zd_sz_dz_list[j]] = true}
            table_insert(zd_sz_dz_combine_list,tmp_map)
        end
    end
    return zd_sz_dz_combine_list
end

local function make_from_disorder_card(real_card_number_set,tmp_card_type_list,disorder_card_map)
    if disorder_card_map[BLACK_JOKER_NUMBER] and disorder_card_map[RED_JOKER_NUMBER] then
        make_wangzha(real_card_number_set,tmp_card_type_list)
        disorder_card_map[BLACK_JOKER_NUMBER] = nil
        disorder_card_map[RED_JOKER_NUMBER] = nil
    end

    for number,_ in pairs(disorder_card_map) do
        make_one_card_card_type(real_card_number_set,number,tmp_card_type_list)
    end
end

local function make_card_type_single(args)
    if make_card_sucess then
        return
    end

    local _,real_card_number_set = process_card_id_list(args.cards_id_list)
    local tmp_card_type_list = alloc_tmp_card_type_list()

    make_from_disorder_card(real_card_number_set,tmp_card_type_list,args.disorder_card_map)
    make_dan_shun(real_card_number_set,tmp_card_type_list,args.card_combine_map)
    make_shuang_shun(real_card_number_set,tmp_card_type_list)
    make_feiji(real_card_number_set,tmp_card_type_list)
    make_san_zhang_pai(real_card_number_set,tmp_card_type_list)
    make_zhadan(real_card_number_set,tmp_card_type_list)
    make_dui_pai(real_card_number_set,tmp_card_type_list)
    make_dan_pai(real_card_number_set,tmp_card_type_list)

    if not make_card_tmp_list then
        make_card_tmp_list = tmp_card_type_list
    else
        select_card_type_list(args.uid,args.ddz_instance,tmp_card_type_list)
    end
end

local function clean_make_card_tmp_list()
    if make_card_tmp_list then
        make_card_tmp_list = nil
    end
    make_card_sucess = false
end

make_card_type = function(uid,ddz_instance)
    clean_make_card_tmp_list()

    local cards_id_list = ddz_instance:get_player_card_ids(uid)
    local _,tmp_real_card_number_set = process_card_id_list(cards_id_list)
    local disorder_card_map = get_disorder_card(tmp_real_card_number_set)
    local zd_sz_dz_list = get_all_zd_sz_dz(tmp_real_card_number_set,disorder_card_map)
    local zd_sz_dz_combine_list = combine_zd_sz_dz_list(zd_sz_dz_list)

    local args = {
        cards_id_list = cards_id_list,
        disorder_card_map = disorder_card_map,
        uid = uid,
        ddz_instance = ddz_instance,
    }

    for _,card_combine_map in pairs(zd_sz_dz_combine_list) do
        args.card_combine_map = card_combine_map
        make_card_type_single(args)
    end

    args.card_combine_map = {}
    make_card_type_single(args)

    return make_card_tmp_list
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
        return false
    end
    if card_type == CARD_SUIT_TYPE_SIDAIER and 
       #self_card_type_list[CARD_SUIT_TYPE_DANPAI] < 2 then
        return false
    end
    if card_type == CARD_SUIT_TYPE_SIDAILIANGDUI and 
       #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] < 2 then
       return false
    end
    if not self_can_must_win(self) then
        return false
    end

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
    elseif card_type == CARD_SUIT_TYPE_WANGZHA then
        if #self_card_type_list[CARD_SUIT_TYPE_WANGZHA] <= 0 then
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
           table_insert(t_xiao_pai,xiao_dan_pai_list[i])
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
           table_insert(t_xiao_pai,xiao_dui_pai_list[i])
           table_insert(t_xiao_pai,xiao_dui_pai_list[i])
       end
       return t_xiao_pai
    end

    return {}
end

local function get_sidaier_xiao_pai(card_suit_type)
    local t_xiao_pai = {}
    if card_suit_type == CARD_SUIT_TYPE_SIDAIER and 
       #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
         for i=1,2 do
             local number = self_card_type_list[CARD_SUIT_TYPE_DANPAI][i]
             t_xiao_pai[number] = 1
         end
    end

    if card_suit_type == CARD_SUIT_TYPE_SIDAIER and
       #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 then
        for i=1,2 do
           local number = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][i]
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
    if second_max_num > max_num then
        max_num = num_list[2]
        second_max_num = num_list[1]
    end
    for i=3,#num_list do
        if num_list[i] > second_max_num then
            if num_list[i] > max_num then
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
        local _,second_max_num = get_max_two_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        return {[second_max_num] = 1}
    end
    if rival_is_remain_one(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        --当敌方报单的时候,必须出单牌时,出第二小的单牌
        local second_min_num = get_second_min_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        return {[second_min_num] = 1}
    end
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_DANPAI][1])
    return {[number] = 1}
end

local function select_dui_pai(self)
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
    local xiao_pai_list = get_feiji_xiao_pai(card_list)
    for _,number in pairs(xiao_pai_list) do
        if ret[number] then
            ret[number] = ret[number] + 1
        else
            ret[number] = 1
        end
    end
    return ret
end

local function select_si_dai_er(self)
    local ret = {}
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_ZHADAN][1])
    ret[number] = 4
    local xiao_pai_table = get_sidaier_xiao_pai(card_suit_type)
    if not next(xiao_pai_table) then
        return 
    end
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
        return select_si_dai_er(self)
    elseif card_suit_type == CARD_SUIT_TYPE_ZHADAN then
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
    --找单牌
    local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
    for _,number in pairs(dan_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            --小王只压2,大王只压小王
            if number == BLACK_JOKER_NUMBER and last_card_suit_key ~= 2 or 
               number == RED_JOKER_NUMBER and last_card_suit_key ~= BLACK_JOKER_NUMBER then
               break
            end

            return {[number] = 1}
        end
    end
    if only_check_dan_pai then return end

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
    return check_zhadan_wangzha()
end

local function check_dui_pai(self,last_card_suit_key,only_check_dui_pai)
    --找对牌
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    for _,number in pairs(dui_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            return {[number] = 2}
        end
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
    --炸弹
    return check_zhadan_wangzha()
end

local function check_xiao_pai_power(number)
    local handle_count = get_card_handle_count(self_card_type_list)
    local pai_2 = 14
    if handle_count > 2 and POWER_MAP[number] >= pai_2 then
        return false
    end
    return true
end

local function get_xiao_pai(except_map,xiaopai_type,xiaopai_count)
    local xiao_pai_map = {}
    local remain_count = xiaopai_count

    if xiaopai_type == 1 then --单牌
        local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        for _,number in pairs(dan_pai_list) do
            if remain_count > 0 and check_xiao_pai_power(number) 
                and not except_map[number] then
                xiao_pai_map[number] = 1
                remain_count = remain_count - 1
            end
        end
        --找6连顺以上的底牌
        local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
        for _,dan_shun in pairs(dan_shun_list) do
            if #dan_shun >= 6 and remain_count > 0 and not except_map[dan_shun[1]] then
                xiao_pai_map[dan_shun[1]] = 1
                remain_count = remain_count - 1
            end
        end
        --拆三条中的牌
        local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        for _,number in pairs(san_zhang_pai_list) do
            if not except_map[number] and remain_count > 0 and check_xiao_pai_power(number) then
                xiao_pai_map[number] = 1
                remain_count = remain_count - 1
            end
        end
        --拆飞机
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        for _,feiji in pairs(feiji_list) do
            for _,number in pairs(feiji) do
                if not except_map[number] and remain_count > 0 then
                    xiao_pai_map[number] = 1
                    remain_count = remain_count - 1
                end     
            end 
        end
        --拆5连顺
        for _,dan_shun in pairs(dan_shun_list) do
            for _,number in pairs(dan_shun) do
                if #dan_shun == 5 and remain_count > 0 then
                    xiao_pai_map[number] = 1
                    remain_count = remain_count - 1
                end
            end
        end
        --拆连对
        local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
        for _,shuang_shun in pairs(shuang_shun_list) do
            for _,number in pairs(shuang_shun) do
                if remain_count > 0 then
                    xiao_pai_map[number] = 1
                    remain_count = remain_count - 1
                end 
            end   
        end
    elseif xiaopai_type ==  2 then  --对牌
        --找对牌
        local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
        for _,number in pairs(dui_pai_list) do
            if remain_count > 0 and check_xiao_pai_power(number) then
                xiao_pai_map[number] = 2
                remain_count = remain_count - 1
            end
        end
        --拆4连对的底对
        local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
        for _,shuang_shun in pairs(shuang_shun_list) do
            if #shuang_shun >= 4 then
                for _,number in pairs(shuang_shun) do
                    if remain_count > 0 then
                        xiao_pai_map[number] = 2
                        remain_count = remain_count - 1
                    end
                end
            end
        end
        --拆三条中的牌
        local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        for _,number in pairs(san_zhang_pai_list) do
            if not except_map[number] and remain_count > 0 and check_xiao_pai_power(number) then
                xiao_pai_map[number] = 2
                remain_count = remain_count - 1
            end    
        end
        --拆3连对
        for _,shuang_shun in pairs(shuang_shun_list) do
            for _,number in pairs(shuang_shun) do 
                if remain_count > 0 then
                    xiao_pai_map[number] = 2
                    remain_count = remain_count - 1
                end    
            end
        end
        --拆飞机
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        for _,feiji in pairs(feiji_list) do
            for _,number in pairs(feiji) do
                if not except_map[number] and remain_count > 0 then
                    xiao_pai_map[number] = 2
                    remain_count = remain_count - 1
                end
            end
        end
    else
       errlog("unknwon xiaopai_count!!!!")
    end

    if remain_count <= 0 then
        return xiao_pai_map
    end
end

local function check_san_zhang_pai(self,last_card_suit_key)
   --拆三条中的牌
    local pai_2 = 14
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[number] <= POWER_MAP[last_card_suit_key] then
            goto continue
        end
        if POWER_MAP[number] == pai_2 then
           if self_can_must_win(self) then
               return {[number] = 3}
           end
        else
            return {[number] = 3}
        end

        ::continue::
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        for _,number in pairs(feiji) do
          if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                return {[number] = 3}
            end
        end 
    end
    --炸弹
    return check_zhadan_wangzha()
end

local function check_san_dai_yi(self,last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local pai_2 = 14
    local ret = {}
    local except_number = 0
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[number] <= POWER_MAP[last_card_suit_key] then
            goto continue
        end
        if POWER_MAP[number] == pai_2 then
           if self_can_must_win(self) then
                ret[number] = 3
                break
           end
        else
            ret[number] = 3
            break
        end

        ::continue::
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(ret) then
            for _,number in pairs(feiji) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    ret[number] = 3
                    break
                end
            end 
        end
    end
    --寻找小牌
    if next(ret) then
        local xiaopai_type = 1
        local xiao_pai_map = get_xiao_pai(ret,xiaopai_type,1)

        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                ret[number] = count
            end

            return ret
        end
    end
    --炸弹
    return check_zhadan_wangzha()
end

local function check_san_dai_yi_dui(self,last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local pai_2 = 14
    local ret = {}
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[number] <= POWER_MAP[last_card_suit_key] then
            goto continue
        end
        if POWER_MAP[number] == pai_2 then
           if self_can_must_win(self) then
                ret[number] = 3
                break
           end
        else
            ret[number] = 3
            break
        end

        ::continue::
    end
    --拆飞机
    
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(ret) then
            for _,number in pairs(feiji) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    ret[number] = 3
                    break
                end
            end 
        end
    end
    --寻找小牌
    if next(ret) then
        local xiaopai_type = 2
        local xiao_pai_map = get_xiao_pai(ret,xiaopai_type,1)
        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                ret[number] = count
            end

            return ret
        end
    end
    --炸弹
    return check_zhadan_wangzha()
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

    return check_zhadan_wangzha()
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
        local xiao_pai_map = get_xiao_pai(ret,xiaopai_type,feiji_len)
        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                ret[number] = count
            end

            return ret
        end
    end
    
    return check_zhadan_wangzha()
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

local function get_max_cards_greater_than_key(last_record)
    local card_type_list = self_card_type_list[last_record.card_suit_type]
    if not next(card_type_list) then
        return
    end

    local max_card_num = card_type_list[1]
    for _,number in pairs(card_type_list) do
        if POWER_MAP[number] > POWER_MAP[max_card_num] then
            max_card_num = number
        end
    end
    if POWER_MAP[max_card_num] <= POWER_MAP[last_record.key] then
        return
    end

    if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return {[max_card_num] = 1}
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return {[max_card_num] = 2}
    end
end

local function on_teammate_play(self,last_card_suit_type,last_card_suit_key)
    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
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
        return check_dui_pai(self,last_card_suit_key,true)
    end
end

local function select_numbers(self,last_card_suit_type,last_card_suit_key,last_card_suit)
    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return check_dan_pai(self,last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return check_dui_pai(self,last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        return check_san_zhang_pai(self,last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        return check_san_dai_yi(self,last_card_suit_key,last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        return check_san_dai_yi_dui(self,last_card_suit_key,last_card_suit)
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
    table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (a > b) end)
end

local function delay_card_type_dui_pai(candidate_type)
    for index,card_type in pairs(candidate_type) do
        if card_type == CARD_SUIT_TYPE_DUIPAI then
            table_remove(candidate_type,index)
            break
        end
    end
    table_insert(candidate_type,CARD_SUIT_TYPE_DUIPAI)
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
                errlog("select card_faild!!! type is ",card_suit_type)
            end
        end
    end
end

local function on_play_pre_is_teammate(self,last_record)
    local ret = on_teammate_play(self,last_record.card_suit_type,last_record.key)
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

    return select_card_on_must_play(self,candidate_type,true)
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

local function next_player_is_teammate(self)
    if self.uid == self.ddz_instance:get_dizhu_uid() then
        return false
    end
    if next_is_dizhu(self) then
        return false
    end
    return true
end

local function on_play_pre_is_rival(self,last_record)
    local ret = select_numbers(self,last_record.card_suit_type,last_record.key,last_record.card_suit)
    if not ret then 
        return {} --不出 
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    return full_result_cards(ret,real_card_number_set)
end

local function on_play_next_is_rival(self,candidate_type_list)
    if self.uid ~= self.ddz_instance:get_dizhu_uid() then
        local candidate_type_list = {
            CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,CARD_SUIT_TYPE_DANSHUN,
            CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_SANZANGPAI,CARD_SUIT_TYPE_DUIPAI,
            CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_SIDAIER,CARD_SUIT_TYPE_SIDAILIANGDUI,
            CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
        }
        return select_card_on_must_play(self,candidate_type_list,false)
    end

    return select_card_on_must_play(self,candidate_type_list,true)
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

    local ret
    if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI and 
       rival_is_remain_one(self) then
       --敌方报单的时候,出单牌
        ret = get_max_cards_greater_than_key(last_record)
    end
    if last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI and
       rival_is_remain_two(self) then
       --敌方报双的时候出对牌
       ret = get_max_cards_greater_than_key(last_record)
    end
    if ret then 
        local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
        local _,real_card_number_set = process_card_id_list(cards_id_list)
        return full_result_cards(ret,real_card_number_set) 
    end 
end

local function on_must_play(self)
    local candidate_type_list = {
        CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_DUIPAI,CARD_SUIT_TYPE_DANSHUN,
        CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,
        CARD_SUIT_TYPE_SIDAIER,CARD_SUIT_TYPE_SIDAILIANGDUI,CARD_SUIT_TYPE_SANZANGPAI,
        CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
    }
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
        return on_play_next_is_rival(self,candidate_type_list)  
    end
end

local function on_not_must_play(self,last_record)
    --处理敌方报单,报双的情况
    local cards = check_next_rival_remain_report(self,last_record)
    if cards then 
        return cards
    end

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
    WEIGH_VALUE_CONF = assert(self.conf.weigh_value_conf)
    JIABEI_CONF = assert(self.conf.jia_bei_conf)

    local ddz_instance = assert(self.ddz_instance)
    self_card_type_list = assert(make_card_type(self.uid,ddz_instance)) 

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

    local result_card_id_list
    if must_play then
        result_card_id_list = on_must_play(self) or {}
    else
        result_card_id_list = on_not_must_play(self,last_record) or {}
    end
    return {card_suit = result_card_id_list}
end

return M