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

	if string.len(prop.sn or '') == 0 then
		return log_cb('Invalid device serial number found', prop.name, prop.sn)
	end

	if string.len(prop.input or '') == 0 then
		return log_cb('Invalid tag input name found', prop.name, prop.input)
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated prop name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function sort_props(props)
	table.sort(props, function(a, b)
		return a.name < b.name
	end)

	return props
end

---
-- [1] hj212 tag name
-- [2] hj212 tag desc
-- [3] hj212 tag unit (not used by HJ212 stack)
-- [4] hj212 tag vt (not used by HJ212 stack)
-- [5] source device sn (without sys_id as the prefix)
-- [6] source tag name
-- [7] source tag value rate
-- [8] hj212 tag value format (optional)
-- [9] hj212 tag value calc

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

			prop.fmt = string.len(v[8]) > 0 and v[8] or nil
			prop.min = string.len(v[9]) > 0 and tonumber(v[9]) or nil
			prop.max = string.len(v[10]) > 0 and tonumber(v[10]) or nil
			prop.calc = string.len(v[11]) > 0 and v[11] or nil
			prop.sum = string.len(v[12]) > 0 and v[12] or nil

			if valid_prop(prop, err_cb) then
				if not devs[prop.sn] then
					devs[prop.sn] = {}
				end
				table.insert(devs[prop.sn], prop)
				table.insert(props, {
					name =prop.name, 
					dev = devs[prop.sn],
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
