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

local make_card_type

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

local CARD_TWO_NUMBER = 2
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

--配置
local WEIGH_VALUE_CONF --权重配置
local ROB_DIZHU_CONF --抢地主配置
local JIABEI_CONF

local MARK_TYPE_WANGZHA = 1
local MARK_TYPE_ZHANDAN  = 2
local MARK_TYPE_DANPAI_RJOKER = 3
local MARK_TYPE_DANPAI_BJOKER = 4
local MARK_TYPE_DANPAI_TWO = 5
local MARK_TYPE_ONE_LAIZI   = 6
local MARK_TYPE_TWO_LAIZI   = 7
local MARK_TYPE_THREE_LAIZI = 8
local MARK_TYPE_FOUR_LAIZI  = 9


local MARK_TYPE_SCORE_MAP = {
    [MARK_TYPE_WANGZHA] = 8,--王炸8分
    [MARK_TYPE_ZHANDAN]  = 6,--炸弹6分
    [MARK_TYPE_DANPAI_RJOKER] = 4, --单牌大王4分
    [MARK_TYPE_DANPAI_BJOKER] = 3, --单牌小王3分
    [MARK_TYPE_DANPAI_TWO] = 2, --一张单牌二 2分
    [MARK_TYPE_ONE_LAIZI] =   1,   --一个癞子 1分
    [MARK_TYPE_TWO_LAIZI] =   4,   --两个癞子 4分
    [MARK_TYPE_THREE_LAIZI] = 9,   --三个癞子 9分
    [MARK_TYPE_FOUR_LAIZI] =  12,  --四个癞子 12分
}

local ROB_DIZHU_PROBABILITY = {
    {score = 0,probability = 0},    --0-4分百分之0概率
    {score = 6,probability = 20},   --6分以上百分之20概率
    {score = 8,probability = 50},   --8分以上百分之50概率
    {score = 12,probability = 100},  --12以上百分之100概率 
}

local REMAIN_CARD_COUNT_ONE = 1 --报单
local REMAIN_CARD_COUNT_TWO = 2 --报双

local card_type_map = {
    [CARD_SUIT_TYPE_WANGZHA] = 1,         --王炸
    [CARD_SUIT_TYPE_ZHADAN] = 2,          --炸弹
    [CARD_SUIT_TYPE_DANPAI] = 3,          --单牌
    [CARD_SUIT_TYPE_DUIPAI] = 4,          --对牌
    [CARD_SUIT_TYPE_SANZANGPAI] = 5,      --三张牌
    [CARD_SUIT_TYPE_DANSHUN] = 7,         --单顺
    [CARD_SUIT_TYPE_SHUANGSHUN] = 8,      --双顺
    [CARD_SUIT_TYPE_FEIJI] = 9,           --飞机
    [CARD_SUIT_TYPE_RUANZHA] = 12,        --软炸
}

local rz_san_zhang_priority_list   = {}
local san_zhang_priority_list      = {}
local rz_dan_shun_priority_list    = {} 
local dan_shun_priority_list       = {}
local rz_shuang_shun_priority_list = {}
local shuang_shun_priority_list    = {}

local self_laizi_count = 0
local self_card_type_list

-----------------------------------------common-----------------------------------------------
local function get_now_ustime()
    local time4,time5 = util.get_now_time() 
    return time4 * 1000000 + time5
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

local function delete_number_on_number_set(real_card_number_set,number,count)
    assert(#real_card_number_set[number] >= count)

    for i=1,count do
        table_remove(real_card_number_set[number],1)
    end
    if #real_card_number_set[number] <= 0 then
        real_card_number_set[number] = nil
    end
end

local function wipe_laizi(real_card_num_set,laizi)
    self_laizi_count = 0
    for number,card_id_list in pairs(real_card_num_set) do
        if number == laizi then
            self_laizi_count = #card_id_list
            delete_number_on_number_set(real_card_num_set,laizi,#card_id_list)
            break
        end
    end
end

local function full_result_cards(ret,real_card_number_set)
    local cards = {}
    for number,count in pairs(ret) do
        local card_id_list = assert(real_card_number_set[number])
        for i = 1,count do
            print("ddd",i,count)
            table_insert(cards,assert(card_id_list[i]))
        end
    end
    return cards
end

local function get_shun_zi_len(shun_zi,card_type)
    local card_count = 0
    for number,count in pairs(shun_zi) do
        card_count = card_count + count
    end

    local shun_zi_type
    if card_type == CARD_SUIT_TYPE_DANSHUN then
        shun_zi_type = 1
    elseif card_type == CARD_SUIT_TYPE_SHUANGSHUN then
        shun_zi_type = 2
    elseif card_type == CARD_SUIT_TYPE_FEIJI then
        shun_zi_type = 3
    end

    return card_count / assert(shun_zi_type)
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

local function wipe_dai_pai_count(total_count,card_type_list)
    local zha_dan_count,san_zhang_count,dui_pai_count,dan_pai_count

    local zhan_dan_list = card_type_list[CARD_SUIT_TYPE_ZHADAN] 
    local ruan_zha_list = card_type_list[CARD_SUIT_TYPE_RUANZHA]
    san_zhang_count = #card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,feiji in pairs(card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        san_zhang_count = san_zhang_count + #feiji
    end
    --四带两手,三带一手
    local da_pai_count = (#zhan_dan_list + #ruan_zha_list) * 2 + san_zhang_count

    dui_pai_count = #card_type_list[CARD_SUIT_TYPE_DUIPAI]
    dan_pai_count = #card_type_list[CARD_SUIT_TYPE_DANPAI]
    local xiao_pai_count = dui_pai_count + dan_pai_count

    local min = math.min(da_pai_count,xiao_pai_count)
    local tmp_count = total_count - min
    return tmp_count
end

--得到手数
local function get_card_handle_count(total_card_type_list)
    local count = 0
    for _,card_type_list in pairs(total_card_type_list) do
        count = (count or 0) + #card_type_list
    end
    count = wipe_dai_pai_count(count,total_card_type_list)

    return count
end

--绝对手数
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
    local laizi = ddz_instance:get_laizi_id() 
    for card_type,card_type_list in pairs(total_card_type_list) do
        for _,card_info in pairs(card_type_list) do
            
            local get_cards = function(cards)
                local new_cards = {}
                for card_id,count in pairs(cards) do
                    for i=1,count do
                        table_insert(new_cards,card_id)
                    end
                end
                return new_cards
            end

            local card_suit = get_cards(card_info.cards)
            local key = card_info.key
            if not lz_remind.lz_can_greater_than(compare_card1_ids,card_suit,card_type,key,laizi) and
                not lz_remind.lz_can_greater_than(compare_card2_ids,card_suit,card_type,key,laizi) then
                 absolute_handle_count = absolute_handle_count + 1
            else
                 one_card_type_no_absolute = card_type
            end
        end
    end

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
   local laizi = self.ddz_instance:get_laizi_id()
   if self.uid == dizhu_uid then
        local farmer1_uid,famer2_uid = self.ddz_instance:get_farmer_uids()

        local farmer1_card_type_list = assert(make_card_type(farmer1_uid,self.ddz_instance,laizi)) 
        if player_can_must_win(farmer1_uid,self.ddz_instance,farmer1_card_type_list) then
            return true
        end

        local farmer2_card_type_list = assert(make_card_type(famer2_uid,self.ddz_instance,laizi)) 
        if player_can_must_win(famer2_uid,self.ddz_instance,farmer2_card_type_list) then
            return true
        end 
        return false
   else
        local dizhu_card_type_list = assert(make_card_type(dizhu_uid,self.ddz_instance,laizi)) 
        return player_can_must_win(dizhu_uid,self.ddz_instance,dizhu_card_type_list)
   end
end

--自己达到必赢条件
local function self_can_must_win(self)
    return player_can_must_win(self.uid,self.ddz_instance,self_card_type_list)
end

local function get_card_weigh_value(total_card_type_list)
    local weigh_value = 0
    for card_type,card_type_list in pairs(total_card_type_list) do
        for _,card_numbers in pairs(card_type_list) do
           if card_type == CARD_SUIT_TYPE_DANSHUN or 
           card_type == CARD_SUIT_TYPE_SHUANGSHUN or 
           card_type == CARD_SUIT_TYPE_FEIJI or 
           card_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
                local beyond_len = #card_numbers.cards - WEIGH_VALUE_CONF[card_type].base_len
                local add = beyond_len * WEIGH_VALUE_CONF[card_type].add
                weigh_value = weigh_value + WEIGH_VALUE_CONF[card_type].base + add
           else
                weigh_value = weigh_value + WEIGH_VALUE_CONF[card_type].base
           end
        end
    end

    return weigh_value
end
-----------------------------------------common-----------------------------------------------------

-----------------------------------------check_rob_dizhu_begin--------------------------------------
local function get_wangzha_score(card_num_set)
    if card_num_set[BLACK_JOKER_NUMBER] and card_num_set[RED_JOKER_NUMBER] then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_WANGZHA]
    end
    return 0
end

local function get_zhadan_score(count_num_map,laizi)
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

local function get_laizi_score(real_card_number_set,laizi)
    local laizi_list = real_card_number_set[laizi] or {}
    local laizi_count = #laizi_list
    if laizi_count ==  1 then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_ONE_LAIZI]
    elseif laizi_count == 2 then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_TWO_LAIZI]
    elseif laizi_count == 3 then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_THREE_LAIZI]
    elseif laizi_count == 4 then
        return MARK_TYPE_SCORE_MAP[MARK_TYPE_FOUR_LAIZI]
    end
    return 0
end

local function wipe_repeat_score(count_num_map,real_card_number_set,score,laizi)
    local total_score = score
    local zhadan_list = count_num_map[4] or {}
    for _,number in pairs(zhadan_list) do
        --癞子加分跟炸弹加分重复
        if number == laizi then
            total_score = total_score - MARK_TYPE_SCORE_MAP[MARK_TYPE_ZHANDAN]
        end
    end
    --癞子加分跟2加分重复
    local list_two = real_card_number_set[2] or {}
    if laizi == 2 and #list_two ~= 4 then
        if #list_two == 1 then
            total_score = total_score - MARK_TYPE_SCORE_MAP[MARK_TYPE_ONE_LAIZI]
        elseif #list_two >= 2 then
            total_score = total_score - #list_two * MARK_TYPE_SCORE_MAP[MARK_TYPE_DANPAI_TWO]
        end
    end

    return total_score
end

local function get_cards_total_score(card_num_set,real_card_num_set,count_num_map,laizi)
    local total_score = 0
    total_score = total_score + get_wangzha_score(card_num_set)
    total_score = total_score + get_zhadan_score(count_num_map)
    total_score = total_score + get_danpai_joker_score(card_num_set)
    total_score = total_score + get_danpai_two_score(real_card_num_set)
    total_score = total_score + get_laizi_score(real_card_num_set,laizi)
    total_score = wipe_repeat_score(count_num_map,real_card_num_set,total_score,laizi)

    return total_score
end

local function get_probabilaty_by_score(total_score)
    local cur_probability = 0
    for _,tb in pairs(ROB_DIZHU_PROBABILITY) do
        if total_score >= tb.score then
            cur_probability = tb.probability
        end
    end
   
    return cur_probability
end

local function is_need_rob_dizhu(uid,ddz_instance)
    local cards_id_list = ddz_instance:get_player_card_ids(uid)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)
    local laizi = ddz_instance:get_laizi_id()
    local total_score = get_cards_total_score(card_num_set,real_card_num_set,count_num_map,laizi)
    local probability = get_probabilaty_by_score(total_score)

    if math.random(1, 100) <= probability then
        return true
    end
    return false
end

-----------------------------------------check_rob_dizhu_end--------------------------------------

local function next_is_dizhu(self)
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local next_position_uid = self.ddz_instance:get_next_position_uid(self.uid)
    if next_position_uid == dizhu_uid then
        return true
    end
    return false
end

-----------------------------------------make_card_type_begin-------------------------------------

