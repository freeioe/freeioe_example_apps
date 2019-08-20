--- 导入需要的模块
local modbus_slave = require 'modbus.slave.skynet'
local modbus_request = require 'modbus.pdu.request'
local modbus_response = require 'modbus.pdu.response'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'

local csv_tpl = require 'csv_tpl'
local data_block = require 'data_block'
local conf_helper = require 'app.conf_helper'
local base_app = require 'app.base'
local basexx = require 'basexx'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = base_app:subclass("MODBUS_LUA_SLAVE_APP")
--- 设定应用最小运行接口版本
app.static.API_VER = 5

--- 应用启动函数
function app:on_start()
	csv_tpl.init(self._sys:app_dir())

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	local config = self._conf or {}
	--[[
	config.devs = config.devs or {
		{ unit = 1, name = 'bms01', sn = 'xxx-xx-1', tpl = 'bms' },
		{ unit = 2, name = 'bms02', sn = 'xxx-xx-2', tpl = 'bms2' }
	}
	]]--

	--- 获取云配置
	if not config.devs or config.cnf then
		if not config.cnf then
			config = 'CNF000000002.1' -- loading cloud configuration CNF000000002 version 1
		else
			config = config.cnf .. '.' .. config.ver
		end
	end

	local helper = conf_helper:new(self._sys, config)
	helper:fetch()

	self._request = modbus_request:new()
	self._response = modbus_response:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()

	self._devs = {}
	for _, v in ipairs(helper:devices()) do
		assert(v.sn and v.name and v.unit and v.tpl)

		--- 生成设备的序列号
		local dev_sn = sys_id.."."..v.sn
		self._log:debug("Loading template file", v.tpl)
		local tpl, err = csv_tpl.load_tpl(v.tpl)
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
			for _, v in ipairs(tpl.inputs) do
				if string.find(v.rw, '[Rr]') then
					inputs[#inputs + 1] = {
						name = v.name,
						desc = v.desc,
						vt = v.vt,
						unit = v.unit,
					}
				end
				if string.find(v.rw, '[Ww]') then
					outputs[#outputs + 1] = {
						name = v.name,
						desc = v.desc,
						unit = v.unit,
					}
				end
			end

			local block = data_block:new(self._data_pack, self._data_unpack)

			table.insert(self._devs, {
				unit = v.unit,
				sn = dev_sn,
				dev = dev,
				tpl = tpl,
				inputs = inputs,
				outputs = outputs,
				block = block
			})
		end
	end

	--- 获取配置
	local conf = helper:config()
	conf.channel_type = conf.channel_type or 'socket'
	if conf.channel_type == 'socket' then
		conf.opt = conf.opt or {
			host = "127.0.0.1",
			port = 1503,
			nodelay = true
		}
	else
		conf.opt = conf.opt or {
			port = "/tmp/ttyS1",
			baudrate = 19200
		}
	end

	if conf.channel_type == 'socket' then
		self._modbus = modbus_slave('tcp', {link='tcp', tcp=conf.opt})
	else
		self._modbus = modbus_slave('rtu', {link='serial', serial=conf.opt})
	end

	for _, v in ipairs(self._devs) do
		self._modbus:add_unit(v.unit, function(pdu, response)
			self:handle_pdu(v, response, self._request:unpack(pdu))
		end)
	end

	--- 设定通讯口数据回调
	self._modbus:set_io_cb(function(io, unit, msg)
		self._log:trace(io, basexx.to_hex(msg))
		local dev = nil
		for _, v in ipairs(self._devs) do
			if v.unit == unit then
				dev = v
				break
			end
		end
		--- 输出通讯报文
		
		if dev then
			self._sys:dump_comm(dev.sn, io, msg)
		else
			self._sys:dump_comm(sys_id, io, msg)
		end
	end)


	self._modbus:start()

	return true
end

function app:handle_pdu(dev, response, fc, ...)
	if not fc then
		-- TODO:
		return
	end
	local h = self['handle_fc_0x'..string.format('%02X', fc)]
	if not h then
		-- TODO:
		return
	end

	return h(self, dev, response, ...)
end

function app:handle_fc_0x01(dev, response, addr, len)
	local block = dev.block
	local data = block:read(0x01, addr, len)
	local pdu = self._response:pack(0x01, len, data)
	return response(pdu)
end

function app:handle_fc_0x02(dev, response, addr, len)
	local block = dev.block
	local data = block:read(0x02, addr, len)
	local pdu = self._response:pack(0x01, len, data)
	return response(pdu)
end

function app:handle_fc_0x03(dev, response, addr, len)
	local block = dev.block
	local data = block:read(0x03, addr, len)
	local pdu = self._response:pack(0x03, len, data)
	return response(pdu)
end

function app:handle_fc_0x04(dev, response, addr, len)
	local block = dev.block
	local data = block:read(0x04, addr, len)
	local pdu = self._response:pack(0x04, len, data)
	return response(pdu)
end

function app:handle_fc_0x05(dev, response, addr, data)
	--- TODO: write prop
end

function app:handle_fc_0x06(dev, response, addr, data)
	--- TODO: write prop
end

function app:handle_fc_0x0F(dev, response, addr, len, data)
	--- TODO: write prop
end

function app:handle_fc_0x10(dev, response, addr, len, data)
	--- TODO: write prop
end

--- 应用退出函数
function app:on_close(reason)
	if self._modbus then
		self._modbus:close()
		self._modbus = nil
	end
	print(self._name, reason)
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	if quality ~= 0 or value ~= 'value' then
		return
	end

	for _, dev in ipairs(self._devs) do
		if dev.sn == sn then
			local block = dev.block
			for _, v in ipairs(v.inputs) do
				if input == v.name then
					block:write(input, value)
					break
				end
			end
		end
	end
end

--- 返回应用对象
return app
