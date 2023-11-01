local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function valid_ti(ti)
	return true
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
				meta.desc = v[3] or 'CS101 Device'
				meta.series = v[4] or 'XXX'
			end
			if v[1] == 'PROP' then
				local prop = {
					sn = v[2] or 'GW',
					name = v[3] or '',
					desc = v[4] or 'UNKNOWN',
				}

				prop.rw = string.upper(v[5] or 'RO')
				if not prop.rw or string.len(prop.rw) == 0 then
					prop.rw = 'RO'
				end

				prop.srv_id = string.upper(v[6] or '')
				if v[7] and string.len(v[7]) > 0 then
					prop.srv_name = v[7]
				else
					prop.srv_name = prop.name
				end

				prop.rate = tonumber(v[8]) or 1
				prop.node_id = v[9]

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
