--- 导入需求的模块
local ioe = require 'ioe'
local base = require 'app.base'
local crypt = require 'skynet.crypt'
local date = require 'date'
local lvl2number = require('log').lvl2number
local cyclebuffer = require 'buffer.cycle'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base:subclass("FREEIOE_HJ212_LOGGER_APP")
--- 设定应用最小运行接口版本 8, which has on_logger callback
app.static.API_VER = 8

function app:on_init()
	self._clients = {}
	self._log_map = {}
	self._comm_map = {}
	self._log_buffer = cyclebuffer:new(function(...)
		return self:publish_log(...)
	end, 256)
	self._comm_buffer = cyclebuffer:new(function(...)
		return self:publish_comm(...)
	end, 512)
end

--- 应用启动函数
function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()
	local logger = self:log_api()

	conf.servers = conf.servers or {
		{ name='syslog_udp', url='udp://172.30.1.160:1514', format="syslog"},
		{ name='syslog_tcp', url='tcp://172.30.1.160:1514', format="syslog"},
		--{ name='syslog_tcp', url='tcp://127.0.0.1:16000', format="syslog"},
	}
	conf.logs = conf.logs or {
		{ app = "*", level = "trace" }
	}
	conf.comms = conf.comms or {
		{ app = "*", sn = "HJ212.ministry", dir = "*", base64=0 }
	}

	local meta = self._api:default_meta()
	meta.name = 'HJ212 Logger' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Logger Device' 
	meta.series = 'N/A'

	local sys_id = sys:id()
	self._host_name = sys_id
	self._dev_sn = sys_id..'.'..self:app_name()
	self._dev = self._api:add_device(self._dev_sn, meta, inputs)

	for _, v in ipairs(conf.logs) do
		local app = v.app == '*' and '.+' or v.app
		self._log_map[app] = lvl2number(v.level)
	end

	for _, v in ipairs(conf.comms) do
		local app = v.app == '*' and '.+' or v.app
		local sn = v.sn == '*' and '.+' or v.sn
		local dir = v.dir == '*' and '.+' or v.dir
		self._comm_map[app] = self._comm_map[app] or {}
		self._comm_map[app][sn] = self._comm_map[app][sn] or {}
		self._comm_map[app][sn][dir] = tonumber(v.base64) ~= 0
	end

	local log_filter = function(app, lvl)
	end
	local comm_filter = function(app, sn, dir)
	end

	--- initialize connections
	for _, v in ipairs(conf.servers) do
		local url = string.lower(v.url)
		local format = string.lower(v.format)
		local proto, host, port = string.match(url, '^(%w+)://([^:]+):(%d+)')
		local r, client_m = pcall(require, 'client.'..proto)
		if not r then
			logger:error(client_m)	
			goto scontinue
		end
		local r, fmt_m = pcall(require, 'format.'..format)
		if not r then
			logger:error(fmt_m)
			goto scontinue
		end

		local fmt = fmt_m(self)
		local client = client_m:new(logger, fmt, host, port)
		local r, err = client:start()
		if not r then
			logger:error(err)
		end
		table.insert(self._clients, client)

		::scontinue::
	end

	return true
end

function app:on_run(tms)
	self._log_buffer:fire_all()
	self._comm_buffer:fire_all()
	return 50
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	for _, cli in ipairs(self._clients) do
		cli:close()
	end
	self._clients = {}
	return true
end

function app:publish_log(app, procid, timestamp, lvl, content)
	for _, cli in ipairs(self._clients) do
		cli:publish_log(app, procid, timestamp, lvl, content)
	end
	return true
end

function app:publish_comm(app, sn, dir, timestamp, base64, ...)
	for _, cli in ipairs(self._clients) do
		cli:publish_comm(app, sn, dir, timestamp, base64, ...)
	end
	return true
end

function app:on_comm(app_src, sn, dir, timestamp, content, ...)
	for app, sn_map in pairs(self._comm_map) do
		if app_src == app or string.match(app_src, app) then
			for k, dir_map in pairs(sn_map) do
				if sn == k or string.match(sn, k) then
					for k, base64 in pairs(dir_map) do
						if dir == k or string.match(dir, k) then
							self._comm_buffer:push(app_src, sn, dir, timestamp, base64, content, ...)
							return true
						end
					end
				end
			end
		end
	end
	return true
end

function app:on_logger(timestamp, level, msg)
	--- example: [00000018]: ::screen:: Uncompleted item	RDATA[Fri Jan  8 12:45:00 2021]
	local procid, app, content = string.match(msg, '^%[(%x+)]: ::(.+):: (.+)$')
	local lvl = lvl2number(level)

	--- TODO: Filter
	for k, v in pairs(self._log_map) do
		if app == k or string.match(app, k) then
			if lvl <= v then
				self._log_buffer:push(app, procid, lvl, timestamp, content)
				return true
				--return self:publish_log(app, procid, lvl, timestamp, content)
			end
		end
	end

	return true
end

--- 返回应用对象
return app

