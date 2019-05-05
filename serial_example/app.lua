local serial = require 'serialdriver'
local basexx = require 'basexx'
local sapp = require 'app.simple'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("SERIAL_EXAMPLE_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	sapp.initialize(self, name, sys, conf)

	--- 设备实例
	self._devs = nil

	self._log:debug("Port example application initlized")
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._sys:gen_sn("hash_key_here_serial")

	--- 增加设备实例
	local inputs = {
		{name="tag1", desc="tag1 desc"}
	}

	local meta = self._api:default_meta()
	meta.name = "Example Device"
	meta.description = "Example Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)
	local port = serial:new("/tmp/ttyS10", 9600, 8, "NONE", 1, "OFF")
	local r, err = port:open()
	if not r then
		self._log:warning("Failed open port, error: "..err)
		return nil, err
	end
	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._log:debug("Recevied data", basexx.to_hex(data))
			self._dev:set_input_prop('tag1', 'value', 1)
		else
			self._log:error(err)
		end
	end)
	self._port = port
	
	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._port then
		self._port:close(reason)
		self._serial:close(reason)
	end
end

--- 应用运行入口
function app:on_run(tms)
	return 10000 --下一采集周期为10秒
end

--- 返回应用对象
return app
