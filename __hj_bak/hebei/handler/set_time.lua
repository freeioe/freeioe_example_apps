local date = require 'date'
local base = require 'hj212.client.handler.base'
local types = require 'hj212.types'

local handler = base:subclass('hj212.client.handler.get_time')

function handler:process(request)
	local params = request:params()
	local pid, err = params:get('PolId')
	if pid == nil then
		return nil, err
	end

	local time, err = params:as_num('SystemTime')
	if not time then
		return nil, err
	end
	local t = date(time)

	self:log('debug', "Set device time for:"..pid..' to:'..t)

	local now = os.time()
	if math.abs(now - time) > 1 then
		return true
	end

	return true
end

return handler
