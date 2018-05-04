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

local ROB_DIZHU_PROBABILITY = {
    {score = 0,probability = 0},    --0-4分百分之0概率
    {score = 4,probability = 20},   --4分以上百分之20概率
    {score = 6,probability = 50},   --6分以上百分之50概率
    {score = 9,probability = 100},  --9以上百分之100概率 
}

local REMAIN_CARD_COUNT_ONE = 1 --报单
local REMAIN_CARD_COUNT_TWO = 2 --报双

local san_zhang_priority_list = {
    [CARD_SUIT_TYPE_WANGZHA]    = {},
    [CARD_SUIT_TYPE_ZHADAN]     = {},
    [CARD_SUIT_TYPE_FEIJI]      = {},
    [CARD_SUIT_TYPE_SANZANGPAI] = {},
    [CARD_SUIT_TYPE_DANSHUN]    = {},
    [CARD_SUIT_TYPE_SHUANGSHUN] = {},
    [CARD_SUIT_TYPE_DUIPAI]     = {},
    [CARD_SUIT_TYPE_DANPAI]     = {},
}

local dan_shun_priority_list = {
    [CARD_SUIT_TYPE_WANGZHA]    = {},
    [CARD_SUIT_TYPE_ZHADAN]     = {},
    [CARD_SUIT_TYPE_FEIJI]      = {},
    [CARD_SUIT_TYPE_DANSHUN]    = {},
    [CARD_SUIT_TYPE_SANZANGPAI] = {},
    [CARD_SUIT_TYPE_SHUANGSHUN] = {},
    [CARD_SUIT_TYPE_DUIPAI]     = {},
    [CARD_SUIT_TYPE_DANPAI]     = {},
}

local shuang_shun_priority_list = {
    [CARD_SUIT_TYPE_WANGZHA]    = {},
    [CARD_SUIT_TYPE_ZHADAN]     = {},
    [CARD_SUIT_TYPE_FEIJI]      = {},
    [CARD_SUIT_TYPE_SANZANGPAI] = {},
    [CARD_SUIT_TYPE_SHUANGSHUN] = {},
    [CARD_SUIT_TYPE_DANSHUN]    = {},
    [CARD_SUIT_TYPE_DUIPAI]     = {},
    [CARD_SUIT_TYPE_DANPAI]     = {},
}

local self_card_type_list

-----------------------------------------common-----------------------------------------------
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
    local total_score = get_cards_total_score(card_num_set,real_card_num_set,count_num_map)
    local probability = get_probabilaty_by_score(total_score)

    if math.random(1, 100) <= probability then
        return true
    end
    return false
end

-----------------------------------------check_rob_dizhu_end--------------------------------------

-----------------------------------------make_card_type_begin-------------------------------------

local function make_zhadan_and_wangzha(real_card_num_set,count_num_map,card_type_list)
    if real_card_num_set[BLACK_JOKER_NUMBER] and real_card_num_set[RED_JOKER_NUMBER] then
        table_insert(card_type_list[CARD_SUIT_TYPE_WANGZHA],{BLACK_JOKER_NUMBER,RED_JOKER_NUMBER})
        real_card_num_set[BLACK_JOKER_NUMBER] = nil
        real_card_num_set[RED_JOKER_NUMBER]   = nil
    end

    local zhadan_list = count_num_map[4] or {}
    for _,number in pairs(zhadan_list) do
        table_insert(card_type_list[CARD_SUIT_TYPE_ZHADAN],number)
        real_card_num_set[number] = nil
    end
end

