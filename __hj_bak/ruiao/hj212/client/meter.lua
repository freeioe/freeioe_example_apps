local class = require 'middleclass'

local meter = class('hj212.client.meter')

function meter:initialize(sn, info_list, tag_list)
	assert(sn, 'Device SN missing')
	assert(tag_list, 'Device tags missing')
	assert(info_list, 'Device info missing')
	self._sn = sn

	for k, v in pairs(info_list) do
		v:set_meter(self)
	end
	self._info_list = info_list

	for k, v in pairs(tag_list) do
		v:set_meter(self)
	end
	self._tag_list = tag_list
	self._flag = nil
end

function meter:sn()
	return self._sn
end

function meter:find_tag(name)
	return self._tag_list[name]
end

function meter:tag_list()
	return self._tag_list
end

function meter:find_info(name)
	return self._info_list[name]
end

function meter:info_list()
	return self._info_list
end

function meter:set_flag(flag)
	self._flag = flag
end

function meter:get_flag()
	return self._flag
end


function meter:init(err_cb)
	for k, v in pairs(self._info_list) do
		local r, err = v:init()
		if not r then
			err_cb(v:info_name(), err)
		end
	end
end

--- Tags value
function meter:set_tag_value(name, value, timestamp, value_z, flag, quality)
	local tag = self._tag_list[name]
	if tag then
		return tag:set_value(value, timestamp, value_z, flag, quality)
	end
	return nil, "No such tag:"..name
end

--- XXXXX-Info value
function meter:set_info_value(name, value, timestamp, quality)
	local info = self._info_list[name]
	if info then
		return info:set_value(value, timestamp, quality)
	end
	return nil, "No sub info:"..name
end

function meter:rdata(timestamp, readonly)
	local data = {}
	for _, tag in ipairs(self._tag_list) do
		local d = tag:query_rdata(timestamp, readonly)
		if d then
			data[#data + 1] = d
		end
	end
	return data
end

function meter:min_data(start_time, end_time)
	local data = {}
	for _, tag in ipairs(self._tag_list) do
		local vals = tag:query_min_data(start_time, end_time)
		table.move(vals, 1, #vals, #data + 1, data)
	end
	return data
end

function meter:hour_data(start_time, end_time)
	local data = {}
	for _, tag in ipairs(self._tag_list) do
		local vals = tag:query_hour_data(start_time, end_time)
		table.move(vals, 1, #vals, #data + 1, data)
	end
	return data
end

function meter:day_data(start_time, end_time)
	local data = {}
	for _, tag in ipairs(self._tag_list) do
		local vals = tag:query_day_data(start_time, end_time)
		table.move(vals, 1, #vals, #data + 1, data)
	end
	return data
end

function meter:info_data()
	local data = {}
	for _, info in ipairs(self._info_list) do
		data[#data + 1] = info:data()
	end
	return data
end

return meter
