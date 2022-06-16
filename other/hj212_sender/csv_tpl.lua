local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local _hj212_name_map = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	if _hj212_name_map[prop.hj212] then
		return log_cb('Name duplicated!!', prop.hj212, prop.sn, prop.name)
	end
	--[[
	if not valid_dt[prop.dt] then
		return log_cb('Invalid prop data type found', prop.name, prop.dt)
	end
	]]--

	return true
end

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local props = {}

	for k,v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'PROP' then
				local prop = {
					sn = v[2],
					name = v[3],
					desc = v[4],
				}

				prop.hj212 = v[5]
				prop.fmt = v[6]
				prop.rate = tonumber(v[7])

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
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
