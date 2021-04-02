local base = require 'hj212.client.handler.base'
local types = require 'hj212.types'

local handler = base:subclass('hj212.client.handler.day_data')

function handler:process(request)
	local params = request:params()
	local stime, err = params:get('BeginTime')
	if not stime  then
		return nil, err
	end
	local etime, err = params:get('EndTime')
	if not etime then
		return nil, err
	end

	self:log('info', "Get HOUR data from: "..stime.." to "..etime)

	stime = stime + 3600 * 24 -- for ending time not start
	etime = etime + 3600 * 24

	return self:client:handle(types.COMMAND.DAY_DATA, stime, etime)
end

return handler
