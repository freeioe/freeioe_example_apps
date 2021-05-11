local class = require 'middleclass'
local cjson = require 'cjson.safe'
local logger = require 'hj212.logger'
local types = require 'hj212.types'
local param_tag = require 'hj212.params.tag'
local calc_mgr_m = require 'hj212.calc.manager'

local tag = class('hj212.client.tag')

--- Calc name
-- Has COU is nil will using auto detect
function tag:initialize(station, name, options)
	assert(station)
	assert(name, "Tag name missing")
	self._station = station
	self._meter = nil

	-- Options
	self._name = name
	self._min = options.min
	self._max = options.max
	self._cou = options.cou -- {calc='simple', cou=0, params = {...}}
	self._fmt = options.fmt
	self._zs_calc = options.zs_calc

	-- Data current
	self._value = nil
	self._flag = types.FLAG.Normal
	self._timestamp = nil
	self._quality = nil
	self._flag = nil

	-- COU calculator
	self._cou_calc = nil
	self._inited = false
end

--- Guess the proper calculator name
local function guess_calc_name(tag_name)
	if string.sub(tag_name, 1, 1) == 'w' then
		return 'water'
	elseif string.sub(tag_name, 1, 1) == 'a' then
		return 'air'
	else
		-- Default is simple calculator
		return 'simple'
	end
end

function tag:init()
	if self._inited then
		return
	end
	local calc_mgr = self._station:calc_mgr()

	local tag_name = self._name
	assert(tag and tag_name)

	local calc_name = self._cou.calc or guess_calc_name(tag_name)
	assert(calc_name)

	local m = assert(require('hj212.calc.'..calc_name))

	local msg = string.format('TAG [%06s] COU:%s ZS:%d', tag_name, calc_name, self._zs_calc and 1 or 0)
	local params = self._cou.params or {}
	if #params > 0 then
		msg = msg .. ' with '..cjson.encode(params)
	end
	logger.log('info', msg)

	local cou_base = upper_tag and upper_tag:cou_calc() or nil
	local mask = calc_mgr_m.TYPES.ALL

	local cou_calc = m:new(self._station, tag_name, mask, self._min, self._max, self._zs_calc, table.unpack(params))

	cou_calc:set_callback(function(type_name, val, timestamp, quality)
		if val.cou ~= nil and type(self._cou.cou) == 'number' then
			val.cou = has_cou
		end

		return self:on_calc_value(type_name, val, timestamp, quality)
	end)

	self._cou_calc = cou_calc
	calc_mgr:reg(self._cou_calc)

	self._inited = true

	return true
end

function tag:inited()
	return self._inited
end

function tag:set_meter(mater)
	self._meter = mater
end

function tag:meter()
	return self._meter
end

function tag:tag_name()
	return self._name
end

function tag:cou_calc()
	return self._cou_calc
end

function tag:upload()
	assert(nil, "Not implemented")
end

function tag:on_calc_value(type_name, val, timestamp)
	assert(nil, "Not implemented")
end

function tag:set_value(value, timestamp, value_z, flag, quality)
	local flag = flag == nil and self._meter:get_flag() or nil
	self._value = value
	self._value_z = value_z
	self._timestamp = timestamp
	self._flag = flag
	self._quality = quality
	return self._cou_calc:push(value, timestamp, value_z, flag, quality)
end

function tag:get_value()
	return self._value, self._timestamp, self._value_z, self._flag, self._quality
end

function tag:query_rdata(timestamp, readonly)
	local val, err = self._cou_calc:query_rdata(timestamp, readonly)
	if not val then
		logger.log('warning', self._name..' rdata missing', err)
		return nil, err
	end

	return param_tag:new(self._name, {
		Rtd = val.value,
		Flag = val.flag,
		ZsRtd = val.value_z,
		--- EFlag is optional
		SampleTime = val.src_time or val.timestamp,
	}, timestamp, self._fmt)
end

function tag:convert_data(data)
	local rdata = {}
	local has_cou = self._cou.cou
	for k, v in ipairs(data) do
		if has_cou ~= false then
			rdata[#rdata + 1] = param_tag:new(self._name, {
				Cou = v.cou,
				Avg = v.avg,
				Min = v.min,
				Max = v.max,
				ZsAvg = v.avg_z,
				ZsMin = v.min_z,
				ZsMax = v.max_z,
				Flag = v.flag,
			}, v.stime, self._fmt)
		else
			rdata[#rdata + 1] = param_tag:new(self._name, {
				Avg = v.avg,
				Min = v.min,
				Max = v.max,
				ZsAvg = v.avg_z,
				ZsMin = v.min_z,
				Flag = v.flag,
			}, v.stime, self._fmt)
		end
	end
	return rdata
end

function tag:query_min_data(start_time, end_time)
	local data = self._cou_calc:query_min_data(start_time, end_time)
	return self:convert_data(data)
end

function tag:query_hour_data(start_time, end_time)
	local data = self._cou_calc:query_hour_data(start_time, end_time)
	return self:convert_data(data)
end

function tag:query_day_data(start_time, end_time)
	local data = self._cou_calc:query_day_data(start_time, end_time)
	return self:convert_data(data)
end

return tag
