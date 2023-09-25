--- 导入需要的模块
local cs101_slave = require 'iec60870.slave.cs101'
local cs101_master = require 'iec60870.slave.cs101.master'
local cs101_channel = require 'iec60870.slave.cs101.channel'
local data_bsi = require 'iec60870.data.bsi'
local iec_util = require 'iec60870.common.util'
local iec_logger = require 'iec60870.common.logger'

local csv_tpl = require 'csv_tpl'
local linker = require 'linker'
local device = require 'device'

local queue = require 'skynet.queue'

local conf_helper = require 'app.conf_helper'
local base_app = require 'app.base'
local basexx = require 'basexx'
local ioe = require 'ioe'
local cov = require 'cov'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base_app:subclass("LUA_POWER_INDUSTRY_CS101_MASTER")
--- 设定应用最小运行接口版本
app.static.API_VER = 14

function app:on_init()
	self._queue = queue()
	local sys = self:sys_api()
	iec_util.time = function()
		return sys:time()
	end
	iec_util.now = function()
		return sys:now()
	end
	iec_util.fork = function(...)
		return sys:fork(...)
	end
	iec_util.wakeup = function(...)
		return sys:wakeup(...)
	end
	iec_util.sleep = function(...)
		return sys:sleep(...)
	end
	iec_util.wait = function(...)
		return sys:wait(...)
	end
	iec_util.timeout = function(...)
		return sys:timeout(...)
	end

	local log = self:log_api()
	iec_logger.set_log(function(lvl, ...)
		local f = log[lvl]
		if f then
			f(log, ...)
		else
			log:error(...)
		end
	end)

	csv_tpl.init(self._sys:app_dir())

end

--- 应用启动函数
function app:on_start()
	self._cov = cov:new(function(...)
		self:handle_cov_data(...)
	end, {})
	self._cov:start()

	local log = self:log_api()
	local sys = self:sys_api()

	csv_tpl.init(sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = sys:id()
	--- Mapping 
	local function map_dev_sn(sn)
		if sn == 'GW' then
			return sys_id
		end
		local sn = sn or 'GW'
		sn = string.gsub(sn, '^GW(%..*)$', sys_id..'%1')
		return sn
	end

	local conf = self._conf or {}

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	if ioe.developer_mode() then
		--[[
		conf.channel_type = 'tcp.client'
		conf.client_opt = {
			host = "127.0.0.1",
			port = 17001,
			nodelay = true
		}
		conf.mode = 'balance'
		]]--

		conf.channel_type = 'serial'
		conf.serial_opt = {
			port = "/tmp/ttyS1",
			baudrate = 19200
		}

		tpl_file = 'test'
	end

	log:info("Loading template", tpl_file)
	local tpl, err = csv_tpl.load_tpl(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end

	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
	end
	self._tpl = tpl

	self._unit = tonumber(conf.unit) or 1 -- default is 1

	conf.channel_type = conf.channel_type or 'tcp.server'
	if conf.channel_type == 'tcp.server' then
		conf.opt = conf.server_opt or {
			host = "0.0.0.0",
			port = 2401,
			nodelay = true
		}
	elseif conf.channel_type == 'tcp.client' then
		conf.opt = conf.client_opt or {
			host = "127.0.0.1",
			port = 2401,
			nodelay = true
		}
	else
		conf.opt = conf.serial_opt or {
			port = "/tmp/ttyS1",
			baudrate = 19200
		}
	end

	self._linker = linker:new(conf.channel_type, conf.opt, log)

	self._slave = cs101_slave:new({FRAME_ADDR_SIZE=1})
	self._channel = cs101_channel:new(self._slave, self._linker)

	-- Create slaves
	log:info("Create slave", conf.addr, conf.mode)
	self._device = device:new(conf.addr, conf.mode or 'unbalance', tpl.props, log)
	local master = cs101_master:new(self._device:DEVICE(), self._channel, false, true)
	self._slave:add_master(master:ADDR(), master)
	local r, err = self._slave:start()
	if not r then
		log:error('Slave start failed', err)
	end

	--- 设定通讯口数据回调
	self._channel:set_io_cb(function(io, unit, msg)
		-- local basexx = require 'basexx'
		-- print(io, unit, basexx.to_hex(msg))
		--- 输出通讯报文
		if self._unit == tonumber(unit) then
			local dev_sn = sys_id.."."..self:app_name()
			sys:dump_comm(dev_sn, io, msg)
		else
			-- self._log:error('No dev for unit:'..unit)
			sys:dump_comm(sys_id, io, msg)
		end
	end)

	self._channel:start()

	sys:timeout(10, function()
		self:read_tags()
	end)

	return true
end

function app:read_tags()
	local api = self:data_api()
	local props = self._tpl.props
	local devs = {}
	for _, v in pairs(props) do
		local dev_api = devs[v.sn]
		print('xxxx', v, v.sn)
		if not dev_api then
			dev_api = api:get_device(v.sn)
			devs[v.sn] = dev_api
		end

		if dev_api then
			local value, timestamp, quality = dev_api:get_input_prop(v.name, 'value')
			if value ~= nil and quality == 0 then
				self._log:debug("Input value got", v.sn, v.name, value, timestamp)

				local key = v.sn..'/'..v.name
				self._cov:handle(key, value, timestamp, quality)
			end
		else
			self._log:error("Failed to find device", sn)
		end
	end
end

--- 应用退出函数
function app:on_close(reason)
	local close_master = function()
		if self._master then
			self._master:stop()
			self._master = nil
		end
		if self._linker then
			self._linker:close()
			self._linker = nil
		end
	end

	self._log:debug("Wait for reading queue finished")
	self._queue(function()
		self._log:debug("Reading queue finished! close master now ...")
		close_master()
	end)
end

function app:handle_cov_data(key, value, timestamp, quality)
	local sn, input = string.match(key, '^([^/]+)/(.+)$')
	self._device:handle_input(sn, input, value, timestamp, quality)
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	-- Skip quality not good value
	if quality ~= 0 or prop ~= 'value' then
		return
	end
	-- Check input
	if self._device:check_input(sn, input) then
		local key = sn..'/'..input
		self._cov:handle(key, value, timestamp, quality)
	end
end

--- 返回应用对象
return app
