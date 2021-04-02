local base = require 'hj212.client.handler.base'
local command = require 'hj212.command.get_time'
local request = require 'hj212.request.base'

local handler = base:subclass('hj212.client.handler.get_time')

function handler:process(req)
	local params = req:params()
	local pid, err = params:get('PolId')
	if pid == nil then
		return nil, err
	end

	self:log('debug', "Get device time for:"..pid)

	local now = os.time()

	local resp = request:new(command:new(pid, now), false)

	return self:send_request(resp)
end

return handler
