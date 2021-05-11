local class = require 'middleclass'
local utils_sort = require 'hj212.utils.sort'
local cems = require 'hj212.client.station.cems'
local waitable = require 'hj212.client.station.waitable'

local station = class('hj212.client.station')

function station:initialize(conf, sleep_func)
	assert(conf, 'Conf missing')
	assert(conf.system and conf.dev_id and conf.name)
	assert(sleep_func, 'Sleep function missing')

	self._conf = conf
	self._sleep_func = sleep_func

	self._client = nil
	self._tag_list = {}
	self._meters = {}
end

function station:client()
	return self._client
end

function station:set_client(client)
	self._client = client
end

function station:station_name()
	return self._conf.name
end

function station:system()
	return self._conf.system
end

function station:id()
	return self._conf.dev_id
end

function station:passwd()
	return self._conf.passwd
end

function station:timeout()
	return self._conf.timeout
end

function station:retry()
	return self._conf.retry
end

function station:version()
	return self._conf.version
end

function station:rdata_interval()
	return self._conf.rdata_interval
end

function station:min_interval()
	return self._conf.min_interval
end

function station:sleep(ms)
	return self._sleep_func(ms)
end

function station:meters()
	return self._meters
end

function station:find_tag(name)
	return self._tag_list[name]
end

function station:find_tag_meter(name)
	local tag = self._tag_list[name]
	if tag then
		return tag:meter()
	end
	return nil, "Not found"
end

function station:tags()
	return self._tag_list
end

function station:add_meter(meter)
	assert(meter)
	table.insert(self._meters, meter)
	for name, tag in pairs(meter:tag_list()) do
		assert(self._tag_list[name] == nil)
		self._tag_list[name] = tag
	end
end

return station
