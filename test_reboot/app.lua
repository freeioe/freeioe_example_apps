local class = require 'middleclass'
--- 导入需要的模块
local modbus = require 'modbus.init'
local sm_client = require 'modbus.skynet_client'
local serialchannel = require 'serialchannel'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("REBOOT_TEST_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._log:debug(name.." Application initlized")

	self._test = false

	if self._test then
		self._ttyport = '/tmp/ttyS10'
		self._file = '/tmp/reboot.count'
	else
		self._ttyport = '/dev/ttyS2'
		self._file = '/mnt/data/reboot.count'
	end
end

--- 应用启动函数
function app:start()
	--- 设定回调处理函数(目前此应用只做数据采集)
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value, timestamp, priv)
			return self:write_output(sn, output, prop, value, timestamp, priv)
		end,
		on_ctrl = function(...)
			print(...)
		end,
	})

	local client = nil
	local opt = {
		port = self._ttyport,
		baudrate = 9600
	}
	if self._test then
		client = sm_client(serialchannel, opt, modbus.apdu_tcp, 1)
	else
		client = sm_client(serialchannel, opt, modbus.apdu_rtu, 1)
	end

	self._client = client

	return true
end

--- 应用退出函数
function app:close(reason)
	if self._client then
		self._client:close()
		self._client = nil
	end
	print(self._name, reason)
end

function app:write_packet(unit, output, value)
	--- 设定写数据的地址
	local req = {
		func = tonumber(output.func) or 0x06, -- 06指令
		addr = output.addr, -- 地址
		unit = unit or output.unit,
		len = output.len or 1,
	}
	local timeout = output.timeout or 500
	local ef = modbus.encode[output.dt]
	local df = modbus.decode[output.dt]
	assert(ef and df)

	local val = math.floor(value * (1/output.rate))
	req.data = table.concat({ ef(val) })
	
	--- 写入数据
	local r, pdu, err = pcall(function(req, timeout) 
		--- 接口调用
		return self._client:request(req, timeout)
	end, req, 1000)

	if not r then 
		pdu = tostring(pdu)
		if string.find(pdu, 'timeout') then
			self._log:debug(pdu, err)
		else
			self._log:warning(pdu, err)
		end
		return nil, pdu
	end

	if not pdu then 
		self._log:warning("write failed: " .. err) 
		return nil, err
	end

	--- 解析数据
	local pdu_data = string.sub(pdu, 4)
	local val_ret = df(pdu_data, 1)
	if val_ret ~= val then
		return nil, "Write failed!"
	end

	return true
end

--- 应用运行入口
function app:run(tms)
	if not self._client then
		return
	end

	local f, err = io.open(self._file, 'r')
	local str = ""
	if f then
		str = f:read('*a')
		f:close()
	end
	local count = tonumber(str) or 0
	count = count + 1

	local f, err = io.open(self._file, 'w+')
	assert(f, err)
	f:write(tostring(count))
	f:close()

	self:write_packet(0, {func=0x05, addr=0, dt='int16', rate=1}, 0)

	--- 返回下一次调用run之前的时间间隔
	return 1000
end

--- 返回应用对象
return app
