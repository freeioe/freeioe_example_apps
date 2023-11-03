local ftcsv = require 'ftcsv'

local tpl_dir = 'tpl/'

local function valid_node_id(node_id)
	if string.len(node_id) ~= 12 then
		return nil, 'NodeId length error'
	end
	return true
end

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end
	local r, err = valid_node_id(prop.node_id)
	if not r then
		return log_cb('Invalid NodeId type found', prop.name, prop.node_id, err)
	end

	return true
end

local function load_tpl(name, err_cb)
	local path = tpl_dir..name..'.csv'
	local t = ftcsv.parse(path, ",", {headers=false})

	local meta = {}
	local props = {}
	local devs = {}

	for _, v in ipairs(t) do
		if #v > 1 then
			if v[1] == 'META' then
				meta.name = v[2] or 'BJZD'
				meta.desc = v[3] or '北京中电'
				meta.manufacturer = v[4] or 'BJZD'
				meta.model = v[5] or 'BJZD-X01'
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

				prop.dt = string.upper(v[6] or '')
				if v[7] and string.len(v[7]) > 0 then
					prop.srv_name = v[7]
				else
					prop.srv_name = prop.name
				end

				prop.rate = tonumber(v[8]) or 1
				prop.node_id = string.upper(v[9] or '')

				if valid_prop(prop, err_cb) then
					props[#props + 1] = prop
				end
			end
			if v[1] == 'DEV' then
				local dev = {
					node_id = v[2],
					name = v[3],
					desc = v[4] or 'Unknown Description',
					manufacturer = v[5] or 'Unknown Manufacturer',
					model = v[6] or 'Unknown Model',
				}
				devs[#devs + 1] = dev
			end
		end
	end

	return {
		meta = meta,
		props = props,
		devs = devs,
	}
end

return {
	load_tpl = load_tpl,
	init = function(dir)
		tpl_dir = dir.."/tpl/"
	end
}
