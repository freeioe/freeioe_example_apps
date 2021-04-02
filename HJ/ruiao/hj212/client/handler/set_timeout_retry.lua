local base = require 'hj212.client.handler.base'

local handler = base:subclass('hj212.client.handler.set_timeout_retry')

function handler:process(request)
	local params = request:params()
	local timeout, err = params:get('OverTime')
	timeout = tonumber(timeout)
	if timeout == nil then
		return nil, err or "Invalid OverTime"
	end
	local retry, err = params:get('ReCount')
	retry = tonumber(retry)
	if timeout == nil then
		return nil, err or "Invalid ReCount"
	end

	self:log('debug', "Set Timeout and Retry", timeout, retry)

	if self._client.set_timeout then
		self._client:set_timeout(timeout)
	else
		return nil, "Client does not support changing timeout"
	end

	if self._client.set_retry then
		self._client:set_retry(retry)
	else
		return nil, "Client does not support changing retry"
	end

	return true
end

return handler
