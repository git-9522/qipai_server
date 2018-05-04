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

local table_insert = table.insert
local table_remove = table.remove
local math_floor = math.floor
local table_sort = table.sort

local M = {}

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

local function get_tablecount(tab)
    local count = 0
    if not tab then
        return count
    end 
    for k,v in pairs(tab) do
        count = count + v
    end
    return count
end

--检查tab是不是全部可以组成对子
local function check_duizi(tab,laizi_num)
    if tab[BLACK_JOKER_NUMBER] or tab[RED_JOKER_NUMBER] then
        return false
    end
    local count = get_tablecount(tab)
    if (count + laizi_num)%2 ~= 0 then
        return false
    end

    for k,v in pairs(tab) do
        if v%2 ~= 0 then
            laizi_num = laizi_num - 1
        end
    end
    if laizi_num < 0 then
        return false
    end
    return true
end

local function copy_table(tab)
    local new = {}
    for k,v in pairs(tab) do
        new[k] = v
    end
    return new
end

local function check_danshun(card_number_set,card_count,laizi)
    local cards_type = {}

    if card_count < 5 then
        return false
    end
    --保存除去癞子的power        
    local power_list = {}
    if card_number_set then
        for k,v in pairs(card_number_set) do
            if k ~= laizi then
                if v > 1 then
                    return false
                end
                table_insert(power_list,POWER_MAP[k])
            end
        end
    end

    table_sort(power_list)
    local laizi_count = card_number_set[laizi] or 0

    local n = power_list[1]
    local max = power_list[#power_list]

    local i = 1
    while i <= #power_list do
        local power = power_list[i]
        local next_power = n + i - 1
        if next_power > POWER_MAP[1] then
            return false
        elseif power ~= next_power then
            n = n + 1
            laizi_count = laizi_count - 1
        else
            i = i + 1
        end
    end

    if laizi_count < 0 then
        return false
    end

    for i=0,laizi_count do
        if max + i < POWER_MAP[2] and power_list[1] - (laizi_count-i) >= POWER_MAP[3] then
            local card = {}
            card[CARD_SUIT_TYPE_DANSHUN] = CONTINUOUS_CARD_MAP[max + i]
            table_insert(cards_type,card)
        end
    end

    return cards_type
end

local function check_shuangshun(card_number_set,card_count,laizi)
    if card_count%2 ~= 0 or card_count < 6 then
        return false
    end
    
    local length = math_floor(card_count/2)

    --保持除去癞子的power
    local power_list = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            if v > 2 then
                return false
            end
            table_insert(power_list,POWER_MAP[k])
        end    
    end
    if #power_list > length then
        return false
    end

    table_sort(power_list)
    local n = power_list[1]
    local i = 1
    local laizi_count = card_number_set[laizi] or 0
    while i <= #power_list do
        local power = power_list[i]
        local next_power = n + i - 1
        if power > POWER_MAP[1] then
            return false
        elseif power ~= next_power then
            laizi_count = laizi_count - 2
            n = n + 1
        elseif power == next_power then
            if card_number_set[CONTINUOUS_CARD_MAP[power]] == 1 then
                laizi_count = laizi_count-1
            end
            i = i + 1    
        end
    end 

    if laizi_count < 0 then
        return false
    end

    local cards_type = {}
    local len = math_floor(laizi_count / 2)
    local max = power_list[#power_list]
    local min = power_list[1]
    for i=0,len do
        if max + i < POWER_MAP[2] and min - (len-i) >= POWER_MAP[3] then
            local card = {}
            card[CARD_SUIT_TYPE_SHUANGSHUN] = CONTINUOUS_CARD_MAP[max + i]
            table_insert(cards_type,card)
        end
    end
    return cards_type
end

local function check_sanzhang(count_number_map,laizi)
    if count_number_map[3] then
        return count_number_map[3][1]
    end

    --两张癞子一张单牌和一张癞子两张单排的情况也可以是3张
    if count_number_map[2][1] == laizi then
        return count_number_map[1][1]
    elseif count_number_map[1][1] == laizi and count_number_map[2] then
        return count_number_map[2][1]
    end

    return false
end 

local function check_sandaiyidui(card_number_set,card_count,laizi)
    local cards_type = {}
    if card_count ~= 5 then
        return false
    end

    if card_number_set[BLACK_JOKER_NUMBER] or card_number_set[RED_JOKER_NUMBER] then
        return false
    end

    --过滤癞子
    local new_cards = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            new_cards[k] = v
        end
    end
    
    for k,v in pairs(new_cards) do
        local laizi_count = card_number_set[laizi] or 0
        local number = v + laizi_count
        local left_cards = copy_table(new_cards)
        if number >= 3 then
            if v <= 3 then
                left_cards[k] = nil
                laizi_count = laizi_count - (3 - v)
            else
                left_cards[k] = v - 3
            end    
                
            if check_duizi(left_cards,laizi_count) then
                local t = {}
                t[CARD_SUIT_TYPE_SANDAIYIDUI] = k
                table_insert(cards_type,t)
            end 
        end
    end

    --有3个癞子以上的情况
    local laizi_count = card_number_set[laizi] or 0
    if laizi_count >= 3 and check_duizi(new_cards,laizi_count-3) then
        local t = {}
        t[CARD_SUIT_TYPE_SANDAIYIDUI] = laizi
        table_insert(cards_type,t)
    end
    return cards_type
end

local function check_sidaier(card_number_set,card_count,laizi)
    if card_count ~= 6 then
        return false
    end

    local cards_type = {}
    if card_count ~= 6 then
        return false
    end

    --过滤癞子
    local new_cards = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            new_cards[k] = v
        end
    end

    local laizi_count = card_number_set[laizi] or 0
    for k,v in pairs(new_cards) do
        local number = v + laizi_count
        if number >= 4 and k ~= BLACK_JOKER_NUMBER and k ~= RED_JOKER_NUMBER then
            local t = {}
            t[CARD_SUIT_TYPE_SIDAIER] = k
            table_insert(cards_type,t)   
        end
    end

    return cards_type
end

local function check_sidailiangdui(card_number_set,card_count,laizi)
    local result = {}
    if card_count ~= 8 then
        return false
    end

    if card_number_set[BLACK_JOKER_NUMBER] or card_number_set[RED_JOKER_NUMBER] then
        return false
    end

    local left_cards = {}
    --过滤癞子
    local new_cards = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            new_cards[k] = v
        end
    end

    for k,v in pairs(new_cards) do
        local left_cards = copy_table(new_cards)
        local laizi_count = card_number_set[laizi] or 0
        local number = v + laizi_count
        if number >= 4 then
            left_cards[k] = nil
            laizi_count = laizi_count - (4 - v)
            if laizi_count > 0 or check_duizi(left_cards,laizi_count) then
                local t = {}
                t[CARD_SUIT_TYPE_SIDAILIANGDUI] = k
                table_insert(result,t)
            end     
        end
    end

    --有四个癞子的情况并且剩余的牌全部可以组成对子
    if card_number_set[laizi] == 4 and check_duizi(new_cards,0) then
        local t = {}
        t[CARD_SUIT_TYPE_SIDAILIANGDUI] = laizi
        table_insert(result,t)
    end

    return result
end

local function check_feijidaicibang(card_number_set,card_count,laizi)
    if card_count < 8 then
        return false
    end

    local result = {}
    
    --先去掉癞子
    local new_cards = {}
    local power_list = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            new_cards[k] = v
            table_insert(power_list,POWER_MAP[k])
        end
    end

    --对所有牌按大小排序
    table.sort(power_list)

    for i=1,#power_list do
        if power_list[i] > POWER_MAP[1] then  --如果飞机起始值大于14直接跳出循环
            break
        end
        local j=i
        local left_cards = copy_table(new_cards)
        for k,v in pairs(left_cards) do
            print(k,v)
        end
        local laizi_count = card_number_set[laizi] or 0
        local next_power = power_list[i]
        local length = 0    --飞机长度
        while j <= #power_list do  
            power = power_list[j]
            if power > POWER_MAP[1] then
                break
            elseif power ~= next_power then
                laizi_count = laizi_count - 3
            elseif power == next_power then
                local count = card_number_set[CONTINUOUS_CARD_MAP[power]]
                if count <= 3 then
                    laizi_count = laizi_count - (3 - count)
                    left_cards[CONTINUOUS_CARD_MAP[power]] = nil
                else
                    left_cards[CONTINUOUS_CARD_MAP[power]] = left_cards[CONTINUOUS_CARD_MAP[power]] - 3
                end    
                j = j + 1    
            end

            if laizi_count < 0 then
                break
            end
            length = length + 1
            --判断是否满足牌型
            local left_count = get_tablecount(left_cards)
            print("++++++++++++++++++++++++left_count,laizi_count",left_count,laizi_count,length)
            --如果剩下的牌有3个癞子的情况
            if laizi_count == 3 and (left_count == length + 1 or (left_count == 2*(length+1) and check_duizi(left_cards,laizi_count))) then
                local s = length + 1
                local v = power + 1
                if v < POWER_MAP[2] then
                    result[v] = true
                end
                if power_list[1] > POWER_MAP[3] then
                    result[power] = true
                end
                break
            elseif length >= 2 then
                if left_count + laizi_count == length then    --剩余牌的数量等于飞机长度
                    result[power] = true
                elseif left_count + laizi_count == 2*length then
                    --判断剩余的牌能不能全部组成对子
                    if check_duizi(left_cards,laizi_count) then
                        result[power] = true
                    end         
                end             
            end
            next_power = next_power + 1 
        end
    end
    local p = {}
    for k,v in pairs(result) do
        local t = {}
        t[CARD_SUIT_TYPE_FEIJIDAICIBANG] = CONTINUOUS_CARD_MAP[k]
        table_insert(p,t)
    end

    return p 
end

local function check_feiji(card_number_set,card_count,laizi)
    if card_count < 6 or card_count%3 ~= 0 then
        return false
    end
    local cards_type = {}

    --先去掉癞子
    local new_cards = {}
    local power_list = {}
    for k,v in pairs(card_number_set) do
        if k ~= laizi then
            if v > 3 then
                return false
            end
            new_cards[k] = v
            table_insert(power_list,POWER_MAP[k])
        end
    end

    --对所有牌按大小排序
    table.sort(power_list)
    
    local laizi_count = card_number_set[laizi] or 0
    local next_power = power_list[1]
    local i=1
    while i <= #power_list do
        power = power_list[i]
        if power > POWER_MAP[1] then
            return false
        elseif power ~= next_power then
            laizi_count = laizi_count - 3
        elseif power == next_power then
            local count = card_number_set[CONTINUOUS_CARD_MAP[power]]
            laizi_count = laizi_count - (3 - count)
  
            i = i + 1    
        end
        next_power = next_power + 1 
    end
    if laizi_count < 0 then
        return false
    end

    local len = math_floor(laizi_count / 3)
    local max = power_list[#power_list]
    local min = power_list[1]
    for i=0,len do
        if max + i < POWER_MAP[2] and min - (len - i) >= POWER_MAP[3] then
            local card = {}
            card[CARD_SUIT_TYPE_FEIJI] = CONTINUOUS_CARD_MAP[max + i]
            table_insert(cards_type,card)
        end
    end
    return cards_type
end

--[[
params:card_number_set 是一个由[牌号->张数]组成的一个数组
return:{牌型:{关键值}}   

]]
local function get_card_suit_type(card_number_set,laizi)
    local card_count = 0
    local count_number_map = {}
    local card_suit_type = {}
    local laizi_count = card_number_set[laizi] or 0

    for number,count in pairs(card_number_set) do
        local t = count_number_map[count]
        if not t then 
            t = {}
            count_number_map[count] = t
        end
        table_insert(t,number)
        card_count = card_count + count
    end
    --非癞子的张数
    local nlz_count = card_count - laizi_count  

    --单牌
    if card_count == 1 then
        local card = {}
        card[CARD_SUIT_TYPE_DANPAI] = count_number_map[1][1]
        table_insert(card_suit_type,card)
        return card_suit_type
    --两张牌
    elseif card_count == 2 then
        if card_number_set[BLACK_JOKER_NUMBER] and card_number_set[RED_JOKER_NUMBER] then
            local card = {}
            card[CARD_SUIT_TYPE_WANGZHA] = RED_JOKER_NUMBER
            table_insert(card_suit_type,card)
        elseif card_number_set[BLACK_JOKER_NUMBER] or card_number_set[RED_JOKER_NUMBER] then
            return
        else
            if count_number_map[2] then
                local card = {}
                card[CARD_SUIT_TYPE_DUIPAI] = count_number_map[2][1]
                table_insert(card_suit_type,card)
            else
                for k,v in pairs(card_number_set) do
                    if laizi_count + v >= 2 and k ~= laizi then
                        local card = {}
                        card[CARD_SUIT_TYPE_DUIPAI] = k
                        table_insert(card_suit_type,card)
                    end
                end
            end
        end
        return card_suit_type
    --三张牌    
    elseif card_count == 3 then
        if card_number_set[BLACK_JOKER_NUMBER] or card_number_set[RED_JOKER_NUMBER] then
            return
        end
        local key = check_sanzhang(count_number_map,laizi)
        if key then
            local card = {}
            card[CARD_SUIT_TYPE_SANZANGPAI] = key
            table_insert(card_suit_type,card)
        end
        return card_suit_type
    elseif card_count == 4 then
        --四张牌可能是炸弹、软炸、三带一
        if count_number_map[4] then
            local card = {}
            card[CARD_SUIT_TYPE_ZHADAN] = count_number_map[4][1]
            table_insert(card_suit_type,card)
            return card_suit_type
        --软炸
        elseif count_number_map[nlz_count] then
            for k,v in pairs(count_number_map[nlz_count]) do
                if v ~= laizi and v ~= BLACK_JOKER_NUMBER and v ~= RED_JOKER_NUMBER then
                    local card = {}
                    card[CARD_SUIT_TYPE_RUANZHA] = v
                    table_insert(card_suit_type,card)
                end
            end
        end
        
        --三带一
        for k,v in pairs(card_number_set) do
            if (v + laizi_count >=3 and k ~= laizi and k ~= BLACK_JOKER_NUMBER and k ~= RED_JOKER_NUMBER) or
                (k == laizi and v == 3) then
                local card = {}
                card[CARD_SUIT_TYPE_SANDAIYI] = k
                table_insert(card_suit_type,card)
            end
        end
    end

    --五张牌以上的情况有可能是三带一对，单顺，双顺，飞机，四带二

    --四带二
    local cards = check_sidaier(card_number_set,card_count,laizi)
    if cards then
    for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end
    end  

    --单顺
    local cards = check_danshun(card_number_set,card_count,laizi)
    if cards then
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end
    end 

    --双顺
   local cards = check_shuangshun(card_number_set,card_count,laizi)
    if cards then 
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end
    end

    --三带一对
    local cards = check_sandaiyidui(card_number_set,card_count,laizi)
    if cards then
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end
    end

    --四带两对
    local cards = check_sidailiangdui(card_number_set,card_count,laizi)
    if cards then
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end
    end
    --飞机
    local cards = check_feiji(card_number_set,card_count,laizi)
    if cards then
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end     
    end

    local cards = check_feijidaicibang(card_number_set,card_count,laizi)
    if cards then
        for i,card in ipairs(cards) do
            table_insert(card_suit_type,card)
        end 
    end

    return card_suit_type
end
M.get_card_suit_type = get_card_suit_type

--根据牌的类型匹配相应的牌
local function match_cards(card_suit,laizi)
    local count_number_map,card_number_set = translate_to_count_number(card_suit)
    local card_suit_type = get_card_suit_type(card_number_set,laizi)
    for k,v in pairs(card_suit_type) do
        for s,d in pairs(v) do
            print("==========================",s,d)
        end
    end
    if #card_suit_type == 0 then
        return false
    end
    local result = {}
    local to_duizi = function(card,new_cards)
        local _,card_number_set = translate_to_count_number(new_cards)
        for number,count in pairs(card_number_set) do
            if number ~= laizi and count%2 ~= 0 then
                table_insert(card,500+number)
                local i = 1
                while new_cards[i] do
                    if new_cards[i] % 100 == laizi then
                        table_remove(new_cards,i)
                    else
                        i = i + 1
                    end
                end
            end
        end
        --剩余的直接插入
        for idx,card_id in pairs(new_cards) do
            table_insert(card,card_id)
        end
    end

    local to_shunzi = function(card,new_cards,shun,key)
            local length = #new_cards / shun
            local left_power = POWER_MAP[key] - length + 1
            for i=left_power,POWER_MAP[key] do
                local tmp_count = 0
                local j = 1 
                while new_cards[j] do
                    print(new_cards[j],CONTINUOUS_CARD_MAP[i])
                    if new_cards[j] % 100 == CONTINUOUS_CARD_MAP[i] then
                        table_insert(card,new_cards[j])
                        table_remove(new_cards,j)
                        --j = j - 1
                        tmp_count = tmp_count + 1
                        if tmp_count == shun then
                            break
                        end
                    else
                        j = j + 1        
                    end
                end
                --插入count个癞子
                if shun > tmp_count then
                    local count = shun-tmp_count
                    for n=1,count do
                        table_insert(card,500 + CONTINUOUS_CARD_MAP[i])
                    end
                    while count > 0 do
                        local j = 1
                        while new_cards[j] do
                            if new_cards[j] % 100 == laizi then
                                table_remove(new_cards,j)
                                count = count - 1
                                break
                            else
                                j = j + 1    
                            end
                        end
                    end
                end    
            end        
    end

    for _,card_obj in ipairs(card_suit_type) do
        local new_cards = copy_table(card_suit)
        for type,key in pairs(card_obj) do
            local t = {}
            t.type = type
            t.key = key
            local card = {}
            if type == CARD_SUIT_TYPE_WANGZHA then
                table_insert(card,BLACK_JOKER_NUMBER)
                table_insert(card,RED_JOKER_NUMBER)
            elseif type == CARD_SUIT_TYPE_ZHADAN or type == CARD_SUIT_TYPE_DANPAI then
                for _,card_id in pairs(new_cards) do
                    table_insert(card,card_id)
                end
            elseif type == CARD_SUIT_TYPE_DUIPAI or type == CARD_SUIT_TYPE_SANZANGPAI or type == CARD_SUIT_TYPE_RUANZHA then
                for _,card_id in pairs(new_cards) do
                    if card_id % 100 == key then
                        table_insert(card,card_id)
                    else
                        table_insert(card,500 + key)    
                    end
                end
            elseif type == CARD_SUIT_TYPE_SANDAIYI then
                local tmp_count = 0
                local i = 1
                while new_cards[i] do
                    if new_cards[i] % 100 == key then
                        table_insert(card,new_cards[i])
                        tmp_count = tmp_count + 1
                        table_remove(new_cards,i)
                    else
                        i = i + 1    
                    end
                end
                --如果没有3个数用癞子补齐
                if tmp_count < 3 then
                    i = 1
                    while new_cards[i] do
                        if new_cards[i] % 100 == laizi then
                            table_insert(card,500+key)
                            tmp_count = tmp_count + 1
                            table_remove(new_cards,i)
                            if tmp_count == 3 then
                                break
                            end
                        else
                            i = i + 1    
                        end
                    end
                end
                --最后一张牌直接插入
                for idx,card_id in pairs(new_cards) do
                    table_insert(card,card_id)
                end
            elseif type == CARD_SUIT_TYPE_SANDAIYIDUI then
                local tmp_count = 0
                local i = 1
                while new_cards[i] do
                    if new_cards[i] % 100 == key then
                        table_insert(card,new_cards[i])
                        tmp_count = tmp_count + 1
                        table_remove(new_cards,i)
                    else
                        i = i + 1    
                    end
                end
                --如果没有3个数用癞子补齐
                if tmp_count < 3 then
                    i = 1
                    while new_cards[i] do
                        if new_cards[i] % 100 == laizi then
                            table_insert(card,500+key)
                            tmp_count = tmp_count + 1
                            table_remove(new_cards,i)
                            if tmp_count == 3 then
                                break
                            end
                        else
                            i = i + 1    
                        end
                    end
                end

                --最后两张牌
                to_duizi(card,new_cards)
            elseif type == CARD_SUIT_TYPE_SIDAIER then
                local tmp_count = 0
                local i = 1
                while new_cards[i] do
                    if new_cards[i] % 100 == key then
                        table_insert(card,new_cards[i])
                        tmp_count = tmp_count + 1
                        table_remove(new_cards,i)
                    else
                        i = i + 1    
                    end
                end
                --如果没有4个数用癞子补齐
                if tmp_count < 4 then
                    local i = 1
                    while new_cards[i] do
                        if new_cards[i] % 100 == laizi then
                            table_insert(card,500+key)
                            tmp_count = tmp_count + 1
                            table_remove(new_cards,i)
                            if tmp_count == 4 then
                                break
                            end
                        else
                            i = i + 1    
                        end
                    end
                end
                --最后两张牌直接插入
                for idx,card_id in pairs(new_cards) do
                    table_insert(card,card_id)
                end
            elseif type == CARD_SUIT_TYPE_SIDAILIANGDUI then
                local tmp_count = 0
                local i = 1
                while new_cards[i] do
                    if new_cards[i] % 100 == key then
                        table_insert(card,new_cards[i])
                        tmp_count = tmp_count + 1
                        table_remove(new_cards,i)
                    else
                        i = i + 1    
                    end
                end
                --如果没有4个数用癞子补齐
                if tmp_count < 4 then
                    i = 1
                    while new_cards[i] do
                        if new_cards[i] % 100 == laizi then
                            table_insert(card,500+key)
                            tmp_count = tmp_count + 1
                            table_remove(new_cards,i)
                            if tmp_count == 4 then
                                break
                            end
                        else
                            i = i + 1    
                        end
                    end
                end
                --最后四张牌组成两对,先获取k值
                to_duizi(card,new_cards)
            elseif type == CARD_SUIT_TYPE_DANSHUN then
                print("----------------------",type,key)
                local left_power = POWER_MAP[key] - #new_cards + 1
                for i=left_power,POWER_MAP[key] do
                    local find = false
                    for idx,card_id in pairs(new_cards) do
                        if card_id % 100 == CONTINUOUS_CARD_MAP[i] then
                            table_insert(card,card_id)
                            table_remove(new_cards,idx)
                            find = true
                            break
                        end
                    end
                    if not find then
                        --没有找到则插入一个癞子

                        table_insert(card,500+CONTINUOUS_CARD_MAP[i])
                        for idx,card_id in pairs(new_cards) do
                            if card_id % 100 == laizi then
                                table_remove(new_cards,idx)
                                break
                            end
                        end
                    end
                end
            elseif type == CARD_SUIT_TYPE_SHUANGSHUN then
                to_shunzi(card,new_cards,2,key)
            elseif type == CARD_SUIT_TYPE_FEIJI then
                to_shunzi(card,new_cards,3,key)
            elseif type == CARD_SUIT_TYPE_FEIJIDAICIBANG then
                local xiaopai_count = 1
                if #new_cards % 4 ~= 0 then
                    xiaopai_count = 2
                end

                local length = #new_cards / ( 3 + xiaopai_count )
                local left_power = POWER_MAP[key] - length + 1
                for i=left_power,POWER_MAP[key] do
                    local tmp_count = 0
                    local j = 1
                    while new_cards[j] do
                        if new_cards[j] % 100 == CONTINUOUS_CARD_MAP[i] then
                            table_insert(card,new_cards[j])
                            table_remove(new_cards,j)
                            tmp_count = tmp_count + 1
                            print("tmp_count",tmp_count)
                            if tmp_count == 3 then
                                break
                            end
                        else
                            j = j + 1        
                        end
                    end
                    --插入count个癞子
                    --print("++++++++++++++++++++++++tmp_count",tmp_count)
                    local count = 3-tmp_count
                    for n=1,count do
                        table_insert(card,500 + CONTINUOUS_CARD_MAP[i])
                    end
                    print("new_cards_length",#new_cards)
                    while count > 0 do
                        j = 1
                        while new_cards[j] do
                            if new_cards[j] % 100 == laizi then
                                table_remove(new_cards,j)
                                count = count - 1
                                break
                            else
                                j = j + 1    
                            end
                        end
                    end
                end
                if xiaopai_count == 1 then
                    for idx,card_id in pairs(new_cards) do
                        table_insert(card,card_id)
                    end
                elseif xiaopai_count == 2 then
                    to_duizi(card,new_cards)
                end    
            end
            t.card = card
            table_insert(result,t)
        end
    end
    return result
end    

M.match_cards = match_cards

return M