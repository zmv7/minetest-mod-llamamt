local s = minetest.get_mod_storage()
local st = minetest.settings

local http = minetest.request_http_api()

if not http then
	minetest.log("error",
		"Can not access HTTP API. Please add this mod to secure.http_mods to grant access")
	return
end

function askllama(msg, callback, with_context)
	if not msg then return end
	http.fetch({
		url = "http://"..(st:get("llamamt_address") or "127.0.0.1")..":"..(st:get("llamamt_port") or "11434").."/api/generate",
		method = "POST",
		extra_headers = {"Content-Type: application/json"},
		data = '{"model":"'..(st:get("llamamt_model") or 'llama3.1')..'","prompt":'..
			minetest.write_json(minetest.strip_colors(msg))..
			(with_context and s:get("context") and ',"context":['..s:get("context")..']' or '')..'}'
	},
	function(res)
		local data = res.data
		local jsons = data:split("\n")
		local out = {}
		for _,json in ipairs(jsons) do
			local parsed = minetest.parse_json(json)
			if parsed and parsed.response then
				table.insert(out, parsed.response)
			end
			if with_context and parsed and parsed.context then
				s:set_string("context", table.concat(parsed.context,","))
			end
		end
		callback(table.concat(out))
	end)
end

local function reset()
	s:set_string("context", "")
	local init_prompt = st:get("llamamt_init_prompt")
	if init_prompt then
		askllama(init_prompt, function(answer)
			minetest.log("action","LLama has been reset ("..answer..")")
		end, true)
	end
end

minetest.register_chatcommand("askllama",{
	description = "Ask LLama (no context)",
	params = "<prompt>",
	func = function(name, param)
		if not param or param == "" then
			return false, "Empty prompt!"
		end
		if enabled then
			askllama(param, function(answer)
				local color = st:get("llamamt_color") or "#aef"
				minetest.chat_send_player(name, minetest.colorize(color, "DM from "..ai_name..": ", answer))
			end)
		else
			return false, "LLama is currently disabled"
		end
end})

minetest.register_chatcommand("resetllama",{
	privs = {server=true},
	description = "Reset LLama context",
	func = function(name, param)
		reset()
		return true, "LLama context has been reset."
end})

minetest.register_chatcommand("togglellama",{
	privs = {server=true},
	description = "Toggle LLama functionality",
	func = function(name, param)
		enabled = not enabled
		st:set_bool("llamamt_enabled", enabled)
		if not s:get("context") then
			reset()
		end
		return true, "LLama has been "..(enabled and "enabled" or "disabled")
end})

local callwords = {
	"^hello!?$",
	"^hello there!?$",
	"^hi!?$",
	"^привет!?$", "^Привет!?$",
}

local function llama_on_chat_msg(name, msg)
	if not enabled or msg:sub(1,1) == "/" then return end
	local reply
	local prefix = st:get("llamamt_prefix") or "!"
	if msg:match("^"..prefix.."%S+") then
		msg = msg:sub(#prefix+1)
		reply = true
	else
		for _,word in ipairs(callwords) do
			if msg:lower():match(word) then
				reply = true
				break
			end
		end
	end
	if reply then
		askllama("<"..name.."> "..msg, function(answer)	
			if not st:get_bool("llamamt_newlines", false) then
				answer = answer:gsub("\n"," ")
			end
			local color = st:get("llamamt_color") or "#aef"
			minetest.chat_send_all(minetest.colorize(color, minetest.format_chat_message((st:get("llamamt_name") or "[AI] LLama"), answer)))
		end, true)
	end
end

minetest.register_on_mods_loaded(function()
	table.insert(minetest.registered_on_chat_messages, 1, llama_on_chat_msg)
	minetest.callback_origins[llama_on_chat_msg] = {
		mod = "llamamt",
		name = "register_on_chat_message"
	}
	if enabled and not s:get("context") then
		reset()
	end
end)
