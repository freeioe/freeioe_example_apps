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

--- lua_HJ212_version: 2021-1-4

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_SERVER_APP")
--- 设定应用最小运行接口版本, 7 has new api and lua5.4???
app.static.API_VER = 7

function app:on_init()
	self._stations = {}
	self._clients = {}
	self._childs = {}
	local log = self:log_api()
	hj212_logger.set_log(function(level, ...)
		assert(level and log[level])
		log[level](log, ...)
	end)
end

function app:create_station(client, system, dev_id, passwd)
	local s = self._stations[dev_id]
	if not s then
		return nil, types.REPLY.ERR_MN
	end
	local station = s.station
	if station:client() then
		return nil, types.REPLY.REJECT
	end

	if tonumber(station:system()) ~= tonumber(system) then
		return nil, types.REPLY.ERR_ST
	end
	if station:passwd() ~= passwd then
		return nil, types.REPLY.ERR_PW
	end

	client:set_sn(s.sn)
	station:set_client(client)

	return station
end

function app:valid_connection(host, port)
	return true
end

function app:on_client_disconnect(client)
	local sn = client:sn()
	for k, v in pairs(self._stations) do
		if v.sn == sn then
			assert(v:client() == client)
			v:set_client(nil)
			client:set_client(nil)
		end
	end
end

function app:create_device(sn)
	local api = self:data_api()
	local sys = self:sys_api()

	local meta = api:default_meta()
	meta.name = 'HJ212' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device' 
	meta.series = 'N/A'

	local sys_id = sys:id()
	local station_sn = sys_id..'.'..self:app_name()..'.'..sn

	local commands = {
		{ name = 'rdata_start', desc = "Start RData upload" },
		{ name = 'rdata_stop', desc = "Stop RData upload" },
		{ name = 'set_time', desc = "Set time sync" },
	}

	local dev = api:add_device(station_sn, meta, inputs, nil, commands)
	return station_sn, dev
end

--- 应用启动函数
function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()

	conf.port = tonumber(conf.port or '') or 6000
	conf.stations = conf.stations or {}
	if #conf.stations == 0 then
		table.insert(conf.stations, {
			name = 'localhost',
			system = '31',
			dev_id = '010000A8900016F000169DC0',
			passwd = '123456',
			timeout = 5,
			retry = 3,
			rdata_interval = 30, -- 30 seconds
			min_interval = 10, -- 10 mins
		})
	end

	self._stations = {}
	self._devs = {}
	for _, v in ipairs(conf.stations) do
		local st = station:new(v, function(ms)
			sys:sleep(ms)
		end)

		local sn, dev = self:create_device(v.name)

		self._stations[v.dev_id] = {
			sn = sn,
			dev = dev,
			station = st,
		}
		self._devs[sn] = dev
	end

	local host = conf.host or '0.0.0.0'
	local port = conf.port or 6000
	self._server = tcp_server:new(self, host, port)

	self._server:set_io_cb(function(sn, io, data)
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

	return 1000
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	--- Close the server
	if self._server then
		self._server:stop()
	end
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
	for _, v in ipairs(self._clients) do
		v[func](v, ...)
	end
end

--- 返回应用对象
return app

