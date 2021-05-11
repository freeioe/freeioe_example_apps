local base = require 'hj212.server.handler.base'

local handler = base:subclass('hj212.server.handler.rdata_start')

local tag_names = {
	S01 = 'a19001',
	S02 = 'a01011',
	S03 = 'a01012',
	S04 = 'a01017',
	S05 = 'a01014',
	S06 = 'a01015',
	S07 = 'a01016',
	S08 = 'a01013',
	['01'] = 'a23013',
	['02'] = 'a21026',
	['03'] = 'a21002',
	['04'] = 'a21005',
	['100'] = 'a00000',
}

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
			local tag_name = tag_names[tag:tag_name()] or tag:tag_name()
			self._client:on_rdata(tag_name, rdata)
		end
	end

	return true
end

return handler
