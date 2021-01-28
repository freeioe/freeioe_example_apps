local class = require 'middleclass'
local client = require 'db.siridb.client'
local database = require 'db.siridb.database'

local hisdb = class('hisdb.hisdb')

function hisdb:initialize(db_name)
	self._dbname = assert(db_name)
	self._client = client:new({})
end

function hisdb:init()
	local list = self._client:get_databases()
	for _, v in ipairs(list) do
		if v == self._dbname then
			print('Found db', self._dbname)
			self._db = database:new({}, self._dbname)
			return true
		end
	end
	local r, err = self._client:new_database(self._dbname, 'ms')

	if r then
		self._db = database:new({}, self._dbname)
	end

	return r, err
end

function hisdb:client()
	return self._client
end

function hisdb:db()
	return assert(self._db)
end

return hisdb
