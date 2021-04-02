local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.min_data')

function cmd:initialize(data_time, begin_time, end_time)
	base.initialize(self, types.COMMAND.MIN_DATA, {
		DataTime = data_time,
		BeginTime = begin_time,
		EndTime = end_time,
	})
end

return cmd
