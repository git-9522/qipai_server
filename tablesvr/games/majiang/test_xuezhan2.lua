package.cpath = '../../../luaclib/?.so;' .. package.cpath
package.path = '../../../common/?.lua;' .. '../../../lualib/?.lua;' .. package.path

local table_remove = table.remove
----------------------------------------------------------------------
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

local HUPAI_NAMES = {
    [HU_PINGHU ] = '平胡',
    [HU_DUIDUIHU ] = '对对胡',
    [HU_QINGYISE ] = '清一色',
    [HU_DAIYAOJIU] = '带幺九',
    [HU_QIDUI] = '七对',
    [HU_JINGOUDIAO ] = '金钩钓',
    [HU_QINGDADUI] = '清大对',
    [HU_JIANGDUI ] = '将对',
    [HU_LONGQIDUI] = '龙七对',
    [HU_QINGQIDUI] = '清七对',
    [HU_QINGYAOJIU] = '清幺九',
    [HU_JIANGJINGOUDIAO] = '将金钩钓',
    [HU_QINGJINGOUDIAO] = '清金钩钓',
    [HU_QINGLONGQIDUI] = '清龙七对',
    [HU_SHIBALUOHAN] = '十八罗汉',
    [HU_QINGSHIBALUOHAN] = '清十八罗汉',
    [HU_TIANHU] = '天胡',
    [HU_DIHU] = '地胡',
}

local FANSHU_DEF = {
    [HU_PINGHU ] = 1,
    [HU_DUIDUIHU ] = 2,
    [HU_QINGYISE ] = 4,
    [HU_DAIYAOJIU] = 4,
    [HU_QIDUI] = 4,
    [HU_JINGOUDIAO ] = 4,
    [HU_QINGDADUI] = 8,
    [HU_JIANGDUI ] = 8,
    [HU_LONGQIDUI] = 8,
    [HU_QINGQIDUI] = 16,
    [HU_QINGYAOJIU] = 16,
    [HU_JIANGJINGOUDIAO] = 16,
    [HU_QINGJINGOUDIAO] = 16,
    [HU_QINGLONGQIDUI] = 32,
    [HU_SHIBALUOHAN] = 64,
    [HU_QINGSHIBALUOHAN] = 256,
    [HU_TIANHU] = 32,
    [HU_DIHU] = 32,
}
----------------------------------------------------------------------
local string_format = string.format
local table_insert = table.insert
local table_concat = table.concat
local function _tostring_r(data,depth)
    if depth >= 6 then return '...' end
    if type(data) == 'table' then
        local s = {'{'}
        for k,v in pairs(data) do
            table_insert(s,string_format('%s:%s,',tostring(k),_tostring_r(v,depth+1)))
        end
        table_insert(s,'}')
        return table_concat(s,'')
    elseif type(data) == 'string' then
        return string_format('"%s"',tostring(data))
    else
        return tostring(data)
    end
end

local function tostring_rp(data)
    return _tostring_r(data,0)
end
-----------------------------------------------------------------------
local print = print

local xprofiler = require "xprofiler"
local util = require "util"
local cjson = require "cjson"

require "preload"

_ENV.print = print

local xuezhan = require "xuezhan"

xuezhan.test_set('DRAW_TILE_WAITING_TIME',120)
xuezhan.test_set('DISCARD_TILE_WAITING_TIME',120)
xuezhan.test_set('HUANSANZHANG_WAITING_TIME',1)
xuezhan.test_set('DINGQUE_WAITING_TIME',1)

local xz = xuezhan.new()
xz:init()
assert(xz:start({8880,8881,8882,8883},{huansanzhang = true}))
assert(xz:shuffle_and_deal(199))

local curr_time = function() return util.get_now_time() end

while true do
    local v = io.stdin:read '*l'
    print('check_and_auto_huansanzhang')
    if xz:check_and_auto_huansanzhang(curr_time()) and 
        xz:check_huansanzhang_over() then
        break
    end
end

while true do
    local v = io.stdin:read '*l'
    print('check_and_auto_dingque')
    if xz:check_and_auto_dingque(curr_time()) and 
        xz:check_dingque_over() then
        break
    end
end


local function make_tiles()
    local player_tiles_map = xz.player_tiles_map
    local keys = {}
    for k in pairs(player_tiles_map) do
        keys[#keys + 1] = k
    end

    player_tiles_map[keys[1]] = {11,11,11,12,12,12,13,13,13,14,14,15,15}
    player_tiles_map[keys[2]] = {21,21,21,22,22,22,23,23,23,24,24,15,15}
    player_tiles_map[keys[3]] = {31,31,31,32,32,32,33,33,33,34,34,35,35}
    player_tiles_map[keys[4]] = {36,36,36,36,37,37,37,38,38,38,39,39,39}

    local all_used_tiles = {}
    for i = 1,3 do
        for j = 1,9 do
            local tile = i*10+j
            all_used_tiles[tile] = 4
        end
    end

    for k,player_tile_list in pairs(player_tiles_map) do
        for _,tile in pairs(player_tile_list) do
            local c = all_used_tiles[tile]
            assert(c > 0)
            c = c -1
            if c > 0 then
                all_used_tiles[tile] = c
            else
                all_used_tiles[tile] = nil
            end
        end
    end

    local tile_list = {}
    for tile,count in pairs(all_used_tiles) do
        for i = 1,count do
            tile_list[#tile_list + 1] = tile
        end
    end

    xz.tile_list = tile_list

    xz.player_dingque_map[keys[1]] = 2
    xz.player_dingque_map[keys[2]] = 3
    xz.player_dingque_map[keys[3]] = 1
    xz.player_dingque_map[keys[4]] = 1

    xz.banker_uid = keys[1]
end

make_tiles()

print(assert(xz:start_play()))

while true do
    local v = io.stdin:read '*l'
    local params = {}
    for k in v:gmatch('(%w+)%s*') do
        table_insert(params,k)
    end
    print('cmds..',tostring_r(params))

    local _,result = xz:check_playing(curr_time())
    if xz:is_game_over() then
        print('game over....')
        break
    end

    local curr_uid = xz:get_curr_player_uid()
    local player_tile_list = xz.player_tiles_map[curr_uid]
    print(curr_uid,tostring_r(player_tile_list),tostring_r(result))
    
    local cmd = params[1]
    if cmd == 'discard' then
        local tile = tonumber(params[2])
        print('======= discard',curr_uid,tile)
        print(tostring_r{xz:do_discard(curr_uid,tile)})
    elseif cmd == 'peng' then
        local uid = tonumber(params[2])
        print('======= peng',uid)
        print(tostring_r{xz:do_peng(uid)})
    elseif cmd == 'gang' then
        local uid = tonumber(params[2])
        print('======= gang',uid)
        print(tostring_r{xz:do_gang(uid)})
    elseif cmd == 'hu' then
        local uid = tonumber(params[2])
        print('======= hu',uid)
        print(tostring_r{xz:do_hu(uid)})
    elseif cmd == 'show' then
        local uid = tonumber(params[2])
        if uid then
            print(tostring_r(xz.player_tiles_map[uid]))
        else
            print(tostring_r(xz.player_tiles_map))
        end
    end
end

print(tostring_r(xz))




xprofiler.show_measurement()