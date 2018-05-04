local M={}
local mail_get_sender_map = {}

local function translate_rank_mail(uid,mail_info,mail_cfg)
    local result_content = mail_cfg.content
    local temp_repl = {rand = mail_info.param1}
    return result_content:gsub('{(.-)}',temp_repl)
end

local MAIL_TYPE_RANK = 102
mail_get_sender_map[MAIL_TYPE_RANK] = translate_rank_mail



function M.get_sender_content(uid,mail_info,mail_template)
    local mail_id = mail_info.mail_id
	local mail_cfg = mail_template[mail_id]
	if not mail_cfg then
		errlog(uid,'get_sender_content failed with mail_id at normal mail',mail_id)
		return
	end
	local hand_func = mail_get_sender_map[mail_id]
	local content = mail_cfg.content
	if hand_func then
		content = hand_func(uid,mail_info,mail_cfg)
	end
    local temp_repl = {rand = mail_info.intp1}
	return mail_cfg.title,content
end

return M