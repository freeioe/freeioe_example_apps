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
				if string.len(v[4]) > 0 then
					input.unit = v[4]
				end

				input.rw = v[5]
				if string.len(input.rw) == 0 then
					input.rw = 'RO'
				end

				input.dt = v[6]
				if string.len(input.dt) == 0 then
					input.dt = 'uint16'
				end

				if string.len(v[7]) > 0 then
					input.vt = v[7]
				else
					input.vt = 'float'
				end

				input.fc = tonumber(v[8]) or 0x03
				input.addr = tonumber(v[9]) or 0
				input.rate = tonumber(v[10]) or 1
				input.offset = tonumber(v[11]) or 0

				inputs[#inputs + 1] = input
			end
		end
	end

	return {
		meta = meta,
		inputs = inputs,
	}
end

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
