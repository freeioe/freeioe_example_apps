local ftcsv = require 'ftcsv'
local utils_sort = require 'hj212.utils.sort'

local tpl_dir = 'tpl/'

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	if string.len(prop.sn or '') == 0 then
		return log_cb('Invalid device serial number found', prop.name, prop.sn)
	end

	if string.len(prop.input or '') == 0 then
		return log_cb('Invalid pollut input name found', prop.name, prop.input)
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated prop name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function sort_props(props)
	table.sort(props, function(a, b)
		return utils_sort.string_compare(a.name, b.name)
	end)

	return props
end

local function NA_BOOL(val, default)
	if val == nil or val == '' then
		return default
	end

	if string.upper(val) == 'N/A' or string.upper(val) == 'N' or string.lower(val) == 'false' then
		return false
	end
	if string.upper(val) == 'Y' or string.lower(val) == 'true' then
		return true
	end
	return default
end

local function NA_BOOL_NUMBER(val, default, num_def)
	if val == nil or val == '' then
		return default
	end

	if string.upper(val) == 'N/A' or string.upper(val) == 'N' or string.lower(val) == 'false' then
		return false
	end
	if string.upper(val) == 'Y' or string.lower(val) == 'true' then
		return true
	end

	return tonumber(val) or (num_def or 0)
end

---
-- [1] hj212 pollut name
-- [2] hj212 pollut desc
-- [3] hj212 pollut unit (not used by HJ212 stack)
-- [4] hj212 pollut vt (not used by HJ212 stack)
-- [5] source device sn (without sys_id as the prefix)
-- [6] source pollut name
-- [7] source pollut value rate
-- [8] hj212 pollut value format (optional)
-- [9] hj212 pollut value calc

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local devs = {}
	local props = {}

	for i,v in ipairs(t) do
		if i ~= 1 and  #v > 1 then
			local prop = {
				name = v[1],
				desc = v[2],
				unit = v[3],
				vt = string.len(v[4]) > 0 and v[4] or 'float',
				sn = v[5],
				input = v[6],
			}

			if string.len(v[7]) > 0 then
				prop.rate = tonumber(v[7]) or 1
			else
				prop.rate = 1
			end

			prop.min = string.len(v[8] or '') > 0 and tonumber(v[8]) or nil
			prop.max = string.len(v[9] or '') > 0 and tonumber(v[9]) or nil
			prop.fmt = string.len(v[10] or '') > 0 and v[10] or nil
			prop.calc = string.len(v[11] or '') > 0 and v[11] or nil
			prop.cou_calc = string.len(v[12] or '') > 0 and v[12] or nil
			prop.upload = NA_BOOL(v[13], true)
			prop.cou = NA_BOOL_NUMBER(v[14], true) -- false will not upload cou, number will set the COU to this number
			prop.zs = string.len(v[15] or '') > 0 and v[15] or nil
			prop.hj2005 = string.len(v[16] or '') > 0 and v[16] or nil
			prop.src_prop = string.len(v[17] or '') > 0 and v[17] or nil
			prop.dt = string.len(v[18] or '') > 0 and tonumber(v[18]) or 0

			if valid_prop(prop, err_cb) then
				local dev = devs[prop.sn] 
				if not dev then
					dev = {}
					devs[prop.sn] = dev
				end
				table.insert(dev, prop)

				table.insert(props, {
					name =prop.name, 
					dev = dev,
					prop = prop,
				})
			end
		end
	end

	return {
		devs = devs,
		props = sort_props(props)
	}
end

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
