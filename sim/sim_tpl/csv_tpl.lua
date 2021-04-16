local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local props = {}

	NAME_CHECKING = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'PROP' then
				local prop = {
					name = v[2],
					desc = v[3],
				}
				if string.len(v[4]) > 0 then
					prop.unit = v[4]
				end

				prop.vt = string.len(v[5] or '') > 0 and v[5] or 'float'
				prop.rw = string.len(v[6] or '') > 0 and v[6] or 'RO'
				prop.base = tonumber(v[7] or '0') or 0
				prop.method = string.len(v[8] or '') > 0 and v[8] or 'RANDOM()'
				prop.freq = tonumber(v[9] or '1') or 1

				if valid_prop(prop, err_cb) then
					props[#props + 1] = prop
				end
			end
		end
	end

	return {
		props = props,
	}
end

return {
	load = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
