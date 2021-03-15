local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local funcs = {}
	local packets =  {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'PMC_RANGE' then
				local input = {
					name = v[2],
					desc = v[3],
				}
				if string.len(v[4]) > 0 then
					input.vt = v[4]
				end
				input.pack = v[5]
				input.rate = tonumber(v[6])
				input.offset = tonumber(v[7] or '')

				table.insert(inputs, input)
			end
			if v[1] == 'PMC_PACKET' then
				local pack = {
					name = v[2],
					desc = v[3],
					addr_type = v[4],
					data_type = v[5],
					start = v[6],
					len = v[7],
				}
				table.insert(packets, pack)
			end
			if v[1] == 'CNC_FUNC' then
				local func = {
					name = v[2],
					desc = v[3],
				}
				if string.len(v[4]) > 0 then
					func.vt = v[4]
				end
				func.rate = tonumber(v[5])
				func.func = v[6]
				func.params = {}
				for i = 7, 15 do
					if not v[i] then
						break
					end
					local val = math.tointeger(v[i]) or tonumber(v[i]) or v[i]
					table.insert(func.params, val)
				end
				table.insert(funcs, func)
			end
		end
	end

	for _, pack in ipairs(packets) do
		pack.inputs = {}
		for _, input in ipairs(inputs) do
			if input.pack == pack.name then
				pack.inputs[#pack.inputs + 1] = input
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
		packets = packets,
		funcs = funcs,
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
