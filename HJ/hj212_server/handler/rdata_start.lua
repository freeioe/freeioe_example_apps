local base = require 'hj212.server.handler.base'

local handler = base:subclass('hj212.server.handler.rdata_start')

function handler:process(request)
	local params = request:params()
	if not params then
		return nil, "Params missing"
	end
	local data_time = params:get('DataTime')
	if not data_time then
		return nil, "DataTime missing"
	end

	if params:has_tags() then
		local tags = params:tags()

		if tags[data_time] == nil then
			return nil, "Tags not found"
		end

		for _, tag in pairs(tags[data_time]) do
			local rdata = {
				SampleTime = tag:get('SampleTime') or data_time,
				Rtd = tag:get('Rtd'),
				Flag = tag:get('Flag') or 'N',
				ZsRtd = tag:get('ZsRtd')
			}
			self._client:on_rdata(tag:id(), rdata, data_time)
		end
	end

	return true
end

return handler
