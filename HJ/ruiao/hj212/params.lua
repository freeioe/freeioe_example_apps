local class = require 'middleclass'
local copy = require 'hj212.utils.copy'
local dtime  require 'hj212.params.value.time'
local datetime = require 'hj212.params.value.datetime'
local simple = require 'hj212.params.value.simple'
local sts_param = require 'hj212.params.state'
local tag_param = require 'hj212.params.tag'
local settings = require 'hj212.settings'

local params = class('hj212.params')

local max_packet_len = settings.MAX_PACKET_LEN or 1024

local fmts = {}
local function ES(fmt)
	local pn = 'hj212.params.ES_'..fmt

	if not fmts[fmt] then
		fmts[fmt] = simple.EASY(pn, fmt)
	end

	return fmts[fmt]
end

local PARAMS = {
	SystemTime = datetime,
	QnRtn = ES('N3'),
	ExeRtn = ES('N3'),
	RtdInterval = ES('N4'),
	MinInterval = ES('N2'),
	RestartTime = datetime,
	PolId = ES('C6'),
	BeginTime = datetime,
	EndTime = datetime,
	DataTime = datetime,
	NewPW = ES('C6'),
	OverTime = ES('N2'),
	ReCount = ES('N2'),
	VaseNo = ES('N2'),
	CstartTime = dtime,
	Ctime = ES('N2'),
	Stime = ES('N4'),
	InfoId = ES('C6'),
}

params.static.PARAMS = PARAMS

function params:initialize(obj)
	self._has_states = false
	self._states = {}
	self._has_tags = false
	self._tags = {}
	self._params = {}
	for k, v in pairs(obj or {}) do
		self:set(k, v)
	end
end

function params:has_tags()
	return self._has_tags
end

function params:tags()
	return self._tags
end

function params:has_states()
	return self._has_states
end

function params:statess()
	return self._states
end

function params:get(name)
	local p = self._params[name]
	if p then
		return p:value()
	end
	return nil, "Not exists!"
end

function params:as_num(name)
	local r, err = self:get(name)
	if r then
		local rn = tonumber(r)
		if not rn then
			return nil, "Not numberic value"
		end
		return rn
	end
	return nil, err
end

function params:set(name, value)
	local p = self._params[name]
	if p then
		return p:set_value(value)
	end

	if PARAMS[name] then
		p = PARAMS[name]:new(name, value)
	else
		p = simple:new(name, value, 'N32')
	end
	self._params[name] = p
end

function params:set_from_raw(name, raw_value)
	local p = self._params[name]
	if p then
		return p:decode(raw_value)
	end

	if PARAMS[name] then
		p = PARAMS[name]:new(name, 0)
	else
		p = simple:new(name, 0, 'N32')
	end
	self._params[name] = p
	return p:decode(raw_value)
end

function params:add_states(data_time, sts)
	assert(data_time)
	self._has_states = true
	local t = self._states[data_time] or {}
	table.insert(t, sts)
	self._states[data_time] = t
end

function params:add_tag(data_time, tag)
	assert(data_time)
	self._has_tags = true
	local t = self._tags[data_time] or {}
	table.insert(t, tag)
	self._tags[data_time] = t
end

function params:encode_states(base)
	local data = {}
	for data_time, stss in pairs(self._states) do
		local function create_data_sub()
			local data_sub = copy.deep(base)
			table.insert(data_sub, string.format('DataTime=%s', datetime:new('DataTime', data_time):encode()))
			local len = string.len(table.concat(data_sub, ';'))
			return data_sub, len
		end
		local data_sub, len = create_data_sub()

		for i, sts in ipairs(stss) do
			local sts_data = sts:encode()
			len = len + string.len(sts_data) + 1

			if len > max_packet_len then
				table.insert(data, table.concat(data_sub, ';'))
				data_sub, len = create_data_sub()
				len = len + string.len(sts_data) + 1
			end
			table.insert(data_sub, sts_data)
		end
		-- Insert data_sub to data
		table.insert(data, table.concat(data_sub, ';'))
	end

	return data
end

function params:encode_tags(base)
	local data = {}
	for data_time, tags in pairs(self._tags) do
		table.sort(tags, function(a, b)
			return a:tag_name() < b:tag_name()
		end)
		local function create_data_sub()
			local data_sub = copy.deep(base)
			table.insert(data_sub, string.format('DataTime=%s', datetime:new('DataTime', data_time):encode()))
			local len = string.len(table.concat(data_sub, ';'))
			return data_sub, len
		end
		local data_sub, len = create_data_sub()

		for i, tag in ipairs(tags) do
			local tag_data = tag:encode()
			len = len + string.len(tag_data) + 1

			if len > max_packet_len then
				table.insert(data, table.concat(data_sub, ';'))
				data_sub, len = create_data_sub()
				len = len + string.len(tag_data) + 1
			end
			table.insert(data_sub, tag_data)
		end
		-- Insert data_sub to data
		table.insert(data, table.concat(data_sub, ';'))
	end

	return data
end

function params:encode()
	-- Remove the DataTime if has states or tags
	if self._has_tags or self._has_states then
		self._params['DataTime'] = nil
	end

	--- Sort the base keys
	local sort = {}
	for k, v in pairs(self._params) do
		sort[#sort + 1] = k
	end
	table.sort(sort)

	local raw = {}
	for _, v in ipairs(sort) do
		local val = self._params[v]
		raw[#raw + 1] = string.format('%s=%s', v, val:encode())
	end

	local stss = self:encode_states(raw)
	local tags = self:encode_tags(raw)
	if #stss == 0 and #tags == 0 then
		return table.concat(raw, ';')
	else
		local data = {}
		for _, v in ipairs(stss) do
			table.insert(data, v)
		end
		for _, v in ipairs(tags) do
			table.insert(data, v)
		end
		return data
	end
end

function params:decode(raw, index)
	self._params = {}
	local stss = {}
	local tags = {}

	for param in string.gmatch(raw, '([^;]+);?') do
		local key, val = string.match(param, '^([^=]+)=(.+)')
		assert(key, "Key mising on "..param)
		assert(val, "Val mising on "..param)
		if PARAMS[key] then
			self:set_from_raw(key, val)
		else
			if string.sub(key, 1, 2) == 'SB' then
				local m = '^SB([^%-]+)%-(%w+)'
				local dev_name, type_name = string.match(key, m)
				if dev_name and type_name then
					sts = sts_param:new(dev_name)
					sts:decode(param)
					table.insert(stss, tag)
				else
					logger.error('Error SB found')
				end
			else
				local m = '^([^%-]+)%-(%w+)'
				local tag_name, type_name = string.match(key, m)
				if tag_name and type_name then
					tag = tag_param:new(tag_name)
					tag:decode(param)
					table.insert(tags, tag)
				end
			end
		end
	end

	local data_time = self:get('DataTime')
	if #tags > 0 then
		self._tags[data_time] = tags
		self._has_tags = true
	end
	if #stss > 0 then
		self._states[data_time] = stss
		self._has_states = true
	end
end

return params
