local tag_finder = require 'hj212.tags.finder'
local base = require 'hj212.server.client'
local cjson = require 'cjson.safe'

local TAG_INFO = {}

local function create_tag_input(tag_name)
	if TAG_INFO[tag_name] then
		return TAG_INFO[tag_name]
	end
	local tag = tag_finder(tag_name)
	if not tag then
		TAG_INFO[tag_name] = {
			name = tag_name,
			desc = tag_name
		}
	else
		TAG_INFO[tag_name] = {
			name = tag_name,
			desc = tag.desc,
			unit = tag.unit
		}
	end
	return TAG_INFO[tag_name]
end

local client = base:subclass('hj212_server.server.client.base')

function client:initialize(server, pfuncs)
	base.initialize(self, pfuncs)
	self._server = server
	self._sn = nil
	self._log = server:log_api()
	self._rdata_map = {}
	self._inputs = {}
	self._inputs_cov = {}
	self:add_handler('handler')
end

function client:sn()
	return self._sn
end

function client:set_sn(sn)
	self._sn = sn
end

function client:set_dev(dev)
	self._dev = dev
end

function client:log_api()
	return self._server:log_api()
end

function client:sys_api()
	return self._server:sys_api()
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

function client:on_station_create(system, dev_id, passwd, ver)
	return self._server:create_station(self, system, dev_id, passwd, ver)
end

function client:on_disconnect()
	return self._server:on_disconnect(self)
end

function client:on_rdata(name, rdata)
	if not self._rdata_map[name] then
		self._inputs_changed = true
		table.insert(self._inputs, create_tag_input(name))
	end
	table.insert(self._inputs_cov, name)
	self._rdata_map[name] = {
		value = rdata.Rtd,
		value_z = rdata.ZsRtd,
		timestamp = rdata.SampleTime,
		quality = (rdata.Flag == 'N') and 0 or string.byte(rdata.Flag),
	}
end

function client:on_run()
	if self._inputs_changed then
		self._inputs_changed = nil
		self._dev:mod(self._inputs)
	end
	if #self._inputs_cov == 0 then
		return
	end

	for _, name in ipairs(self._inputs_cov) do
		local rdata = self._rdata_map[name]
		self._dev:set_input_prop(name, 'value', rdata.value, nil, rdata.quality)
		self._dev:set_input_prop(name, 'RDATA', cjson.encode(rdata), rdata.timestamp, rdata.quality)
	end

	self._inputs_cov = {}
end

return client
