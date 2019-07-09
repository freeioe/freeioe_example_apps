local serial = require 'serialdriver'
local basexx = require 'basexx'
local sapp = require 'app.base'
local device_inputs = require 'oliver355.inputs'
local device_outputs = require 'oliver355.outputs'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = sapp:subclass("OLIVER_355_MONITOR_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	sapp.initialize(self, name, sys, conf)

	self._log:debug("Port example application initlized")

	conf.down = conf.down or {
		port = "/dev/ttymcx0",
		--port = "/tmp/ttyS1",
		baudrate = 19200,
		data_bits = 8,
		parity = "NONE",
		stop_bits = 1,
		flow_control = "OFF"
	}
	conf.up = conf.up or {
		port = "/dev/ttymcx1",
		--port = "/tmp/ttyS2",
		baudrate = 19200,
		data_bits = 8,
		parity = "NONE",
		stop_bits = 1,
		flow_control = "OFF"
	}
	self._up_stream_buffer = {}
	self._down_stream_buffer = {}
end

--- 应用启动函数
function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._sys:gen_sn("hash_key_here_serial")

	local meta = self._api:default_meta()
	meta.name = "Oliver 355"
	meta.manufacturer = "武汉华日精密激光有限公司"
	meta.description = "武汉华日精密激光Oliver 355"

	local inputs = {}
	local outputs = {}

	for _, v in ipairs(device_inputs) do
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc,
			vt = v.vt,
			unit = v.unit
		}
	end

	self._dev = self._api:add_device(sn, meta, inputs)
	self._inputs = device_inputs

	local down_conf = self._conf.down
	local up_conf = self._conf.up

	--local port = serial:new("/tmp/ttyS10", 9600, 8, "NONE", 1, "OFF")

	local down_port = serial:new(down_conf.port,
								 down_conf.baudrate,
								 down_conf.data_bits,
								 down_conf.parity, 
								 down_conf.stop_bits, 
								 down_conf.flow_control)
	local r, err = down_port:open()
	if not r then
		self._log:warning("Failed open port["..down_conf.port.."] error: "..err)
		return nil, err
	end

	local up_port = serial:new(up_conf.port,
							   up_conf.baudrate,
							   up_conf.data_bits,
							   up_conf.parity, 
							   up_conf.stop_bits, 
							   up_conf.flow_control)
	local r, err = up_port:open()
	if not r then
		self._log:warning("Failed open port["..up_conf.port.."] error: "..err)
		return nil, err
	end


	down_port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._log:debug("DownPort Recevied data", basexx.to_hex(data))
			self._dev:dump_comm("DEV-IN", data)
			if self._up_port then
				self._dev:dump_comm("PC-OUT", data)
				self._up_port:write(data)
			end
			self._sys:post('stream_from_down', data)
		else
			self._log:error(err)
			--- TODO:
			self:on_close()
			self._sys:exit()
		end
	end)
	self._down_port = down_port

	up_port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._log:debug("UpPort Recevied data", basexx.to_hex(data))
			self._dev:dump_comm("PC-IN", data)
			if self._down_port then
				self._dev:dump_comm("DEV-OUT", data)
				self._down_port:write(data)
			end
			self._sys:post('stream_from_up', data)
		else
			self._log:error(err)
			--- TODO:
			self:on_close()
			self._sys:exit()
		end
	end)
	self._up_port = up_port
	
	return true
end

--- 应用退出函数
function app:on_close(reason)
	if self._up_port then
		self._up_port:close(reason)
		self._up_port = nil
	end
	if self._down_port then
		self._down_port:close(reason)
		self._down_port = nil
	end
end

--- 应用运行入口
function app:on_run(tms)
	return 10000 --下一采集周期为10秒
end

function app:on_post_stream_from_up(stream)
	if self._working_cmd then
		local cmd = self._working_cmd
		local cmd_time = self._working_cmd_time

		if cmd.decode_mode == 0 then
			local content = table.concat(self._down_stream_buffer)
			self._dev:dump_comm("DEV-PACKET", content)
			self._dev:set_input_prop(cmd.name, 'value', conent, cmd_time, 0)
		else
			self._log:warning(string.format("CMD[%s] timeout!!", cmd.name))
		end

		self._working_cmd = nil
		self._down_stream_buffer = {}
	end

	table.insert(self._up_stream_buffer, stream)
	local buf = table.concat(self._up_stream_buffer)
	local cmd = string.match(buf, "^([^%?]+)%?[\r]*\n")
	if cmd then
		self._log:trace("PC Sending command", cmd)
		--- Clean all buffers
		self._up_stream_buffer = {}
		self._down_stream_buffer = {}
		self._working_cmd = nil

		for _, v in ipairs(self._inputs) do
			if v.cmd == cmd then
				self._log:trace("Finded supported command", cjson.encode(v))
				self._working_cmd = v
				self._working_cmd_time = self._sys:time()
			end
		end
	end
end

function app:on_post_stream_from_down(stream)
	local cmd = self._working_cmd
	if cmd then
		table.insert(self._down_stream_buffer, stream)
		if cmd.decode_mode == 1 then
			local str = table.concat(self._down_stream_buffer)

			local rp = cmd.rp or cmd.cmd
			if string.len(str) > string.len(rp) then
				local index = string.find(str, rp, 1, true)
				if index > 1 then
					self._log:trace("Drop stream prefix", index)
					str = string.sub(str, index )
					self._down_stream_buffer = {str}
				end

				self._log:trace("Finding supported command result", rp)
				local value = string.match(str, "^%s(.+)[\r]*\n", string.len(rp) + 1)
				if value then
					self._log:trace("Got command result", value)
					self._dev:dump_comm("DEV-PACKET", str)
					self._dev:set_input_prop(cmd.name, 'value', value)
					self._working_cmd = nil
					self._down_stream_buffer = {}
				end
			end
		else
			--- Wait for next command is comming
		end
	end
end

--- 返回应用对象
return app
