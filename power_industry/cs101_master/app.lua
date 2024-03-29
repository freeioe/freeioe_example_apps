--- 导入需要的模块
local cs101_master = require 'iec60870.master.cs101'
local cs101_slave = require 'iec60870.master.cs101.slave'
local cs101_channel = require 'iec60870.master.cs101.channel'
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

function app:set_input_value(unit, ti, addr, val, timestamp, iv)
	for _, v in ipairs(self._devs) do
		if v.unit == unit then
			for _, input in ipairs(v.inputs) do
				if input.ti == ti and input.addr == addr then
					if ti == 'BO' then
						local bsi = data_bsi:new(val)
						v.dev:set_input_prop(input.name, 'value', bsi:BIT(input.offset), timestamp, iv)
					else
						v.dev:set_input_prop(input.name, 'value', val, timestamp, iv)
					end
				end
			end
		end
	end
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
	self._master = cs101_master:new({FRAME_ADDR_SIZE=1})

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

	-- Create slaves
	for _, v in ipairs(self._devs) do
		local slave = self._master:find_slave(v.addr)
		if not slave then
			local slave = cs101_slave:new(self._master, self._channel, v.addr, 'unbalance', false)
			slave:set_caoa(v.caoa)
			slave:set_poll_cycle(self._loop_gap)
			self._master:add_slave(v.addr, slave)
		else
			slave:add_caoa(v.caoa)
		end
		slave:set_data_cb(data_parser:new(function(caoa, ti, addr, data, timestamp, iv)
			-- print('CB', caoa, ti, addr, data, timestamp, iv)
			self:set_input_value(caoa, ti, addr, data, timestamp, iv)
		end))

		v.slave = slave
	end

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

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if prop ~= 'value' then
		return false, "Cannot write property which is not value"
	end

	local dev = nil
	for _, v in ipairs(self._devs) do
		if v.sn == sn then
			dev = v
			break
		end
	end
	if not dev then
		return false, "Cannot find device sn "..sn
	end

	local tpl_output = nil
	for _, v in ipairs(dev.outputs or {}) do
		if v.name == output then
			tpl_output = v
			break
		end
	end
	if not tpl_output then
		return false, "Cannot find output "..sn.."."..output
	end

	local val = value
	if tpl_output.rate and tpl_output.rate ~= 1 then
		val = val / tpl_output.rate
	end

	local r, err = self._queue(self.write_packet, self, dev.slave, dev.stat, dev.unit, tpl_output, val)

	return r, err or "Done"
end

function app:write_packet(slave, stat, unit, output, value)
	if not self._master then
		return
	end

	--- 设定写数据的地址
	local addr = assert(output.addr)

	-- TODO: pack value?
	--local val_data = self._data_pack[output.dt](self._data_pack, value)
	local val_data = value

	local req = nil
	local err = nil

	self._log:debug("Fire write request:", unit, output.wcmd, addr, value)

	local writer = data_writer:new(slave)

	local pdu, err = writer(output.ti, addr, val_data)

	if not pdu then 
		self._log:error("write failed: " .. err)
		return nil, err
	end

	return true, "Write Done!"
end

function app:invalid_dev(dev, pack)
	for _, input in ipairs(pack.inputs) do
		dev:set_input_prop(input.name, "value", 0, nil, 1)
	end
end

--- 应用运行入口
function app:on_run(tms)
	if not self._master then
		return
	end

	local begin_time = self._sys:time()
	local gap = self._loop_gap or 5000

	for _, dev in ipairs(self._devs) do
		if not self._master then
			break
		end
		if not dev.slave then
			local slave = cs101_slave:new(self._master, self._channel, dev.unit, false, false)
			slave:set_poll_cycle(self._loop_gap)
			if self._master:add_slave(dev.unit, slave) then
				dev.slave = slave
			end
		else
			self:on_output('TEST', dev.sn, 'SP0', 'value', 1)
		end
		-- self._master:poll_data(dev.unit)
	end

	local next_tms = gap - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app
