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
			print(tag:id(), tag:get('Info'))
		end
	end

	return true
end

return handler
