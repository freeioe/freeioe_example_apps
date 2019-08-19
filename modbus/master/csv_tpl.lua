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
				input.unit = v[4]
				input.rw = v[5]
				input.dt = v[6]
				if string.len(v[7]) > 0 then
					input.vt = v[7]
				end
				input.fc = tonumber(v[8])
				input.addr = tonumber(v[9])
				input.rate = tonumber(v[10])
				input.offset = tonumber(v[11])

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
