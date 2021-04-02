local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.day_status')

function cmd:initialize(data_time, begin_time, end_time)
	base.initialize(self, types.COMMAND.DAY_STATUS, {
		DataTime = data_time,
		BeginTime = begin_time,
		EndTime = end_time,
	})
end

return cmd
