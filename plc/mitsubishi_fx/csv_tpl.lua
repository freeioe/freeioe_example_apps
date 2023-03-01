local ftcsv = require 'ftcsv'
local fx_helper = require 'fx.helper'

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
				local addr_col = assert(v[9])
				local addr_name, addr_index = string.match(addr_col, '^(%a+)(%d+)')
				prop.addr = addr_col
				prop.addr_name = addr_name
				prop.addr_index = fx_helper.convert_addr(addr_name, addr_index)

				prop.rate = tonumber(v[10]) or 1
				prop.wcmd = v[11] or 'WT'
				if v[12] and string.len(v[12]) > 0 then
					prop.slen = tonumber(v[12]) or 1
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
