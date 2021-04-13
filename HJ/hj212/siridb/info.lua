local cjson = require 'cjson.safe'
local base = require 'hj212.calc.db'
local siri_data = require 'db.siridb.data'
local siri_series = require 'db.siridb.series'
local data_merge = require 'siridb.data_merge'

local info = base:subclass('siridb.info')

local DB_VER = 1 -- version

function info:initialize(hisdb, poll_id)
	self._hisdb = hisdb
	self._poll_id = poll_id
	self._samples = {}
	self._db = nil
end

function info:init()
	self._db = assert(self._hisdb:db('INFO'))

	return true
end

function info:push(value, timestamp, quality)
	assert(type(value) == 'table')
	local val, err = cjson.encode({quality, value})
	if not val then
		return nil, err
	end

	table.insert(self._samples, {value = val, timestamp = timestamp})
	if #self._samples > 3600 then
		assert(nil, 'Info of pollut:'..self._poll_id..'\t reach max sample data unsaving')
		self._samples = {}
	end
end

function info:samples_size()
	return #self._samples
end

function info:save()
	local list = self._samples
	if #list == 0 then
		return true
	end
	self._samples = {}
	return self:write(list, true)
end

--[[
select * from /INFO.a00000.*/ after 1611980819000
--]]
local read_sql = 'select * from %s between %d and %d'
local function build_read(name, stime, etime)
	return string.format(read_sql, name, math.floor(stime * 1000), math.floor(etime * 1000) + 1)
end
function info:read(start_time, end_time)
	assert(start_time and end_time)
	local info_name = 'INFO.'..self._poll_id

	local db = assert(self._db, 'DB not found')
	local sql = build_read(info_name, start_time, end_time)
	local data, err = db:query(sql)
	if not data then
		--TODO: Log error
		return {}
	end

	local values = data[info_name]
	if not values then
		print(cjson.encode(data))
		return {}
	end

	local data = {}
	for _, v in ipairs(values) do
		local timestamp = v[1] * 0.001
		local val, err = cjson.decode(v[2])
		if val then
			table.insert(data, {
				timestamp = timestamp,
				value = val[2],
				quality = val[1]
			})
		else
			print(err)
		end
	end

	--[[
	local cjson = require 'cjson.safe'
	print(poll_id, cate, start_time, end_time)
	print(cjson.encode(dm:data()))
	]]--

	return data
end

function info:write(data)
	local db_data = siri_data:new()

	local name = 'INFO.'..self._poll_id
	local series = siri_series:new(name, 'string')

	for _, d in ipairs(data) do
		print(_, d.timestamp, d.value)
		series:push_value(d.value, assert(d.timestamp))
	end

	db_data:add_series(name, series)

	local db = assert(self._db)

	return db:insert(db_data)
end

return info
