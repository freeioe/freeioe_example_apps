--- 导入需要的模块
local cs104_master = require 'iec60870.master.cs104'
local cs104_slave = require 'iec60870.master.cs104.slave'
local cs104_channel = require 'iec60870.master.cs104.channel'
local data_pack = require 'iec60870.data.pack'
local data_unpack = require 'iec60870.data.unpack'
local data_bsi = require 'iec60870.data.bsi'
local iec_util = require 'iec60870.common.util'
local iec_logger = require 'iec60870.common.logger'

local csv_tpl = require 'csv_tpl'
local valid_value = require 'valid_value'
local linker = require 'linker'
local data_parser = require 'data_parser'

local queue = require 'skynet.queue'
local conf_helper = require 'app.conf_helper'
local base_app = require 'app.base'
local basexx = require 'basexx'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base_app:subclass("LUA_POWER_INDUSTRY_CS104_MASTER")
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
		config.opt = {
			host = "192.168.1.138",
			port = 2404,
			nodelay = true
		}
		config.devs = {
			{ unit = 1, name = 'DEV.1', sn = 'dev1', tpl = 'example', is_fx1 = false, pack_opt = 'default' }
		}
		config.tpls = {}
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()

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

	if #self._devs == 0 then
		return nil, "Device list empty"
	end

	--- 获取配置
	local conf = helper:config()
	conf.opt = conf.opt or {
		host = "127.0.0.1",
		port = 2404,
		nodelay = true
	}

	self._loop_gap = conf.loop_gap or self._conf.loop_gap

	local log = self:log_api()
	self._linker = linker:new({ link = 'tcp', tcp = conf.opt }, log)

	--- TODO: master conf
	self._master = cs104_master:new()

	self._channel = cs104_channel:new(self._master, self._linker)
	local dev = assert(self._devs[1])

	--- 设定通讯口数据回调
	self._channel:set_io_cb(function(io, key, msg)
		self._log:trace(io, key, basexx.to_hex(msg))
		dev.dev:dump_comm(io, msg)
		--- 计算统计信息
		if io == 'IN' then
			dev.stat:inc('bytes_in', string.len(msg))
		else
			dev.stat:inc('bytes_out', string.len(msg))
		end
	end)

	local r, err = self._channel:start()
	if not r then
		self._log:error(err)
		return nil, err
	end

	-- Create slave
	local slave = cs104_slave:new(self._master, self._channel, dev.unit, false, {k = 12, w = 8})
	slave:set_poll_cycle(self._loop_gap)
	slave:set_data_cb(data_parser:new(function(unit, ti, addr, data, timestamp, iv)
		print('CB', unit, ti, addr, data, timestamp, iv)
		self:set_input_value(unit, ti, addr, data, timestamp, iv)
	end))
	if self._master:add_slave(self._linker, slave) then
		self._slave = slave
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

	local val, err = valid_value(tpl_output.dt, val)
	if not val then
		self._log:error("Write value validation", err)
		return false, err
	end

	if tpl_output.dt == 'bit' and tpl_output.wcmd ~= 'BT' then
		return nil, 'Bit value only can write by BT command'
	end

	local r, err = self._queue(self.write_packet, self, dev.dev, dev.stat, dev.unit, tpl_output, val)
	--[[
	if not r then
		local info = "Write output failure!"
		local data = { sn=sn, output=output, prop=prop, value=value, err=err }
		self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_DEV, info, data)
	end
	]]--
	return r, err or "Done"
end

function app:write_packet(dev, stat, unit, output, value)
	if not self._client then
		return
	end

	--- 设定写数据的地址
	local addr = assert(output.addr)
	local timeout = output.timeout or 5000
	local val_data = self._data_pack[output.dt](self._data_pack, value)

	local req = nil
	local err = nil

	--- 写入数据
	stat:inc('packets_out', 1)
	self._log:debug("Fire write request:", unit, output.wcmd, addr, value, timeout)
	local count = 1
	if output.wcmd == 'WW' or output.wcmd == 'QW' then
		count = string.len(val_data) // 2
	end
		local basexx = require 'basexx'
	print(count, string.len(val_data), basexx.to_hex(val_data))
	local pdu, err = self._client:write(unit, output.wcmd, addr, count, val_data, nil, timeout)

	if not pdu then 
		self._log:warning("write failed: " .. err) 
		return nil, err
	end

	--- 统计数据
	stat:inc('packets_in', 1)

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
		-- self._master:poll_data(dev.unit)
	end

	local next_tms = gap - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app
