package.path = '../tablesvr/games/?.lua;../lualib/?.lua;' .. package.path
package.cpath = '../luaclib/?.so;' .. package.cpath
local match = require "lz_match_cards"
table_insert = table.insert

local DESCRIPTIONS = {
    "王炸","炸弹","单牌","对牌","三张牌",
    "三带一","单顺","双顺","飞机","飞机带翅膀",
    "四带二","软炸","三带一对","四带两对"
}



--[[local function get_card()
    local card = io.read("number")
    local card_suit = {}
    while card ~= -1 do
        table_insert(card_suit,card)
        card = io.read("number")
    end    
    return card_suit
end


local card_suit = get_card()
for k,v in pairs(card_suit) do 
    print(k,v)
end
io.write("请选择一张牌作为癞子：")
local laizi = io.read("number")
print("laizi is ",laizi)]]

--[[local card_suit,laizi = {104,204,304,404,105,205,306,406},3
local card_suit,laizi = {105,205,305,403,103,203,104,204,304,409,107,207},3
local card_suit,laizi = {108,208,308,403,103,203,104,209,309,409,107,207},3
local card_suit,laizi = {105,205,305,103,203,303,104,204,304,306,106,206,406},3
local card_suit,laizi = {105,205,305,103,203,303,104,204,304,306,106,206,406},3
local card_suit,laizi = {105,205,305,103,203,303,104,204,304,306,106,206,406,107},3
local card_suit,laizi = {105,205,305,103,203,303,104,204,304,306,106,206,406,107},3
local card_suit,laizi = {14,15},3]]
--local card_suit,laizi = {103,104,105,106,108},3
--local card_suit,laizi = {101,205},5
--local card_suit,laizi = {103,203,105},5
--local card_suit,laizi = {105,305,110,210},10
--local card_suit,laizi = {104,205,204,304,105,305},5
--local card_suit,laizi = {104,205,204,304,105,305,108,209},5
--local card_suit,laizi = {112,212,15,105},6
--local card_suit,laizi = {104,205,204,304,105,306,108,209},6
--local card_suit,laizi = {106,206,306,104,404},5
--local card_suit,laizi = {103,204,305,106,407},0
local card_suit,laizi = {103,205,406,104,204},4

local card_type = match.match_cards(card_suit,laizi)
if not card_type then
    print("+++++++++++++++++++++++++++++++play error")
end



print("请选择要出的牌:")
for i=1,#card_type do

        print("类型:"..DESCRIPTIONS[card_type[i].type],"值:"..card_type[i].key)
        print("cards is :")
        for j=1,#card_type[i].card do
            print(card_type[i].card[j])
        end

end


