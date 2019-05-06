local class = require 'middleclass'
local app_port = require 'app.port'
local sapp = require 'app.base'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("PORT_EXAMPLE_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id..".example"

	--- 增加设备实例
	local inputs = {
		{name="tag1", desc="tag1 desc"}
	}

	local meta = self._api:default_meta()
	meta.name = "Example Device"
	meta.description = "Example Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)
	self._port = app_port.new_socket({
		host = "127.0.0.1",
		port = 16000,
		nodelay = true
	})
	self._serial = app_port.new_serial({
		--port = "/dev/ttymxc1",
		port = "/tmp/ttyS10",
		baudrate = 115200
	})

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
	local r, err = self._port:request('DDDDD', function(sock)
		--local data, err = sock:read(4)
		local helper = require 'app.port_helper'
		local data, err = helper.read_socket(sock, 4)
		return data, err
	end, false, 1000)
	self._log:debug('[SOCKET] Request returns:', r, err)

	local r, err = self._serial:request('EEEEE', function(serial)
		--local data, err = serial:read(4)
		local helper = require 'app.port_helper'
		local data, err = helper.read_serial(serial, 4)
		return data, err
	end, false, 1000)
	self._log:debug('[SERIAL] Request returns:', r, err)

	return 10000 --下一采集周期为10秒
end

--- 返回应用对象
return app
