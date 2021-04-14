local date = require 'date'
local base = require 'hj212.client.handler.base'
local types = require 'hj212.types'

local handler = base:subclass('hj212.client.handler.hb_door_add_persion')

function handler:process(request)
	local params = request:params()

	local data_time = params:get('DataTime')
	if not data_time then
		return nil, "DataTime missing"
	end
	local SFP = params:get('SFP')

	local info = {}

	if params:has_tags() then
		local tags = params:tags()
		if tags[data_time] == nil then
			return nil, "Tags not found"
		end

		for _, tag in pairs(tags[data_time]) do
			info[tag:id()] = tag:get('Info')
		end
	end

	if info.i3310A and info.i3310D and info.i3310J and info.i3310I then
		return self._client:on_door_add_persion(info, SFP == 1)
	end

	return nil, "Incorrect Request"
end

return handler
