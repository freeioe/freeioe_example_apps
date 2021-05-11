local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.get_info')

function cmd:initialize(data_time, pol_id, info_id, begin_time, end_time)
	local pol_id = pol_id or 'xxxxx'
	local data_time = data_time or os.time()
	base.initialize(self, types.COMMAND.GET_METER_INFO, {
		PolId = pol_id,
		DataTime = data_time,
		InfoId = info_id,
		-- <InfoId>-Info
		BeginTime = begin_time,
		EndTime = end_time,
	})
end

return cmd
