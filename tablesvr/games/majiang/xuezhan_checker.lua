
local table_insert = table.insert
local table_sort = table.sort
local table_remove = table.remove
local table_concat = table.concat

local string_format = string.format
local math_floor = math.floor
local tostring = tostring
local tonumber = tonumber


---------------------------牌型定义-----------------------------
local HU_PINGHU         = 1     --平胡
local HU_DUIDUIHU       = 2     --对对胡
local HU_QINGYISE       = 3     --清一色
local HU_DAIYAOJIU      = 4     --带幺九
local HU_QIDUI          = 5     --七对
local HU_JINGOUDIAO     = 6     --金钩钓
local HU_QINGDADUI      = 7     --清大对
local HU_JIANGDUI       = 8     --将对
local HU_LONGQIDUI      = 9     --龙七对
local HU_QINGQIDUI      = 10     --清七对
local HU_QINGYAOJIU     = 11     --清幺九
local HU_JIANGJINGOUDIAO    = 12     --将金钩钓
local HU_QINGJINGOUDIAO     = 13     --清金钩钓
local HU_QINGLONGQIDUI      = 14     --清龙七对
local HU_SHIBALUOHAN        = 15     --十八罗汉
local HU_QINGSHIBALUOHAN    = 16     --清十八罗汉
local HU_TIANHU             = 17     --天胡
local HU_DIHU               = 18     --地胡

---------------------------番数定义-----------------------------
local FANSHU_DEF = {
    [HU_PINGHU ] = 1,
    [HU_DUIDUIHU ] = 2,
    [HU_QINGYISE ] = 3,
    [HU_DAIYAOJIU] = 3,
    [HU_QIDUI] = 3,
    [HU_JINGOUDIAO ] = 3,
    [HU_QINGDADUI] = 4,
    [HU_JIANGDUI ] = 4,
    [HU_LONGQIDUI] = 4,
    [HU_QINGQIDUI] = 5,
    [HU_QINGYAOJIU] = 5,
    [HU_JIANGJINGOUDIAO] = 5,
    [HU_QINGJINGOUDIAO] = 5,
    [HU_QINGLONGQIDUI] = 6,
    [HU_SHIBALUOHAN] = 7,
    [HU_QINGSHIBALUOHAN] = 9,
    [HU_TIANHU] = 6,
    [HU_DIHU] = 6,
}

--[[
    麻将牌定义:
        11-19   万
        21-29   筒
        31-39   索
]]
local ALL_TILES = {}
for i = 1,3 do
    for j = 1,9 do
        ALL_TILES[i*10+j] = true
    end
end

