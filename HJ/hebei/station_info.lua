local base = require 'hjinfo'
local param_tag = require 'hj212.params.tag'
local finder = require 'hj212.tags.finder'

local info = base:subclass('HJ212_HJ_STATION_INFO')

function info:set_conn(poll_id, status, timestamp, quality)
	local status = tonumber(status) == 0 and 0 or 1
	return self:update_value_by_key(poll_id .. '-i22004', status, timestamp, quality)
end

function info:set_conn_list(poll_list, status, timestamp, quality)
	local status = tonumber(status) == 0 and 0 or 1
	assert(status)
	assert(timestamp)
	assert(quality)

	local value, tm = self:get_value()
	assert(tm <= timestamp)

	local changed = false
	for _, v in ipairs(poll_list) do
		local key = v..'-i22004'
		if value[key] == status then
			value[key] = status
			changed = true
		end
	end
	if not changed then
		return
	end

	return self:set_value(value, timemstamp, quality)
end

function info:set_mode(mode, timestamp, quality)
	return self:update_value_by_key('i22001', mode, timestamp, quality)
end

function info:set_alarm(alarm, timestamp, quality)
	return self:update_value_by_key('i22003', mode, timestamp, quality)
end

function info:set_alarm_new(alarm, timestamp, quality)
	return self:update_value_by_key('i22005', mode, timestamp, quality)
end

function info:update_value_by_key(key, val, timestamp, quality)
	assert(val)
	assert(timestamp)
	assert(quality)

	local value, tm = self:get_value()
	assert(tm <= timestamp)
	if value[key] == val then
		return
	end

	value[key] = val

	return self:set_value(value, timemstamp, quality)
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

return info
