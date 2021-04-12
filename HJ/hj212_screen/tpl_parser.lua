local ftcsv = require 'ftcsv'

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		else
			print(...)
		end
		return false
	end

	if string.len(prop.sn or '') == 0 then
		return log_cb('Invalid device sn found', prop.name, prop.sn)
	end

	if string.len(prop.input or '') == 0 then
		return log_cb('Invalid tag input name found', prop.name, prop.sn, prop.input)
	end

	if NAME_CHECKING[prop.name] then
		return log_cb("Duplicated prop name found", prop.name)
	end
	NAME_CHECKING[prop.name] = true

	return true
end

local function valid_setting(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
	end

	--[[
	if string.len(prop.hj212 or '') == 0 then
		return log_cb('Invalid HJ212 tag name found', prop.name, prop.sn)
	end
	]]--

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
local function load_tpl(path, err_cb)
	assert(path)
	local t = ftcsv.parse(path, ",", {headers=false})

	local inputs = {}
	local status = {}
	local settings = {}

	for i,v in ipairs(t) do
		if v[1] == 'INPUT' then
			local prop = {
				name = v[2],
				desc = v[3],
				sn = string.len(v[4]) > 0 and v[4] or nil,
				input = v[5],
			}

			if valid_prop(prop, err_cb) then
				table.insert(inputs, prop)
			end
		end
		if v[1] == 'STATUS' then
			local prop = {
				name = v[2],
				desc = v[3],
				sn = string.len(v[4]) > 0 and v[4] or nil,
				input = v[5]
			}
			local option, input = string.match(prop.input, '^%[(.+)%](.+)$')
			if option and input then
				local t, port = string.match(option, '^(.+)%.(.+)$')
				if t and port then
					prop.input = input
					prop.stat = {port = port}
				end
			end
			if valid_prop(prop, err_cb) then
				table.insert(status, prop)
			end
		end
		if v[1] == 'SETTING' then
			local setting = {
				name = v[2],
				desc = v[3],
				hj212 = string.len(v[4]) > 0 and v[4] or nil,
				vt = string.len(v[5]) > 0 and v[5] or nil
			}
			if valid_setting(setting, err_cb) then
				table.insert(settings, setting)
			end
		end
	end

	return {
		inputs = sort_props(inputs),
		status = sort_props(status),
		settings = sort_props(settings),
	}
end

return load_tpl
