local base = require 'hj212.params.value.simple'
local datetime = require 'hj212.params.value.datetime'
local tag_finder = require 'hj212.tags.finder'

local tv = base:subclass('hj212.params.value.tag')

local function get_tag_format(name)
	local tag = tag_finder(name)
	if not tag then
		return nil
	end
	return tag.format	
end

function tv:initialize(name, value, fmt)
	local fmt = fmt or get_tag_format(name)
	base.initialize(self, name, value, fmt)
end

function tv:encode()
	if self._format == 'YYYYMMDDHHMMSS' then
		local d = datetime(self._name, self._value)		
		return d:encode()
	else
		return base.encode(self)
	end
end

function tv:decode(raw, index)
	if self._format == 'YYYYMMDDHHMMSS' then
		local d = datetime(self._name, self._value)		
		local index = d:encode(raw, index)
		self._value = d:value()
	else
		return base.decode(self, raw, index)
	end
end

return tv
