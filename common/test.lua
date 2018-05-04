package.cpath = '../../deps/skynet/luaclib/?.so;../luaclib/?.so;' .. package.cpath
local bson = require "bson"
local cjson = require "cjson"
local dbdata = require "dbdata"

local player = dbdata.new('player')

print(player:get_dirty_fields())
player.name = 'hello'
player.age = 10
player.height = 180
print(player.name)
print(player.age)
print(player.height)

assert(player:get_dirty_fields())
player:clear_dirty_fields()

local subdata = player:new_table_field('subdata')
assert(not player:get_dirty_fields())
player:clear_dirty_fields()
subdata.name = 10
assert(player:get_dirty_fields())
player:clear_dirty_fields()
assert(not player:get_dirty_fields())

print(player.subdata)
subdata:new_table_field('haha')
assert(not player:get_dirty_fields())
subdata.haha.name = 10
subdata.haha.name = 10
subdata.haha.name = 10
subdata.haha.name = 10
assert(player:get_dirty_fields())
print(subdata.haha)
print(player.subdata.haha)

for k in pairs(player:get_dirty_fields()) do
    print(k)
end

local fake_table = {
    level = 10,
    name = 20,
    exp = 30,
    xxx = {
        name = 'xxx',
        level = 30,
        exp = 40,
        speed = false,
        money = 399,
        haha = {
            x = 10,
            b = 30
        }
    },
    yyy = {}
}

local n = dbdata.new_from('n',fake_table)
table.insert(n.yyy,1)
table.insert(n.yyy,2)
for k in pairs(n:get_dirty_fields()) do
    print(k)
end

print(#n.yyy)



local table_insert = table.insert 
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
    if depth >= 6 then return '' end
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
local copy = n:deep_copy()
print(tostring_r(copy))
print('bson length',#bson.encode(copy))
print('json length',#cjson.encode(copy))
print('--------------------------------------------------------')


local test = dbdata.new('test')
print(tostring_r(test:deep_copy()))
local sub = test:new_table_field('sub')
for i = 1, 10 do
    sub[#sub + 1] = i
end
print('test pairs ................')

for k,v in pairs(sub) do
    print('fffffffffff',k,v)
end
print('test pairs ................ over')


print(tostring_r(test:deep_copy()))
print(tostring_r(test._dirty_fields))

sub:reset_field()
print(tostring_r(test:deep_copy()))
print(tostring_r(test._dirty_fields))

print('22222222222222222222222222222222222222')

local player = dbdata.new('player')
local child = player:new_table_field('child')
table.insert(child,1)
table.insert(child,2)
table.insert(child,3)
table.insert(child,4)
table.insert(child,5)

for i,v in ipairs(child) do 
    print(i,v)
end

print('3333333333333333333333333333333333333333')
child:remove_from_array(3)

for i,v in ipairs(child) do 
    print(i,v)
end

child:delete_from_hash(1)

print('3333333333333333333333333333333333333333')
for i,v in pairs(child) do 
    print(i,v)
end
