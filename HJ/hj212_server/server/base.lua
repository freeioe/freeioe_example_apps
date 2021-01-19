local types = require 'hj212.types'
local base = require 'hj212.server.base'

local server = base:subclass('hj212_server.server.base')

function server:initialize(app)
	base.initialize(self)
	self._app = app
	self._io_cb = nil
	self._stations = {}
end

function server:create_station(client, system, dev_id, passwd, ver)
	local sys = self:sys_api()
	local log = self:log_api()
	if self._stations[dev_id] then
		log:error('Client already exists', system, dev_id, passwd)
		return nil, types.REPLY.ERR_UNKNOWN
	end
	local station, err_code = self._app:create_station(client, system, dev_id, passwd)
	if not station then
		local err = string.format('Client auth error ST=%d;PW=%s;MN=%s errno:%d', system, passwd, dev_id, err_code)
		log:error(err)
		sys:timeout(100, function()
			client:close()
		end)
		return nil, err_code
	end
	self._stations[dev_id] = station
	return station
end

function server:valid_connection(client)
	return self._app:valid_connection(client:host(), client:port())
end

function server:on_disconnect(client)
	return self._app:on_client_disconnect(client)
end

function server:sys_api()
	return self._app:sys_api()
end

function server:log_api()
	return self._app:log_api()
end

function server:app()
	return self._app
end

function server:set_io_cb(cb)
	self._io_cb = cb
end

function server:dump_raw(sn, io, data)
	if self._io_cb then
		self._io_cb(sn, io, data)
	end
end

function server:stop()
	self._stations = {}
	return true
end

return server
