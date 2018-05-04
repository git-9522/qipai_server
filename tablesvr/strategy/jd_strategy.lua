local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort
local lz_remind = require "lz_remind"

local assert = assert
local pairs = pairs
local ipairs = ipairs

local M = {}

local CARD_SUIT_TYPE_INVALID = 0        --无效牌型
local CARD_SUIT_TYPE_WANGZHA = 1        --王炸
local CARD_SUIT_TYPE_ZHADAN = 2         --炸弹
local CARD_SUIT_TYPE_DANPAI = 3         --单牌
local CARD_SUIT_TYPE_DUIPAI = 4         --对牌
local CARD_SUIT_TYPE_SANZANGPAI = 5     --三张牌
local CARD_SUIT_TYPE_SANDAIYI = 6       --三带一
local CARD_SUIT_TYPE_DANSHUN = 7        --单顺
local CARD_SUIT_TYPE_SHUANGSHUN = 8     --双顺
local CARD_SUIT_TYPE_FEIJI = 9          --飞机
local CARD_SUIT_TYPE_FEIJIDAICIBANG = 10    --飞机带翅膀
local CARD_SUIT_TYPE_SIDAIER = 11       --四带二
local CARD_SUIT_TYPE_RUANZHA = 12    --软炸
local CARD_SUIT_TYPE_SANDAIYIDUI = 13   --三带一对
local CARD_SUIT_TYPE_SIDAILIANGDUI = 14 --四带两对

