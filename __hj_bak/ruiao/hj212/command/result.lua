local base = require 'hj212.command.base'
local types = require 'hj212.types'

local result = base:subclass('hj212.command.result')

function result:initialize(value)
	local val = value ~= nil and value or types.RESULT.SUCCESS
	base.initialize(self, types.COMMAND.RESULT, {
		ExeRtn = val 
	})
end

return result
