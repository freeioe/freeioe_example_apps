local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local NAME_MAP = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	if NAME_MAP[prop.name] then
		log_cb('Duplicated name found:'..prop.name)
	end
	NAME_MAP[prop.name] = prop

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
					sn = v[2],
					name = v[3],
					desc = v[4],
				}
				prop.rate = tonumber(v[5]) or 1
				prop.tag = v[6]
				if not prop.tag or string.len(prop.tag) < 1 then
					prop.tag = prop.name
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