local function make_dan_pai(real_card_num_set,count_number_map,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 1 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DANPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DANPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_dui_pai(real_card_num_set,count_num_map,card_type_list)
   for number,card_id_list in pairs(real_card_num_set) do
       if #card_id_list == 2 then
          table_insert(card_type_list[CARD_SUIT_TYPE_DUIPAI],number)
          real_card_num_set[number] = nil
       end
   end

   local tmp_list = card_type_list[CARD_SUIT_TYPE_DUIPAI]
   table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_san_zhang_pai(real_card_num_set,count_num_map,card_type_list)
    for number,card_id_list in pairs(real_card_num_set) do
        if #card_id_list == 3 then
            table_insert(card_type_list[CARD_SUIT_TYPE_SANZANGPAI],number)
            real_card_num_set[number] = nil
        end
    end

    local tmp_list = card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    table_sort(tmp_list,function(a,b) return (POWER_MAP[a] < POWER_MAP[b]) end)
end

local function make_feiji(real_card_number_set,count_number_map,card_type_list)
    local tmp_list = count_number_map[3] or {}
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

local function make_dan_shun(real_card_number_set,count_number_map,card_type_list)
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

local function make_shuang_shun(real_card_number_set,count_number_map,card_type_list)
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

--三条,顺子,连对
local function make_san_zhang_priority_card_type(cards_id_list)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    make_zhadan_and_wangzha(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_feiji(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_san_zhang_pai(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_dan_shun(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_shuang_shun(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_dui_pai(real_card_num_set,count_num_map,san_zhang_priority_list)
    make_dan_pai(real_card_num_set,count_num_map,san_zhang_priority_list)
end

--三张,连对,顺子
local function make_shuang_shun_priority_card_type(cards_id_list)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    make_zhadan_and_wangzha(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_feiji(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_shuang_shun(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_dan_shun(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_dui_pai(real_card_num_set,count_num_map,shuang_shun_priority_list)
    make_dan_pai(real_card_num_set,count_num_map,shuang_shun_priority_list)
end

--顺子,三条,连对
local function make_dan_shun_priority_card_type(cards_id_list)
    local card_num_set,real_card_num_set,count_num_map = process_card_id_list(cards_id_list)

    make_zhadan_and_wangzha(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_feiji(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_dan_shun(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_san_zhang_pai(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_shuang_shun(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_dui_pai(real_card_num_set,count_num_map,dan_shun_priority_list)
    make_dan_pai(real_card_num_set,count_num_map,dan_shun_priority_list)
end

local function wipe_san_dai_yi_count(total_count,card_type_list)
    local san_zhang_count,dui_pai_count,dan_pai_count

    san_zhang_count = #card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,feiji in pairs(card_type_list[CARD_SUIT_TYPE_FEIJI]) do
        san_zhang_count = san_zhang_count + #feiji
    end
    dui_pai_count = #card_type_list[CARD_SUIT_TYPE_DUIPAI]
    dan_pai_count = #card_type_list[CARD_SUIT_TYPE_DANPAI]
    if san_zhang_count <= 0 then
        return total_count
    end

    local min = math.min(san_zhang_count,dui_pai_count + dan_pai_count)
    local tmp_count = total_count - min
    return tmp_count
end

local function select_card_type_list()
    --确定手数的时候,三张需要带上一手
    local san_zhang_priority_count,dan_shun_priority_count,shuang_shun_priority_count

    for _,card_type_list in pairs(san_zhang_priority_list) do
        san_zhang_priority_count = (san_zhang_priority_count or 0) + #card_type_list
    end
    san_zhang_priority_count = wipe_san_dai_yi_count(san_zhang_priority_count,san_zhang_priority_list)

    for _,card_type_list in pairs(dan_shun_priority_list) do
        dan_shun_priority_count = (dan_shun_priority_count or 0) + #card_type_list
    end
    dan_shun_priority_count = wipe_san_dai_yi_count(dan_shun_priority_count,dan_shun_priority_list)

    for _,card_type_list in pairs(shuang_shun_priority_list) do
        shuang_shun_priority_count = (shuang_shun_priority_count or 0)+ #card_type_list
    end
    shuang_shun_priority_count = wipe_san_dai_yi_count(shuang_shun_priority_count,shuang_shun_priority_list)


    --手数少的为最优牌型,相等的情况下,默认第一种
    local min = san_zhang_priority_count
    self_card_type_list = san_zhang_priority_list
    if min > dan_shun_priority_count then
        min = dan_shun_priority_count
        self_card_type_list = dan_shun_priority_list
    end
    if min > shuang_shun_priority_count then
        min = shuang_shun_priority_count
        self_card_type_list = shuang_shun_priority_list
    end
end

local function clear_card_type_list()
    for k,_ in pairs(san_zhang_priority_list) do
        san_zhang_priority_list[k] = {}
    end
    for k,_ in pairs(dan_shun_priority_list) do
        dan_shun_priority_list[k] = {}
    end
    for k,_ in pairs(shuang_shun_priority_list) do
        shuang_shun_priority_list[k] = {}
    end
end

local function make_card_type(cards_id_list)
    clear_card_type_list()

    make_san_zhang_priority_card_type(cards_id_list)
    make_shuang_shun_priority_card_type(cards_id_list)
    make_dan_shun_priority_card_type(cards_id_list)

    select_card_type_list()
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

local function check_card_type(card_type,min_num_map)
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
        for _,number in pairs(dui_pai_list) do
            if min_num_map[number] then
                return true
            end
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_SANZANGPAI then
        local sanzhang_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        if #sanzhang_list > 0 then
            return true
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_DANSHUN then
        local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
        if #dan_shun_list <= 0 then
            return false
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
        if #feiji_list > 0 then
            return true
        end
        return false
    elseif card_type == CARD_SUIT_TYPE_ZHADAN then
        if #self_card_type_list[CARD_SUIT_TYPE_ZHADAN] <= 0 then
            return false
        end
    elseif card_type == CARD_SUIT_TYPE_WANGZHA then
        if #self_card_type_list[CARD_SUIT_TYPE_WANGZHA] <= 0 then
            return false
        end
    else
        print("unknwon card type on check_card_type!!!",card_type)
    end

    return true
end

local function get_xiao_pai_on_must_play()
   local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
   local dui_pai_list = self_card_type_list[CARD_SUIT_TYPE_DUIPAI]

   local dan_pai_num = dan_pai_list[1]
   if dan_pai_num then
       for _,number in pairs(dan_pai_list) do
          if POWER_MAP[dan_pai_num] > POWER_MAP[number] then
             dan_pai_num = number
          end
       end
   end

   local dui_pai_num = dui_pai_list[1]
   if dui_pai_num then
       for _,number in pairs(dui_pai_list) do
          if POWER_MAP[dui_pai_num] > POWER_MAP[number] then
             dui_pai_num = number
          end
       end
   end

   local now_count --手数
   for _,card_type_list in pairs(self_card_type_list) do
        now_count = (now_count or 0) + #card_type_list
   end
   now_count = wipe_san_dai_yi_count(now_count,self_card_type_list)
   --大于两手牌的时候 不能带大于等于二的牌,写死算了
   if now_count >= 2 and dan_pai_num and POWER_MAP[dan_pai_num] >= 14 then
      dan_pai_num = nil
   end
   if now_count >= 2 and dui_pai_num and POWER_MAP[dui_pai_num] >= 14 then
      dui_pai_num = nil
   end

   return dan_pai_num,dui_pai_num
end

local function select_by_type(card_suit_type)

    if card_suit_type == CARD_SUIT_TYPE_DANPAI then
        local number = self_card_type_list[CARD_SUIT_TYPE_DANPAI][1]
        return {[number] = 1}
    elseif card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        local number = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][1]
        return {[number] = 2}
    elseif card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        local number = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI][1]
        local dan_pai_num,dui_pai_num = get_xiao_pai_on_must_play()
        if dan_pai_num then
            return {[number] = 3,[dan_pai_num] = 1} --三带一
        elseif dui_pai_num then
            return {[number] = 3,[dui_pai_num] = 2} --三带二
        else
            return {[number] = 3} --三条
        end
        return 
    elseif card_suit_type == CARD_SUIT_TYPE_DANSHUN then
       local ret = {}
       local card_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN][1]
       for _,number in pairs(card_list) do
           ret[number] = 1
       end
       return ret
    elseif card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
       local ret = {}
       local card_list = self_card_type_list[CARD_SUIT_TYPE_SHUANGSHUN][1]
       for _,number in pairs(card_list) do
           ret[number] = 2
       end
       return ret
    elseif card_suit_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
       local ret = {}
       local card_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI][1]
       for _,number in pairs(card_list) do
           ret[number] = 3
       end

       local xiao_pai_count = #card_list
       if #self_card_type_list[CARD_SUIT_TYPE_DANPAI] >= xiao_pai_count then
           for i=1,xiao_pai_count do
              local number = self_card_type_list[CARD_SUIT_TYPE_DANPAI][i]
              ret[number] = 1
           end
           return ret
        elseif #self_card_type_list[CARD_SUIT_TYPE_DUIPAI] >= xiao_pai_count then
           for i=1,xiao_pai_count do
               local number = self_card_type_list[CARD_SUIT_TYPE_DUIPAI][i]
               ret[number] = 2
           end
           return ret
        end
        return
    elseif card_suit_type == CARD_SUIT_TYPE_FEIJI then
       local ret = {}
       local card_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI][1]
       for _,number in pairs(card_list) do
           ret[number] = 3
       end
       return ret
    elseif card_suit_type == CARD_SUIT_TYPE_ZHADAN then
        local number = self_card_type_list[CARD_SUIT_TYPE_ZHADAN][1]
        return {[number] = 4}
    elseif card_suit_type == CARD_SUIT_TYPE_WANGZHA then
        return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
    else
        errorlog("unknwon card type on select_by_type!!!")
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

local function check_dan_pai(last_card_suit_key,only_check_dan_pai)
    --找单牌
    local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
    for _,number in pairs(dan_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
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

local function check_dui_pai(last_card_suit_key,only_check_dui_pai)
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

local function get_xiao_pai(except_map,xiaopai_type,xiaopai_count)
    local xiao_pai_map = {}
    local remain_count = xiaopai_count

    if xiaopai_type == 1 then --单牌
        local dan_pai_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
        for _,number in pairs(dan_pai_list) do
            if remain_count > 0 then
                xiao_pai_map[number] = 1
                remain_count = remain_count - 1
            end
        end
        --找6连顺以上的底牌
        local dan_shun_list = self_card_type_list[CARD_SUIT_TYPE_DANSHUN]
        for _,dan_shun in pairs(dan_shun_list) do
            if #dan_shun >= 6 and remain_count > 0 then
                xiao_pai_map[dan_shun[1]] = 1
                remain_count = remain_count - 1
            end
        end
        --拆三条中的牌
        local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
        for _,number in pairs(san_zhang_pai_list) do
            if not except_map[number] and remain_count > 0 then
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
            if remain_count > 0 then
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
            if not except_map[number] and remain_count > 0 then
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
       errorlog("unknwon xiaopai_count!!!!")
    end

    if remain_count <= 0 then
        return xiao_pai_map
    end
end

local function check_san_zhang_pai(last_card_suit_key)
   --拆三条中的牌
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            return {[number] = 3}
        end
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

local function check_san_dai_yi(last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local ret = {}
    local except_number = 0
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            ret[number] = 3
            except_number = number
            break
        end
    end
    --拆飞机
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(ret) then
            for _,number in pairs(feiji) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    ret[number] = 3
                    except_number = number
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

local function check_san_dai_yi_dui(last_card_suit_key,last_card_suit)
    --拆三条中的牌
    local ret = {}
    local except_number = 0
    local san_zhang_pai_list = self_card_type_list[CARD_SUIT_TYPE_SANZANGPAI]
    for _,number in pairs(san_zhang_pai_list) do
        if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
            ret[number] = 3
            except_number = number
            break
        end
    end
    --拆飞机
    
    local feiji_list = self_card_type_list[CARD_SUIT_TYPE_FEIJI]
    for _,feiji in pairs(feiji_list) do
        if not next(ret) then
            for _,number in pairs(feiji) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    ret[number] = 3
                    except_number = number
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
    --再找不同张数的单顺,双顺,飞机
    for _,card_type_table in pairs(card_type_list) do
        for _,shun_zi in pairs(card_type_table) do
            local max_num = shun_zi[#shun_zi]
            if #shun_zi > shun_zi_count and POWER_MAP[last_card_suit_key] < POWER_MAP[max_num] then
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
            for _,number in pairs(shuang_shun) do
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

local function check_min_dan_pai(cards_id_list)
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

local function on_teammate_play(last_card_suit_type,last_card_suit_key)
    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        --大于等于A的时候不出
        local pai_A = 12
        if POWER_MAP[last_card_suit_key] >= pai_A then
            return
        end
        return check_dan_pai(last_card_suit_key,true)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        --大于等于KK的时候不出
        local pai_k = 11 
        if POWER_MAP[last_card_suit_key] >= pai_k then
            return
        end
        return check_dui_pai(last_card_suit_key,true)
    end
end

local function select_numbers(last_card_suit_type,last_card_suit_key,last_card_suit)
    if last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
        return check_dan_pai(last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
        return check_dui_pai(last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
        return check_san_zhang_pai(last_card_suit_key)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
        return check_san_dai_yi(last_card_suit_key,last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
        return check_san_dai_yi_dui(last_card_suit_key,last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_DANSHUN then
        return check_dan_shun(last_card_suit_key,#last_card_suit)
    elseif last_card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
        return check_shuang_shun(last_card_suit_key,#last_card_suit)
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

local function on_not_must_play(self,last_record,self_is_dizhu,pre_is_dizhu)
    last_card_suit_type = last_record.card_suit_type
    last_card_suit_key = last_record.key
    last_card_suit = last_record.card_suit

    local rival_min_count = self.ddz_instance:get_rival_min_card_count(is_dizhu)
    if rival_min_count <= REMAIN_CARD_COUNT_ONE then
        if self_is_dizhu or (not self_is_dizhu and not pre_is_dizhu)then
            table_sort(self_card_type_list[CARD_SUIT_TYPE_DANPAI],function(a,b) return (a > b) end)
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)

    --队友出的牌
    if not self_is_dizhu and not pre_is_dizhu then
        local tmp_ret = on_teammate_play(last_card_suit_type,last_card_suit_key) 
        if not tmp_ret then return nil end
        return full_result_cards(tmp_ret,real_card_number_set) 
    end
    
    local ret = select_numbers(last_card_suit_type,last_card_suit_key,last_card_suit)
    if not ret then return nil end

    local cards = {}
    for number,count in pairs(ret) do
        local card_id_list = assert(real_card_number_set[number])
        for i = 1,count do
            table_insert(cards,assert(card_id_list[i]))
        end
    end

    return cards
end

local function on_must_play(self,self_is_dizhu,pre_is_dizhu)
    local candidate_type = {
        CARD_SUIT_TYPE_DANPAI,CARD_SUIT_TYPE_DUIPAI,CARD_SUIT_TYPE_DANSHUN,
        CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_FEIJIDAICIBANG,CARD_SUIT_TYPE_FEIJI,
        CARD_SUIT_TYPE_SANZANGPAI,CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_WANGZHA,
    }

    local rival_min_count = self.ddz_instance:get_rival_min_card_count(self_is_dizhu)
    if self_is_dizhu or (not self_is_dizhu and not pre_is_dizhu) then
        if rival_min_count <= REMAIN_CARD_COUNT_ONE then
            candidate_type[#candidate_type + 1] = CARD_SUIT_TYPE_DANPAI
            table_remove(candidate_type,1)
            local tmp_list = self_card_type_list[CARD_SUIT_TYPE_DANPAI]
            table_sort(tmp_list,function(a,b) return (POWER_MAP[a] > POWER_MAP[b]) end)
        end
    end

    local cards_id_list = self.ddz_instance:get_player_card_ids(self.uid)
    local _,real_card_number_set = process_card_id_list(cards_id_list)
    local teammate_min_count = self.ddz_instance:get_teammate_min_card_count(self.uid)
    if not self_is_dizhu and teammate_min_count and teammate_min_count <= REMAIN_CARD_COUNT_ONE then
        local ret = check_min_dan_pai(cards_id_list)
        if ret then 
            return full_result_cards(ret,real_card_number_set)     
        else
            errorlog("select card_faild!!!")
        end
        return
    end

    local min_num_map = check_min_dan_pai(cards_id_list)
    for _,card_suit_type in pairs(candidate_type) do
        if not check_card_type(card_suit_type,min_num_map) then
            goto continue
        end

        local ret = select_by_type(card_suit_type)
        if ret then 
            return full_result_cards(ret,real_card_number_set)
        else
            print("select card_faild!!! type is ",card_suit_type)
        end

        ::continue::
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

function M.analyse_play(self)
    local ddz_instance = assert(self.ddz_instance)

    local last_record = ddz_instance:get_last_card_suit_ex()
    local must_play = false
    if not last_record or last_record.uid == self.uid then
        must_play = true
    end

    --确定牌型
    local cards_id_list = ddz_instance:get_player_card_ids(self.uid)
    make_card_type(cards_id_list)

    local dizhu_uid     = ddz_instance:get_dizhu_uid()
    local self_is_dizhu = dizhu_uid == self.uid
    local pre_is_dizhu  = false
    if  last_record and dizhu_uid == last_record.uid then
        pre_is_dizhu = true
    end

print(string.format('[%d] begin select must_play is =>[%d] is_dizhu =>[%d] pre_is_dizhu =>[%d]',
        self.uid,must_play and 1 or 0,self_is_dizhu and 1 or 0,pre_is_dizhu and 1 or 0))

    local result_card_id_list
    if must_play then
        result_card_id_list = on_must_play(self,self_is_dizhu,pre_is_dizhu) or {}
    else
        result_card_id_list = on_not_must_play(self,last_record,self_is_dizhu,pre_is_dizhu) or {}
    end
    
   return {card_suit = result_card_id_list}
end

return M