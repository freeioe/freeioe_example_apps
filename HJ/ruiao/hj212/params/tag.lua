local logger = require 'hj212.logger'
local class = require 'middleclass'
local datetime = require 'hj212.params.value.datetime'
local simple = require 'hj212.params.value.simple'
local tag_val = require 'hj212.params.value.tag'

local tag = class('hj212.params.tag')

local fmts = {}
local function ES(fmt)
	local pn = 'hj212.params.tag.ES_'..fmt

	if not fmts[fmt] then
		fmts[fmt] = simple.EASY(pn, fmt)
	end

	return fmts[fmt]
end

local PARAMS = {
	SampleTime = datetime,
	Rtd = tag_val,
	Min = tag_val,
	Avg = tag_val,
	Max = tag_val,
	ZsRtd = tag_val,
	ZsMin = tag_val,
	ZsMax = tag_val,
	ZsAvg = tag_val,
	Flag = ES('C1'),
	EFlag = ES('C4'),
	Cou	= tag_val, -- TODO:
	Data = ES('N3.1'),
	DayDate = ES('N3.1'),
	NightData = ES('N3.1'),
	SN = ES('C24'),
	Info = tag_val,
}

tag.static.PARAMS = PARAMS

function tag:initialize(tag_name, obj, data_time, default_fmt)
	self._name = tag_name
	self._data_time = data_time
	self._default_fmt = default_fmt
	self._items = {}
	self._cloned = nil
	for k, v in pairs(obj or {}) do
		self:set(k, v, default_fmt)
	end
end

function tag:clone(new_tag_name)
	local new_obj = tag:new(new_tag_name)
	new_obj._cloned = true
	new_obj._data_time = self._data_time
	for k, v in pairs(self._items) do
		new_obj._items[k] = v
	end
	return new_obj
end

function tag:transform(func)
	assert(func)
	local new_obj = tag:new(self._name)
	new_obj._data_time = self._data_time
	new_obj._items = {}
	new_obj._default_fmt = self._default_fmt
	for k, v in pairs(self._items) do
		local key, val = func(k, v:value())
		new_obj:set(key, val, self._default_fmt)
	end
	return new_obj
end

function tag:tag_name()
	return self._name
end

function tag:data_time()
	return self._data_time
end

function tag:set_data_time(time)
	self._data_time = time
end

function tag:default_format()
	return self._default_fmt
end

function tag:get(name)
	local p = self._items[name]
	if p then
		return p:value()
	end
	return nil, "Not exists!"
end

function tag:set(name, value, def_fmt)
	assert(not self._cloned)
	local def_fmt = def_fmt or self._default_fmt
	local p = self._items[name]
	if p then
		return p:set_value(value)
	end

	if PARAMS[name] then
		p = PARAMS[name]:new(self._name, value, def_fmt)
	else
		p = simple:new(name, value, def_fmt)
	end
	self._items[name] = p
end

function tag:_set_from_raw(name, value)
	local p = self._items[name]
	if p then
		return p:decode(value)
	end
	if PARAMS[name] then
		p = PARAMS[name]:new(self._name)
	else
		p = simple:new(name)
	end
	self._items[name] = p
	return p:decode(value)
end

function tag:encode()
	local raw = {}
	local sort = {}
	for k, v in pairs(self._items) do
		sort[#sort + 1] = k
	end
	table.sort(sort)
	for _, v in ipairs(sort) do
		local val = self._items[v]
		raw[#raw + 1] = string.format('%s-%s=%s', self._name, v, val:encode())
	end
	return table.concat(raw, ',')
end

function tag:decode(raw)
	self._items = {}

	for param in string.gmatch(raw, '([^;,]+),?') do
		local name, key, val = string.match(param, '^([^%-]+)%-([^=]+)=(.+)')
		if self._name == nil then
			self._name = name
		end
		if name == self._name then
			self:_set_from_raw(key, val)
		else
			logger.error('Error tag attr', name, key, val)
		end
	end
end

return tag
