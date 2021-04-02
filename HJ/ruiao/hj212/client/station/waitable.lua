local class = require 'middleclass'

local waitable = class('hj212.client.station.waitable')

function waitable:initialize(station, tag_name)
	self._station = station
	self._tag_name = tag_name
end

function waitable:tag()
	return self._station:find_tag(self._tag_name)
end

function waitable:value(timeout)
	local timeout = timeout or 10 --- default is ten seconds
	local tag, err = self._station:find_tag(self._tag_name)
	if not tag then
		return nil, "Cannot found this tag"
	end

	local now = os.time()
	-- Ten seconds
	while os.time() - now < timeout do
		local val, timestamp = tag:get_value()
		if val ~= nil then
			return val, timestamp
		end

		self._station:sleep(50) -- 50 ms
	end
	return nil, "Wait for value timeout"
end

return waitable
