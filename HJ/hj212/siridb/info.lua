local cjson = require 'cjson.safe'
local base = require 'hj212.calc.db'
local siri_data = require 'db.siridb.data'
local siri_series = require 'db.siridb.series'
local data_merge = require 'siridb.data_merge'

local info = base:subclass('siridb.info')

local DB_VER = 1 -- version

function info:initialize(hisdb, info_name, vt)
	self._hisdb = hisdb
	self._info_name = info_name
	self._vt = vt
	self._samples = {}
	self._db = nil
end

function info:init()
	self._db = assert(self._hisdb:db('INFO'))

	return true
end

function info:push(value, timestamp, quality)
	local val = type(value) ~= 'table' and value or cjson.encode(value)
	table.insert(self._samples, {value = val, timestamp = timestamp, quality = quality})
	if #self._samples > 3600 then
		assert(nil, 'Info Name:'..self._info_name..'\t reach max sample data unsaving')
		self._samples = {}
	end
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
select * from /RDATA.a00000.*/ after 1611980819000
--]]
local read_sql = 'select * from /%s.*/ between %d and %d'
local function build_read(name, stime, etime)
	return string.format(read_sql, name, math.floor(stime * 1000), math.floor(etime * 1000) + 1)
end
function info:read(start_time, end_time)
	assert(start_time and end_time)
	local info_name = self._info_name

	local db = assert(self._db, 'DB not found')
	local sql = build_read(info_name, start_time, end_time)
	local data, err = db:query(sql)
	if not data then
		--TODO: Log error
		return {}
	end

	local dm = data_merge:new()
	for name, values in pairs(data) do
		local c, n, k, t = string.match(name, '^([^%.]+)%.([^%.]+)%.([^%.]+)%.(.+)$')
		if not c or c ~= cate or n ~= info_name then
			goto CONTINUE
		end

		if (k == 'value' and self._vt == t) or k == 'quality' then
			dm:push_kv(k, values, 0.001)
		else
			-- Skip vt not found values
		end
		::CONTINUE::
	end

	--[[
	local cjson = require 'cjson.safe'
	print(info_name, cate, start_time, end_time)
	print(cjson.encode(dm:data()))
	]]--

	return dm:data()
end

function info:write(data, is_array)
	local db_data = siri_data:new()

	if not is_array then
		data = {data}
	end

	local series_map = {}
	for _, d in ipairs(data) do
		for k, v in pairs(d) do
			local series = series_map[k]
			if not series and k ~= 'timestamp' then
				local vt = k == 'value' and self._vt or nil
				if k == 'quality' then
					vt = 'int'
				end

				if vt then
					local name = self._info_name..'.'..k..'.'..vt
					--print(name, vt)
					series = siri_series:new(name, vt)
					series_map[k] = series
					db_data:add_series(name, series)
				end
			end
			if series then
				series:push_value(v, assert(d.timestamp))
			end
		end
	end

	local db = assert(self._db)

	return db:insert(db_data)
end

return info
