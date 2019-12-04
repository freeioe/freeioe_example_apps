local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function load_tpl(name)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local inputs = {}
	local outputs = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.manufacturer = v[2]
				meta.name = v[3]
				meta.desc = v[4]
				meta.series = v[5]
			end
			if v[1] == 'INPUT' then
				local input = {
					name = v[2],
					desc = v[3],
					vt = string.len(v[4]) > 0 and v[4] or 'float',
					ns = tonumber(v[5] and v[5] or 0) or 0,
					rate = tonumber(v[7] and v[7] or 1) or 1,
					itype = string.lower( (v[8] and string.len(v[8]) > 0) and v[8] or 'auto')
				}

				if v[6] and string.len(v[6]) > 0 then
					if input.itype == 'auto' then
						input.i = tonumber(v[6]) or v[6]
					else
						input.i = v[6]
					end
				end
				assert(input.i, "INPUT NodeID index missing")
				if string.len(input.desc) == 0 then
					input.desc = nil -- will auto load the display name for description
				end
				inputs[#inputs + 1] = input
			end
			if v[1] == 'OUTPUT' then
				local output = {
					name = v[2],
					desc = v[3],
					vt = string.len(v[4]) > 0 and v[4] or 'float',
					ns = tonumber(v[5] and v[5] or 0) or 0,
					rate = tonumber(v[7] and v[7] or 1) or 1,
					itype = string.lower( (v[8] and string.len(v[8]) > 0) and v[8] or 'auto')
				}
				if v[6] and string.len(v[6]) > 0 then
					if output.itype == 'auto' then
						output.i = tonumber(v[6]) or v[6]
					else
						output.i = v[6]
					end
				end
				assert(output.i, "OUTPUT NodeID index missing")
				if string.len(output.desc) == 0 then
					output.desc = nil -- will auto load the display name for description
				end
				outputs[#outputs + 1] = output
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
		outputs = outputs,
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
