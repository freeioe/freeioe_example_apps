local base = require 'hjinfo'
local param_tag = require 'hj212.params.tag'
local finder = require 'hj212.tags.finder'
local copy = require 'hj212.utils.copy'

local info = base:subclass('HJ212_HJ_STATION_INFO')

function info:set_conn(poll_id, status, timestamp, quality)
	local status = tonumber(status) == 0 and 0 or 1
	local val = {
		[poll_id..'-i22004'] = status
	}
	return self:set_value(val, timestamp, quality)
end

function info:set_conn_list(poll_list, status, timestamp, quality)
	local status = tonumber(status) == 1 and 0 or 1
	assert(status)
	assert(timestamp)
	assert(quality)

	local value = {}
	for _, v in ipairs(poll_list) do
		value[v..'-i22004'] = status
	end

	return self:set_value(value, timestamp, quality)
end

function info:set_alarm(alarm, timestamp, quality)
	return self:set_value({
		i22003 = alarm,
		i22005 = alarm
	}, timestamp, quality)
end

function info:get_format(info_name)
	if string.match(info_name, '(.+)%-i22004') then
		local info = finder('i22004')
		return info and info.format or 'N2'
	end

	local info = finder(info_name)
	if info then
		return info.format
	end

	return nil
end

function info:set_value(value, timestamp, quality)
	if value.i23001 then
		value.i23011 = value.i23011 or (value.i23001 * 1000)
	end

	local org = self:get_value()

	for k, v in pairs(org or {}) do
		if value[k] == nil then
			value[k] = v
		end
	end

	return base.set_value(self, value, timestamp, quality)
end

return info
