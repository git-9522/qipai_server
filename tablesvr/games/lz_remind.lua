local table_insert = table.insert
local table_sort = table.sort

local util = require "util"

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

local BLACK_JOKER_NUMBER = 14
local RED_JOKER_NUMBER = 15
local POWER_MAP = {
    [0] = 0,
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

local function copy_table(tab)
    local new = {}
    for k,v in pairs(tab) do
        new[k] = v
    end
    return new
end

local function get_now_ustime()
    local time4,time5 = util.get_now_time() 
    return time4 * 1000000 + time5
end

local function card_remind(card_suit,last_card_suit,last_type,last_key,laizi)
        local laizi = laizi or 0
        local real_card_number_set = {}
        for _,card_id in pairs(card_suit) do
            local number = extract_card_number(card_id)
            local t = real_card_number_set[number]
            if not t then t = {} real_card_number_set[number] = t end
            table_insert(t,card_id)
        end

        local count_number_map,card_number_set = translate_to_count_number(card_suit)
        for k,v in pairs(count_number_map) do
            table_sort(v,function(a,b) return POWER_MAP[a] < POWER_MAP[b] end)
        end

        local laizi_count = card_number_set[laizi] or 0
        --card_number_set过滤掉癞子
        card_number_set[laizi] = nil
        local remind = {}
        local zhadanwangzha_remind = function()
            --先考虑炸弹
            if count_number_map[4] then
                for k,v in pairs(count_number_map[4]) do
                        local t = {}
                        local card = {}
                        card[v] = 4
                        t.card = card
                        t.power = 10000 + POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_ZHADAN
                        t.key = v
                        table_insert(remind,t)
                end
            end
            --考虑王炸
            if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
                local t = {}
                local card = {}
                card[BLACK_JOKER_NUMBER] = 1
                card[RED_JOKER_NUMBER] = 1
                t.card = card
                t.power = 10000 + POWER_MAP[RED_JOKER_NUMBER]
                t.type = CARD_SUIT_TYPE_WANGZHA
                t.key = RED_JOKER_NUMBER
                table_insert(remind,t)
            end
            --考虑软炸
            local left = 4 - laizi_count
            for i=3,left,-1 do
                local ruanzha_list = count_number_map[i]
                if ruanzha_list then
                    for _,number in ipairs(ruanzha_list) do
                        if number ~= laizi and number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER then
                            local t = {}
                            local card = {}
                            card[number] = i
                            card[laizi] = 4-i
                            t.card = card
                            t.power = 10000 + (4 - i)*1000 + POWER_MAP[number]
                            t.type = CARD_SUIT_TYPE_RUANZHA
                            t.key = number
                            table_insert(remind,t)
                        end
                    end
                end
            end
        end

        local shunzi_remind = function(shun)
            local key_power = POWER_MAP[last_key] + 1
            local shun_count = #last_card_suit / shun

            while CONTINUOUS_CARD_MAP[key_power] do
                --尝试着找一下有没有符合条件的顺牌
                local ret = {}
                local ret_count = 0
                local num = laizi_count
                for i = 1,shun_count do
                    local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
                    local count = card_number_set[number] or 0
                    if count == 0 then
                        num = num - shun
                    elseif count < shun then
                        num = num - (shun - count)
                    end
                    if count > shun then
                        ret[number] = shun
                    else
                        ret[number] = card_number_set[number]
                    end 
                    ret_count = ret_count + 1
                end
                if laizi_count - num > 0 then
                    ret[laizi] = laizi_count - num
                end    
                if ret_count == shun_count and num >= 0 then
                    local t = {}
                    t.card = ret
                    t.power = (laizi_count - num) * 1000 + key_power
                    t.key = CONTINUOUS_CARD_MAP[key_power]
                    if shun == 1 then
                        t.type = CARD_SUIT_TYPE_DANSHUN
                    elseif shun == 2 then
                        t.type = CARD_SUIT_TYPE_SHUANGSHUN
                    elseif shun == 3 then
                        t.type = CARD_SUIT_TYPE_FEIJI
                    end            
                    table_insert(remind,t)   
                end
                --继续往上追溯
                key_power = key_power + 1
            end
        end

        if last_type == CARD_SUIT_TYPE_WANGZHA then
            return {}
        elseif last_type == CARD_SUIT_TYPE_ZHADAN then
            --先考虑炸弹
            if count_number_map[4] then
                for k,v in pairs(count_number_map[4]) do
                    if last_key ~= laizi and (v == laizi or POWER_MAP[v] > POWER_MAP[last_key]) then
                        local t = {}
                        local card = {}
                        card[v] = 4
                        t.card = card
                        t.power = 10000 + POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_ZHADAN
                        t.key = v
                        table_insert(remind,t)
                    end    
                end
            end
            --考虑王炸
            if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
                local t = {}
                local card = {}
                card[BLACK_JOKER_NUMBER] = 1
                card[RED_JOKER_NUMBER] = 1
                t.card = card
                t.power = 10000 + POWER_MAP[RED_JOKER_NUMBER]
                t.type = CARD_SUIT_TYPE_WANGZHA
                t.key = RED_JOKER_NUMBER
                table_insert(remind,t)
            end
        elseif last_type == CARD_SUIT_TYPE_RUANZHA then
            --考虑软炸
            local left = 4 - laizi_count
            for i=3,left,-1 do
                local ruanzha_list = count_number_map[i]
                if ruanzha_list then
                    for _,number in ipairs(ruanzha_list) do
                        if number ~= laizi and number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and 
                        POWER_MAP[last_key] < POWER_MAP[number] then
                            local t = {}
                            local card = {}
                            card[number] = i
                            card[laizi] = 4-i
                            t.card = card
                            t.power = 10000 + (4-i)*1000 + POWER_MAP[number]
                            t.type = CARD_SUIT_TYPE_RUANZHA
                            t.key = number
                            table_insert(remind,t)
                        end
                    end
                end
            end

            if count_number_map[4] then
                for k,v in pairs(count_number_map[4]) do
                        local t = {}
                        local card = {}
                        card[v] = 4
                        t.card = card
                        t.power = 10000 + POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_ZHADAN
                        t.key = v
                        table_insert(remind,t)
                end
            end
            --考虑王炸
            if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
                local t = {}
                local card = {}
                card[BLACK_JOKER_NUMBER] = 1
                card[RED_JOKER_NUMBER] = 1
                t.card = card
                t.power = 10000 + POWER_MAP[RED_JOKER_NUMBER]
                t.type = CARD_SUIT_TYPE_WANGZHA
                t.key = RED_JOKER_NUMBER
                table_insert(remind,t)
            end
        elseif last_type == CARD_SUIT_TYPE_DANPAI then
            if count_number_map[1] then
                for k,v in pairs(count_number_map[1]) do
                    if v ~= laizi and POWER_MAP[v] > POWER_MAP[last_key] then
                        local t = {}
                        local card = {}
                        card[v] = 1
                        t.card = card
                        t.power = POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_DANPAI
                        t.key = v
                        table_insert(remind,t)
                    end 
                end
            end    
            --考虑拆牌的情况
            for k,v in pairs(card_number_set) do
                if v > 1 and POWER_MAP[k] > POWER_MAP[last_key] then
                    local t = {}
                    local card = {}
                    card[k] = 1
                    t.card = card
                    t.power = 100 + POWER_MAP[k]
                    t.type = CARD_SUIT_TYPE_DANPAI
                    t.key = k
                    table_insert(remind,t)
                end
            end
            --考虑癞子
            if laizi_count>1 and POWER_MAP[laizi] > POWER_MAP[last_key] then
                local t = {}
                local card = {}
                card[laizi] = 1
                t.card = card
                t.power = 1000
                t.type = CARD_SUIT_TYPE_DANPAI
                t.key = laizi
                table_insert(remind,t)
            end
            --考虑炸弹
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_DUIPAI then
            if count_number_map[2] then
                for k,v in pairs(count_number_map[2]) do
                    if v ~= laizi and POWER_MAP[v] > POWER_MAP[last_key] then
                        local t = {}
                        local card = {}
                        card[v] = 2
                        t.card = card
                        t.power = POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_DUIPAI
                        t.key = v
                        table_insert(remind,t)
                    end 
                end
            end
            --考虑拆牌的情况
            for k,v in pairs(card_number_set) do
                if v > 2 and POWER_MAP[k] > POWER_MAP[last_key] then
                    local t = {}
                    local card = {}
                    card[k] = 2
                    t.card = card 
                    t.power = 100 + POWER_MAP[k]
                    t.type = CARD_SUIT_TYPE_DUIPAI
                    t.key = k
                    table_insert(remind,t)
                end
            end
 
            --考虑癞子的情况
            for k,v in pairs(card_number_set) do
                if v < 2 and k ~= BLACK_JOKER_NUMBER and k ~= RED_JOKER_NUMBER and laizi_count + v >= 2 and POWER_MAP[k] > POWER_MAP[last_key] then
                    local t = {}
                    local card = {}
                    card[k] = 1
                    card[laizi] = 1
                    t.card = card
                    t.power = 1000 + POWER_MAP[k]
                    t.type = CARD_SUIT_TYPE_DUIPAI
                    t.key = k
                    table_insert(remind,t)
                end
            end

            if laizi_count>2 and POWER_MAP[laizi] > POWER_MAP[last_key] then
                local t = {}
                local card = {}
                card[laizi] = 2
                t.card = card
                t.power = 1000*2
                t.type = CARD_SUIT_TYPE_DUIPAI
                t.key = laizi
                table_insert(remind,t)
            end
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SANZANGPAI then
            if count_number_map[3] then
                for k,v in pairs(count_number_map[3]) do
                    if v ~= laizi and POWER_MAP[v] > POWER_MAP[last_key] then
                        local t = {}
                        local card = {}
                        card[v] = 3
                        t.card = card 
                        t.power = POWER_MAP[v]
                        t.type = CARD_SUIT_TYPE_SANZANGPAI
                        t.key = v
                        table_insert(remind,t)
                    end 
                end
            end
            --考虑拆牌的情况
            for k,v in pairs(card_number_set) do
                if v > 3 and POWER_MAP[k] > POWER_MAP[last_key] then
                    local t = {}
                    local card = {}
                    card[k] = 3
                    t.card = card
                    t.power = 100 + POWER_MAP[k]
                    t.type = CARD_SUIT_TYPE_SANZANGPAI
                    t.key = k
                    table_insert(remind,t)
                end
            end

             --考虑癞子的情况
            for k,v in pairs(card_number_set) do
                if v < 3 and k ~= BLACK_JOKER_NUMBER and k ~= RED_JOKER_NUMBER and laizi_count + v >= 3 and POWER_MAP[k] > POWER_MAP[last_key] then
                    local t = {}
                    local card = {}
                    card[k] = v
                    card[laizi] = 3-v
                    t.card = card
                    t.power = 1000*(3 - v) + POWER_MAP[k]
                    t.type = CARD_SUIT_TYPE_SANZANGPAI
                    t.key = k
                    table_insert(remind,t)
                end
            end

            if laizi_count>3 and POWER_MAP[laizi] > POWER_MAP[last_key] then
                local t = {}
                local card = {}
                card[laizi] = 3
                t.card = card
                t.power = 1000*3
                t.type = CARD_SUIT_TYPE_SANZANGPAI
                t.key = laizi
                table_insert(remind,t)
            end            
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SANDAIYI then
            for number,count in pairs(card_number_set) do
                if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and count + laizi_count >= 3 and POWER_MAP[last_key] < POWER_MAP[number] then
                    local card = {}
                    if count >= 3 then
                        card[number] = 3
                    else 
                        card[number] = count
                        card[laizi] = 3 - count
                    end    
                   
                    local follow = false
                    if count_number_map[1] then
                        for k,v in pairs(count_number_map[1]) do
                            if v ~= laizi and v ~= number then
                                card[v] = 1
                                follow = true
                                break
                            end
                        end
                    end
                    if not follow then
                        for k,v in pairs(card_number_set) do
                            if k ~= number and v > 1 then
                                card[k] = 1
                                follow = true
                                break  
                            end
                        end
                    end
                    if follow then
                        local t = {}
                        t.card = card
                        t.power = (card[laizi] or 0) * 1000 + POWER_MAP[number]
                        t.type = CARD_SUIT_TYPE_SANDAIYI
                        t.key = number
                        table_insert(remind,t)
                    end    
                end
            end
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SANDAIYIDUI then
            for number,count in pairs(card_number_set) do
                if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and count + laizi_count >= 3 and POWER_MAP[last_key] < POWER_MAP[number] then
                    local card = {}
                    if count >= 3 then
                        card[number] = 3
                    else 
                        card[number] = count
                        card[laizi] = 3 - count
                    end    
                    --只要不是joker或与number相同的其它牌都可以出
                    local follow = false
                    if count_number_map[2] then
                        for k,v in pairs(count_number_map[2]) do
                            if v ~= laizi and v ~= number then
                                card[v] = 2
                                follow = true
                                break
                            end
                        end
                    end
                    if not follow then
                        for k,v in pairs(card_number_set) do
                            if k ~= number and k ~= BLACK_JOKER_NUMBER and k~= RED_JOKER_NUMBER then
                                if v > 2 then
                                    card[k] = 2
                                    follow = true
                                    break
                                elseif count < 4 and laizi_count - (3 - count) > 0 then
                                    card[k] = 1
                                    card[laizi] = (card[laizi] or 0) + 1
                                    follow = true
                                    break    
                                end
                            end
                        end
                    end
                    if follow then
                        local t = {}
                        t.card = card
                        t.power = (card[laizi] or 0) * 1000 + POWER_MAP[number]
                        t.type = CARD_SUIT_TYPE_SANDAIYIDUI
                        t.key = number
                        table_insert(remind,t)
                    end    
                end
            end
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SIDAIER then
            for number,count in pairs(card_number_set) do
                if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and count + laizi_count >= 4 and POWER_MAP[last_key] < POWER_MAP[number] then
                    local card = {}
                    if count >= 4 then
                        card[number] = 4
                    else 
                        card[number] = count
                        card[laizi] = 4 - count
                    end    
                   
                    local tmp_count = 0
                    if count_number_map[1] then
                        for k,v in pairs(count_number_map[1]) do
                            if v ~= laizi and v ~= number then
                                card[v] = 1
                                tmp_count = tmp_count + 1  
                            end
                            if tmp_count == 2 then
                                break
                            end  
                        end
                    end
                    if tmp_count < 2 then
                        for k,v in pairs(card_number_set) do
                            if k ~= number and v > 1 then
                                if tmp_count == 1 then 
                                    card[k] = 2-tmp_count
                                    tmp_count = 2
                                    break
                                else
                                    card[k] = 2
                                    tmp_count = 2
                                    break
                                end   
                            end
                        end
                    end
                    if tmp_count == 2 then
                        local t = {}
                        t.card = card
                        t.power = (card[laizi] or 0) * 1000 + POWER_MAP[number]
                        t.type = CARD_SUIT_TYPE_SIDAIER
                        t.key = number
                        table_insert(remind,t)
                    end    
                end
            end
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SIDAILIANGDUI then
            for number,count in pairs(card_number_set) do
                if number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and count + laizi_count >= 4 and POWER_MAP[last_key] < POWER_MAP[number] then
                    local card = {}
                    if count >= 4 then
                        card[number] = 4
                    else 
                        card[number] = count
                        card[laizi] = 4 - count
                    end    
                   
                    local tmp_count = 0
                    if count_number_map[2] then
                        for k,v in pairs(count_number_map[2]) do
                            if v ~= laizi and v ~= number then
                                card[v] = 2
                                tmp_count = tmp_count + 1  
                            end
                            if tmp_count == 2 then
                                break
                            end  
                        end
                    end
                    if tmp_count < 2 then
                        for k,v in pairs(card_number_set) do
                            if k ~= number then
                                if v > 2 then
                                    card[k] = 2
                                    tmp_count = tmp_count + 1
                                elseif v < 2 and laizi_count - (4 - count) >= 1 then
                                    card[k] = 1
                                    card[laizi] = (card[laizi] or 0) + 1
                                    tmp_count = tmp_count + 1
                                end
                                if tmp_count == 2 then
                                    break
                                end    
                            end
                        end
                    end
                    if tmp_count == 2 then
                        local t = {}
                        t.card = card
                        t.power = (card[laizi] or 0) * 1000 + POWER_MAP[number]
                        t.type = CARD_SUIT_TYPE_SIDAILIANGDUI
                        t.key = number
                        table_insert(remind,t)
                    end    
                end
            end
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_DANSHUN then
            shunzi_remind(1)
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_SHUANGSHUN then
            shunzi_remind(2)
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_FEIJI then
            shunzi_remind(3)
            zhadanwangzha_remind()
        elseif last_type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
            local xiaopai_count = 1
            if #last_card_suit % 4 ~= 0 then
                xiaopai_count = 2
            end

            local key_power = POWER_MAP[last_key] + 1
            local shun_count = #last_card_suit / (3 + xiaopai_count)

            while CONTINUOUS_CARD_MAP[key_power] do
                --尝试着找一下有没有符合条件的顺牌
                local ret = {}
                local ret_count = 0
                local num = laizi_count
                local left_card = copy_table(card_number_set)
                for i = 1,shun_count do
                    local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
                    local count = card_number_set[number] or 0
                    if count == 0 then
                        num = num - 3
                    elseif count < 3 then
                        num = num - (3 - count)
                    end
                    if count > 3 then
                        ret[number] = 3
                        left_card[number] = count - 3
                    else
                        ret[number] = card_number_set[number]
                        left_card[number] = nil
                    end 
                    ret_count = ret_count + 1
                end
                if laizi_count - num > 0 then
                    ret[laizi] = laizi_count - num
                    left_card[laizi] = num
                end
                --在剩余的牌中组小牌
                local tmp_count = 0
                if ret_count == shun_count and num >= 0 then
                    for k,v in pairs(left_card) do
                        if xiaopai_count == 1 and k ~= laizi then
                            if tmp_count + v <= shun_count then
                                ret[k] = v
                                tmp_count = tmp_count + v
                            else
                                ret[k] = shun_count - tmp_count
                                tmp_count = shun_count
                            end
                        elseif xiaopai_count == 2 and k ~= laizi then
                            if v >= 2 then
                                ret[k] = 2
                                tmp_count = tmp_count + 1
                            elseif v + num >= 2 then
                                ret[k] = 1
                                ret[laizi] = (ret[laizi] or 0) + 1
                                tmp_count = tmp_count + 1
                            end    
                        end
                        if tmp_count == shun_count then
                            break
                        end            
                    end    
                end
                if tmp_count == shun_count and num >= 0 then
                    local t = {}
                    t.card = ret
                    t.power = (ret[laizi] or 0) * 1000 + key_power
                    t.type = CARD_SUIT_TYPE_FEIJIDAICIBANG
                    t.key = CONTINUOUS_CARD_MAP[key_power]
                    table_insert(remind,t)    
                end
                --继续往上追溯
                key_power = key_power + 1
            end
            zhadanwangzha_remind()            
        end

        local result = {}
        table_sort(remind,function(a,b) return a.power < b.power end)
        for i=1,#remind do
            local cards = {}
            for number,count in pairs(remind[i].card) do
                local card_number_list = assert(real_card_number_set[number],'no such number ' .. tostring(number))
                for i = 1,count do
                    table_insert(cards,assert(card_number_list[i]))
                end
            end
            local t = {}
            t.card_suit = cards
            t.type = remind[i].type
            t.key = remind[i].key
            table_insert(result,t)
        end
        return result
end

local function lz_can_greater_than(card_suit,last_card_suit,last_card_suit_type,last_card_suit_key,laizi)
--    print("key",tostring_r(last_card_suit))
    local laizi = laizi or 0
    local start_time = get_now_ustime()

    --大过上家就行
    local cards_id_list = card_suit

    local card_number_set = {}
    local real_card_number_set = {}
    for _,card_id in pairs(cards_id_list) do
        local number = extract_card_number(card_id)
        card_number_set[number] = (card_number_set[number] or 0) + 1

        local t = real_card_number_set[number]
        if not t then t = {} real_card_number_set[number] = t end
        table_insert(t,card_id)
    end
    local laizi_count = card_number_set[laizi] or 0
    card_number_set[laizi] = nil

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

    local check_shunzi = function(shun)
        local key_power = POWER_MAP[last_card_suit_key] + 1
        local shun_count = #last_card_suit / shun

        while CONTINUOUS_CARD_MAP[key_power] do
            --尝试着找一下有没有符合条件的顺牌
            local ret = {}
            local ret_count = 0
            local num = laizi_count
            for i = 1,shun_count do
 --               print(i,key_power,shun_count)
                local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
 --               print(key_power - i + 1,"ss",number)
                local count = card_number_set[number] or 0
                if count == 0 then
                    num = num - shun
                elseif count < shun then
                    num = num - (shun - count)
                end
                if count > shun then
                    ret[number] = shun
                else
                    ret[number] = card_number_set[number]
                end 
                ret_count = ret_count + 1
            end
            if laizi_count - num > 0 then
                ret[laizi] = laizi_count - num
            end    
            if ret_count == shun_count and num >= 0 then
                return true  
            end
            --继续往上追溯
            key_power = key_power + 1
        end
        return false
    end

    local select_numbers = function()
        if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
            print("can_greater_than111111111111",get_now_ustime() - start_time)
            return true
        end

        if  last_card_suit_type ~= CARD_SUIT_TYPE_ZHADAN and 
            last_card_suit_type ~= CARD_SUIT_TYPE_WANGZHA and 
            last_card_suit_type ~= CARD_SUIT_TYPE_RUANZHA then
            if count_number_map[4] then
                return true
            end

            local left = 4 - laizi_count
            --print("left++++++++++++++++++++++++",left)
            for i=3,left,-1 do
                local ruanzha_list = count_number_map[i]
                if ruanzha_list then
                    for _,number in ipairs(ruanzha_list) do
                        --print("number+++++++++++++++++++++++",number)
                        if number ~= laizi and number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER then
                            return true
                        end
                    end
                end
            end
        end

        if last_card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            local zhadan_list = count_number_map[4] or {}
            for _,number in ipairs(zhadan_list) do
                if POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                   print("can_greater_than2222222222222222222222",get_now_ustime() - start_time)
                    return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_RUANZHA then
            if count_number_map[4] then
                return true
            end
    
            local left = 4 - laizi_count
            for i=3,left,-1 do
                local ruanzha_list = count_number_map[i]
                if ruanzha_list then
                    for _,number in ipairs(ruanzha_list) do
                        if number ~= laizi and number ~= BLACK_JOKER_NUMBER and number ~= RED_JOKER_NUMBER and 
                        POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                            return true
                        end
                    end
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
            for number,count in pairs(card_number_set) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    print("can_greater_than33333333333333333333",get_now_ustime() - start_time)
                    return true
                end
            end
            if laizi_count > 0 and POWER_MAP[last_card_suit_key] < POWER_MAP[laizi] then
                return true
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
            for number,count in pairs(card_number_set) do
                print(count + laizi_count,number,last_card_suit_key)
                if (count + laizi_count) >= 2 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                    print("can_greater_than444444444444444444",get_now_ustime() - start_time)
                    return true
                end
            end
            if laizi_count >= 2 and POWER_MAP[last_card_suit_key] < POWER_MAP[laizi] then
                return true
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
            for number,count in pairs(card_number_set) do
                if count + laizi_count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                    print("can_greater_than55555555555555555555555",get_now_ustime() - start_time)
                    return true
                end
            end
            if laizi_count >= 3 and POWER_MAP[last_card_suit_key] < POWER_MAP[laizi] then
                return true
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
            for number,count in pairs(card_number_set) do
                if count + laizi_count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] 
                   and card_count >= 4 then
                   print("can_greater_than666666666666666666666",get_now_ustime() - start_time)
                   return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
            for number,count in pairs(card_number_set) do
                if count + laizi_count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] 
                   and card_count >= 5 
                   and (count_number_map[2] or laizi_count >= 1) then
                   print("can_greater_than87777777777777777777",get_now_ustime() - start_time)
                   return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANSHUN then
            local ret = check_shunzi(1) 
            print("can_greater_than8888888888888888888888",get_now_ustime() - start_time)
            return ret 
        elseif last_card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
             local ret = check_shunzi(2) 
             print("can_greater_than9999999999999999999999",get_now_ustime() - start_time)
             return ret 
        elseif last_card_suit_type == CARD_SUIT_TYPE_FEIJI then
             local ret = check_shunzi(3) 
             --print("can_greater_than12121212121212121212",get_now_ustime() - start_time)
             return ret  
        end
        --print("can_greater_than13131313131313131313",get_now_ustime() - start_time)
        return false
    end
    return select_numbers()
