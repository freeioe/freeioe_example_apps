local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local valid_dt = {
	bit = true,
	bit_num = true,
	int8 = true,
	uint8 = true,
	int16 = true,
	uint16 = true,
	int32 = true,
	uint32 = true,
	int32_r = true,
	uint32_r = true,
	int64 = true,
	uint64 = true,
	int64_r = true,
	uint64_r = true,
	float = true,
	float_r = true,
	double = true,
	double_r = true,
	raw = true,
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

	if prop.dt == 'raw' then
		if not prop.slen or prop.slen < 1 or prop.slen > 126 then
			return log_cb('Invalid string length found', prop.name, prop.dt, prop.slen)
		end
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function convert_addr(name, index)
	if string.upper(name) == 'X' then
		return tonumber(index, 8)
	elseif string.upper(name) == 'Y' then
		return tonumber(index, 8)
	else
		return tonumber(index)
	end
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
				local name_col = v[2] or ''
				local name, index = string.match('^(%a+)(%d+)')
				local addr = convert_addr(name, index)
				local prop = {
					name = string.upper(name),
					addr = addr,
					desc = v[3] or 'UNKNOWN',
				}
				if string.len(v[4]) > 0 then
					prop.unit = v[4]
				end

				prop.rw = string.upper(v[5] or 'RO')
				if not prop.rw or string.len(prop.rw) == 0 then
					prop.rw = 'RO'
				end

				prop.dt = v[6]
				if not prop.dt or string.len(prop.dt) == 0 then
					prop.dt = 'uint16'
				end

				if v[7] and string.len(v[7]) > 0 then
					prop.vt = v[7]
				else
					prop.vt = 'int'
				end

				prop.cmd = string.upper(v[8] or 'WR')
				prop.rate = tonumber(v[9]) or 1
				prop.wfc = v[10] or 'WT'
				if v[11] and string.len(v[11]) > 0 then
					prop.slen = tonumber(v[11]) or 1
				end

				if prop.dt == 'string' then
					prop.dt = 'raw'
					prop.slen = prop.slen or 1
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
