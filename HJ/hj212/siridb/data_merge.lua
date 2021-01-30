local class = require 'middleclass'

local data = class('db.data_merge')

function data:initialize()
	self._data = {}
end

function data:push_kv(key, values, time_rate)
	local offset = 0
	local list = self._data
	for i, v in ipairs(values) do
		local index = i + offset
		assert(index >= 1)

		local timestamp = time_rate and v[1] * time_rate or v[1]
		local val = v[2]

		local data = list[index]
		if not data then 
			data = {timestamp = timestamp}
			list[index] = data
		end

		if math.abs(data.timestamp - timestamp) < 0.001 then
			data[key] = val
		else
			while index >= 1 and data.timestamp > timestamp do
				offset = offset - 1
				index = index - 1
				data = list[index]

				if index == 1 and data.timestamp > timestamp then
					data = {timestamp = timestamp}
					table.insert(list, 1, data)
					offset = 0 -- reset offset
					break
				end
			end
			assert(offset >= 0)

			while data.timestamp < timestamp do
				offset = offset + 1
				index = index + 1
				data = list[index]
				if not data then
					data = {timestamp = timestamp}
					list[index] = data
					break
				end
			end
			data[key] = val
			assert(offset >= 0)
		end
	end
end

function data:data()
	return self._data
end

return data
