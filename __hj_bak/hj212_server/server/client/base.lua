local ioe = require 'ioe'
local types = require 'hj212.types'
local tag_finder = require 'hj212.tags.finder'
local base = require 'hj212.server.client'
local cjson = require 'cjson.safe'

local TAG_INFO = {}

local function create_poll_input(poll_id)
	if TAG_INFO[poll_id] then
		return TAG_INFO[poll_id]
	end
	local tag = tag_finder(poll_id)
	if not tag then
		TAG_INFO[poll_id] = {
			name = poll_id,
			desc = poll_id,
			vt = 'string'
		}
	else
		local vt = 'string'
		if tag.format and string.sub(tag.format, 1, 1) == 'N' then
			vt = 'float'
		end
		TAG_INFO[poll_id] = {
			name = poll_id,
			desc = tag.desc,
			unit = tag.unit,
			vt = vt
		}
	end
	return TAG_INFO[poll_id]
end

local function create_poll_info(poll_id, info_id)
	local poll_id = poll_id .. '_' .. info_id

	if TAG_INFO[poll_id] then
		return TAG_INFO[poll_id]
	end
	local tag = tag_finder(info_id)
	if not tag then
		TAG_INFO[poll_id] = {
			name = poll_id,
			desc = poll_id,
			vt = 'string',
		}
	else
		local vt = 'string'
		if tag.format and string.sub(tag.format, 1, 1) == 'N' then
			vt = 'float'
		end
		TAG_INFO[poll_id] = {
			name = poll_id,
			desc = tag.desc,
			unit = tag.unit,
			vt = vt
		}
	end
	return TAG_INFO[poll_id]
end

local client = base:subclass('hj212_server.server.client.base')

function client:initialize(server, pfuncs)
	base.initialize(self, pfuncs)
	self._server = server
	self._sn = nil
	self._log = server:log_api()
	self._opt = {}

	self._meter_rs = nil -- unknown

	self._rdata_map = {}
	self._inputs = {
		{ name = 'RS', desc = 'Meter state', vt = 'int' },
	}
	self._inputs_changed = true
	self._inputs_cov = {}

	self._info_map = {}
	self._info_cov = {}

	self:add_handler('handler')
end

function client:sn()
	return self._sn
end

function client:set_sn(sn)
	self._sn = sn
end

function client:set_option(opt)
	self._opt = opt or {}
end

function client:rdata_timestamp_reset()
	return string.lower(self._opt.rdata_timestamp_reset or 'NO') == 'yes'
end

function client:timeout()
	return self._opt.timeout or 3000
end

function client:retry()
	return self._opt.retry or 3
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
	local now = ioe.time()
	self._meter_rs = nil
	if self._dev then
		self._dev:set_input_prop('RS', 'value', types.RS.Stoped, now, -1)

		for name, rdata in pairs(self._rdata_map) do
			self._dev:set_input_prop(name, 'value', rdata.value, now, -1)
			self._dev:set_input_prop(name, 'RDATA', cjson.encode(rdata), now, -1)
		end
	end
	return self._server:on_disconnect(self)
end

function client:on_rdata(name, rdata, data_time)
	if not self._rdata_map[name] then
		self._inputs_changed = true
		table.insert(self._inputs, create_poll_input(name))
	end

	table.insert(self._inputs_cov, name)

	local timestamp = rdata.SampleTime or data_time

	if self:rdata_timestamp_reset() then
		timestamp = ioe.time()
	end

	self._rdata_map[name] = {
		value = assert(rdata.Rtd),
		value_z = rdata.ZsRtd,
		timestamp = timestamp,
		flag = rdata.Flag or self:rs_flag()
	}

	if not self._meter_rs and (not rdata.Flag or rdata.Flag == 'N') then
		self._meter_rs = types.RS.Normal
		self._dev:set_input_prop('RS', 'value', self._meter_rs)
	end
end

function client:on_info(name, info_list, no_cov)
	local changed = false
	local info = self._info_map[name]
	if not info then
		self._info_map[name] = {}
		info = self._info_map[name]
		changed = true
	end

	for k, v in pairs(info_list) do
		if info[k] == nil then
			self._inputs_changed = true
			table.insert(self._inputs, create_poll_info(name, k))
		end

		if info[k] ~= v then
			info[k] = v
			changed = true
		end
	end
	if changed or no_cov then
		table.insert(self._info_cov, name)
	end
end

function client:on_run()
	if self._inputs_changed then
		self._inputs_changed = nil
		self._dev:mod(self._inputs)
		self._dev:set_input_prop('RS', 'value', self._meter_rs ~= nil and self._meter_rs or types.RS.Stoped)
	end

	for _, name in ipairs(self._inputs_cov) do
		local rdata = self._rdata_map[name]
		local quality = (self._meter_rs and self._meter_rs ~= types.RS.Normal) and self._meter_rs or nil
		self._dev:set_input_prop(name, 'value', rdata.value, nil, quality)
		self._dev:set_input_prop(name, 'RDATA', rdata, rdata.timestamp)
	end

	for _, name in ipairs(self._info_cov) do
		local info_list = self._info_map[name]
		--print('INFO', name, cjson.encode(info_list))
		self._dev:set_input_prop(name, 'INFO', info_list)

		for k, v in pairs(info_list) do
			self._dev:set_input_prop(name..'_'..k, 'value', v)
		end
	end

	self._inputs_cov = {}
	self._info_cov = {}
end

function client:set_meter_rs(rs)
	assert(rs)
	self._meter_rs = rs
	self._dev:set_input_prop('RS', 'value', self._meter_rs)

	for name, rdata in pairs(self._rdata_map) do
		table.insert(self._inputs_cov, name)
	end
end

function client:rs_flag()
	if not self._meter_rs then
		return nil
	end
	if self._meter_rs == types.RS.Normal then
		return nil -- unset the flag
	end
	if self._meter_rs == types.RS.Stoped then
		return types.FLAG.Stoped
	end
	if self._meter_rs == types.RS.Calibration then
		return types.FLAG.Calibration
	end
	if self._meter_rs == types.RS.Maintain then
		return types.FLAG.Maintain
	end
	if self._meter_rs == types.RS.Alarm then
		return types.FLAG.Error
	end
	if self._meter_rs == types.RS.Clean then
		return types.FLAG.Calibration
	end
	return types.FLAG.Error
end

return client
