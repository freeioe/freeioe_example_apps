local _M = {}

-- SUM(8bits)
local sum = require 'hashings.sum'
local cjson = require 'cjson.safe'

function _M.sum(data)
	return sum:new(data):digest()
end

function _M.tostring(data)
	if type(data) == 'table' and data.__totable then
		return cjson.encode(data:__totable())
	end
	return cjson.encode(data)
end

function _M.totable(data)
	if type(data) == 'table' and data.__totable then
		return data:__totable()
	end
	return data
end

function _M.to_hex(data)
	if type(data) == 'table' and data.to_hex then
		return data:to_hex()
	end
	return data
end

return _M
