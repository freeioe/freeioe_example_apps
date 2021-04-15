local base = require 'hj212.calc.db'
local siri_data = require 'db.siridb.data'
local siri_series = require 'db.siridb.series'
local data_merge = require 'siridb.data_merge'
local cjson = require 'cjson.safe'

local poll = base:subclass('siridb.poll')

function poll:initialize(hisdb, poll_id)
	self._hisdb = hisdb
	self._poll_id = poll_id
	self._samples = {}
	self._value_type_map = {}
	self._db_map = {}
end

local function map_value_type(v_type)
	if v_type == 'DOUBLE' then
		return 'float'
	elseif v_type == 'INTEGER' then
		return 'int'
	else
		return 'string'
	end
end

function poll:init()
	local meta = self:sample_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['SAMPLE.'..v.name] = map_value_type(v.type)
	end
	self._db_map['SAMPLE'] = assert(self._hisdb:db('SAMPLE'))

	meta = self:rdata_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['RDATA.'..v.name] = map_value_type(v.type)
	end
	self._db_map['RDATA'] = assert(self._hisdb:db('RDATA'))

	meta = self:cou_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['MIN.'..v.name] = map_value_type(v.type)
		self._value_type_map['HOUR.'..v.name] = map_value_type(v.type)
		self._value_type_map['DAY.'..v.name] = map_value_type(v.type)
	end
	self._db_map['MIN'] = assert(self._hisdb:db('MIN'))
	self._db_map['HOUR'] = assert(self._hisdb:db('HOUR'))
	self._db_map['DAY'] = assert(self._hisdb:db('DAY'))

	return true
end

function poll:get_value_type(cate, prop)
	if prop == 'timestamp' then
		return nil
	end
	local k = cate..'.'..prop
	local vt = self._value_type_map[k]
	if vt then
		return vt
	end
	--print(self._poll_id, cate, prop)
	return nil -- skipped those data
end

function poll:push_sample(data)
	table.insert(self._samples, data)
	if #self._samples > 3600 then
		assert(nil, 'Tag Name:'..self._poll_id..'\t reach max sample data unsaving')
		self._samples = {}
	end
end

function poll:save_samples()
	local list = self._samples
	if #list == 0 then
		return true
	end
	self._samples = {}
	return self:write('SAMPLE', list, true)
end

function poll:read_samples(start_time, end_time)
	return self:read('SAMPLE', start_time, end_time)
end

--[[
select * from /RDATA.a00000.*/ after 1611980819000
--]]
local read_sql = 'select * from /%s.%s.*/ between %d and %d'
local function build_read(cate, name, stime, etime)
	return string.format(read_sql, cate, name, math.floor(stime * 1000), math.floor(etime * 1000) + 1)
end
function poll:read(cate, start_time, end_time)
	assert(cate and start_time and end_time)
	local poll_id = self._poll_id

	local db = assert(self._db_map[cate], 'CATE:'..cate..' not found')
	local sql = build_read(cate, poll_id, start_time, end_time)
	local data, err = db:query(sql)
	if not data then
		--TODO: Log error
		return {}
	end

	local dm = data_merge:new()
	for name, values in pairs(data) do
		local c, n, k, t = string.match(name, '^([^%.]+)%.([^%.]+)%.([^%.]+)%.(.+)$')
		if not c or c ~= cate or n ~= poll_id then
			goto CONTINUE
		end

		local vt = self:get_value_type(cate, k)
		if vt and vt == t then
			dm:push_kv(k, values, 0.001)
		else
			-- Skip vt not found values
		end
		::CONTINUE::
	end

	--[[
	local cjson = require 'cjson.safe'
	print(poll_id, cate, start_time, end_time)
	print(cjson.encode(dm:data()))
	]]--

	return dm:data()
end

function poll:write(cate, data, is_array)
	local db_data = siri_data:new()

	if not is_array then
		data = {data}
	end

	local series_map = {}
	for _, d in ipairs(data) do
		for k, v in pairs(d) do
			local val = v
			local series = series_map[k]
			if not series and k ~= 'timestamp' then
				local vt = self:get_value_type(cate, k)
				if vt then
					local name = cate..'.'..self._poll_id..'.'..k..'.'..vt
					--print(name, vt)
					series = siri_series:new(name, vt)
					series_map[k] = series
					db_data:add_series(name, series)
				end
			end
			if series then
				series:push_value(val, assert(d.timestamp))
			end
		end
	end

	local db = assert(self._db_map[cate])

	return db:insert(db_data)
end

return poll
