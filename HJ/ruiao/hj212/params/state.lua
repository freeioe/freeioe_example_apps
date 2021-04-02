local class = require 'middleclass'
local logger = require 'hj212.logger'
local simple = require 'hj212.params.value.simple'

local state = class('hj212.params.state')

local fmts = {}
local function ES(fmt)
	local pn = 'hj212.state.ES_'..fmt

	if not fmts[fmt] then
		fmts[fmt] = simple.EASY(pn, fmt)
	end

	return fmts[fmt]
end

local PARAMS = {
	RS = ES('N1'),
	RT = ES('N2.2'),
}

state.static.PARAMS = PARAMS

function state:initialize(dev_name, obj)
	self._name = dev_name
	self._items = {}
	for k, v in pairs(obj or {}) do
		self:set(k, v)
	end
end

function state:get(name)
	local p = self._items[name]
	if p then
		return p:value()
	end
	return nil, "Not exists!"
end

function state:set(name, value)
	local p = self._items[name]
	if p then
		return p:set_value(value)
	end

	if PARAMS[name] then
		p = PARAMS[name]:new(name, value)
	else
		p = simple:new(name, value, 'N32')
	end
	self._items[name] = p
end

function state:_set_from_raw(name, value)
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

function state:encode()
	local raw = {}
	local sort = {}
	for k, v in pairs(self._items) do
		sort[#sort + 1] = k
	end
	table.sort(sort)
	for _, v in ipairs(sort) do
		local val = self._items[v]
		raw[#raw + 1] = string.format('SB%s-%s=%s', self._name, v, val:encode())
	end
	return table.concat(raw, ',')
end

function state:decode(raw)
	self._items = {}

	for param in string.gmatch(raw, '([^,;]+),?') do
		local name, key, val = string.match(param, '^SB([^%-]+)%-([^=]+)=(%w+)')
		if name == self._name then
			self:_set_from_raw(key, val)
		else
			logger.error("Error found", name, key, val)
		end
	end
end

return state
