local serial = require 'serialdriver'
local basexx = require 'basexx'
local base = require 'app.base'
local chk_sum = require 'hasings.sum16'
local ioe = require 'ioe'

local app = base:subclass("YXK_12AB_APP")
app.static.API_VER = 10

function app:on_init()
	self._log:debug("Port example application initlized")
end

--- 应用启动函数
function app:on_start()
	local conf = self:app_conf()
	local log = self:log_api()
	local sys = self:sys_api()

	--- 生成设备唯一序列号
	local sys_id = sys:id()

	if ioe.developer_mode() ~= 0 then
		conf.devs = {
			{ no = 1, name = "#1" }
		}
	end

	self._devs = {}
	for _, v in ipairs(conf.devs) do
		--- 增加设备实例
		local inputs = {}
		local vals = {}
		for i = 1, 12 do
			vals[i] = 0 -- default is 0
			table.insert(inputs, {
				name = "chn_"..i,
				desc = "插座#"..i,
				vt = "int"
			})
		end

		local meta = self._api:default_meta()
		meta.name = "YXK-12AB"
		meta.inst = self._name..'.'..v.no
		meta.description = "YXK-12AB开关模块"

		local sn = sys_id.."."..conf.sn_prefix.."."..v.no
		self._devs[sn] = {
			conf = v,
			vals = vals,
			dev = self._api:add_device(sn, meta, inputs, outputs)
		}
	end

	local opt = self._conf.serial
	local port = serial:new(opt.port, opt.baudrate or 19200, opt.data_bits or 8, opt.parity or 'NONE', opt.stop_bits or 1, opt.flow_control or "OFF")
	local r, err = port:open()
	if not r then
		self._log:warning("Failed open port, error: "..err)
		return nil, err
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._dev:dump_comm('SERIAL-IN', data)
			self._serial_recv = self._serial_recv + string.len(data)
		else
			self._log:error(err)
		end
	end)
	self._port = port

	sys:timeout(10, function()
		for k, v in pairs(self._devs) do
			self:set_dev_output(v)
		end
	end)

	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._port then
		local to_close = self._port
		self._port = nil
		to_close:close(reason)
	end
	return true
end

--- 应用运行入口
function app:on_run(tms)
	return 1000 --下一采集周期为1秒
end

function app:set_dev_output(dev)
	if not self._port then
		return nil, "Port is not open"
	end

	local data = "%"..string.format("%03d", dev.conf.no)
	for i = 1, 12 do
		data = data..tostring(dev.vals[i] % 10)
	end

	local sum = chk_sum:new(data):hexdigest()
	data = "UU"..data..sum

	dev.dev:sump_comm("OUT", data)
	self._port:write(data)

	return true
end

--- 返回应用对象
return app