local function make_zhadan_and_wangzha(real_card_num_set,card_type_list)
    if real_card_num_set[BLACK_JOKER_NUMBER] and real_card_num_set[RED_JOKER_NUMBER] then
        local cards = {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
        table_insert(card_type_list[CARD_SUIT_TYPE_WANGZHA],{cards = cards,key = RED_JOKER_NUMBER})

        delete_number_on_number_set(real_card_num_set,BLACK_JOKER_NUMBER,1)
        delete_number_on_number_set(real_card_num_set,RED_JOKER_NUMBER,1)
    end

    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list ==  4 then
            local cards = {[number] = 4}
            table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],{cards = cards,key = number})

            delete_number_on_number_set(real_card_num_set,number,#card_id_list)
        end
    end
end

local function get_number_list_by_count(real_card_num_set,count)
    local number_list = {}
    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == count then
            table_insert(number_list,number)
        end
    end
    return number_list
end

local function make_ruan_zha(real_card_num_set,count_number_map,card_type_list,laizi)
    if self_laizi_count == 0 then
        return
    end
    
    local left = 4 - self_laizi_count
    for i=3,left,-1 do
        if self_laizi_count < (4-i) then
            break
        end
        local ruanzha_list = get_number_list_by_count(real_card_num_set,i)
        for _,number in pairs(ruanzha_list) do
            if self_laizi_count < (4-i) then
                break
            end

            if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER then
                local cards = {[number] = i,[laizi] = 4-i}
                table_insert(card_type_list[CARD_SUIT_TYPE_RUANZHA],{cards = cards,key = number})

                delete_number_on_number_set(real_card_num_set,number,i)
                self_laizi_count = self_laizi_count - (4-i)
            end
        end
    end
end

local function make_dan_pai(real_card_num_set,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 1 then
            local cards = {[number] = 1}
            table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],{cards = cards,key = number})
            delete_number_on_number_set(real_card_num_set,number,#card_id_list)
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DANPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
end

local function make_dui_pai(real_card_num_set,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == 2 then
                local cards = {[number] = 2}
                table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],{cards = cards,key = number})
                delete_number_on_number_set(real_card_num_set,number,#card_id_list)
        end
    end
    local tmp_list = card_type_list[CARD_SUIT_TYPE_DUIPAI]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
end

local function make_san_zhang_pai(real_card_num_set,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == 3 then
            local cards = {[number] = 3}
            table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],{cards = cards,key = number})
            delete_number_on_number_set(real_card_num_set,number,#card_id_list)
        end
    end
    local tmp_list = card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
end

local function make_feiji(real_card_number_set,card_type_list)
    local power_list = {}
    local tmp_list = get_number_list_by_count(real_card_number_set,3)
    for _,number in pairs(tmp_list) do
        if real_card_number_set[number] then
            table_insert(power_list,POWER_MAP[number])
        end
    end
    if #power_list < 2 then
        return
    end
    table_sort(power_list)

    local function delete_and_save_feiji(continuous)
        local key
        local cards = {}
        for _,number in pairs(continuous) do
            cards[number] = 3
            key = number
            delete_number_on_number_set(real_card_number_set,number,3)
        end
        table_insert(card_type_list[CARD_SUIT_TYPE_FEIJI],{cards = cards,key = key})
    end

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
            delete_and_save_feiji(continuous)
        end
        if #continuous > 0 then
            continuous = {}
        end
        last_power = power
        table_insert(continuous,CONTINUOUS_CARD_MAP[power])

        ::continue::
    end

    if #continuous >= 2 then
        delete_and_save_feiji(continuous)
    end
end

local function get_max_num_from_shun_zi(shun_zi)
    local max_num 
    for number,_ in pairs(shun_zi) do
        max_num = number
    end
    return max_num
end

local function get_min_num_from_shun_zi(shun_zi)
    local min_number
    for number,_ in pairs(shun_zi) do
        min_number = number
        break
    end
    return min_number
end

local function make_dan_shun(real_card_number_set,card_type_list)
    local tmp_dan_shun_list = {}
    local key
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
            dan_shun[number] = 1
            key = number
            dan_shun_count = dan_shun_count + 1 
        elseif dan_shun_count < 5 then
            dan_shun = {}
            dan_shun_count = 0
        end
        power = power + 1

        if dan_shun_count >= 5 then
            table_insert(tmp_dan_shun_list,{cards = dan_shun,key = key})

            for number,_ in pairs(dan_shun) do
                delete_number_on_number_set(real_card_number_set,number,1)
            end
            dan_shun = {}
            dan_shun_count = 0
            power = 1
        end
    end
    --拓展五连
    local order_numbers = {}
    for number,_ in pairs(real_card_number_set) do
        table_insert(order_numbers,number)
    end
    table_sort(order_numbers,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)

    for _,number in pairs(order_numbers) do
        local power = POWER_MAP[number]
        for _,dan_shun in pairs(tmp_dan_shun_list) do
            local last_power = POWER_MAP[dan_shun.key]
            if last_power + 1 == power then
                dan_shun.cards[number] = 1
                dan_shun.key = number
                delete_number_on_number_set(real_card_number_set,number,1)

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
            local pre_max_power = POWER_MAP[pre_list.key]
            local len = get_shun_zi_len(next_list.cards,CARD_SUIT_TYPE_DANSHUN)
            local next_min_power = POWER_MAP[next_list.key] - len + 1

            if pre_max_power + 1 == next_min_power then
                for number,count in pairs(next_list.cards) do
                    tmp_dan_shun_list[i].cards[number] = count
                end
                tmp_dan_shun_list[i].key = next_list.key
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

local function is_equal_dan_shun(dan_shun1,dan_shun2)
    local len1 = get_shun_zi_len(dan_shun1.cards,CARD_SUIT_TYPE_DANSHUN)
    local len2 = get_shun_zi_len(dan_shun2.cards,CARD_SUIT_TYPE_DANSHUN)
    if len1 ~= len2 then
        return false
    end

    return dan_shun1.key == dan_shun2.key
end

local function make_shuang_shun(real_card_number_set,card_type_list)
    --在单顺中组建双顺
    local i = 1
    local dan_shun_list = card_type_list[CARD_SUIT_TYPE_DANSHUN]
    while dan_shun_list[i] and dan_shun_list[i+1] do
        if is_equal_dan_shun(dan_shun_list[i],dan_shun_list[i+1]) then
            local key = dan_shun_list[i].key
            local cards = {}
            for number,_ in pairs(dan_shun_list[i].cards) do
                cards[number] = 2
            end
            table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],{cards = cards,key = key})

            for j=1,2 do
                table_remove(dan_shun_list,i)
            end
        else
            i = i + 1
        end
    end

    --在剩余牌中组建双顺
    local power = 1
    local key = 0
    local cards = {}
    local tmp_count = 0
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end
        local card_id_list = real_card_number_set[number]
        if card_id_list and #card_id_list >= 2 then
            cards[number] = 2
            key = number
            tmp_count = tmp_count + 1
        elseif tmp_count >= 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],{cards = cards,key = key})

            for number,_ in pairs(cards) do
                delete_number_on_number_set(real_card_number_set,number,2)
            end
            cards = {}
            tmp_count = 0
        elseif tmp_count > 0 then
            cards = {}
            tmp_count = 0
        end
        power = power + 1
    end
end

