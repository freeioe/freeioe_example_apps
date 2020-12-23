local ftcsv = require 'ftcsv'

local NAME_CHECKING = {}

local function valid_prop(prop, err_cb)
	local log_cb = function(...)
		if err_cb then
			err_cb(...)
		end
		return false
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
local function load_tpl(path, err_cb)
	assert(path)
	local t = ftcsv.parse(path, ",", {headers=false})

	local props = {}

	for i,v in ipairs(t) do
		if i ~= 1 and  #v > 1 then
			local prop = {
				name = v[1],
				desc = v[2],
				sn = string.len(v[3]) > 0 and v[3] or nil,
				input = v[4],
				setting = tostring(v[5]) == '1'
			}

			if valid_prop(prop, err_cb) then
				table.insert(props, prop)
			end
		end
	end

	return {
		props = sort_props(props)
	}
end

return load_tpl
