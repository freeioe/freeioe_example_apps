local class = require 'middleclass'
local param_tag = require 'hj212.params.tag'

local info = class('hj212.client.info')

function info:initialize(station, name, options)
	assert(station)
	assert(name)

	self._station = station
	self._meter = nil

	self._name = name
	self._fmt = options.fmt
	self._info = nil
	self._timestamp = nil
end

function info:info_name()
	return self._name
end

function info:set_meter(meter)
	self._meter = meter
end

function info:meter()
	return self._meter
end

function info:set_value(info, timestamp, quality)
	self._info = info
	self._timestamp = timestamp
	self._quality = quality
	return true
end

function info:get_value()
	return self._info, self._timestamp, self._quality
end

function info:data()
	if type(self._info) ~= 'table' then
		return param_tag:new(self._name, {
			Info = self._info
		}, timestamp, self._fmt)
	else
		return param_tag:new(self._name, self._info, timestamp, self._fmt)
	end
end

return info