local function check_qidui(tile_count_map,gangpeng_map)
    if gangpeng_map and next(gangpeng_map) then
        --只要有过杠碰，就不会是这种牌型
        return
    end
    local qidui = true
    for tile,count in pairs(tile_count_map) do
        if count ~= 2 and count ~= 4 then
            qidui = false
            break
        end
    end

    if not qidui then return end

    local r = {}
    for tile,count in pairs(tile_count_map) do
        r[#r + 1] = tile * 100 + count
    end 
    return '=' .. table_concat(r,'=')
end

local function find_the_minimal(tile_count_map)
    local min = next(tile_count_map)

    for tile in pairs(tile_count_map) do
        if tile < min then
            min = tile
        end
    end

    return min,tile_count_map[min]
end

local function reduce_tiles(tile_count_map,del_map)
    local new_tile_count_map = {}
    for tile,count in pairs(tile_count_map) do
        if not del_map[tile] then
            new_tile_count_map[tile] = count
        else
            local remaining = count - del_map[tile]
            assert(remaining >= 0,string_format('[%d] = %d,del=%d',tile,remaining,del_map[tile]))
            if remaining > 0 then
                new_tile_count_map[tile] = remaining
            end
        end
    end

    return new_tile_count_map
end

local function check_pinghu(result,result_list,tile_count_map)
    if not next(tile_count_map) then
        --没牌再看看有没有将，有的话则是胡牌
        if result:find('#') then
            result_list[#result_list + 1] = result
        end
        return
    end

    local tile,count = assert(find_the_minimal(tile_count_map))

    if tile_count_map[tile + 1] and tile_count_map[tile + 2] then
        --单张可以组成顺子，则继续往下
        local r = (tile * 10000 + (tile + 1) * 100 + (tile + 2))
        check_pinghu(result .. '+' .. r,result_list,reduce_tiles(tile_count_map,{
            [tile] = 1,
            [tile + 1] = 1,
            [tile + 2] = 1,
        }))
    end

    if count >= 2 then
        if not result:find('#') then
            --有可能这个牌可以组成一个<将>
            check_pinghu(result .. '#' .. tile,result_list,reduce_tiles(tile_count_map,{[tile] = 2}))
        end
    end

    if count >= 3 then
        check_pinghu(result ..'*'.. (tile * 100 + 3),result_list,
            reduce_tiles(tile_count_map,{[tile] = 3}))
    end

    --[[
    if count >= 4 then
        check_pinghu(result ..'*'.. (tile * 100 + 4),result_list,
            reduce_tiles(tile_count_map,{[tile] = 4}))
    end]]
end

local function check_hupai(tile_list,que,gangpeng_map)
    --如果有定缺的牌，则不可能有胡牌
    local tile_count_map = {}
    local has_quepai
    for _,tile in ipairs(tile_list) do
        tile_count_map[tile] = (tile_count_map[tile] or 0) + 1
        if math_floor(tile/10) == que then  
            --如果有缺牌直接返回 
            return
        end 
    end

    --先过滤[七对]
    local result_list = {}

    local hupai = check_qidui(tile_count_map,gangpeng_map)
    if hupai then 
        result_list[#result_list + 1] = hupai
    end

    check_pinghu('',result_list,tile_count_map)

    return result_list
end


local function next_tingpai(result,result_list,ting_tile,tile_count_map)
    if not next(tile_count_map) then
        --没牌再看看有没有将，有的话则是胡牌
        if result:find('#') then
            result_list[#result_list + 1] = result .. '-' .. ting_tile
        end
        return
    end

    local tile,count = assert(find_the_minimal(tile_count_map))

    if tile_count_map[tile + 1] and tile_count_map[tile + 2] then
        --单张可以组成顺子，则继续往下
        local r = (tile * 10000 + (tile + 1) * 100 + (tile + 2))
        next_tingpai(result .. '+' .. r,result_list,ting_tile,reduce_tiles(tile_count_map,{
            [tile] = 1,
            [tile + 1] = 1,
            [tile + 2] = 1,
        }))
    elseif not ting_tile then
        local ting_tile_list = {}
        if ALL_TILES[tile - 1] and tile_count_map[tile + 1] then 
            local tmp_ting = tile - 1
            ting_tile_list[#ting_tile_list + 1] = (tmp_ting << 12 | tile << 6 | (tile + 1)) << 6 | tmp_ting
        end
        if not tile_count_map[tile + 1] and tile_count_map[tile + 2] then
            local tmp_ting = tile + 1
            ting_tile_list[#ting_tile_list + 1] = (tile << 12 | tmp_ting << 6 | (tile + 2)) << 6 | tmp_ting
        end
        if tile_count_map[tile + 1] and ALL_TILES[tile + 2] then
            local tmp_ting = tile + 2
            ting_tile_list[#ting_tile_list + 1] = (tile << 12 | (tile + 1) << 6 | tmp_ting) << 6 | tmp_ting
        end

        for _,t in ipairs(ting_tile_list) do
            local r = t >> 6
            local tmp_ting = t & 63
            local t1,t2,t3 = r & 63,(r >> 6) & 63,(r >> 12) & 63
            local del_map = {[t1] = 1,[t2] = 1,[t3] = 1}

            del_map[tmp_ting] = nil
            
            local r = t3 * 10000 + t2 * 100 + t1
            next_tingpai(result .. '+' .. r,result_list,tmp_ting,
                reduce_tiles(tile_count_map,del_map))
        end
    end

    if count >= 2 and not result:find('#') then
        --有可能这个牌可以组成一个<将>
        next_tingpai(result .. '#' .. tile,result_list,ting_tile,reduce_tiles(tile_count_map,{[tile] = 2}))
    elseif not ting_tile and not result:find('#')  then
        next_tingpai(result .. '#' .. tile,result_list,tile,
            reduce_tiles(tile_count_map,{[tile] = 1}))
    end

    if count >= 3 then
        next_tingpai(result ..'*'.. (tile * 100 + 3),result_list,ting_tile,
            reduce_tiles(tile_count_map,{[tile] = 3}))
    elseif not ting_tile and count == 2 then
        next_tingpai(result ..'*'.. (tile * 100 + 3),result_list,tile,
            reduce_tiles(tile_count_map,{[tile] = 2}))
    end

    --[[此处算的是手上的牌，除了杠碰牌，
        不可能会有4张牌为一坎的情况，如果有也只能是【七对】系列，
        而【七对】系列已经在一开始的时候过滤掉了
    if count >= 4 then
        next_tingpai(result ..'*'.. (tile * 100 + 4),result_list,ting_tile,
            reduce_tiles(tile_count_map,{[tile] = 4}))
    elseif not ting_tile and count == 3 then
        next_tingpai(result ..'*'.. (tile * 100 + 4),result_list,tile,
            reduce_tiles(tile_count_map,{[tile] = 3}))
    end]]
end

local function next_qidui(tile_count_map,gangpeng_map)
    if gangpeng_map and next(gangpeng_map) then
        return
    end

    local count_tile_map = {}
    for tile,count in pairs(tile_count_map) do
        local l = count_tile_map[count]
        if not l then
            l = {}
            count_tile_map[count] = l
        end
        l[#l + 1] = tile * 100 + count
    end

    local count_2 = count_tile_map[2]
    local count_4 = count_tile_map[4]

    count_tile_map[2] = nil
    count_tile_map[4] = nil

    local count_1 = count_tile_map[1]
    local count_3 = count_tile_map[3]

    local ting_tile,ting_result
    if count_1 and #count_1 == 1 then
        count_tile_map[1] = nil
        if not next(count_tile_map) then
            ting_tile = math_floor(count_1[1] / 100)
            ting_result = ting_tile * 100 + 2
        end
    elseif count_3 and #count_3 == 1 then
        count_tile_map[3] = nil
        if not next(count_tile_map) then
            ting_tile = math_floor(count_3[1] / 100)
            ting_result = ting_tile * 100 + 4
        end
    else
        return
    end

    if not ting_result or not ting_tile then
        return
    end

    local r = ''
    if count_2 then
        r = r .. '=' .. table_concat(count_2,'=')
    end

    if count_4 then
        r = r .. '=' .. table_concat(count_4,'=')
    end

    return r .. '=' .. ting_result .. '-' .. ting_tile
end

local function check_tingpai(tile_list,que,gangpeng_map)
    --如果有定缺的牌，则不可能有胡牌
    local tile_count_map = {}
    for _,tile in ipairs(tile_list) do
        tile_count_map[tile] = (tile_count_map[tile] or 0) + 1
    end

   for tile,_ in pairs(tile_count_map) do
       if math_floor(tile / 10) == que then
            return
        end
   end

    local result_list = {}
    local r = next_qidui(tile_count_map,gangpeng_map)
    if r then
        result_list[#result_list + 1] = r
        return result_list
    end

    next_tingpai('',result_list,nil,tile_count_map)

    return result_list
end

--[[
    result 定义{
        牌型 type
        组合 
        模式 +111213+131415#18*2203*2303-13
            =1802=1302=1402=1104=1504-15

        +后面跟顺子
        #后面跟两张将
        -后面跟听的牌
        *后面跟对子（三张或四张）
        =后面跟龙七对
    }

    清龙七对	32番	    即同一种花色的龙七对
    清七对	    16番     即同一种花色的七对
    龙七对     8番      即在七对的基础上，有4张牌一样的
    七对	    4番       即胡牌时手牌全是对子，没有碰或杠过牌
]]
local function parse_hupai(s,gangpeng_map,rules)
    local result = {}
    local flowers = {}   --收集存在的花色
    local yaojiu_count = 0 --判断幺九的数量

    local group_count = 0  --手里有几坎牌
    local four_list = {}    --四张一样的牌数
    local three_list = {}   --三张一样的牌数
    local jiang_tile    --一对将,是七对则没有将牌

    for n in s:gmatch('([%+%-%*%=%#]%d+)') do
        local tp = n:sub(1,1)
        local value = tonumber(n:sub(2))

        if tp == '+' then
            local t1 = math_floor(value / 10000) % 100
            local t2 = math_floor(value / 100) % 100
            local t3 = value % 100
            
            --由于是连牌，判断头跟尾即可
            if t1 % 10 == 1 or t3 % 10 == 9 then
                yaojiu_count = yaojiu_count + 1
            end

            --记录这张牌的花色
            flowers[math_floor(t1 / 10)] = true
        elseif  tp == '*' then
            local t = math_floor(value / 100)
            local tn = value % 100

            if t % 10 == 1 or t % 10 == 9 then
                yaojiu_count = yaojiu_count + 1
            end

            --花色
            flowers[math_floor(t / 10)] = true
            if tn == 4 then
                four_list[#four_list + 1] = t
            elseif tn == 3 then
                three_list[#three_list + 1] = t
            end
        elseif  tp == '=' then
            local t = math_floor(value / 100)
            local tn = value % 100

            if t % 10 == 1 or t % 10 == 9 then
                yaojiu_count = yaojiu_count + 1
            end
            --花色
            flowers[math_floor(t / 10)] = true
            if tn == 4 then
                four_list[#four_list + 1] = t
            end
        elseif  tp == '#' then
            assert(not jiang_tile)
            jiang_tile = value

            if value % 10 == 1 or value % 10 == 9 then
                yaojiu_count = yaojiu_count + 1
            end
            --花色
            flowers[math_floor(value / 10)] = true
        else
            assert(false,'invalid symbol ' .. tp)
        end

        group_count = group_count + 1
    end

    local shoupai_group_count = group_count --手里有的牌数，这是不算杠出去的

    for t,tn in pairs(gangpeng_map) do
        --检查碰杠牌
        if t % 10 == 1 or t % 10 == 9 then
            yaojiu_count = yaojiu_count + 1
        end
        --花色
        flowers[math_floor(t / 10)] = true
        if tn == 4 then
            four_list[#four_list + 1] = t
        elseif tn == 3 then
            three_list[#three_list + 1] = t
        end

        group_count = group_count + 1
    end
    
    local flowers_count = 0
    for _,_ in pairs(flowers) do
        flowers_count = flowers_count + 1
    end

    local is_qingyise = (flowers_count == 1)   --判断清一色

    if not jiang_tile then
        assert(not next(gangpeng_map))
        --没有将牌则是七对
        if #four_list > 0 then
            --至少是龙七对
            if is_qingyise then
                --清龙七对
                return {type = HU_QINGLONGQIDUI,pattern = s}
            end
            return {type = HU_LONGQIDUI,pattern = s}
        elseif is_qingyise then
            --清七对
            return {type = HU_QINGQIDUI,pattern = s}
        end

        return {type = HU_QIDUI,pattern = s}
    end

    --从最高番检查起

    --单吊胡牌
    if shoupai_group_count == 1 then
        --十八罗汉
        local gangpai_count = 0
        local jingoudiao_test = {}
        for t,tn in pairs(gangpeng_map) do
            if tn == 4 then
                gangpai_count = gangpai_count + 1
            end
            jingoudiao_test[t % 10] = true
        end

        if gangpai_count == group_count - 1 then
            --此时有18张牌
            if is_qingyise then
                return {type = HU_QINGSHIBALUOHAN,pattern = s}
            end
            return {type = HU_SHIBALUOHAN,pattern = s}
        end

        --金钩钓: 所有牌都已碰出或杠出，手里就只剩一张牌单吊胡牌
        if is_qingyise then
            return {type = HU_QINGJINGOUDIAO,pattern = s}
        end

        jingoudiao_test[jiang_tile % 10] = true
        jingoudiao_test[2] = nil
        jingoudiao_test[5] = nil
        jingoudiao_test[8] = nil
        if not next(jingoudiao_test) and rules.jiangdui then
            return {type = HU_JIANGJINGOUDIAO,pattern = s}
        end
        
        return {type = HU_JINGOUDIAO,pattern = s}
    end
    
    local is_yaojiu = (yaojiu_count == group_count)
    if is_yaojiu and rules.daiyaojiu then
        --至少是一个带幺九
        if is_qingyise then
            return {type = HU_QINGYAOJIU,pattern = s}
        end
        return {type = HU_DAIYAOJIU,pattern = s}
    elseif #four_list + #three_list == group_count - 1 then
        --判断所有的牌是不是大对子
        local jiangdui_test = {}
        for _,t in ipairs(four_list) do
            jiangdui_test[t % 10] = true
        end
        for _,t in ipairs(three_list) do
            jiangdui_test[t % 10] = true
        end
        jiangdui_test[2] = nil
        jiangdui_test[5] = nil
        jiangdui_test[8] = nil
        if not next(jiangdui_test) and rules.jiangdui then
            return {type = HU_JIANGDUI,pattern = s} 
        end
        if is_qingyise then
            return {type = HU_QINGDADUI,pattern = s} 
        end
        return {type = HU_DUIDUIHU,pattern = s} 
    end

    if is_qingyise then
        return {type = HU_QINGYISE,pattern = s}
    end

    return {type = HU_PINGHU,pattern = s}
end

local function parse_hupai_list(hupai_list,gangpeng_map,rules)
    local result_list = {}
    for _,s in ipairs(hupai_list) do
        local result = parse_hupai(s,gangpeng_map,rules)
        result.fan = FANSHU_DEF[result.type]
        result_list[#result_list + 1] = result
    end

    return result_list
end

--找出听牌需要打出的子
--[[
    返回值:{
        [可以打出的牌]->{可以胡的牌型列表1,可以胡的牌型列表2,...}
    }
]]
local function find_out_tingpai(tile_list,que,gangpeng_map)
    local tile_map = {}
    for i,tile in ipairs(tile_list) do
        tile_map[tile] = i
    end

    if tile_map[que] then
        --含有定缺的牌
        return
    end

    local function copy() 
        local o = {}
        for k,v in ipairs(tile_list) do 
            o[k] = v
        end
        return o
    end

    for tile,i in pairs(tile_map) do
        local test_tile_list = copy()
        table_remove(test_tile_list,i)
        local l = check_tingpai(test_tile_list,que,gangpeng_map)
        if #l > 0 then
            tile_map[tile] = l
        else
            tile_map[tile] = nil
        end
    end

    --外部还得根据牌面上已经出过的牌来算出真正的听牌列表

    return tile_map
end

local M = {
    FANSHU_DEF = FANSHU_DEF,
    ALL_TILES = ALL_TILES,

    check_hupai = function(...) return check_hupai(...) end,
    check_tingpai = function(...) return check_tingpai(...) end,
    parse_hupai_list = function(...) return parse_hupai_list(...) end,
    find_out_tingpai = function(...) return find_out_tingpai(...) end,
    parse_hupai = function(...) return parse_hupai(...) end,
}

M.HU_QIDUI = HU_QIDUI
M.HU_LONGQIDUI = HU_LONGQIDUI
M.HU_QINGQIDUI = HU_QINGQIDUI
M.HU_QINGLONGQIDUI = HU_QINGLONGQIDUI

return M