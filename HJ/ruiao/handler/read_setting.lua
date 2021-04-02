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
			print(tag:tag_name(), tag:get('CurrZero'), tag:get('DemCoeff'), tag:get('ScaleGasNd'), 
				tag:get('CailDate'), tag:get('ZeroRange'), tag:get('FullRange'),
				tag:get('ZeroDev'), tag:get('CailDev'), tag:get('ZeroCail'),
				tag:get('ZeroRange'), tag:get('FullRange'), tag:get('ZeroOrigin'),
				tag:get('CailOrigin'), tag:get('RealOrigin'), tag:get('Rtd'))

				--[[
			local rdata = {
				SampleTime = tag:get('SampleTime') or data_time,
				Rtd = tag:get('Rtd'),
				Flag = tag:get('Flag') or 'N',
				ZsRtd = tag:get('ZsRtd')
			}
			self._client:on_rdata(tag:tag_name(), rdata)
			]]--
		end
	end

	return true
end

return handler