local function laizi_expand_sanzhang_pai(card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    local delete_map = {}
    for _,dui_pai in pairs(card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
        if self_laizi_count <= 0 then
            break
        end

        local cards = dui_pai.cards
        cards[laizi] = 1
        table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],{cards = cards,key = dui_pai.key})
        self_laizi_count = self_laizi_count - 1
        delete_map[dui_pai.key] = true
    end 

    local tmp_list = {}
    for _,dui_pai in pairs(card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
        if not delete_map[dui_pai.key] then
            table_insert(tmp_list,dui_pai)
        end
    end
    card_type_list[CARD_SUIT_TYPE_DUIPAI] = tmp_list

    table_sort(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
end

local function get_dan_pai_map(card_type_list)
    local dan_pai_map = {}
    for _,number in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        dan_pai_map[number.key] = true
    end

    return dan_pai_map
end

local function make_dan_shun_lian_pai(card_type_list)
    local lian_pai_list = {}
    local lian_pai = {}
    local power = 1

    local dan_pai_map = get_dan_pai_map(card_type_list)
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end

        if dan_pai_map[number] then
            table_insert(lian_pai,number)
        elseif #lian_pai > 0 then
            table_insert(lian_pai_list,lian_pai)
            lian_pai = {}
        end
        power = power + 1
    end

    return lian_pai_list
end

local function laizi_expand_dan_shun(card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    local lian_pai_list = make_dan_shun_lian_pai(card_type_list)
    table_sort(lian_pai_list,function(a,b) return (#a > #b) end)

    local delete_map = {}
    local dan_shun_list = card_type_list[CARD_SUIT_TYPE_DANSHUN]
    for _,dan_shun in pairs(dan_shun_list) do
        for index,lian_pai in pairs(lian_pai_list) do
            if self_laizi_count <= 0 then
                break
            end

            local len = get_shun_zi_len(dan_shun.cards,CARD_SUIT_TYPE_DANSHUN)
            local min_number = dan_shun.key - len + 1
            if POWER_MAP[min_number] == POWER_MAP[lian_pai[#lian_pai]] + 2 then
                for _,number in pairs(lian_pai) do
                   dan_shun.cards[number] = 1
                   delete_map[number] = true
                end
                dan_shun.cards[laizi] = 1
                self_laizi_count = self_laizi_count - 1
                break
            end

            if POWER_MAP[lian_pai[1]] == POWER_MAP[dan_shun.key] + 2 then
                for _,number in pairs(lian_pai) do
                   dan_shun.cards[number] = 1
                   dan_shun.key = number
                   delete_map[number] = true
                end
                dan_shun.cards[laizi] = 1
                self_laizi_count = self_laizi_count - 1
                break
            end
        end
    end

    local tmp_list = {}
    for _,number in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        if not delete_map[number] then
            table_insert(tmp_list,number)
        end
    end
    card_type_list[CARD_SUIT_TYPE_DANPAI] = tmp_list
end

local function get_dui_pai_map(card_type_list)
    local dui_pai_map = {}
    for _,dui_pai in pairs(card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
        dui_pai_map[dui_pai.key] = true
    end

    return dui_pai_map
end

local function make_shuang_shun_lian_pai(card_type_list)
    local dui_pai_map = get_dui_pai_map(card_type_list)

    local lian_pai_list = {}
    local lian_pai = {}
    local lian_pai_count = 0
    local power = 1

    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end

        if dui_pai_map[number] then
            for i=1,2 do
                table_insert(lian_pai,number)
            end
            lian_pai_count = lian_pai_count + 1 
        elseif lian_pai_count >= 1 then
            table_insert(lian_pai_list,lian_pai)
            lian_pai = {}
            lian_pai_count = 0
        end
        power = power + 1
    end

    return lian_pai_list
end

local function laizi_expand_shuang_shun(card_type_list,laizi)
    if self_laizi_count <= 0 then
        return
    end

    local lian_pai_list = make_shuang_shun_lian_pai(card_type_list)
    table_sort(lian_pai_list,function(a,b) return (#a > #b) end)

    local dan_pai_map = get_dan_pai_map(card_type_list)
    local delete_dui_pai_map = {}
    local delete_dan_pai_map = {}
    local shuang_shun_list = card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]

    for _,shuang_shun in pairs(shuang_shun_list) do
        for index,lian_pai in pairs(lian_pai_list) do
            if self_laizi_count <= 0 then
                break
            end

            --左边拓展
            local len = get_shun_zi_len(shuang_shun,cards,CARD_SUIT_TYPE_SHUANGSHUN)
            local min_number = shuang_shun.key - len + 1
            if POWER_MAP[min_number] == POWER_MAP[lian_pai[#lian_pai]] + 2 then
               local mid_power  = POWER_MAP[lian_pai[#lian_pai]] + 1
               local mid_number = CONTINUOUS_CARD_MAP[min_power]
               if dan_pai_map[mid_number] then
                    shuang_shun.cards[mid_number] = 1
                    shuang_shun.cards[laizi]      = 1
                    for _,number in pairs(lian_pai) do
                        shuang_shun.cards[number] = 2
                        delete_dui_pai_map[number] = true
                    end
                    delete_dan_pai_map[mid_number] = true
                    self_laizi_count = self_laizi_count - 1
               end
               break
            end

            --右边拓展
            if POWER_MAP[lian_pai[1]] == POWER_MAP[shuang_shun.key] + 2 then
               local mid_power  = POWER_MAP[shuang_shun.key] + 1
               local mid_number = CONTINUOUS_CARD_MAP[mid_power]
               if dan_pai_map[mid_number] then
                    shuang_shun.cards[mid_number] = 1
                    shuang_shun.cards[laizi]      = 1
                    for _,number in pairs(lian_pai) do
                        shuang_shun.cards[number] = 2
                        shuang_shun.key = number
                        delete_dui_pai_map[number] = true
                    end
                    delete_dan_pai_map[mid_number] = true
                    self_laizi_count = self_laizi_count - 1
               end
               break
            end
        end
    end

    local tmp_dan_pai_list = {}
    for _,number in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        if not delete_dan_pai_map[number] then
            table_insert(tmp_dan_pai_list,number)
        end
    end
    card_type_list[CARD_SUIT_TYPE_DANPAI] = tmp_dan_pai_list

    local tmp_dui_pai_list = {}
    for _,dui_pai in pairs(card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
        if not delete_dui_pai_map[dui_pai.key] then
            table_insert(tmp_dui_pai_list,dui_pai)
        end
    end
    card_type_list[CARD_SUIT_TYPE_DUIPAI] = tmp_dui_pai_list
end

local function laizi_make_danshun(card_number_set,card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    local use_laizi_count = 0
    local power = 1
    local cards = {}
    local key
    local dan_shun_count = 0
    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end
        if card_number_set[number] and card_number_set[number] > 0 then
            cards[number] = 1
            key = number
            dan_shun_count = dan_shun_count + 1
        elseif self_laizi_count - use_laizi_count > 0 then
            cards[laizi] = (cards[laizi] or 0) + 1
            key = number
            dan_shun_count = dan_shun_count + 1
            use_laizi_count = use_laizi_count + 1
        elseif dan_shun_count >= 5 then
            table_insert(card_type_list[CARD_SUIT_TYPE_DANSHUN],{cards = cards,key = key})
            self_laizi_count = self_laizi_count - use_laizi_count
 
            for number,count in pairs(cards) do
                if number ~= laizi then
                    assert(card_number_set[number] > 0)
                    card_number_set[number] = card_number_set[number] - count
                    if card_number_set[number] <= 0 then
                        card_number_set[number] = nil
                    end 
                end    
            end

            dan_shun_count = 0
            break
        elseif dan_shun_count ~= 0 then
            cards = {}
            key = nil
            dan_shun_count = 0
            use_laizi_count = 0
        end
        power = power + 1
    end

    if dan_shun_count >= 5 then
        table_insert(card_type_list[CARD_SUIT_TYPE_DANSHUN],{cards = cards,key = key})
        self_laizi_count = self_laizi_count - use_laizi_count

        for number,count in pairs(cards) do
            if number ~= laizi then 
                assert(card_number_set[number] > 0)
                card_number_set[number] = card_number_set[number] - count
                if card_number_set[number] <= 0 then
                    card_number_set[number] = nil
                end
            end    
        end
    end

end

local function laizi_make_shuangshun(card_number_set,card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    local use_laizi_count = 0
    local power = 1
    local cards = {}
    local key
    local shuang_shun_count = 0

    while true do
        local number = CONTINUOUS_CARD_MAP[power]
        if not number then
            break 
        end
        local number_count = card_number_set[number] or 0
        if number_count >= 2 then
            cards[number] = 2
            key = number
            shuang_shun_count = shuang_shun_count + 1
        elseif self_laizi_count - use_laizi_count >= 2 - number_count then 
            cards[laizi] = (cards[laizi] or 0) + 2 - number_count
            if number ~= 0 then
                cards[number] = number_count
            end
            key = number
            shuang_shun_count = shuang_shun_count + 1
            use_laizi_count = use_laizi_count + 2 - number_count
        elseif shuang_shun_count >= 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],{cards = cards,key = key})
            self_laizi_count = self_laizi_count - use_laizi_count
 
            for number,count in pairs(cards) do
                if number ~= laizi then
                    print("++",card_number_set[number],count)
                    assert(card_number_set[number] >= count)
                    card_number_set[number] = card_number_set[number] - count
                    if card_number_set[number] <= 0 then
                        card_number_set[number] = nil
                    end
                end    
            end

            shuang_shun_count = 0
            break
        elseif shuang_shun_count ~= 0 then
            cards = {}
            key = nil
            shuang_shun_count = 0
            use_laizi_count = 0
        end
        power = power + 1
    end    

    if shuang_shun_count >= 3 then
        table_insert(card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],{cards = cards,key = key})
        self_laizi_count = self_laizi_count - use_laizi_count

        for number,count in pairs(cards) do
            if number ~= laizi then 
                assert(card_number_set[number] >= count)
                card_number_set[number] = card_number_set[number] - count
                if card_number_set[number] <= 0 then
                    card_number_set[number] = nil
                end
            end    
        end
    end
end

local function laizi_make_sanzhang(card_number_set,card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    for number,card_count in pairs(card_number_set) do
        if card_count == 2 and self_laizi_count > 0 then
            local cards = {}
            cards[laizi] = 1
            cards[number] = 2
            table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],{cards = cards,key = number})
            self_laizi_count = self_laizi_count - 1
            for number,count in pairs(cards) do
                if number ~= laizi then
                    assert(card_number_set[number] >= count)
                    card_number_set[number] = card_number_set[number] - count
                    if card_number_set[number] <= 0 then
                        card_number_set[number] = nil
                    end
                end    
            end
        end
    end

    table_sort(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)

    -- 检查是否有飞机
    if #card_type_list[CARD_SUIT_TYPE_SANZANGPAI] < 2 then
        return
    end
    local sanzhang_list = card_type_list[CARD_SUIT_TYPE_SANZANGPAI]

    local n = 1
    local length = 0
    local cards = {}
    local list_key = {}
    local key
    while sanzhang_list[n] do
        if not key then
            length = 1
            key = sanzhang_list[n].key
            for k,v in pairs(sanzhang_list[n].cards) do
                cards[k] = v
            end
            list_key[key] = true
        elseif POWER_MAP[sanzhang_list[n].key] == POWER_MAP[key] + 1 then
            length = length + 1
            key = sanzhang_list[n].key
            for k,v in pairs(sanzhang_list[n].cards) do
                cards[k] = v
            end
            list_key[key] = true
        elseif length >= 2 then
            table_insert(card_type_list[CARD_SUIT_TYPE_FEIJI],{cards = cards,key = key})
            length = 0
            cards = {}
            break
        elseif length ~= 0 then
            list_key = {}
            length = 0
            key = nil    
        end

        n = n+1
    end

    if length >= 2 then
        table_insert(card_type_list[CARD_SUIT_TYPE_FEIJI],{cards = cards,key = key})
    end  

    local new_san_zhang_list = {}
    for k,v in pairs(card_type_list[CARD_SUIT_TYPE_SANZANGPAI]) do
        if not list_key[v.key] then
            table_insert(new_san_zhang_list,v)
        end
    end
    card_type_list[CARD_SUIT_TYPE_SANZANGPAI] = new_san_zhang_list
end

local function get_card_by_duipai_danpai(card_type_list)
    local card_number_set = {}
    for k,v in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        card_number_set[v.key] = 1
    end
    for k,v in pairs(card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
        card_number_set[v.key] = 2
    end

    return card_number_set
end

local function make_duipai_danpai(card_number_set,card_type_list,laizi)
    local danpai_list = {}
    local duipai_list = {}
    for number,count in pairs(card_number_set) do
        if count == 1 then
            local cards = {[number] = 1}
            table_insert(danpai_list,{cards = cards,key = number})
        elseif count == 2 then
            local cards = {[number] = 2}
            table_insert(duipai_list,{cards = cards,key = number})    
        end
    end
    card_type_list[CARD_SUIT_TYPE_DANPAI] = danpai_list
    card_type_list[CARD_SUIT_TYPE_DUIPAI] = duipai_list
end

local function laizi_make_card_type_zapai(card_type_list,laizi)
    local card_number_set = get_card_by_duipai_danpai(card_type_list)
    laizi_make_danshun(card_number_set,card_type_list,laizi)
    laizi_make_shuangshun(card_number_set,card_type_list,laizi)
    laizi_make_sanzhang(card_number_set,card_type_list,laizi)
    make_duipai_danpai(card_number_set,card_type_list,laizi)
end

local function laizi_make_dui_pai_from_dan_pai(card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    --print("laizi_make_dui_pai_from_dan_pai",tostring_r(card_type_list))
    local delete_dan_pai_map = {}

    table_sort(card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
    for _,danpai in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        if danpai.key ~= BLACK_JOKER_NUMBER and danpai.key ~= RED_JOKER_NUMBER 
            and self_laizi_count > 0 then

            local cards = {[danpai.key] = 1,[laizi] = 1}
            table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],{cards = cards,key = danpai.key})
            delete_dan_pai_map[danpai.key] = true
            self_laizi_count = self_laizi_count - 1
        end
    end
    --print("delete_dan_pai_map",tostring_r(delete_dan_pai_map))
    --print("card_type_list[CARD_SUIT_TYPE_DANPAI]",tostring_r(card_type_list[CARD_SUIT_TYPE_DANPAI]))

    local tmp_dan_pai_list = {}
    for _,danpai in pairs(card_type_list[CARD_SUIT_TYPE_DANPAI]) do
        if not delete_dan_pai_map[danpai.key] then
            local cards = {[danpai.key] = 1}
            table_insert(tmp_dan_pai_list,{cards = cards,key = danpai.key})
        end
    end
    
    card_type_list[CARD_SUIT_TYPE_DANPAI] = tmp_dan_pai_list
    --print("card_type_list[CARD_SUIT_TYPE_DANPAI]2222222222",tostring_r(card_type_list[CARD_SUIT_TYPE_DANPAI]))
    if #card_type_list[CARD_SUIT_TYPE_DANPAI] > 1 then
        table_sort(card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
    end
    if #card_type_list[CARD_SUIT_TYPE_DUIPAI] > 1 then
        --print_r(card_type_list[CARD_SUIT_TYPE_DUIPAI])
        table_sort(card_type_list[CARD_SUIT_TYPE_DUIPAI],function(a,b) return (POWER_MAP[a.key] < POWER_MAP[b.key]) end)
    end
end

local function laizi_make_card_type_self(card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    local cards = {}
    if self_laizi_count == 1 then
        cards[laizi] = 1
        table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],{cards = cards,key = laizi})
    elseif self_laizi_count == 2 then
        cards[laizi] = 2
        table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],{cards = cards,key = laizi})
    elseif self_laizi_count == 3 then
        cards[laizi] = 3
        table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],{cards = cards,key = laizi})
    elseif self_laizi_count == 4 then
        cards[laizi] = 4
        table_insert(card_type_list[CARD_SUIT_TYPE_RUANZHA],{cards = cards,key = laizi})
    end
end

--第一种
--癞子匹配软炸,然后三条,顺子,连对
local function make_rz_san_zhang_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,rz_san_zhang_priority_list)
    make_ruan_zha(real_card_num_set,count_num_map,rz_san_zhang_priority_list,laizi)
    make_feiji(real_card_num_set,rz_san_zhang_priority_list)
    make_san_zhang_pai(real_card_num_set,rz_san_zhang_priority_list)
    make_dan_shun(real_card_num_set,rz_san_zhang_priority_list)
    make_shuang_shun(real_card_num_set,rz_san_zhang_priority_list)
    make_dui_pai(real_card_num_set,rz_san_zhang_priority_list)
    make_dan_pai(real_card_num_set,rz_san_zhang_priority_list)
    laizi_make_card_type_self(rz_san_zhang_priority_list,laizi)
end

local function laizi_match_san_zhang_priority_list(card_type_list,laizi)
    if self_laizi_count < 1 then
        return
    end

    laizi_expand_sanzhang_pai(card_type_list,laizi)
    laizi_expand_dan_shun(card_type_list,laizi)
    laizi_expand_shuang_shun(card_type_list,laizi)
    laizi_make_dui_pai_from_dan_pai(card_type_list,laizi)
    laizi_make_card_type_self(card_type_list,laizi)
end
--第二种
--三条,顺子,连对,癞子匹配
local function make_san_zhang_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,san_zhang_priority_list)
    make_feiji(real_card_num_set,san_zhang_priority_list)
    make_san_zhang_pai(real_card_num_set,san_zhang_priority_list)
    make_dan_shun(real_card_num_set,san_zhang_priority_list)
    make_shuang_shun(real_card_num_set,san_zhang_priority_list)
    make_dui_pai(real_card_num_set,san_zhang_priority_list)
    make_dan_pai(real_card_num_set,san_zhang_priority_list)
    laizi_make_card_type_zapai(san_zhang_priority_list,laizi)
    laizi_match_san_zhang_priority_list(san_zhang_priority_list,laizi)
end
--第三种
--癞子匹配软炸,然后三张,连对,顺子
local function make_rz_shuang_shun_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,rz_shuang_shun_priority_list)
    make_ruan_zha(real_card_num_set,count_num_map,rz_shuang_shun_priority_list,laizi)
    make_feiji(real_card_num_set,rz_shuang_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,rz_shuang_shun_priority_list)
    make_shuang_shun(real_card_num_set,rz_shuang_shun_priority_list)
    make_dan_shun(real_card_num_set,rz_shuang_shun_priority_list)
    make_dui_pai(real_card_num_set,rz_shuang_shun_priority_list)
    make_dan_pai(real_card_num_set,rz_shuang_shun_priority_list)
    laizi_make_card_type_self(rz_shuang_shun_priority_list,laizi)
end

local function laizi_match_shuang_shun_priority_list(card_type_list,laizi)
    laizi_expand_sanzhang_pai(card_type_list,laizi)
    laizi_expand_shuang_shun(card_type_list,laizi)
    laizi_expand_dan_shun(card_type_list,laizi)
    laizi_make_dui_pai_from_dan_pai(card_type_list,laizi)
    laizi_make_card_type_self(card_type_list,laizi)
end
--第四种
--三张,连对,顺子
local function make_shuang_shun_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,shuang_shun_priority_list)
    make_feiji(real_card_num_set,shuang_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,shuang_shun_priority_list)
    make_shuang_shun(real_card_num_set,shuang_shun_priority_list)
    make_dan_shun(real_card_num_set,shuang_shun_priority_list)
    make_dui_pai(real_card_num_set,shuang_shun_priority_list)
    make_dan_pai(real_card_num_set,shuang_shun_priority_list)
    --print("ggggggggggggggggggggggg++++++++++++++++++",tostring_r(shuang_shun_priority_list))
    laizi_make_card_type_zapai(shuang_shun_priority_list,laizi)
    laizi_match_shuang_shun_priority_list(shuang_shun_priority_list,laizi)
end
--第五种
--癞子匹配软炸,顺子,三条,连对
local function make_rz_dan_shun_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,rz_dan_shun_priority_list)
    make_feiji(real_card_num_set,rz_dan_shun_priority_list)
    make_ruan_zha(real_card_num_set,count_num_map,rz_dan_shun_priority_list,laizi)
    make_dan_shun(real_card_num_set,rz_dan_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,rz_dan_shun_priority_list)
    make_shuang_shun(real_card_num_set,rz_dan_shun_priority_list)
    make_dui_pai(real_card_num_set,rz_dan_shun_priority_list)
    make_dan_pai(real_card_num_set,rz_dan_shun_priority_list)
    --print("ggggggggggggggggggggggg+++++++++++++++++++",tostring_r(rz_dan_shun_priority_list))
    laizi_make_card_type_self(rz_dan_shun_priority_list,laizi)
end

local function laizi_match_dan_shun_priority_list(card_type_list,laizi)
    laizi_expand_dan_shun(card_type_list,laizi)
    laizi_expand_sanzhang_pai(card_type_list,laizi)
    laizi_expand_shuang_shun(card_type_list,laizi)
    laizi_make_dui_pai_from_dan_pai(card_type_list,laizi)
    laizi_make_card_type_self(card_type_list,laizi)
end
--第六种
--癞子匹配顺子,三条,连对
local function make_dan_shun_priority_card_type(cards_id_list,laizi)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    wipe_laizi(real_card_num_set,laizi)
    make_zhadan_and_wangzha(real_card_num_set,dan_shun_priority_list)
    make_feiji(real_card_num_set,dan_shun_priority_list)
    make_dan_shun(real_card_num_set,dan_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,dan_shun_priority_list)
    make_shuang_shun(real_card_num_set,dan_shun_priority_list)
    make_dui_pai(real_card_num_set,dan_shun_priority_list)
    make_dan_pai(real_card_num_set,dan_shun_priority_list)
    laizi_make_card_type_zapai(dan_shun_priority_list,laizi)
    --print("gggggggggggggggggggggg+++++++++++++++++++++",tostring_r(dan_shun_priority_list))
    laizi_match_dan_shun_priority_list(dan_shun_priority_list,laizi)
end


local function select_card_type_list(uid,ddz_instance)
    --确定手数的时候,三张需要带上一手
    local rz_san_zhang_priority_count,rz_dan_shun_priority_count,rz_shuang_shun_priority_count
    local san_zhang_priority_count,dan_shun_priority_count,shuang_shun_priority_count

    rz_san_zhang_priority_count = get_card_handle_count(rz_san_zhang_priority_list)
    san_zhang_priority_count    = get_card_handle_count(san_zhang_priority_list)
    rz_dan_shun_priority_count  = get_card_handle_count(rz_dan_shun_priority_list)
    dan_shun_priority_count     = get_card_handle_count(dan_shun_priority_list)
    rz_lian_dui_priority_count  = get_card_handle_count(rz_shuang_shun_priority_list)
    lian_dui_priority_count     = get_card_handle_count(shuang_shun_priority_list)

    --绝对手数
    local absolute_rz_san_zhang_priority_count = get_absolute_handle_count(uid,ddz_instance,rz_san_zhang_priority_list)
    local absolute_san_zhang_priority_count = get_absolute_handle_count(uid,ddz_instance,san_zhang_priority_list)
    local absolute_rz_dan_shun_priority_count = get_absolute_handle_count(uid,ddz_instance,rz_dan_shun_priority_list)
    local absolute_dan_shun_priority_count = get_absolute_handle_count(uid,ddz_instance,dan_shun_priority_list)
    local absolute_rz_lian_dui_priority_count = get_absolute_handle_count(uid,ddz_instance,rz_shuang_shun_priority_list)
    local absolute_lian_dui_priority_count = get_absolute_handle_count(uid,ddz_instance,shuang_shun_priority_list)

    --权值
    local weigh_rz_san_zhang_priority = get_card_weigh_value(rz_san_zhang_priority_list)
    local weigh_san_zhang_priority = get_card_weigh_value(san_zhang_priority_list)
    local weigh_rz_dan_shun_priority = get_card_weigh_value(rz_dan_shun_priority_list)
    local weigh_dan_shun_priority = get_card_weigh_value(dan_shun_priority_list)
    local weigh_rz_lian_dui_priority = get_card_weigh_value(rz_shuang_shun_priority_list)
    local weigh_lian_dui_priority = get_card_weigh_value(shuang_shun_priority_list)

    print(weigh_rz_san_zhang_priority,weigh_san_zhang_priority,weigh_rz_dan_shun_priority,weigh_dan_shun_priority,weigh_rz_lian_dui_priority,weigh_lian_dui_priority)
    --手数少的为最优牌型,相等的情况下,默认第一种
    local min = rz_san_zhang_priority_count
    local self_card_type_list = rz_san_zhang_priority_list
    local absolute_handle_count = absolute_rz_san_zhang_priority_count
    local weigh_value = weigh_rz_san_zhang_priority

    if min > san_zhang_priority_count or 
    (min == san_zhang_priority_count and absolute_handle_count < absolute_san_zhang_priority_count) or 
    (min == san_zhang_priority_count and absolute_handle_count == absolute_san_zhang_priority_count and weigh_value < weigh_san_zhang_priority) then
        min = san_zhang_priority_count
        self_card_type_list = san_zhang_priority_list
        absolute_handle_count = absolute_san_zhang_priority_count
        weigh_value = weigh_san_zhang_priority
        print("san_zhang_priority_count")
    end
    if min > rz_dan_shun_priority_count or 
    (min == rz_dan_shun_priority_count and absolute_handle_count < absolute_rz_dan_shun_priority_count) or 
    (min == rz_dan_shun_priority_count and absolute_handle_count == absolute_rz_dan_shun_priority_count and weigh_value < weigh_rz_dan_shun_priority) then
        min = rz_dan_shun_priority_count
        self_card_type_list = rz_dan_shun_priority_list
        absolute_handle_count = absolute_rz_dan_shun_priority_count
        weigh_value = weigh_rz_dan_shun_priority
        print("rz_dan_shun_priority_count")
    end
    if min > dan_shun_priority_count or 
    (min == dan_shun_priority_count and absolute_handle_count < absolute_dan_shun_priority_count) or 
    (min == dan_shun_priority_count and absolute_handle_count == absolute_dan_shun_priority_count and weigh_value < weigh_dan_shun_priority) then
        min = dan_shun_priority_count
        self_card_type_list = dan_shun_priority_list
        absolute_handle_count = absolute_dan_shun_priority_count
        weigh_value = weigh_dan_shun_priority
        print("dan_shun_priority_count")
    end
    if min > rz_lian_dui_priority_count or 
    (min == rz_lian_dui_priority_count and absolute_handle_count < absolute_rz_lian_dui_priority_count) or
    (min == rz_lian_dui_priority_count and absolute_handle_count == absolute_rz_lian_dui_priority_count and weigh_value < weigh_rz_lian_dui_priority) then
        min = rz_lian_dui_priority_count
        self_card_type_list = rz_shuang_shun_priority_list
        absolute_handle_count = absolute_rz_lian_dui_priority_count
        weigh_value = weigh_rz_lian_dui_priority
        print("rz_lian_dui_priority_count")
    end
    if min > lian_dui_priority_count or 
    (min == lian_dui_priority_count and absolute_handle_count < absolute_lian_dui_priority_count) or 
    (min == lian_dui_priority_count and absolute_handle_count == absolute_lian_dui_priority_count and weigh_value < weigh_lian_dui_priority) then
        min = lian_dui_priority_count
        self_card_type_list = shuang_shun_priority_list
        absolute_handle_count = absolute_lian_dui_priority_count
        weigh_value = weigh_lian_dui_priority
        print("lian_dui_priority_count")
    end
    print("select result is :",weigh_value,min,absolute_handle_count,tostring_r(self_card_type_list))

    local ret = {}
    for type,card_info in pairs(self_card_type_list) do
        ret[type] = card_info
    end
    return ret
end

local function init_card_type_list()
    for k,_ in pairs(card_type_map) do
        rz_san_zhang_priority_list[k]   = {}
        san_zhang_priority_list[k]      = {}
        rz_dan_shun_priority_list[k]    = {}
        dan_shun_priority_list[k]       = {}
        rz_shuang_shun_priority_list[k] = {}
        shuang_shun_priority_list[k]    = {}
    end
end

make_card_type = function(uid,ddz_instance,laizi,cards_id_list)
    init_card_type_list()
    if not laizi then
        laizi = ddz_instance:get_laizi_id()
    end
    if not cards_id_list then
        cards_id_list = ddz_instance:get_player_card_ids(uid)
    end    
    make_rz_san_zhang_priority_card_type(cards_id_list,laizi)
    make_san_zhang_priority_card_type(cards_id_list,laizi)

    make_rz_dan_shun_priority_card_type(cards_id_list,laizi)
    make_dan_shun_priority_card_type(cards_id_list,laizi)

    make_rz_shuang_shun_priority_card_type(cards_id_list,laizi)
    make_shuang_shun_priority_card_type(cards_id_list,laizi)

    return select_card_type_list(uid,ddz_instance)
end

-----------------------------------------make_card_type_end----------------------------------------------


-----------------------------------------select_card_play-----------------------------------
local function get_san_zhang_pai_count()
    local count = #self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,fei_ji_list in pairs(self_card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        count = count + #fei_ji_list.cards
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

local function check_card_type(self,card_type,min_num_map)
    if card_type == CARD_SUIT_TYPE_DANPAI then
        local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        if #dan_pai_list <= 0 then
            return false
        end
        local san_zhang_count = get_san_zhang_pai_count()
        local dan_dui_pai_count = get_dan_shuang_pai_count()
        print("count",san_zhang_count,dan_dui_pai_count)
        if san_zhang_count > 0 and dan_dui_pai_count - 2 <  san_zhang_count then
            return false
        end 
        if not min_num_map then
            return true
        end

        for _,dan_pai in pairs(dan_pai_list) do
            if min_num_map[dan_pai.key] then
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
        print("sanzhang_count",san_zhang_count,dan_dui_pai_count)
        if san_zhang_count > 0 and dan_dui_pai_count - 2 <  san_zhang_count then
            return false
        end
        if not min_num_map then
            return true
        end 
        for _,dui_pai in pairs(dui_pai_list) do
            if min_num_map[dui_pai.key] then
                return true
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_SANZANGPAI or
        card_type == CARD_SUIT_TYPE_SANDAIYI or
        card_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        local sanzhang_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        if #sanzhang_list <= 0 then
            return false
        end

        if next_is_dizhu(self) and get_card_handle_count(self_card_type_list) >= 4 then
            local min_num = assert(sanzhang_list[1].key)
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
            for number,_ in pairs(dan_shun.cards) do
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
        if not min_num_map then
            return true
        end
        for _,shuang_shun in pairs(shuang_shun_list) do
            for number,_ in pairs(shuang_shun.cards) do
                if min_num_map[number] then
                    return true
                end
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_FEIJI or card_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        if #feiji_list  <= 0 then
            return false
        end
        --当手数大于4，判断出Q或以上的飞机，优先出其他牌型(下家是地主时)
        if next_is_dizhu(self) and get_card_handle_count(self_card_type_list) then
            local min_feiji_num = feiji_list[1].key
            local pai_Q = 10
            if POWER_MAP[min_feiji_num] >= pai_Q then
                return false
            end
        end
    elseif card_type == CARD_SUIT_TYPE_SIDAIER or card_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
        return check_si_dai_er(self,card_type)    
    elseif card_type == CARD_SUIT_TYPE_RUANZHA then
        if #self_card_type_list[CARD_SUIT_TYPE_RUANZHA] <= 0 then
            return false
        end
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

local function get_xiao_dan_pai(laizi)
    if #self_card_type_list[CARD_SUIT_TYPE_DANPAI] <= 0 then
        return 
    end

    local xiao_dan_pai = RED_JOKER_NUMBER
    for _,dan_pai in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
      if dan_pai.key ~= laizi and POWER_MAP[xiao_dan_pai] > POWER_MAP[dan_pai.key] then
         xiao_dan_pai = dan_pai.key
      end
    end

    local dan_pai_map = get_dan_pai_map(self_card_type_list)
    local handle_count = get_card_handle_count(self_card_type_list)
    if handle_count >= 2 and POWER_MAP[xiao_dan_pai] >= 14 or not dan_pai_map[xiao_dan_pai] then
       return
    end
    return xiao_dan_pai
end

local function get_xiao_dui_pai(laizi)
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    
    if #dui_pai_list == 0 then
        return 
    end
    local xiao_dui_pai
    for _,dui_pai in pairs(dui_pai_list) do
        if not dui_pai.cards[laizi] then
            xiao_dui_pai = dui_pai
            break
        end
    end

    if not xiao_dan_pai then
        return
    end
    local handle_count = get_card_handle_count(self_card_type_list)
    if handle_count >= 2 and POWER_MAP[xiao_dui_pai.key] >= 13 then
       xiao_dui_pai = nil
    end
    return xiao_dui_pai
end

local function get_max_two_number(num_list)
    assert(#num_list >= 2)
    local max_num = num_list[1].key
    local second_max_num = num_list[2].key
    if POWER_MAP[second_max_num] > POWER_MAP[max_num] then
        max_num = num_list[2].key
        second_max_num = num_list[1].key
    end

    for i=2,#num_list do
        print(POWER_MAP[num_list[i].key],POWER_MAP[second_max_num])
        if POWER_MAP[num_list[i].key] > POWER_MAP[second_max_num] then
            if POWER_MAP[num_list[i].key] > POWER_MAP[max_num] then
                second_max_num = max_num
                max_num = num_list[i].key
            else
               second_max_num = num_list[i].key
            end
        end
    end
    return max_num,second_max_num
end

local function get_second_min_number(num_list)
    assert(#num_list >= 2)
    local min_num = num_list[1]
    local second_min_num = num_list[2]
    if second_min_num.key < min_num.key then
        min_num = num_list[2]
        second_min_num = num_list[1]
    end
    for i=3,#num_list do
        if POWER_MAP[num_list[i].key] < POWER_MAP[second_min_num.key] then
            if POWER_MAP[num_list[i].key] < POWER_MAP[min_num.key] then
                second_min_num = min_num
                min_num = num_list[i]
            else
               second_min_num = num_list[i]
            end
        end
    end
    return second_min_num
end

local function select_dan_pai(self)
    if next_is_dizhu(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        --从权值第二大的单牌从大到小出
        local max_num,second_max_num = get_max_two_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        print("max_num,second_max_num",max_num,second_max_num)
        if rival_is_remain_one(self) then
            return {[max_num] = 1},CARD_SUIT_TYPE_DANPAI,max_num
        else
            return {[second_max_num] = 1},CARD_SUIT_TYPE_DANPAI,second_max_num
        end
    end
    if rival_is_remain_one(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
        --当敌方报单的时候,必须出单牌时,出第二小的单牌
        local second_min_num = get_second_min_number(self_card_type_list[CARD_SUIT_TYPE_DANPAI])
        return second_min_num.cards,CARD_SUIT_TYPE_DANPAI,second_min_num.key
    end

    if self_can_must_win(self) and get_card_handle_count(self_card_type_list) <=2 then
        local tmp_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        table_sort(tmp_list,function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
    end
    local number = assert(self_card_type_list[CARD_SUIT_TYPE_DANPAI][1].key)
    return {[number] = 1},CARD_SUIT_TYPE_DANPAI,number
end

local function select_dui_pai(self)
    if get_card_handle_count(self_card_type_list) <=2 and self_can_must_win(self) then
        local tmp_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
        table_sort(tmp_list,function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
    end

    local number = assert(self_card_type_list[CARD_SUIT_TYPE_DUIPAI][1]) 
    if rival_is_remain_two(self) then
        --如果敌方报双,必须出单牌的时,拆开出单牌
        return {[number.key] = 1},CARD_SUIT_TYPE_DANPAI,number.key
    end
    --下家是地主
    if next_is_dizhu(self) and #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= 2 then 
        if get_card_handle_count(self_card_type_list) > 3 then
            local second_min_num = get_second_min_number(self_card_type_list[CARD_SUIT_TYPE_DUIPAI])
            return second_min_num.cards,CARD_SUIT_TYPE_DUIPAI,second_min_num.key
        end
    end
    return number.cards,CARD_SUIT_TYPE_DUIPAI,number.key
end

local function select_by_type(self,card_suit_type,laizi)
    if card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return select_dan_pai(self)
    elseif card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return select_dui_pai(self)

    elseif card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        local san_zhang = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI][1]
        local xiao_pai = get_xiao_dan_pai(laizi)
        if not xiao_pai then
            return
        end
        local cards = san_zhang.cards
        cards[xiao_pai] = 1
        return cards,card_suit_type,san_zhang.key
    elseif card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        local san_zhang = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI][1]
        local dui_pai = get_xiao_dui_pai(laizi)
        if not dui_pai then 
            return 
        end
        local cards = san_zhang.cards
        cards[dui_pai.key] = 2
        return cards,card_suit_type,san_zhang.key
    elseif card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        local san_zhang = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI][1]
        return san_zhang.cards,card_suit_type,san_zhang.key
    elseif card_suit_type == CARD_SUIT_TYPE_DANSHUN then
       local dan_shun = self_card_type_list[CARD_SUIT_TYPE_DANSHUN][1]
       return dan_shun.cards,card_suit_type,dan_shun.key
    elseif card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
       local shuang_shun = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN][1]
       return shuang_shun.cards,card_suit_type,shuang_shun.key
    elseif card_suit_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
       local feiji = self_card_type_list[CARD_SUIT_TYPE_FEIJI][1]
       local cards = feiji.cards
       local feiiji_count = 0
       for number,count in pairs(cards) do
           feiiji_count = feiiji_count + count
       end

        local xiao_pai_count = feiiji_count / 3
        if #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= xiao_pai_count then
           for i=1,xiao_pai_count do
              local number = self_card_type_list[CARD_SUIT_TYPE_DANPAI][i]
              cards[number] = 1
           end
           return cards,card_suit_type,feiji.key
        elseif #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= xiao_pai_count then
           for i=1,xiao_pai_count do
               local dui_pai = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][i]
               for number,count in pairs(dui_pai.cards) do
                   cards[number] = count
               end
           end
           return cards,card_suit_type,feiji.key
        end
        return
    elseif card_suit_type == CARD_SUIT_TYPE_FEIJI then
       local feiji = self_card_type_list[CARD_SUIT_TYPE_FEIJI][1]
       return feiji.cards,card_suit_type,feiji.key
    elseif card_suit_type == CARD_SUIT_TYPE_RUANZHA then
       local ruan_zha = self_card_type_list[CARD_SUIT_TYPE_RUANZHA][1]
       if ruan_zha.key == laizi then
          ruan_zha.key = CARD_SUIT_TYPE_ZHADAN
       end
       return ruan_zha.cards,card_suit_type,ruan_zha.key
    elseif card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        local zha_dan = self_card_type_list[CARD_SUIT_TYPE_ZHADAN][1]
        return zha_dan.cards,card_suit_type,zha_dan.key
    elseif card_suit_type == CARD_SUIT_TYPE_WANGZHA then
        local  wang_zha = self_card_type_list[CARD_SUIT_TYPE_WANGZHA][1]
        return wang_zha.cards,card_suit_type,wang_zha.key
    else
        errlog("unknwon card type on select_by_type!!!",card_suit_type)
    end
end

local function check_zhadan_wangzha(ruan_zha_key,zha_dan_key)
    --软炸
    local ruan_zha_list = self_card_type_list[CARD_SUIT_TYPE_RUANZHA]
    for _,ruan_zha in pairs(ruan_zha_list) do
        if ruan_zha_key then
            if POWER_MAP[ruan_zha.key] > POWER_MAP[ruan_zha_key] then
                return ruan_zha.cards,CARD_SUIT_TYPE_RUANZHA,ruan_zha.key
            end
        else
            return ruan_zha.cards,CARD_SUIT_TYPE_RUANZHA,ruan_zha.key
        end
    end
    --炸弹
    local zhadan_list = self_card_type_list[CARD_SUIT_TYPE_ZHADAN]
    for _,zha_dan in pairs(zhadan_list) do
        if zha_dan_key then
            if POWER_MAP[zha_dan.key] > POWER_MAP[zha_dan_key] then
                return zha_dan.cards,CARD_SUIT_TYPE_ZHADAN,zha_dan.key
            end
        else
            return zha_dan.cards,CARD_SUIT_TYPE_ZHADAN,zha_dan.key
        end
    end
    --王炸
    local wang_zha = self_card_type_list[CARD_SUIT_TYPE_WANGZHA]
    if next(wang_zha) then
        return wang_zha.cards,CARD_SUIT_TYPE_WANGZHA,wang_zha.key
    end
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

local function check_dan_pai(self,last_card_suit_key,only_check_dan_pai)
    --大小王压2
    print("check_dan_pai++++++++++++++++++++++++++++")
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local laizi = self.ddz_instance:get_laizi_id()
    local _,real_card_number_set = process_card_id_list(cards_id_list) 
    if last_card_suit_key == CARD_TWO_NUMBER then
        if real_card_number_set[BLACK_JOKER_NUMBER] and real_card_number_set[RED_JOKER_NUMBER] and self_can_must_win(self) then
            return {[RED_JOKER_NUMBER] = 1,[BLACK_JOKER_NUMBER] = 1},CARD_SUIT_TYPE_WANGZHA,RED_JOKER_NUMBER
        elseif real_card_number_set[BLACK_JOKER_NUMBER] then --小王压2
            return {[BLACK_JOKER_NUMBER] = 1},CARD_SUIT_TYPE_DANPAI,BLACK_JOKER_NUMBER
        elseif real_card_number_set[RED_JOKER_NUMBER] and self_da_pai_more_than_rival(self) then --大王压2
            return {[RED_JOKER_NUMBER] = 1},CARD_SUIT_TYPE_DANPAI,RED_JOKER_NUMBER
        end
    end

    if last_card_suit_key == BLACK_JOKER_NUMBER then    --大王压小王
        if real_card_number_set[RED_JOKER_NUMBER] then
            return {[RED_JOKER_NUMBER] = 1},CARD_SUIT_TYPE_DANPAI,RED_JOKER_NUMBER
        end
    end

    --找单牌
    local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
    for _,dan_pai in pairs(dan_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[dan_pai.key] then
            print("111111111111",tostring_r(dan_pai_list))
            if rival_can_must_win(self) or self_can_must_win(self) then
                return {[dan_pai.key] = 1},CARD_SUIT_TYPE_DANPAI,dan_pai.key
            end
            if dan_pai.key == BLACK_JOKER_NUMBER or dan_pai.key == RED_JOKER_NUMBER or dan_pai.key == laizi then
                break
            end
            print("22222222222222222222")
            return {[dan_pai.key] = 1},CARD_SUIT_TYPE_DANPAI,dan_pai.key
        end
    end
    if only_check_dan_pai then return end

    --拆2
    if real_card_number_set[CARD_TWO_NUMBER] and 
        #real_card_number_set[CARD_TWO_NUMBER] < 4 and
        laozi ~=  CARD_TWO_NUMBER and
       POWER_MAP[CARD_TWO_NUMBER] > POWER_MAP[last_card_suit_key] then
       return {[CARD_TWO_NUMBER] = 1},CARD_SUIT_TYPE_DANPAI,CARD_TWO_NUMBER
    end
    print("chai dui pai++++++++++++++++++++++++++++")
    --拆对牌
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    for _,dui_pai in pairs(dui_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[dui_pai.key] then
            for k,v in pairs(dui_pai.cards) do
                if v ~= laizi then
                    return {[v] = 1},CARD_SUIT_TYPE_DANPAI,v
                end
            end
        end
    end
    print("chai lianshun pai++++++++++++++++++++++++++++")
    --拆6连顺以上的顶牌
    local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
    for _,dan_shun in pairs(dan_shun_list) do
        local shun_zi_len = get_shun_zi_len(dan_shun.cards,CARD_SUIT_TYPE_DANSHUN)
        if shun_zi_len >= 6 and dan_shun.key ~= laizi and
           POWER_MAP[last_card_suit_key] < POWER_MAP[dan_shun.key] and
           dan_shun.cards[key] then
           return {[dan_shun.key] = 1},CARD_SUIT_TYPE_DANPAI,dan_shun.key
        end
    end
    print("chai san tiao++++++++++++++++++++++++++++++++")
    --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,san_zhang_pai in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[san_zhang_pai.key] then
            for _,card_id in pairs(san_zhang_pai.cards) do
                if card_id ~= laizi then
                    return {[san_zhang_pai.key] = 1},CARD_SUIT_TYPE_DANPAI,san_zhang_pai.key
                end    
            end
        end
    end
    print("chai feiji+++++++++++++++++++++++++++++++++")
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
       if POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
           return {[feiji.key] = 1},CARD_SUIT_TYPE_DANPAI,feiji.key
       end 
    end
    --拆5连顺
    print("chai lianshun+++++++++++++++++++")
    for _,dan_shun in pairs(dan_shun_list) do
        local shun_zi_len = get_shun_zi_len(dan_shun.cards,CARD_SUIT_TYPE_DANSHUN)
        if shun_zi_len == 5 and dan_shun.key ~= laizi and 
           POWER_MAP[last_card_suit_key] < POWER_MAP[dan_shun.key] then

           return {[dan_shun.key] = 1},CARD_SUIT_TYPE_DANPAI,dan_shun.key
        end
    end
    --拆连对
    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun.key] and
        shuang_shun.key ~= laizi then
            return {[shuang_shun.key] = 1},CARD_SUIT_TYPE_DANPAI,shuang_shun.key
        end
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_dui_pai(self,last_card_suit_key,last_uid,only_check_dui_pai,laizi)
    --找对牌
    local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
    for _,dui_pai in pairs(dui_pai_list) do
        if not (self_can_must_win(self) or rival_can_must_win(self)) and number == CARD_TWO_NUMBER then
            goto continue
        end
        if POWER_MAP[last_card_suit_key] < POWER_MAP[dui_pai.key] then 
            return dui_pai.cards,CARD_SUIT_TYPE_DUIPAI,dui_pai.key
        end
        ::continue::
    end
    if only_check_dui_pai then return end

    print("11111111111111")
    --拆4连对的顶对
    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        local shun_zi_len = get_shun_zi_len(shuang_shun.cards,CARD_SUIT_TYPE_SHUANGSHUN)
        if shun_zi_len >= 4 and POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun.key] then
            for card,count in pairs(shuang_shun.cards) do
                if card == shuang_shun.key and card ~= laizi and count >= 2 then
                    return {[shuang_shun.key] = 2},CARD_SUIT_TYPE_DUIPAI,shuang_shun.key
                end
            end    
        end
    end
    print("222222222222222")
    --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,san_zhang in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[san_zhang.key] then
            for card,count in pairs(san_zhang.cards) do
                if card ~= laizi and count >= 2 then
                    return {[san_zhang.key] = 2},CARD_SUIT_TYPE_DUIPAI,san_zhang.key
                end
            end        
        end
    end
    print("33333333333333")
    --拆3连对
    for _,shuang_shun in pairs(shuang_shun_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun.key] then
            for card,count in pairs(shuang_shun.cards) do
                if card ~= laizi and POWER_MAP[last_card_suit_key] < POWER_MAP[card] and count >= 2 then
                    return {[shuang_shun.key] = 2},CARD_SUIT_TYPE_DUIPAI,shuang_shun.key
                end
            end
        end
    end
    print("44444444444444444444444")
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            for card,count in pairs(feiji.cards) do
                if card ~= laizi and count >= 2 and POWER_MAP[last_card_suit_key] < POWER_MAP[card] then 
                    return {[feiji.key] = 2},CARD_SUIT_TYPE_DUIPAI,feiji.key
                end
            end    
        end 
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function get_xiao_pai(except_map,xiaopai_type,xiaopai_count,laizi)
    local xiao_pai_map = {}
    local remain_count = xiaopai_count

    if xiaopai_type == 1 then --单牌
        local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        for _,dan_pai in pairs(dan_pai_list) do
            if not except_map[dan_pai.key] and danpai.key ~= laizi and remain_count > 0 then
                xiao_pai_map[dan_pai.key] = 1
                remain_count = remain_count - 1
            end
        end
        --找6连顺以上的底牌
        local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
        for _,dan_shun in pairs(dan_shun_list) do
            local len = get_shun_zi_len(dan_shun.cards,CARD_SUIT_TYPE_DANSHUN)
            if len >= 6 and remain_count > 0 and not except_map[dan_shun.key] and dan_shun.key ~= laizi then
                xiao_pai_map[dan_shun.key] = 1
                remain_count = remain_count - 1
            end
        end
        --拆三条中的牌
        local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        for _,san_zhang in pairs(san_zhang_pai_list) do
            if not except_map[san_zhang.key] and san_zhang.key ~= laizi and remain_count > 0 then
                xiao_pai_map[san_zhang.key] = 1
                remain_count = remain_count - 1
            end
        end
        --拆飞机
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        for _,feiji in pairs(feiji_list) do
            if not except_map[feiji.key] and remain_count > 0 then
                for card,count in pairs(feiji.cards) do
                    if card ~= laizi then
                        xiao_pai_map[card] = 1
                        remain_count = remain_count - 1
                    end
                end    
            end      
        end
        --拆5连顺
        for _,dan_shun in pairs(dan_shun_list) do
            local len = get_shun_zi_len(dan_shun.cards,CARD_SUIT_TYPE_DANSHUN)
            if not except_map[dan_shun.key] and len == 5 and remain_count > 0 then
                for card,count in pairs(dan_shun.cards) do
                    if card ~= laizi then
                        xiao_pai_map[card] = 1
                        remain_count = remain_count - 1
                    end
                end
            end
        end
        --拆连对
        local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
        for _,shuang_shun in pairs(shuang_shun_list) do
            if not except_map[shuang_shun.key] and remain_count > 0 then
                for card,count in pairs(shuang_shun.cards) do
                    if card ~= laizi then
                        xiao_pai_map[shuang_shun.key] = 1
                        remain_count = remain_count - 1
                    end
                end
            end    
        end
    elseif xiaopai_type ==  2 then  --对牌
        --找对牌
        local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]
        for _,dui_pai in pairs(dui_pai_list) do
            if not except_map[dui_pai.key] and remain_count > 0 then
                for card,count in pairs(dui_pai.cards) do
                    if card ~= laizi and count >= 2 then
                        xiao_pai_map[card] = 2
                        remain_count = remain_count - 1
                    end
                end
            end
        end
        --拆4连对的底对
        local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
        for _,shuang_shun in pairs(shuang_shun_list) do
            local len = get_shun_zi_len(shuang_shun.cards,CARD_SUIT_TYPE_SHUANGSHUN)
            if not except_map[shuang_shun.key] and len >= 4 and remain_count > 0 then
                for card,count in pairs(shuang_shun.cards) do
                    if card == shuang_shun.key and card ~= laizi and count >= 2 then
                        xiao_pai_map[shuang_shun.key] = 2
                        remain_count = remain_count - 1
                    end
                end
            end
        end
        --拆三条中的牌
        local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        for _,san_zhang in pairs(san_zhang_pai_list) do
            if not except_map[san_zhang.key] and remain_count > 0 then
                for card,count in pairs(san_zhang.cards) do
                    if card ~= laizi and count >= 2 then
                        xiao_pai_map[san_zhang.key] = 2
                        remain_count = remain_count - 1
                    end
                end
            end    
        end
        --拆3连对
        for _,shuang_shun in pairs(shuang_shun_list) do
            if not except_map[shuang_shun.key] and remain_count > 0 then
                for card,count in pairs(shuang_shun.cards) do
                    if card ~= laizi and count >= 2 then
                        xiao_pai_map[shuang_shun.key] = 2
                        remain_count = remain_count - 1
                    end
                end
            end    
        end
        --拆飞机
        local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
        for _,feiji in pairs(feiji_list) do
            if not except_map[feiji.key] and remain_count > 0 then
                for card,count in pairs(feiji.cards) do
                    if card ~= laizi and count >= 2 then
                        xiao_pai_map[feiji.key] = 2
                        remain_count = remain_count - 1
                    end
                end        
            end
        end
    else
       errorlog("unknwon xiaopai_count!!!!")
    end

    if remain_count <= 0 then
        return xiao_pai_map
    end
end

local function check_san_zhang_pai(self,last_card_suit_key,last_uid,only_check_dui_pai)
   --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,san_zhang in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[san_zhang.key] then
            return {[san_zhang.key] = 3},CARD_SUIT_TYPE_SANZANGPAI,san_zhang.key
        end
    end
    if only_check_dan_pai then
        return
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            return {[feiji.key] = 3},CARD_SUIT_TYPE_SANZANGPAI,feiji.key
        end 
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_san_dai_yi(self,last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local cards = {}
    local key
    local laizi = self.ddz_instance:get_laizi_id()
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,san_zhang in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[san_zhang.key] then
            cards[san_zhang.key] = 3
            key = san_zhang.key
            break
        end
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(cards) then
            if POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
                cards[feiji.key] = 3
                key = feiji.key
                break
            end 
        end
    end
    --寻找小牌
    if next(cards) then
        local xiao_pai_map = get_xiao_pai(cards,1,1,laizi)
        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                cards[number] = count
            end
            return cards,CARD_SUIT_TYPE_SANDAIYI,key
        end
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_san_dai_yi_dui(self,last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local cards = {}
    local key
    local laizi = self.ddz_instance:get_laizi_id()
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,san_zhang in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[san_zhang.key] then
            cards[san_zhang.key] = 3
            key = san_zhang.key
            break
        end
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(cards) then
            if POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
                cards[feiji.key] = 3
                key = feiji.key
                break
            end 
        end
    end
    --寻找小牌
    if next(cards) then
        local xiao_pai_map = get_xiao_pai(cards,2,1,laizi)
        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                cards[number] = count
            end
            return cards,CARD_SUIT_TYPE_SANDAIYIDUI,key
        end
    end
    --炸弹
    --return check_zhadan_wangzha()
end

local function check_dan_shun(last_card_suit_key,shun_zi_len)
    local card_type_list = {
       [CARD_SUIT_TYPE_DANSHUN] = self_card_type_list[CARD_SUIT_TYPE_DANSHUN],
       [CARD_SUIT_TYPE_SHUANGSHUN] = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN],
       [CARD_SUIT_TYPE_FEIJI] =  self_card_type_list[CARD_SUIT_TYPE_FEIJI],
    }

    local function make_result(key,shun_zi_len)
        local cards = {}
        local power = POWER_MAP[key]
        for i = 1,shun_zi_len do
            local number = assert(CONTINUOUS_CARD_MAP[power])
            power = power - 1
            cards[number] = 1
        end
        return cards,CARD_SUIT_TYPE_DANSHUN,key
    end

    --先找相同张数的单顺,双顺,飞机
    for card_type,card_type_table in pairs(card_type_list) do
        for _,shun_zi in pairs(card_type_table) do
            local max_num = get_max_num_from_shun_zi(shun_zi.cards)
            local len = get_shun_zi_len(shun_zi.cards,card_type)
            if len == shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[shun_zi.key] then
                return make_result(shun_zi.key,shun_zi_len)
            end
        end
    end
    --再找不同张数的单顺,双顺,飞机
    for card_type,card_type_table in pairs(card_type_list) do
        for _,shun_zi in pairs(card_type_table) do
            local max_num = get_max_num_from_shun_zi(shun_zi.cards)
            local len = get_shun_zi_len(shun_zi.cards,card_type)
            if len > shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[shun_zi.key] then
                return make_result(shun_zi.key,shun_zi_len)
            end
        end
    end
end

local function check_shuang_shun(last_card_suit_key,shun_zi_len)
    --拆相同张数的双顺
    local function make_result(key,shun_zi_len)
        local cards = {}
        local power = POWER_MAP[key]
        for i = 1,shun_zi_len do
            local number = assert(CONTINUOUS_CARD_MAP[power])
            power = power - 1
            cards[number] = 2
        end
        return cards,CARD_SUIT_TYPE_SHUANGSHUN,key
    end

    local shuang_shun_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN]
    for _,shuang_shun in pairs(shuang_shun_list) do
        local len = get_shun_zi_len(shuang_shun.cards,CARD_SUIT_TYPE_SHUANGSHUN)
        if len == shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun.key] then
            return make_result(shuang_shun.key,shun_zi_len)
        end
    end
    --拆不同张数的双顺
    for _,shuang_shun in pairs(shuang_shun_list) do
        local len = get_shun_zi_len(shuang_shun.cards,CARD_SUIT_TYPE_SHUANGSHUN)
        if len > shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[shuang_shun.key] then
            return make_result(shuang_shun.key,shun_zi_len)
        end
    end
    --拆不同张数的飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
        if len > shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            return make_result(feiji.key,shun_zi_len)
        end
    end 
    --拆相同张数的飞机
    for _,feiji in pairs(feiji_list) do
        local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
        if len == shun_zi_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            return make_result(feiji.key,shun_zi_len)
        end
    end 
end

local function check_feiji(last_card_suit_key,last_card_suit)
    local rival_count_number_map = translate_to_count_number(last_card_suit)
    local sanzhang_list = assert(rival_count_number_map[3])
    local feiji_len = #sanzhang_list

    local function make_result(key,feiji_len)
        local cards = {}
        local power = POWER_MAP[key]
        for i = 1,feiji_len do
            local number = assert(CONTINUOUS_CARD_MAP[power])
            power = power - 1
            cards[number] = 3
        end
        return cards,CARD_SUIT_TYPE_FEIJI,key
    end

    --拆相同张数的飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
        if len == feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            return make_result(feiji.key,feiji_len)
        end
    end 
    --拆不同张数的飞机
    for _,feiji in pairs(feiji_list) do
        local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
        if len > feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            return make_result(feiji.key,feiji_len)
        end
    end 

    --return check_zhadan_wangzha()
end

local function check_feiji_and_wing(self,last_card_suit_key,last_card_suit)
    local xiaopai_type = 1
    if #last_card_suit % 4 ~= 0 then
        xiaopai_type = 2
    end
    local feiji_len = math.floor(#last_card_suit / (3 + xiaopai_type)) 

    local laizi = self.ddz_instance:get_laizi_id()
    --拆相同张数的飞机
    local cards = {}
    local key
    local found = false
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
        if len == feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
            local power = POWER_MAP[feiji.key]
            for i = 1,feiji_len do
                local number = assert(CONTINUOUS_CARD_MAP[power])
                power = power - 1
                cards[number] = 3
            end
            key = feiji.key
            found = true
        end
    end 
    --拆不同张数的飞机
    if not found then
        for _,feiji in pairs(feiji_list) do
            local len = get_shun_zi_len(feiji.cards,CARD_SUIT_TYPE_FEIJI)
            if #feiji > feiji_len and POWER_MAP[last_card_suit_key] < POWER_MAP[feiji.key] then
                local power = POWER_MAP[feiji.key]
                for i = 1,feiji_len do
                    local number = assert(CONTINUOUS_CARD_MAP[power])
                    power = power - 1
                    cards[number] = 3
                end
                key = feiji.key
                found = true
            end
        end 
    end

    if found then
        local xiao_pai_map = get_xiao_pai(cards,xiaopai_type,feiji_len,laizi)
        if xiao_pai_map then
            for number,count in pairs(xiao_pai_map) do
                cards[number] = count
            end
            return cards,CARD_SUIT_TYPE_FEIJIDAICIBANG,key
        end
    end
    
    --return check_zhadan_wangzha()
end

--找出最小的牌
local function check_min_card_type(cards_id_list,laizi)
    assert(#cards_id_list > 0)

    local card_number_set = process_card_id_list(cards_id_list)
    local ruan_zha_map = {}
    for _,ruan_zha in pairs(self_card_type_list[CARD_SUIT_TYPE_RUANZHA]) do
        ruan_zha_map[ruan_zha.key] = true
    end

    local function get_number_count(card_number_set)
        local count = 0
        for number,_ in pairs(card_number_set) do
            count = count + 1
        end
        return count
    end

    local card_number_list = {}
    local number_count = get_number_count(card_number_set)
    for number,count in pairs(card_number_set) do
        if  number_count > 1 then
            if count ~= 4 and number ~= laizi and not ruan_zha_map[number] then  --去掉炸弹,癞子牌
                table_insert(card_number_list,number)
            end
        else
            table_insert(card_number_list,number)
        end
    end

    local min_number = card_number_list[1]
    local cards = {}
    if #card_number_list <= 0 then
        return cards,CARD_SUIT_TYPE_DANPAI,min_number
    end

    for _,number in pairs(card_number_list) do
        if POWER_MAP[min_number] > POWER_MAP[number] then
            min_number = number
        end
    end
    cards[min_number] = 1
    return cards,CARD_SUIT_TYPE_DANPAI,min_number
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
local function check_min_dan_pai(cards_id_list)
    local tmp_number_list = get_number_list(cards_id_list)
    local min_number = tmp_number_list[1]
    for _,number in pairs(tmp_number_list) do
        if POWER_MAP[min_number] > POWER_MAP[number] then
            min_number = number
        end
    end
    return {[min_number] = 1},CARD_SUIT_TYPE_DANPAI,min_number
end

local function check_max_dan_pai(cards_id_list,key)
    local tmp_number_list = get_number_list(cards_id_list)
    local max_number = tmp_number_list[1]
    for _,number in pairs(tmp_number_list) do
        if POWER_MAP[max_number] < POWER_MAP[number] then
            max_number = number
        end
    end

    if POWER_MAP[max_number] <= POWER_MAP[key] then return end
    return {[max_number] = 1},CARD_SUIT_TYPE_DANPAI,max_number
end

local function player_can_play(self,last_record,uid)
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key
    local last_card_suit = last_record.card_suit
    local player_cards_id = self.ddz_instance:get_player_card_ids(uid)
    local laizi = self.ddz_instance:get_laizi_id()

    return lz_remind.lz_can_greater_than(player_cards_id,last_card_suit,last_card_suit_type,last_card_suit_key,laizi)
end

local function on_teammate_play(self,last_record)
    print("on_teammate_play++++++++++++++++++++++")
    local last_card_suit_type = last_record.card_suit_type
    local last_card_suit_key = last_record.key
    local last_card_suit = last_record.card_suit
  --  print("zzzzzzzzzzz",tostring_r(self_card_type_list))
    local card_type_list = assert(make_card_type(last_record.uid,self.ddz_instance))
    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
   -- print("jjjjjjjjjjjjjj",tostring_r(self_card_type_list))
    if not player_can_play(self,last_record,dizhu_uid) and player_can_must_win(last_record.uid,self.ddz_instance,card_type_list) then
        print("on_teammate_play player_can_must_win")
        return
    end
   -- print("yyyyyyyyy",tostring_r(card_type_list))
   -- print("xxxxxxxxx",tostring_r(self_card_type_list))

    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        --[[if next_is_dizhu(self) and #self_card_type_list[CARD_SUIT_TYPE_DANPAI] > 0 then
            local dizhu_card_list = assert(make_card_type(dizhu_uid,self.ddz_instance))
            if #dizhu_card_list[CARD_SUIT_TYPE_DANPAI] >= 2 then
                print("33333333333333")
                local _,second_max_num = get_max_two_number(dizhu_card_list[CARD_SUIT_TYPE_DANPAI])
                local len = #self_card_type_list[CARD_SUIT_TYPE_DANPAI]
                local self_max_num = self_card_type_list[CARD_SUIT_TYPE_DANPAI][len]
                if POWER_MAP[self_max_num.key] > POWER_MAP[last_card_suit_key] then
                    if POWER_MAP[self_max_num.key] < POWER_MAP[second_max_num] then
                        return {[self_max_num.key] = 1},CARD_SUIT_TYPE_DANPAI,self_max_num.key
                    else
                        for _,dan_pai in pairs(self_card_type_list[CARD_SUIT_TYPE_DANPAI]) do
                            local number = dan_pai.key
                            if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and 
                               POWER_MAP[number] > POWER_MAP[second_max_num] and 
                               POWER_MAP[number] > POWER_MAP[last_card_suit_key] then                  
                               return {[number] = 1},CARD_SUIT_TYPE_DANPAI,number
                            end
                        end
                    end
                end
            end
        end]]

        --大于等于A的时候不出
        local pai_A = 12
        if POWER_MAP[last_card_suit_key] >= pai_A then
            return
        end
        return check_dan_pai(self,last_card_suit_key,true)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        --大于等于KK的时候不出
        local pai_k = 11 
        if POWER_MAP[last_card_suit_key] >= pai_k then
            return
        end
        return check_dui_pai(self,last_card_suit_key,last_record.uid,true)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        local pai_J = 9
        if not self_can_must_win(self) and POWER_MAP[last_card_suit_key] >= pai_J then
            return
        end 
        return check_san_zhang_pai(self,last_card_suit_key,last_record.uid)
    end
end

local function select_numbers(self,last_record)
    if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return check_dan_pai(self,last_record.key)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return check_dui_pai(self,last_record.key,last_record.uid)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        return check_san_zhang_pai(last_record.key)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        return check_san_dai_yi(self,last_record.key,last_record.card_suit)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        return check_san_dai_yi_dui(self,last_record.key,last_record.card_suit)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_DANSHUN then
        return check_dan_shun(last_record.key,#last_record.card_suit)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
        return check_shuang_shun(last_record.key,#last_record.card_suit / 2)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_FEIJI then
        return check_feiji(last_record.key,last_record.card_suit)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
        return check_feiji_and_wing(self,last_record.key,last_record.card_suit)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SIDAIER then
        return check_zhadan_wangzha()
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
        return check_zhadan_wangzha()
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_RUANZHA then
        return check_zhadan_wangzha(last_record.key)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        return check_zhadan_wangzha(RED_JOKER_NUMBER,last_record.key)
    elseif last_record.card_suit_type == CARD_SUIT_TYPE_WANGZHA then
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
    table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
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
        for _,dui_pai in pairs(self_card_type_list[CARD_SUIT_TYPE_DUIPAI]) do
            for id,count in pairs(dui_pai.cards) do
                local cards = {}
                cards[id] = 1
                table_insert(self_card_type_list[CARD_SUIT_TYPE_DANPAI],{cards = cards,key = id})
            end    
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
        table_sort(self_card_type_list[card_type],function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
    end    
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
    local ddz_instance = assert(self.ddz_instance)
    local dizhu_uid = ddz_instance:get_dizhu_uid()
    if self.uid == dizhu_uid then
        return false
    end
    
    local next_position_uid = ddz_instance:get_next_position_uid(self.uid)
    if next_position_uid == dizhu_uid then
        return false
    end
    return true
end

local function select_card_on_must_play(self,candidate_type,check_min,laizi)
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)

    local min_card_map
    if check_min then
        min_card_map = check_min_card_type(cards_id_list,laizi)
    end

    for _,card_suit_type in pairs(candidate_type) do
        --print(tostring_r(self_card_type_list))
        --print(card_suit_type,tostring_r(min_card_map))
        if check_card_type(self,card_suit_type,min_card_map) then
        --   print("card_type is ++++++++++++++++",card_suit_type)
            local ret,type,key = select_by_type(self,card_suit_type,laizi)
          --  print(ret,type,key)
            if ret then 
                print("kkkkkkkkkkkkk",type,key,tostring_r(ret))
                local  cards = full_result_cards(ret,real_card_number_set)
                return cards,type,key
            end
        end
    end
end

local function rival_is_remain_one_handle(self,last_uid)
    --对手出的牌并且只剩一手牌
    local laizi = self.ddz_instance:get_laizi_id()
    local card_type_list = assert(make_card_type(last_uid,self.ddz_instance,laizi))
    local handle_count = get_card_handle_count(card_type_list)
    print("handle_count>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>",handle_count)
    if handle_count == 1 then
        return true
    end
    return false
end

local function check_next_rival_on_remain_one(self,last_record,laizi)
    if last_record.card_suit_type ~= CARD_SUIT_TYPE_DANPAI 
        or next_player_is_teammate(self) then
       return
    end

    local dizhu_uid = self.ddz_instance:get_dizhu_uid()
    local is_dizhu = dizhu_uid == self.uid
    local rival_min_count = self.ddz_instance:get_rival_min_card_count(is_dizhu)
    if rival_min_count ~= REMAIN_CARD_COUNT_ONE then
        return 
    end
    
    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    local ret,type,key = check_max_dan_pai(cards_id_list,last_record.key)
    if not ret then 
        return   
    end
    print("1111111111111111")
    local cards = full_result_cards(ret,real_card_number_set)
    return cards,type,key 
end

local function on_play_pre_is_teammate(self,last_record,laizi)
    local ret,card_type,key = on_teammate_play(self,last_record)
    print("ggggg",tostring_r(ret),card_type,key)
    if not ret then 
        return {} --不出
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    print("222222222222222222222")
    local cards = full_result_cards(ret,real_card_number_set)
    return cards,card_type,key
end

local function on_play_next_is_teammate(self,candidate_type_list,laizi)
    local next_player_card_count = self.ddz_instance:get_next_pos_player_card_count(self.uid)
    if next_player_card_count == REMAIN_CARD_COUNT_ONE then
        local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
        local ret,type,key = check_min_dan_pai(cards_id_list,laizi)
        if not ret then 
            errlog("select card_faild!!!")
            return   
        end

        local _,real_card_number_set = process_card_id_list(cards_id_list)
        print("333333333333333333")
        local cards = full_result_cards(ret,real_card_number_set)
        return cards,type,key     
    end

    local check_min = true
    if rival_is_remain_one(self) or self_can_must_win(self) then
        check_min = false
    end

    return select_card_on_must_play(self,candidate_type_list,check_min,laizi)
end

local function check_separate_laizi_play(self,card_suit,card_id_list,handle_count)
    print("check+++++++++++++++++++++++++++++++",tostring_r(card_suit),tostring_r(card_id_list))
    local new_card_id_list = {}
    for idx,card in pairs(card_id_list) do
        new_card_id_list[idx] = card
    end

    local _,card_number_set = process_card_id_list(new_card_id_list)
    for _,card in pairs(card_suit) do
        for idx,card_id in pairs(new_card_id_list) do
            if card == card_id then
                table_remove(new_card_id_list,idx)
                break
            end
        end
    end


    local new_card_type_list = assert(make_card_type(self.uid,self.ddz_instance,laizi,new_card_id_list))
    local new_handle_count = get_card_handle_count(new_card_type_list)

    print("check_coount+++++++++++++++++++++++++++++++++++++++",new_handle_count,handle_count)
    return (new_handle_count <= handle_count + 2)
end

local function on_separate_laizi_play(self,last_record)
    --TODO:拆癞子压死
    local card_suit = last_record.card_suit
    local card_suit_type = last_record.card_suit_type
    local key = last_record.key
    local card_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local laizi = self.ddz_instance:get_laizi_id()
    print("tttttttttttttttttttt",tostring_r(card_suit))
    if lz_remind.lz_can_greater_than(card_id_list,card_suit,card_suit_type,key,laizi) then
        local result = lz_remind.card_remind(card_id_list,card_suit,card_suit_type,key,laizi)
        if result and result[1] then
            print("zzzzzzzzzzzzzzzzzzzzzgghhh")
            local handle_count = get_card_handle_count(self_card_type_list)
            local ret = check_separate_laizi_play(self,result[1].card_suit,card_id_list,handle_count)
            if ret then
                print("999999999999999999999",tostring_r(result)) 
                return result[1].card_suit,result[1].type,result[1].key
            end
        end    
    end
    return
end

local function on_play_pre_is_rival(self,last_record,laizi)
    local ret,card_type,key = select_numbers(self,last_record)
    if not ret then
        ret,card_type,key = on_separate_laizi_play(self,last_record)
        if ret then
            return ret,card_type,key
        elseif rival_is_remain_one_handle(self,last_record.uid) then
            print("xxxxxxxxxxxxxxxxxxxxxxx")
            ret,card_type,key = check_zhadan_wangzha()
        else
            return {}        
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    print("4444444444444444444444")
    local cards = full_result_cards(ret,real_card_number_set)
    return cards,card_type,key
end

local function on_play_next_is_rival(self,candidate_type,laizi)
    --print("hhhhhhhhhhhhhhhhhhhhh")
    --local next_player_card_count = self.ddz_instance:get_next_pos_player_card_count(self.uid)
    --if next_player_card_count == REMAIN_CARD_COUNT_ONE then --对手只剩一张牌
    --    return select_card_on_must_play(self,candidate_type,false,laizi)
    --end
    local check_min = true
    if self_can_must_win(self) or rival_is_remain_one(self) or rival_is_remain_two(self) then
        check_min = false
    end

    return select_card_on_must_play(self,candidate_type,true,laizi)
end

local function on_must_play(self,laizi)
    local candidate_type_list = {
        CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_DUIPAI,CARD_SUIT_TYPE_DANSHUN,
        CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_SANDAIYI,
        CARD_SUIT_TYPE_SANDAIYIDUI,CARD_SUIT_TYPE_SANZANGPAI,
        CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,
        CARD_SUIT_TYPE_SIDAIER,CARD_SUIT_TYPE_SIDAILIANGDUI,
        CARD_SUIT_TYPE_RUANZHA,
        CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
    }
    local can_must_win,card_type_finaly_play = self_can_must_win(self)
    if can_must_win then
        print("===================can_must_win")
        if rival_is_remain_one(self) then
            delay_card_type_dan_pai(candidate_type_list)
        end
        if card_type_finaly_play then
            print("===========================",card_type_finaly_play)
            delay_card_type(candidate_type_list,card_type_finaly_play)
        end
        return select_card_on_must_play(self,candidate_type_list,false,laizi)
    end

    if rival_is_remain_one(self) then
        delay_card_type_dan_pai(candidate_type_list)
    end

    if rival_is_remain_two(self) then
        delay_card_type_dui_pai(candidate_type_list)
    end

    if next_player_is_teammate(self) then  
        --如果下家是队友
        return on_play_next_is_teammate(self,candidate_type_list,laizi)
    else  
        --如果下家是敌对                           
        return on_play_next_is_rival(self,candidate_type_list,laizi)
    end
end

local function on_play_follow(self,last_record)
    local ret,type,key = select_numbers(self,last_record)
    if not ret then
        if last_record.card_suit_type ~= CARD_SUIT_TYPE_ZHADAN and 
        last_record.card_suit_type ~= CARD_SUIT_TYPE_WANGZHA then
            ret,type,key = check_zhadan_wangzha()
        end
        if not ret then
            return {}
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    local cards = full_result_cards(ret,real_card_number_set)
    return cards,type,key
end

local function on_not_must_play(self,last_record,laizi)
    local cards,card_type,key = check_next_rival_on_remain_one(self,last_record,laizi)
    if cards then 
        return cards,card_type,key
    end    

    local can_must_win,card_type = self_can_must_win(self)
    if can_must_win then
        local player_cards_id = self.ddz_instance:get_player_card_ids(self.uid)
        if lz_remind.can_greater_than(player_cards_id,last_record.card_suit,last_record.card_suit_type,last_record.key) then
            if last_record.card_suit_type == CARD_SUIT_TYPE_DANPAI then
                table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)
            elseif last_record.card_suit_type == CARD_SUIT_TYPE_DUIPAI then
                table_sort(self_card_type_list[CARD_SUIT_TYPE_DUIPAI],function(a,b) return (POWER_MAP[a.key] > POWER_MAP[b.key]) end)    
            end
            return on_play_follow(self,last_record)
        end
    end

    if pre_player_is_teammate(self,last_record) then
        --如果上家是队友
        return on_play_pre_is_teammate(self,last_record,laizi)
    else
        --如果上家是敌对
        return on_play_pre_is_rival(self,last_record,laizi)
    end
end

local M = {}

function M.analyse_rob_dizhu(self)
    local ddz_instance = assert(self.ddz_instance)
    if not self.is_rob then
        self.is_rob = is_need_rob_dizhu(self.uid,self.ddz_instance)
    end

    return {score = 0,is_rob = self.is_rob and 1 or 0}
end

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

function M.analyse_jiabei(self)
    WEIGH_VALUE_CONF = assert(self.conf.weigh_value_conf)
    JIABEI_CONF = assert(self.conf.jia_bei_conf)

    local ddz_instance = assert(self.ddz_instance)
    local laizi = ddz_instance:get_laizi_id()
    self_card_type_list = assert(make_card_type(self.uid,ddz_instance,laizi)) 
    --make_farmer_role(self)

    local is_jiabei = is_need_jiabei(self.uid,self.ddz_instance)
    return { type = is_jiabei and 1 or 0}
end

-- function M.analyse_play(self)
--     local ddz_instance = assert(self.ddz_instance)

--     local last_record = ddz_instance:get_last_card_suit_ex()
--     local must_play = false
--     if not last_record or last_record.uid == self.uid then
--         must_play = true
--     end

--     --确定牌型
--     local cards_id_list = ddz_instance:get_player_card_ids(self.uid)
--     local laizi = ddz_instance:get_laizi_id()
--     make_card_type(cards_id_list,laizi)

--     local cards,card_type,card_key
--     if must_play then
--         cards,card_type,card_key = on_must_play(self,laizi)
--     else
--         cards,card_type,card_key = on_not_must_play(self,last_record,laizi)
--     end
    
--     return {card_suit = cards,card_suit_type = card_type,card_suit_key = card_key}
-- end

function M.analyse_play(self)
    local start_time = get_now_ustime()
    local ddz_instance = assert(self.ddz_instance)

    local last_record = ddz_instance:get_last_card_suit_ex()
    local must_play = false
    if not last_record or last_record.uid == self.uid then
        must_play = true
    end

    --确定牌型
    local cards_id_list = ddz_instance:get_player_card_ids(self.uid)
    local laizi = ddz_instance:get_laizi_id()
    self_card_type_list = make_card_type(self.uid,ddz_instance,laizi)
    print("time is+++++++++++++++++++++",get_now_ustime()-start_time)

    local tmpf = function()
        local cards,card_type,card_key
        if must_play then
            cards,card_type,card_key = on_must_play(self,laizi)
            print("11111111111")
        else
            cards,card_type,card_key = on_not_must_play(self,last_record,laizi)
            print("22222222222222")
        end
        if must_play and (not cards or #cards == 0) then
            return false
        end
        return {card_suit = cards,card_suit_type = card_type,card_suit_key = card_key}
    end

    local ok,ret = pcall(tmpf,debug.traceback)

    print("time2 is+++++++++++++++++++++",get_now_ustime()-start_time)
    if ok then return ret end
   -- errlog(ret)

    if must_play then
        --local number = extract_card_number(cards_id_list[1])
        assert(cards_id_list[1])
        return {card_suit = {cards_id_list[1]},card_suit_type = CARD_SUIT_TYPE_DANPAI,card_suit_key = number}
    else
        return {card_suit = {}}
    end
end

return M
