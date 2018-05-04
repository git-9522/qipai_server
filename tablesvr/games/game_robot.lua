local skynet = require "skynet"
local util = require "util"
local table_unpack = table.unpack
local table_insert = table.insert

local M = {}

local Methods = {}
local MT = {
    __index = Methods
}

function M.new(uid,AI,addr,fd,conf)
    local o = {
        uid = uid,
        AI = AI,
        addr = addr,
        fd = fd,
        conf = conf
    }

    return setmetatable(o, MT)
end

function Methods:on_register()
    skynet.send(self.addr,'lua','enter',self.uid,self.fd)
end

--自己进桌
function Methods:on_enter()
    return
end

local function analyse_rob_dizhu(self)
    if not self.ddz_instance:is_rob_dizhu() then
        return
    end
    if self.ddz_instance:get_setting_uid() == self.uid then
        self.rob_time = util.get_now_time() + util.randint(4,5)
        self.rob_request = self.AI.analyse_rob_dizhu(self)
    end
end

local function analyse_play(self)
    if not self.ddz_instance:is_playing() then
        return
    end
    if self.ddz_instance:get_next_player_uid() == self.uid then
        self.play_time = util.get_now_time() + util.randint(1,1)
        self.play_request = self.AI.analyse_play(self)
    end
end

local function analyse_jiabei(self)
    if not self.ddz_instance:is_jiabei() then
        return
    end
    self.jiabei_time = util.get_now_time() + util.randint(1,1)
    self.jiabei_request = self.AI.analyse_jiabei(self)
end

--游戏开始触发
function Methods:on_start(ddz_instance)
    self.ddz_instance = ddz_instance
    
    analyse_rob_dizhu(self)
end

--抢地主
function Methods:on_rob_dizhu(uid,score,is_rob)
    dbglog('on_rob_dizhu')
    if uid == self.uid then return end
    analyse_rob_dizhu(self)
end

--加倍
function Methods:on_jiabei()
    dbglog('on_jiabei')
    analyse_jiabei(self)
end

function Methods:on_start_play()
    dbglog('on_start_play')
    analyse_play(self)
    
    if self.is_rob then self.is_rob = false end
end

--出牌
function Methods:on_play(uid,card_id_list)
    dbglog('on_play ....')
    if uid == self.uid then return end
    analyse_play(self)
end

--游戏结束
function Methods:on_game_over()
    self.ddz_instance = nil
    --下一轮准备
end

function Methods:on_restart()
    dbglog('on_restart')
    self.ready_time = util.get_now_time() + util.randint(3,6)
end

function Methods:on_nodizhu_restart()
    dbglog('on_nodizhu_restart ...')
    self.ddz_instance = nil
end

function Methods:check_ready(curr_time)
    if not self.ready_time then
        return
    end

    if curr_time >= self.ready_time then
        self.ready_time = nil
        if skynet.getenv "shenhe" then
            skynet.send(self.addr,'lua','REQ_READY',self.uid,{ready=1},self.fd)
        else
            skynet.send(self.addr,'lua','REQ_READY',self.uid,{ready=2},self.fd)
        end
    end
end

function Methods:update_rob_dizhu(curr_time)
    local ddz_instance = self.ddz_instance
    if not ddz_instance:is_rob_dizhu() then
        return
    end
    --轮到自己抢地主
    if ddz_instance:get_setting_uid() == self.uid and 
        self.rob_time and curr_time >= self.rob_time then
        local req_msg = assert(self.rob_request)
        self.rob_request = nil
        self.rob_time = nil
        skynet.send(self.addr,'lua','REQ_ROBDIZHU',self.uid,req_msg,self.fd)
        dbglog_r(self.uid,req_msg)
    end
end

function Methods:update_play(curr_time)
    local ddz_instance = self.ddz_instance
    if not ddz_instance:is_playing() then
        return
    end
    --轮到自己出牌
    if ddz_instance:get_next_player_uid() == self.uid and 
        self.play_time and curr_time >= self.play_time then
        local req_msg = assert(self.play_request)
        self.play_request = nil
        self.play_time = nil
        skynet.send(self.addr,'lua','REQ_PLAY',self.uid,req_msg,self.fd)
        dbglog_r(self.uid,req_msg)
    end
end

function Methods:update_jiabei(curr_time)
    local ddz_instance = self.ddz_instance
    if not ddz_instance:is_jiabei() then
        return
    end
    if self.jiabei_time and curr_time >= self.jiabei_time then
        local req_msg = assert(self.jiabei_request)
        self.jiabei_request = nil
        self.jiabei_time = nil
        skynet.send(self.addr,'lua','REQ_JIABEI',self.uid,req_msg,self.fd)
        dbglog_r(self.uid,req_msg)
    end
end

function Methods:update()
    while self.exit do
        local curr_time = util.get_now_time()

        if self.ddz_instance then
            --当前是抢地主？
            self:update_rob_dizhu(curr_time)
            --当前是否加倍？
            self:update_jiabei(curr_time)
            --当前可以出牌？
            self:update_play(curr_time)
        else
            --游戏未开始则需要检查自己是否准备了
            self:check_ready(curr_time)
        end

        skynet.sleep(50)    --500ms
    end

    dbglog(self.uid,'exit !!!!')
end

function Methods:exit()
    self.exit = true
end

return M