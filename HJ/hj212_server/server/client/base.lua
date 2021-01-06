
local base = require 'hj212.server.client'

local client = base:subclass('hj212_server.server.client.base')

function client:initialize(server)
	base.initialize(self)
	self._server = server
	self._sn = nil
	self._log = server:log_api()
	self:add_handler('handler')
end

function client:sn()
	return self._sn
end

function client:set_sn(sn)
	self._sn = sn
end

function client:log_api()
	return self._server:log_api()
end

function client:dump_raw(io, data)
	return self._server:dump_raw(self._sn, io, data)
end

function client:log(level, ...)
	local f = self._log[level] or self._log.debug
	return f(self._log, ...)
end

function client:server()
	return self._server
end

function client:on_station_create(system, dev_id, passwd)
	return self._server:create_station(self, system, dev_id, passwd)
end

function client:on_disconnect()
	return self._server:on_disconnect(self)
end

return client
