--- 导入需求的模块
local date = require 'date'
local ioe = require 'ioe'
local app_base = require 'app.base'
local conf = require 'app.conf'
local sysinfo = require 'utils.sysinfo'
local timer = require 'utils.timer'

local types = require 'hj212.types'
local hj212_logger = require 'hj212.logger'
local station = require 'hj212.server.station'

local tcp_server = require 'server.tcp'
local serial_server = require 'server.serial'

--- lua_HJ212_version: 2021-01-15

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_SERVER_APP")
--- 设定应用最小运行接口版本, 9 has new api and lua5.4???
app.static.API_VER = 9

function app:on_init()
	self._stations = {}
	self._clients = {}
	self._childs = {}
	self._devs = {}
	self._dev = nil
	local log = self:log_api()
	hj212_logger.set_log(function(level, ...)
		assert(level and log[level])
		log[level](log, ...)
	end)
end

function app:create_station(client, system, dev_id, passwd, ver)
	self._log:info('Auth client', system, dev_id, passwd, ver)
	local s = self._stations[dev_id]
	if not s then
		self._log:error('Client MN invalid')
		return nil, types.REPLY.ERR_MN
	end
	local station = s.station
	if station:client() then
		self._log:error('Client MN already connected')
		return nil, types.REPLY.REJECT
	end

	if tonumber(station:system()) ~= tonumber(system) then
		self._log:error('Client ST invalid')
		return nil, types.REPLY.ERR_ST
	end
	if station:passwd() ~= passwd then
		self._log:error('Client PW invalid')
		return nil, types.REPLY.ERR_PW
	end

	local dev_sn = assert(s.sn)

	if not self._devs[dev_sn] then
		local dev = self:create_device(dev_sn, s.info)
		self._devs[dev_sn] = dev
	end

	client:set_sn(dev_sn)
	client:set_dev(self._devs[dev_sn])

	station:set_client(client)

	self._dev:set_input_prop('status_'..dev_id, 'value', 1)
	local info = string.format('%s:%s', client:host(), client:port())
	self._dev:set_input_prop('client_'..dev_id, 'value', info)

	self._clients[dev_sn] = client

	return station
end

function app:valid_connection(host, port)
	return true
end

function app:on_client_disconnect(client)
	local sn = client:sn()
	if not sn then
		return
	end
	self._log:error('Client disconnected', sn)

	client:set_sn(nil)
	self._clients[sn] = nil

	if self._devs[sn] then
		--[[
		local api = self:data_api()
		api:del_device(self._devs[sn])
		self._devs[sn] = nil
		]]--
	end

	for k, v in pairs(self._stations) do
		if v.sn == sn then
			v.station:set_client(nil)
			self._dev:set_input_prop('status_'..k, 'value', 0)
			self._dev:set_input_prop('client_'..k, 'value', '')
			return
		end
	end
end

function app:create_device(sn, info)
	assert(sn)
	local api = self:data_api()
	local sys = self:sys_api()

	local meta = api:default_meta()
	meta.name = 'HJ212 Station - '..info.name
	meta.manufacturer = 'FreeIOE.org'
	meta.description = 'HJ212 Smart Device'
	meta.series = 'N/A'

	local commands = {
		{ name = 'rdata_start', desc = "Start RData upload" },
		{ name = 'rdata_stop', desc = "Stop RData upload" },
		{ name = 'set_time', desc = "Set time sync" },
	}

	local dev = api:add_device(sn, meta, {}, nil, commands)
	return dev
end

--- 应用启动函数
function app:on_start()
	local api = self:data_api()
	local sys = self:sys_api()
	local conf = self:app_conf()

	conf.port = tonumber(conf.port or '') or 6000
	conf.stations = conf.stations or {}

	if ioe.developer_mode() and #conf.stations == 0 then
		conf.channel_type = 'serial'
		table.insert(conf.stations, {
			name = 'station_1',
			system = '31',
			dev_id = '88888880000001',
			passwd = '123456',
			timeout = 5,
			retry = 3,
			rdata_interval = 30, -- 30 seconds
			min_interval = 10, -- 10 mins
		})
	end

	self._stations = {}
	self._devs = {}
	local inputs = {
		{name = 'host', desc = 'Listen Host', vt = 'string'},
		{name = 'port', desc = 'Listen Port', vt = 'int'},
		--{name = 'connections', desc = 'Currrent Connection Count', vt = 'int'},
	}
	local sys_id = sys:id()

	for i, v in ipairs(conf.stations) do
		local st = station:new(v, function(ms)
			sys:sleep(ms)
		end)

		local station_sn = sys_id..'.'..self:app_name()..'.'..v.dev_id

		self._stations[v.dev_id] = {
			sn = station_sn,
			station = st,
			info = v,
		}
		inputs[#inputs + 1] = {
			name = 'status_'..v.dev_id,
			desc = 'Station '..v.name..' connection status',
			vt = 'int'
		}
		inputs[#inputs + 1] = {
			name = 'client_'..v.dev_id,
			desc = 'Station '..v.name..' connection information',
			vt = 'string'
		}
	end

	local meta = api:default_meta()
	meta.name = 'HJ212 Server Status' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Server Status' 
	meta.series = 'N/A'
	local commands = {
		{ name = 'kick', desc = "Kick connection" },
	}
	local dev_sn = sys_id..'.'..self:app_name()
	self._dev = api:add_device(dev_sn, meta, inputs, nil, commands)

	local opt = conf.serial_opt or {
		port = "/tmp/ttyS1",
		--port = "/dev/ttyUSB0",
		baudrate = 9600
	}
	self._server = serial_server:new(self, opt)

	self._dev:set_input_prop('host', 'value', opt.port)
	self._dev:set_input_prop('port', 'value', 0)

	self._server:set_io_cb(function(sn, io, data)
		--self._log:trace(io, data)
		local dev = self._devs[sn]
		if not dev then
			sys:dump_comm(nil, io, data)
		else
			dev:dump_comm(io, data)
		end
	end)

	return self._server:start()
end

function app:on_run(tms)
	self:for_earch_client('on_run')

	--[[
	for k, v in pairs(self._stations) do
		local c = v.station:client()
		if c then
			self._dev:set_input_prop('status_'..k, 'value', 1)
		else
			self._dev:set_input_prop('status_'..k, 'value', 0)
		end
	end
	]]--

	return 1000
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	--- Close the server
	if self._server then
		self._server:stop()
	end
	self._log:warning('Server closed')
	return true
end

function app:on_command(app_src, sn, command, param, priv)
	if command == 'purge_hisdb' then
		if param.pwd == self:app_name() then
			return self._hisdb:purge_all(), "History database has been purged"
		else
			return false, "Password incorrect"
		end
	end
	return false, "Unknown command"
end

function app:for_earch_client(func, ...)
	for _, v in pairs(self._clients) do
		v[func](v, ...)
	end
end

--- 返回应用对象
return app

