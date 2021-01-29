local ftcsv = require 'ftcsv'

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated prop name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

---
-- [1] hj212 tag name
-- [2] hj212 tag desc
-- [3] rate.Rtd
-- [4] rate.ZsRtd
-- [5] rate.Cou
-- [6] rate.Cou_z
-- [7] rate.Avg
-- [8] rate.ZsAvg
-- [9] rate.Min
-- [10] rate.ZsMin
-- [11] rate.Max
-- [12] rate.ZsMax

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local props = {}

	for i,v in ipairs(t) do
		if i ~= 1 and  #v > 1 then
			local prop = {
				name = v[1],
				desc = v[2],
				Rtd = string.len(v[3]) > 0 and tonumber(v[3]) or nil,
				ZsRtd = string.len(v[4]) > 0 and tonumber(v[4]) or nil,
				Cou = string.len(v[5]) > 0 and tonumber(v[5]) or nil,
				ZsCou = string.len(v[6]) > 0 and tonumber(v[6]) or nil,
				Avg = string.len(v[7]) > 0 and tonumber(v[7]) or nil,
				ZsAvg = string.len(v[8]) > 0 and tonumber(v[8]) or nil,
				Min = string.len(v[9]) > 0 and tonumber(v[9]) or nil,
				ZsMin = string.len(v[10]) > 0 and tonumber(v[10]) or nil,
				Max = string.len(v[11]) > 0 and tonumber(v[11]) or nil,
				ZsMax = string.len(v[12]) > 0 and tonumber(v[12]) or nil,
			}

			if valid_prop(prop, err_cb) then
				props[prop.name] = prop
			end
		end
	end

	return function(name, key, value)
		local prop = props[name]
		if not prop then
			return key, value
		end
		local rate = prop[key]
		if not rate then
			return key, value
		end
		--print(name, key, value, rate, value * rate)
		return key, value * rate
	end
end

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/value_tpl/"
	end
}
