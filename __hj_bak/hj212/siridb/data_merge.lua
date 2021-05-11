local class = require 'middleclass'

local data = class('db.data_merge')

function data:initialize()
	self._data = {}
end

function data:push_kv(key, values, time_rate)
	local offset = 0
	local list = self._data
	local exchanged = false
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
			--print(data.timestamp, timestamp, i, index, offset)
			exchanged = true
			while data.timestamp > timestamp do
				if index == 1 then
					--print('insert one ', data.timestamp, timestamp)
					data = {timestamp = timestamp}
					table.insert(list, 1, data)
					break
				end

				offset = offset - 1
				index = index - 1
				data = list[index]
				if math.abs(data.timestamp - timestamp) < 0.001 then
					--print('found data', data.timestamp, timestamp, index, offset)
					break
				end

				if data.timestamp < timestamp then
					--print('insert one ', data.timestamp, timestamp)
					data = {timestamp = timestamp}
					table.insert(list, index, data)
					break
				end
			end
			assert(index >= 0)

			while data.timestamp < timestamp do
				offset = offset + 1
				index = index + 1
				data = list[index]
				if math.abs(data.timestamp - timestamp) < 0.001 then
					break
				end

				if not data then
					--print('insert tail ', data.timestamp, timestamp)
					data = {timestamp = timestamp}
					list[index] = data
					break
				end
				if data.timestamp > timestamp then
					--print('insert one ', data.timestamp, timestamp, index)
					data = {timestamp = timestamp}
					table.insert(list, index - 1, data)
					break
				end
			end
			data[key] = val
			assert(index >= 0)
		end
	end
	--[[
	if exchanged then
		local cjson = require 'cjson.safe'
		print(cjson.encode(values))
		print(cjson.encode(list))
	end
	]]--
end

function data:data()
	return self._data
end

return data
