local class = require 'middleclass'
local utils_sort = require 'hj212.utils.sort'
local cems = require 'hj212.client.station.cems'

local station = class('hj212.client.station')

function station:initialize(system, id, sleep_func)
	assert(system, 'System code missing')
	assert(id, 'Device id missing')
	assert(sleep_func, 'Sleep function missing')
	self._system = tonumber(system)
	self._id = id
	self._sleep_func = sleep_func
	self._handlers = {}
	self._tag_list = {}
	self._info_list = {}
	self._meters = {}
	self._cems = cems:new(self)
	self._water = nil
	self._air = nil
	self._calc_mgr = nil
end

function station:set_handlers(handlers)
	self._handlers = handlers or {}
end

function station:system()
	return self._system
end

function station:id()
	return self._id
end

function station:sleep(ms)
	return self._sleep_func(ms)
end

function station:meters()
	return self._meters
end

function station:cems()
	return self._cems
end

function station:water(func)
	if self._water then
		func(self._water)
	else
		self:wait_tag('w00000', function(tag)
			self._water = tag
			func(self._water)
		end)
	end
end

function station:air(func)
	if self._air then
		func(self._air)
	else
		self:wait_tag('a00000', function(tag)
			self._air = tag
			func(self._air)
		end)
	end
end

function station:wait_tag(name, func)
	assert(self._tag_waits, "Cannot call this function out of initing")
	table.insert(self._tag_waits, {
		tag = name,
		func = func
	})
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

function station:calc_mgr()
	return self._calc_mgr
end

function station:init(calc_mgr, err_cb)
	assert(self._calc_mgr == nil)
	self._calc_mgr = calc_mgr
	self._tag_waits = {}

	for _, v in ipairs(self._meters) do
		v:init(err_cb)
	end

	utils_sort.for_each_sorted_key(self._tag_list, function(tag)
		local r, err = tag:init(self)
		if not r then
			err_cb(tag:tag_name(), err)
		end
	end)

	local waits = self._tag_waits
	self._tag_waits = nil
	for _, v in ipairs(waits) do
		local tag = self:find_tag(v.tag)
		v.func(tag)
	end
end

function station:add_meter(meter)
	assert(meter)
	table.insert(self._meters, meter)
	for name, tag in pairs(meter:tag_list()) do
		assert(self._tag_list[name] == nil)
		self._tag_list[name] = tag
	end
	for name, info in pairs(meter:info_list()) do
		assert(self._info_list[name] == nil)
		self._info_list[name] = info
	end
end

--- Tags value
function station:set_tag_value(name, value, timestamp, value_z, flag, quality)
	assert(name ~= nil)
	assert(value ~= nil)
	assert(timestamp ~= nil)
	local tag = self._tag_list[name]
	if tag then
		return tag:set_value(value, timestamp, value_z, flag, quality)
	end
	return nil, "No such tag:"..name
end

function station:set_info_value(name, value, timestamp, quality)
	assert(name ~= nil)
	assert(value ~= nil)
	assert(timestamp ~= nil)
	local info = self._info_list[name]
	if info then
		return info:set_value(value, timestamp, quality)
	end
	return nil, "No such info:"..name
end

function station:rdata(timestamp, readonly)
	local data = {}
	for _, tag in pairs(self._tag_list) do
		if tag:upload() then
			local d = tag:query_rdata(timestamp, readonly)
			if d then
				data[#data + 1] = d
			end
		end
	end
	return data
end

function station:min_data(start_time, end_time)
	local data = {}
	for _, tag in pairs(self._tag_list) do
		if tag:upload() then
			local vals = tag:query_min_data(start_time, end_time)
			if vals then
				table.move(vals, 1, #vals, #data + 1, data)
			end
		end
	end
	return data
end

function station:hour_data(start_time, end_time)
	local data = {}
	for _, tag in pairs(self._tag_list) do
		if tag:upload() then
			local vals = tag:query_hour_data(start_time, end_time)
			if vals then
				table.move(vals, 1, #vals, #data + 1, data)
			end
		end
	end
	return data
end

function station:day_data(start_time, end_time)
	local data = {}
	for _, tag in pairs(self._tag_list) do
		if tag:upload() then
			local vals = tag:query_day_data(start_time, end_time)
			if vals then
				table.move(vals, 1, #vals, #data + 1, data)
			end
		end
	end
	return data
end

function station:info_data()
	local data = {}
	for _, info in pairs(self._info_list) do
		data[#data + 1] = info:data()
	end
	return data
end

function station:update_rdata_interval(interval)
	self._rdata_interval = interval
	if self._handlers.rdata_interval then
		local r, rr, err = pcall(self._handlers.rdata_interval, interval)
		if r then
			return rr, err
		end
		return nil, "Program failure!!"
	end
end

function station:update_min_interval(interval)
	self._min_interval = interval
	if self._handlers.min_interval then
		local r, rr, err = pcall(self._handlers.min_interval, interval)
		if r then
			return rr, err
		end
		return nil, "Program failure!!"
	end
end

function station:set_rdata_interval(interval)
	self._rdata_interval = interval
end

function station:rdata_interval()
	return self._rdata_interval
end

function station:set_min_interval(interval)
	self._min_interval = interval
end

function station:min_interval()
	return self._min_interval
end

return station
