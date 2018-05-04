package.path = '../tablesvr/games/?.lua;' .. package.path

local ddz = require "ddz"
local table_insert = table.insert

local trustee_AI = {}

function trustee_AI.new()
    return setmetatable({},{__index = trustee_AI})
end

function trustee_AI:init(uid,ddz_instance)
    self.uid = uid
    self.ddz_instance = ddz_instance
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
local CARD_SUIT_TYPE_FEIJI = 9          --飞机
local CARD_SUIT_TYPE_SIDAIER = 11       --四带二

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
math.randomseed(os.time())
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

local DESCRIPTIONS = {
    "王炸","炸弹","单牌","对牌","三张牌",
    "三带一","单顺","双顺","飞机","四带二",
}
local function select_cards(cards_id_list,required_type)
    local card_number_set = {}
    local real_card_number_set = {}
    for _,card_id in pairs(cards_id_list) do
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
            return {[tmp_list[idx]] = 1}
        elseif card_suit_type == CARD_SUIT_TYPE_DUIPAI then
            local tmp_list = get_count_greater_than(2)
            if not tmp_list then 
                return
            end
            local idx = math.random(1, #tmp_list)
            return {[tmp_list[idx]] = 2}
        elseif card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
            local tmp_list = get_count_greater_than(3)
            if not tmp_list then 
                return
            end
            local idx = math.random(1, #tmp_list)
            return {[tmp_list[idx]] = 3}
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
            table.sort(power_list)
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
                table.remove(continuous)
            end
        elseif card_suit_type == CARD_SUIT_TYPE_SIDAIER then
            local tmp_list = count_number_map[4]
            if not tmp_list then
                return 
            end
            local ret = {[tmp_list[1]] = 4}
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
            error('unknwon suit type ...',last_card_suit_type)
        end
    end

    local ret = select_by_type(required_type)
    if not ret then
        print('failed to select ',DESCRIPTIONS[required_type],table.concat(cards_id_list,','))
        return 
    end
    local cards = {}
    for number,count in pairs(ret) do
        local card_id_list = assert(real_card_number_set[number])
        for i = 1,count do
            table_insert(cards,assert(card_id_list[i]))
        end
    end

    return table.concat(cards,',')
end

print (select_cards({104,204,304,404,105,205,306,406},CARD_SUIT_TYPE_SIDAIER))
print (select_cards({105,205,305,403,103,203,104,204,304,409,107,207},CARD_SUIT_TYPE_FEIJI))
print (select_cards({108,208,308,403,103,203,104,209,309,409,107,207},CARD_SUIT_TYPE_FEIJI))
print (select_cards({105,205,305,103,203,303,104,204,304,306,106,206,406},CARD_SUIT_TYPE_SHUANGSHUN))
print (select_cards({105,205,305,103,203,303,104,204,304,306,106,206,406},CARD_SUIT_TYPE_ZHADAN))
print (select_cards({105,205,305,103,203,303,104,204,304,306,106,206,406,107},CARD_SUIT_TYPE_DANSHUN))
print (select_cards({105,205,305,103,203,303,104,204,304,306,106,206,406,107},CARD_SUIT_TYPE_SANDAIYI))
print (select_cards({14,15},CARD_SUIT_TYPE_WANGZHA))
print (select_cards({14,15},CARD_SUIT_TYPE_DANPAI))
print (select_cards({14,15,101,201,301},CARD_SUIT_TYPE_DUIPAI))
print (select_cards({14,15,101,201,301,401},CARD_SUIT_TYPE_SANZANGPAI))
print (select_cards({14,15,101,201,301,302,404,209,302},CARD_SUIT_TYPE_DANPAI))

local function get_card_number_set(card_suit)
    local card_number_set = {}
    for _,card_id in pairs(card_suit) do
        local number = card_id % 100
        card_number_set[number] = (card_number_set[number] or 0) + 1
    end
    return card_number_set
end
local function select_cards_ex(cards_id_list,last_card_suit)
    local last_card_suit_type,last_card_suit_key = 
        ddz.get_card_suit_type(get_card_number_set(last_card_suit))

    local card_number_set = {}
    local real_card_number_set = {}
    for _,card_id in pairs(cards_id_list) do
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

    local check_zhadan_wangzha = function()
        local zhadan_list = count_number_map[4]
        if zhadan_list then
            for _,number in ipairs(zhadan_list) do
                return {[number] = 4}
            end
        end
        --如果有王炸也行
        if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
            return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
        end
        return
    end

    local check_shunzi = function(shun)
        local key_power = POWER_MAP[last_card_suit_key] + 1
        local shun_count = #last_card_suit / shun

        while CONTINUOUS_CARD_MAP[key_power] do
            --尝试着找一下有没有符合条件的顺牌
            local ret = {}
            local ret_count = 0
            for i = 1,shun_count do
                local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
                local count = card_number_set[number]
                if not count or count < shun then
                    break
                end
                ret[number] = shun
                ret_count = ret_count + 1
            end
            if ret_count == shun_count then
                return ret
            end
            --继续往上追溯
            key_power = key_power + 1
        end
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

    local select_numbers = function()
        if last_card_suit_type == nil then
            --随便什么牌都行
            return random_select()
        end
        
        if last_card_suit_type == CARD_SUIT_TYPE_WANGZHA then
            return
        elseif last_card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            local zhadan_list = count_number_map[4]
            if zhadan_list then
                for _,number in ipairs(zhadan_list) do
                    if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                        return {[number] = 4}
                    end
                end
            end
            --如果有王炸也行
            if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
                return {[BLACK_JOKER_NUMBER] = 1,[RED_JOKER_NUMBER] = 1}
            end
            return
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
            for number,count in pairs(card_number_set) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    return {[number] = 1}
                end
            end
            return check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
            for number,count in pairs(card_number_set) do
                if count >= 2 then
                    if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                        return {[number] = 2}
                    end
                end
            end
            return check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
            for number,count in pairs(card_number_set) do
                if count >= 3 then
                    if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                        return {[number] = 3}
                    end
                end
            end
            return check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
            local rival_count_number_map = translate_to_count_number(last_card_suit)
            --究竟是带一张还是带一对
            local xiaopai_count = 1
            if not rival_count_number_map[1] then
                assert(rival_count_number_map[2])
                xiaopai_count = 2
            end
            for number,count in pairs(card_number_set) do
                if count >= 3 and POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    local ret = {[number] = 3}
                    --只要不是joker或与number相同的其它牌都可以出
                    for following,count in pairs(card_number_set) do
                        if following ~= BLACK_JOKER_NUMBER and 
                            following ~= RED_JOKER_NUMBER and 
                            following ~= number and count >= xiaopai_count then
                            ret[following] = xiaopai_count
                            return ret
                        end
                    end
                end
            end
            return check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANSHUN then
            return check_shunzi(1) or check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
            return check_shunzi(2) or check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_FEIJI then
            local rival_count_number_map = translate_to_count_number(last_card_suit)
            --先确定是三张的连数，再确定是带一对还是带一只
            local sanzhang_list = assert(rival_count_number_map[3])
            local xiaopai_count = 1
            if not rival_count_number_map[1] then
                xiaopai_count = 2
            end
            local sanzhang_count = #sanzhang_list
            assert(#rival_count_number_map[xiaopai_count] == sanzhang_count)

            local key_power = POWER_MAP[last_card_suit_key] + 1
            while CONTINUOUS_CARD_MAP[key_power] do
                --尝试着找一下有没有符合条件的顺牌
                local ret = {}
                local found = true
                for i = 1,sanzhang_count do
                    local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
                    local count = card_number_set[number]
                    if not count or count < 3 then
                        found = false
                        break
                    end
                    ret[number] = 3
                end

                if found then
                    --找到了，则找小牌
                    local tmp_count = 0
                    for following,count in pairs(card_number_set) do
                        if following ~= BLACK_JOKER_NUMBER and 
                            following ~= RED_JOKER_NUMBER and 
                            not ret[following] and 
                            count >= xiaopai_count then
                            ret[following] = xiaopai_count
                            tmp_count = tmp_count + 1
                            if tmp_count == sanzhang_count then
                                return ret
                            end
                        end
                    end
                end
                key_power = key_power + 1
            end
            return check_zhadan_wangzha()
        elseif last_card_suit_type == CARD_SUIT_TYPE_SIDAIER then
            local sizhang_list = count_number_map[4]
            if not sizhang_list then
                --连四张都没有就只能看有没有王炸了
                return check_zhadan_wangzha()
            end
            local rival_count_number_map = translate_to_count_number(last_card_suit)
            --确定是带一对还是带一只
            local xiaopai_count = 1
            if not rival_count_number_map[1] then
                xiaopai_count = 2
            end
            assert(#rival_count_number_map[xiaopai_count] == 2)

            for _,number in ipairs(sizhang_list) do
                if POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                    local ret = {[number] = 4}
                    local tmp_count = 0
                    for following,count in pairs(card_number_set) do
                        if following ~= BLACK_JOKER_NUMBER and 
                            following ~= RED_JOKER_NUMBER and 
                            not ret[following] and 
                            count >= xiaopai_count then
                            ret[following] = xiaopai_count
                            tmp_count = tmp_count + 1
                            if tmp_count == 2 then
                                return ret
                            end
                        end
                    end
                end
            end
            return check_zhadan_wangzha()
        else
            error('unknwon suit type ...',last_card_suit_type)
        end
    end

    local ret = select_numbers()
    if not ret then
        return string.format('failed to beat[%s] mycards[%s] rival cards[%s] ',
            DESCRIPTIONS[last_card_suit_type],
            table.concat(cards_id_list,','),
            table.concat(last_card_suit,','))
    end
    local cards = {}
    for number,count in pairs(ret) do
        local card_id_list = assert(real_card_number_set[number])
        for i = 1,count do
            table_insert(cards,assert(card_id_list[i]))
        end
    end

    return table.concat(cards,',')
end
print('================================')
print(select_cards_ex({101},{202}))
print(select_cards_ex({101,201,301,403},{202,302}))
print(select_cards_ex({101,201,301,401},{14,15}))
print(select_cards_ex({101,201,301,401},{110,210,310,410}))
print(select_cards_ex({101,201,301,412,413},{110,210,310,411}))
print(select_cards_ex({101,201,301},{110,210,310}))
print(select_cards_ex({101,201,301,103,104,105,106,107,108,109},{203,204,205,206,207,208}))
print(select_cards_ex({101,201,301,103,203,104,204,105,205,106,206},{303,403,304,404,305,405}))
print(select_cards_ex({308,408,108,109,209,309,107,207,106,206},{307,407,107,108,208,308,103,203,109,209}))
print(select_cards_ex({308,408,108,208,209,309,109,409,106,206},{303,403,103,203,105,210,205,310}))
print(select_cards_ex({308,14,15,109,409,106,206},{303,403,103,203,105,210,205,310}))
print(select_cards_ex({308,408,108,208,209,309,14,15},{303,403,103,203,105,210,205,310}))
print(select_cards_ex({308,408,108,208,101,202},{303,404,109,209,309,409}))