end

local function can_greater_than(card_suit,last_card_suit,last_card_suit_type,last_card_suit_key)
    local start_time = get_now_ustime()

    --大过上家就行
    local cards_id_list = card_suit

    local card_number_set = {}
    local real_card_number_set = {}
    print("fff",cards_id_list)
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

    local check_shunzi = function(shun)
        local key_power = POWER_MAP[last_card_suit_key] + 1
        local shun_count = #last_card_suit / shun

        while CONTINUOUS_CARD_MAP[key_power] do
            --尝试着找一下有没有符合条件的顺牌
            local ret_count = 0
            for i = 1,shun_count do
                local number = CONTINUOUS_CARD_MAP[key_power - i + 1]
                local count = card_number_set[number]
                if not count or count < shun then
                    break
                end
                ret_count = ret_count + 1
            end
            if ret_count == shun_count then
                return true
            end
            --继续往上追溯
            key_power = key_power + 1
        end
        return false
    end

    local select_numbers = function()
        if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
            print("can_greater_than111111111111",get_now_ustime() - start_time)
            return true
        end

        if last_card_suit_type ~= CARD_SUIT_TYPE_ZHADAN and 
           last_card_suit_type ~= CARD_SUIT_TYPE_WANGZHA then
           if count_number_map[4] then
              return true
           end
        end

        if last_card_suit_type == CARD_SUIT_TYPE_ZHADAN then
            local zhadan_list = count_number_map[4] or {}
            for _,number in ipairs(zhadan_list) do
                if POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                   print("can_greater_than2222222222222222222222",get_now_ustime() - start_time)
                    return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANPAI then
            for number,count in pairs(card_number_set) do
                if POWER_MAP[last_card_suit_key] < POWER_MAP[number] then
                    print("can_greater_than33333333333333333333",get_now_ustime() - start_time)
                    return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DUIPAI then
            for number,count in pairs(card_number_set) do
                if count >= 2 and POWER_MAP[number] > POWER_MAP[last_card_suit_key]then
                    print("can_greater_than444444444444444444",get_now_ustime() - start_time)
                    return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANZANGPAI then
            for number,count in pairs(card_number_set) do
                if count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] then
                    print("can_greater_than55555555555555555555555",get_now_ustime() - start_time)
                    return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYI then
            for number,count in pairs(card_number_set) do
                if count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] 
                   and count_number_map[1] then
                   print("can_greater_than666666666666666666666",get_now_ustime() - start_time)
                   return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_SANDAIYIDUI then
            for number,count in pairs(card_number_set) do
                if count >= 3 and POWER_MAP[number] > POWER_MAP[last_card_suit_key] 
                   and count_number_map[2] then
                   print("can_greater_than87777777777777777777",get_now_ustime() - start_time)
                   return true
                end
            end
        elseif last_card_suit_type == CARD_SUIT_TYPE_DANSHUN then
            local ret = check_shunzi(1) 
            print("can_greater_than8888888888888888888888",get_now_ustime() - start_time)
            return ret 
        elseif last_card_suit_type == CARD_SUIT_TYPE_SHUANGSHUN then
             local ret = check_shunzi(2) 
             print("can_greater_than9999999999999999999999",get_now_ustime() - start_time)
             return ret 
        elseif last_card_suit_type == CARD_SUIT_TYPE_FEIJI then
             local ret = check_shunzi(3) 
             --print("can_greater_than12121212121212121212",get_now_ustime() - start_time)
             return ret  
        end
        --print("can_greater_than13131313131313131313",get_now_ustime() - start_time)
        return false
    end
    return select_numbers()
end

local M ={}
M.card_remind = card_remind
M.can_greater_than = can_greater_than
M.lz_can_greater_than = lz_can_greater_than
return M