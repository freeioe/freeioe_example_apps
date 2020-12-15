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

	if not prop.elem_name or string.len(prop.elem_name) == 0 then
		return log_cb('Invalid prop elem_name found', prop.name, prop.elem_name)
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated prop name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local props = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2]
				meta.desc = v[3]
				meta.series = v[4]
			end
			if v[1] == 'PROP' then
				local prop = {
					name = v[2],
					desc = v[3],
				}
				if string.len(v[4]) > 0 then
					prop.unit = v[4]
				end

				prop.rw = v[5]
				if not prop.rw or string.len(prop.rw) == 0 then
					prop.rw = 'RO'
				end

				if v[6] and string.len(v[6]) > 0 then
					prop.vt = v[6]
				else
					prop.vt = 'float'
				end

				prop.elem_name = v[7]
				prop.rate = tonumber(v[8]) or 1

				if valid_prop(prop, err_cb) then
					props[#props + 1] = prop
				end
			end
		end
	end

	return {
		meta = meta,
		props = props,
	}
end

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
