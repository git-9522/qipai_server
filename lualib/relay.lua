local skynet = require 'skynet'

local M = {}

function M.dispatch(fd,msg,sz)
    --(msg,sz)是一个内部协议，内部协议的具体格式由该模块做适配，从而产生出一个新的包体以及新的目标地址即可
end

return M