local FIRST_PLAY = {
    [1] = CARD_SUIT_TYPE_DANPAI,
    [2] = CARD_SUIT_TYPE_DUIPAI,
    [3] = CARD_SUIT_TYPE_SANZANGPAI,
    [4] = CARD_SUIT_TYPE_ZHADAN,
}

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
--[[
local function random_select(card_id_list)
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

    local get_count_greater_than = function(count)
        local result
        for i = count, 4 do
            local tmp_list = count_number_map[i]
            if tmp_list then
                result = result or {}
                for _,v in ipairs(tmp_list) do
                    table_insert(result,v)
                end
            end
        end
        return result
    end

    local select_by_type = function(card_suit_type)
        if card_suit_type == CARD_SUIT_TYPE_WANGZHA then
           if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
                return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
            end
        elseif card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            local zhadan_list = count_number_map[4]
            if zhadan_list then
                local _,number = next(zhadan_list)
                return {[number] = 4}
            end
        elseif card_suit_type == CARD_SUIT_TYPE_DANPAI then
            local tmp_list = assert(get_count_greater_than(1))
            local idx = math.random(1, #tmp_list)
            return {[tmp_list[idx];] = 1}
        elseif card_suit_type == CARD_SUIT_TYPE_DUIPAI then
            local tmp_list = get_count_greater_than(2)
            if not tmp_list then 
                return
            end
            local idx = math.random(1, #tmp_list)
            return {[tmp_list[idx];] = 2}
        elseif card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
            local tmp_list = get_count_greater_than(3)
            if not tmp_list then 
                return
            end
            local idx = math.random(1, #tmp_list)
            return {[tmp_list[idx];] = 3}
        elseif card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
            local tmp_list = get_count_greater_than(3)
            if not tmp_list then
                return
            end
            for _,number in pairs(tmp_list) do
                local ret = {[number] = 3}
                for following,count in pairs(card_number_set) do
                    if not ret[following] then
                        if count > 2 then count = 2 end
                        ret[following] = count
                        return ret
                    end
                end
            end
        elseif card_suit_type == CARD_SUIT_TYPE_DANSHUN then
            local power = 1
            local ret = {}
            local ret_count = 0
            while true do
                local number = CONTINUOUS_CARD_MAP[power]
                if not number then
                    break 
                end
                if card_number_set[number] then
                    ret[number] = 1
                    ret_count = ret_count + 1
                elseif ret_count >= 5 then
                    return ret
                elseif ret_count ~= 0 then
                    ret = {}
                    ret_count = 0
                end
                power = power + 1
            end
            if ret_count >= 5 then 
                return ret
            end
        elseif card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
            local power = 1
            local ret = {}
            local ret_count = 0
            while true do
                local number = CONTINUOUS_CARD_MAP[power]
                if not number then
                    break 
                end
                local count = card_number_set[number]
                if count and count >= 2 then
                    ret[number] = 2
                    ret_count = ret_count + 1
                elseif ret_count >= 3 then
                    return ret
                elseif ret_count ~= 0 then
                    ret = {}
                    ret_count = 0
                end
                power = power + 1
            end
            if ret_count >= 3 then 
                return ret
            end
        elseif card_suit_type == CARD_SUIT_TYPE_FEIJI then
            local tmp_list = count_number_map[3]
            if not tmp_list or #tmp_list < 2 then
                return 
            end
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
                elseif #continuous >= 2 then
                    break
                else
                    if #continuous > 0 then
                        continuous = {}
                    end
                    last_power = power
                    table_insert(continuous,CONTINUOUS_CARD_MAP[power])
                end
            end
            if #continuous < 2 then
                return
            end
            local transform = function()
                local ret = {}
                for _,number in pairs(continuous) do
                    ret[number] = 3
                end
                return ret
            end

            local ensure_same_xiaopai = function(ret)
                for k,v in pairs(ret) do
                    if v == 1 then
                        for k1,v2 in pairs(ret) do
                            if v2 == 2 then ret[k1] = 1 end
                        end
                        break
                    end
                end
                return ret
            end
            while #continuous >= 2 do
                local ret = transform()
                local xiaopai_count = 0
                for number,count in pairs(card_number_set) do
                    if not ret[number] and count then
                        if count > 2 then count = 2 end
                        ret[number] = count
                        xiaopai_count = xiaopai_count + 1
                        if xiaopai_count == #continuous then
                            return ensure_same_xiaopai(ret)
                        end
                    end
                end
                table_remove(continuous)
            end
        elseif card_suit_type == CARD_SUIT_TYPE_SIDAIER then
            local ret
            if card_number_set[RED_JOKER_NUMBER] and 
                card_number_set[BLACK_JOKER_NUMBER] then
                ret = {[RED_JOKER_NUMBER] = 1,[BLACK_JOKER_NUMBER] = 1}
            else
                local tmp_list = count_number_map[4]
                if not tmp_list then
                    return 
                end
                ret = {[tmp_list[1];] = 4}
            end

            local xiaopai_count = 0
            for number,count in pairs(card_number_set) do
                if not ret[number] and count then
                    ret[number] = 1
                    xiaopai_count = xiaopai_count + 1
                    if xiaopai_count == 2 then
                        return ret
                    end
                end
            end
        else
            error('unknwon suit type ...',card_suit_type)
        end
    end

    local function full_result_cards(ret)
        local cards = {}
        for number,count in pairs(ret) do
            local card_id_list = assert(real_card_number_set[number])
            for i = 1,count do
                table_insert(cards,assert(card_id_list[i]))
            end
        end
        return cards
    end

  return (function()
        local candidate_type = {
            CARD_SUIT_TYPE_WANGZHA,CARD_SUIT_TYPE_ZHADAN,CARD_SUIT_TYPE_DANPAI,
            CARD_SUIT_TYPE_DUIPAI,CARD_SUIT_TYPE_SANZANGPAI,CARD_SUIT_TYPE_SANDAIYI,
            CARD_SUIT_TYPE_DANSHUN,CARD_SUIT_TYPE_SHUANGSHUN,CARD_SUIT_TYPE_FEIJI,
            CARD_SUIT_TYPE_SIDAIER
        }
        while true do
            local index = assert(math.random(1,#candidate_type))
            local card_suit_type = table_remove(candidate_type,index)
            local ret = select_by_type(card_suit_type)
            if ret then 
                return full_result_cards(ret)
            end
        end
    end)()
end--]]

--第一次出牌时，选择最小的牌出
local function random_select(card_id_list)
    local real_card_number_set = {}
    for _,card_id in pairs(card_id_list) do
        local number = extract_card_number(card_id)
        local t = real_card_number_set[number]
        if not t then t = {} real_card_number_set[number] = t end
        table_insert(t,card_id)
    end

    local count_number_map,card_number_set = translate_to_count_number(card_id_list)
    --按大小排序
    local play_list = {}
    for k,v in pairs(card_number_set) do
        local power = 0
        local t = {}
        if k == laizi then
            power = 100
        else 
            power = POWER_MAP[k]    
        end
        t.id = k
        t.power = power
        table_insert(play_list,t)
    end
    table_sort(play_list,function(a,b) return a.power < b.power end)

    local must_play = false
    while true do
        for i=1,#play_list do
            local count = card_number_set[play_list[i].id]
            if must_play or count < 4 then
                local key = play_list[i].id
                local type = FIRST_PLAY[count]
                local card_suit = real_card_number_set[key]
                return card_suit,type,key
            end
        end
        must_play = true
    end
end


local function select_card(uid,ddz_instance,last_card_suit_type,last_card_suit_key,last_card_suit)
    local cards_id_list = ddz_instance:get_player_card_ids(uid)
   
    local remind = lz_remind.card_remind(cards_id_list,last_card_suit,last_card_suit_type,last_card_suit_key,0)
    if remind and remind[1] then
        return remind[1].card_suit,remind[1].type,remind[1].key
    end
    return false
end

local M = {}

function M.analyse_rob_dizhu(self)
    local ddz_instance = assert(self.ddz_instance)
    return {score = 0,is_rob = 0}
end


function M.analyse_play(self)
    local ddz_instance = assert(self.ddz_instance)
    local last_record = ddz_instance:get_last_card_suit_ex()
    --必须出牌
    local must_play = false
    if not last_record or last_record.uid == self.uid then
        must_play = true
    end

    local card_id_list = ddz_instance:get_player_card_ids(self.uid)
    local dizhu_uid = ddz_instance:get_dizhu_uid()

    local result_card_id_list
    if must_play then
        --必须出牌的话，则表示可以出任意牌
        result_card_id_list = assert(random_select(card_id_list,last_record))
    else
        if dizhu_uid == self.uid or dizhu_uid == last_record.uid  then
            --自己是地主或者上家是地主，尽量压制吧
            result_card_id_list = select_card(self.uid,ddz_instance,last_record.card_suit_type,last_record.key,last_record.card_suit) or {}
        else
            --上家是农民
            result_card_id_list = {}
        end
    end

    return {card_suit = result_card_id_list}
end

return M