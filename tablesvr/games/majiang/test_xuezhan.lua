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

local print = print

local xprofiler = require "xprofiler"
xprofiler.require("xuezhan_checker")

require "preload"

_ENV.print = print

local xuezhan_checker = require "xuezhan_checker"

local print_result = function(tile_list,gangpeng_map)
    local result_list = xuezhan_checker.check_hupai(tile_list,nil,gangpeng_map or {})
    result_list = xuezhan_checker.parse_hupai_list(result_list,gangpeng_map or {})
    for _,result in ipairs(result_list) do
        local p = profiler()
        print(HUPAI_NAMES[result.type],
            FANSHU_DEF[result.type]..'番',
            result.pattern,p:stop())
    end
end

print('=======================================================平胡')
print_result({11,12,13,21,22,23,11,12,13,15,15,16,16,16})

print('=======================================================对对胡')
print_result({11,11,11,21,21,21,23,23,23,15,15,16,16,16})

print('=======================================================清一色')
print_result({11,11,11,19,19,19,13,14,15,15,15,16,16,16})

print('=======================================================带幺九')
print_result({11,12,13,21,22,23,11,12,13,29,29,27,28,29})

print('=======================================================七对')
print_result({18,18,19,19,12,12,13,13,14,14,25,25,27,27})

print('=======================================================金钩钓')
print_result({22,22},{[14] = 4,[13] = 3,[15] =3,[21] = 3})

print('=======================================================清大对')
print_result({18,18,11,11,11},{[14] = 4,[13] = 3,[15] =3})

print('=======================================================将对')
print_result({18,18,12,12,12},{[15] = 4,[25] = 3,[22] =3})

print('=======================================================龙七对')
print_result({18,18,19,19,12,12,13,13,24,24,24,24,17,17})

print('=======================================================清七对')
print_result({18,18,19,19,12,12,13,13,14,14,15,15,17,17})

print('=======================================================清幺九')
print_result({11,12,13,11,12,13,11,12,13,19,19,17,18,19})

print('=======================================================将金钩钓')
print_result({18,18},{[15] = 4,[25] = 3,[22] =3,[12]=3})

print('=======================================================清金钩钓')
print_result({18,18},{[14] = 4,[13] = 3,[15] =3,[11] = 3})

print('=======================================================清龙七对')
print_result({18,18,19,19,12,12,13,13,14,14,14,14,17,17})

print('=======================================================十八罗汉')
print_result({18,18},{[24] = 4,[13] = 4,[15] =4,[19] = 4})

print('=======================================================清十八罗汉')
print_result({18,18},{[14] = 4,[13] = 4,[15] =4,[19] = 4})

print('=======================================================清大对')
print_result({18,18,11,11,11},{[14] = 4,[13] = 3,[15] =3})


--[[
    清龙七对	32番	    即同一种花色的龙七对
    清七对	    16番     即同一种花色的七对
    龙七对     8番      即在七对的基础上，有4张牌一样的
    七对	    4番       即胡牌时手牌全是对子，没有碰或杠过牌
]]

--计算出胡牌需要打出哪张牌
local tile_list = {11,12,13,21,22,23,11,12,13,15,15,16,25,25}  --缺一张
local p = profiler()
local r = xuezhan_checker.find_out_tingpai(tile_list)
local e = p:stop()
print(e,tostring_r(r))


xprofiler.show_measurement()