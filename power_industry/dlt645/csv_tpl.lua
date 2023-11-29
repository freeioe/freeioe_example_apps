local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local outputs = {}
	local packets =  {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'INPUT' then
				local input = {
					name = v[2],
					desc = v[3],
				}
				input.addr = tonumber(v[4])
				if string.len(v[5]) > 0 then
					input.vt = v[5]
				end
				input.offset = v[6]
				if string.len(v[7]) > 0 then
					output.rate = v[7]
				end
				if string.len(v[8]) > 0 then
					input.format = v[8]
				end

				inputs[#inputs + 1] = input
			end
			if v[1] == 'OUTPUT' then
				local output = {
					name = v[2],
					desc = v[3],
				}
				output.addr = tonumber(v[4])
				if string.len(v[5]) > 0 then
					output.vt = v[5]
				end
				if string.len(v[6]) > 0 then
					output.rate = v[6]
				end
				if string.len(v[7]) > 0 then
					output.format = v[7]
				end
				outputs[#outputs + 1] = output
			end
		end
	end

	local packets_map = {}
	for _, input in ipairs(inputs) do
		local pack = packets_map[input.addr] or {
			addr = input.addr,
			inputs = {}
		}
		pack.inputs[#pack.inputs + 1] = input
		packets_map[pack.addr] = pack
	end
	for k,v in pairs(packets_map) do
		table.sort(v.inputs, function(i, j)
			return i.offset < j.offset
		end)
		packets[#packets + 1] = v
	end

	return {
		meta = meta,
		inputs = inputs,
		outputs = outputs,
		packets = packets
	}
end

--[[
--local cjson = require 'cjson.safe'
local tpl = load_tpl('bms')
print(cjson.encode(tpl))
]]--

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
