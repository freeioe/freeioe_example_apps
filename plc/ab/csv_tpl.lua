local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local valid_dt = {
	int8 = true,
	uint8 = true,
	int16 = true,
	uint16 = true,
	int32 = true,
	uint32 = true,
	float32 = true,
	float64 = true
}

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end
	if not valid_dt[prop.dt] then
		return log_cb('Invalid prop data type found', prop.name, prop.dt)
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

	NAME_CHECKING = {}

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

				prop.dt = v[6]
				if not prop.dt or string.len(prop.dt) == 0 then
					prop.dt = 'uint32'
				end
				if prop.dt == 'float' then
					prop.dt = 'float32'
				end
				if prop.dt == 'double' then
					prop.dt = 'float64'
				end

				if v[7] and string.len(v[7]) > 0 then
					prop.vt = v[7]
				else
					prop.vt = 'float'
				end

				prop.elem_name = v[8]
				prop.offset = tonumber(v[9]) or 0
				prop.rate = tonumber(v[10]) or 1

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
