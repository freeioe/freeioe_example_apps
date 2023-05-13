local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local TI_TYPES = {
	'SP', 'DP', 'ME', 'IT', 'ST', 'BO'
}

local function valid_ti(ti)
	for _, v in ipairs(TI_TYPES) do
		if v == string.upper(ti) then
			return true
		end
	end
	return false
end

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end
	if not valid_ti(prop.ti) then
		return log_cb('Invalid prop TI type found', prop.name, prop.ti)
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

	local meta = {}
	local props = {}

	NAME_CHECKING = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2] or 'Device'
				meta.desc = v[3] or 'CS104 Device'
				meta.series = v[4] or 'XXX'
			end
			if v[1] == 'PROP' then
				local prop = {
					name = v[2] or '',
					desc = v[3] or 'UNKNOWN',
				}
				if string.len(v[4]) > 0 then
					prop.unit = v[4]
				end

				prop.rw = string.upper(v[5] or 'RO')
				if not prop.rw or string.len(prop.rw) == 0 then
					prop.rw = 'RO'
				end

				if v[6] and string.len(v[6]) > 0 then
					prop.vt = v[6]
				else
					prop.vt = 'int'
				end

				prop.ti = string.upper(v[7] or '')
				prop.addr = assert(tonumber(v[8]))

				prop.rate = tonumber(v[9]) or 1
				prop.offset = tonumber(v[10]) or 0
				if v[11] and string.len(v[11]) > 0 then
					prop.slen = tonumber(v[11]) or 1
				end

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
