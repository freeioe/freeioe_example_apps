--- 导入需要的模块
local cs101_slave = require 'iec60870.slave.cs101'
local cs101_master = require 'iec60870.slave.cs101.master'
local cs101_channel = require 'iec60870.slave.cs101.channel'
local data_bsi = require 'iec60870.data.bsi'
local iec_util = require 'iec60870.common.util'
local iec_logger = require 'iec60870.common.logger'

local csv_tpl = require 'csv_tpl'
local linker = require 'linker'
local data_parser = require 'data_parser'
local data_writer = require 'data_writer'

local queue = require 'skynet.queue'
local conf_helper = require 'app.conf_helper'
local base_app = require 'app.base'
local basexx = require 'basexx'
local ioe = require 'ioe'

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
	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	local config = self._conf or {}

	if ioe.developer_mode() then
		self._log:debug('IN Developer mode........')
		config.channel_type = 'socket'
		config.socket_opt = {
			host = "127.0.0.1",
			port = 17001,
			-- port = 15000,
			nodelay = true
		}
		config.devs = {
			{ unit = 1, name = 'DEV.1', sn = 'dev1', tpl = 'example', is_fx1 = false, pack_opt = 'default' }
		}
		config.tpls = {}
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	local dev_sn_prefix = config.dev_sn_prefix ~= nil and config.dev_sn_prefix or true

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.unit and v.tpl)

		--- 生成设备的序列号
		local dev_sn = dev_sn_prefix and sys_id.."."..v.sn or v.sn
		self._log:debug("Loading template file", v.tpl)
		local tpl, err = csv_tpl.load_tpl(v.tpl, function(...) self._log:error(...) end)
		if not tpl then
			self._log:error("loading csv tpl failed", err)
		else
			local meta = self._api:default_meta()
			meta.name = tpl.meta.name or "Modbus"
			meta.description = tpl.meta.desc or "Modbus Device"
			meta.series = tpl.meta.series or "XXX"
			meta.inst = v.name

			local inputs = {}
			local outputs = {}
			local tpl_inputs = {}
			local tpl_outputs = {}
			for _, v in ipairs(tpl.props) do
				if string.find(v.rw, '[Rr]') then
					inputs[#inputs + 1] = {
						name = v.name,
						desc = v.desc,
						vt = v.vt,
						unit = v.unit,
					}
					tpl_inputs[#tpl_inputs + 1] = v
				end
				if string.find(v.rw, '[Ww]') then
					outputs[#outputs + 1] = {
						name = v.name,
						desc = v.desc,
						unit = v.unit,
					}
					tpl_outputs[#tpl_outputs + 1] = v
				end
			end

			--- 生成设备对象
			local dev = self._api:add_device(dev_sn, meta, inputs, outputs)
			--- 生成设备通讯口统计对象
			local stat = dev:stat('port')

			table.insert(self._devs, {
				unit = tonumber(v.unit) or 0,
				sn = dev_sn,
				dev = dev,
				tpl = tpl,
				stat = stat,
				inputs = tpl_inputs,
				outputs = tpl_outputs,
			})
		end
	end

	--- 获取配置
	local conf = helper:config()
	conf.channel_type = conf.channel_type or 'socket'
	if conf.channel_type == 'socket' then
		conf.opt = conf.socket_opt or {
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
	self._loop_gap = conf.loop_gap or self._conf.loop_gap

	local log = self:log_api()
	if conf.channel_type == 'socket' then
		self._linker = linker:new({ link = 'tcp', tcp = conf.opt }, log)
	else
		self._linker = linker:new({ link = 'serial', serial = conf.opt }, log)
	end

	--- TODO: master conf
	self._slave = cs101_slave:new({FRAME_ADDR_SIZE=1})

	self._channel = cs101_channel:new(self._master, self._linker)
	--- 设定通讯口数据回调
	self._channel:set_io_cb(function(io, unit, msg)
		self._log:trace(io, basexx.to_hex(msg))
		--[[
		]]--

		local dev = nil
		for _, v in ipairs(self._devs) do
			if v.unit == tonumber(unit) then
				dev = v
				break
			end
		end
		--- 输出通讯报文
		
		if dev then
			dev.dev:dump_comm(io, msg)
			--- 计算统计信息
			if io == 'IN' then
				dev.stat:inc('bytes_in', string.len(msg))
			else
				dev.stat:inc('bytes_out', string.len(msg))
			end
		else
			self._sys:dump_comm(sys_id, io, msg)
		end
	end)
	local r, err = self._channel:start()
	if not r then
		self._log:error(err)
		return nil, err
	end

	-- Create objects

	return self._master:start()
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

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	if quality ~= 0 or prop ~= 'value' then
		return
	end

	for _, dev in ipairs(self._devs) do
		if dev.sn == sn or dev.dev_sn == sn then
			local key = sn..'/'..input
			self._cov:handle(key, value, timestamp, quality)
		end
	end
end

--- 应用运行入口
function app:on_run(tms)
	if not self._master then
		return
	end

	return 5000
end

--- 返回应用对象
return app
