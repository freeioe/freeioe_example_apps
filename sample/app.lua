local base_app = require 'app.base'

--- 创建自己应用的子类
--- create your own application subclass
local my_app = base_app:subclass("THIS_IS_AN_SIMEPLE_APP_EXAMPLE")

--- 设定最小适配的API版本，此示例应用最小适用版本为4。
--- Set proper required API version to make sure your application run with correct FreeIOE core
my_app.static.API_VER = 4


--- 应用初始化
function my_app:on_init()
	self._devs = {}
end

--[[ 
--启用下述函数用以处理设备数据,
--un-comment following if your application handles device data

---
-- 处理设备数据
-- Handle device real time data
-- app: 数据来源应用名称（实例名）[Source application instance name]
-- sn: 数据源设备的序列号 [Device serial number e.g XXX.PLC1]
-- input: 数据源名称 [Device input name. e.g temperature]
-- prop: 数据源属性 [Device input property. e.g. value]
-- value: 数据值 [Device input property value.  e.g 20]
-- timestamp: 时间戳 [Data timestamp]
-- quality: 质量戳 [Data quality 0 means good]
function my_app:on_input(app, sn, input, prop, value, timestamp, quality)
	return
end

--- 
-- 处理紧急数据，如需要立马响应的数据
--		紧急数据同步调用on_input函数，如应用无需针对紧急数据进行特殊处理，请忽略此函数
-- Process emergency data
--		If your application treat all data in same way, skip this callback.
--
--- 参数同上 [Same as above]
function  my_app:on_input_em(app, sn, input, prop, value, timestamp, quality)
	return
end
]]--

--- 
-- 设备输出项回调函数，当本应用生成的设备有输出项时，使用此函数捕获指令调用.
-- If your application has an output property this will be called if anybody wants to write value to it
--
-- app: 来源应用名称（实例名）[Source application instance name]
-- sn: 输出项设备的序列号 [Device serial number e.g XXX.DEV1]
-- input: 输出项名称 [Device input name. e.g switch1]
-- prop: 输出项属性 [Device input property. e.g. value]
-- value: 输出值 [Device output property value.  e.g 1]
-- timestamp: 触发输出的时间 
--
-- @return: boolean with error information
function my_app:on_output(app, sn, output, prop, value, timestamp)
	for _, dev in ipairs(self._devs) do
		if sn == dev:sn() then
			self._log:debug("I am a output test!")
			if output ~= 'output1' then
				self._log:error("Output name incorrect!")
			end
			return true
		end
	end
	return false, "There is no output handler"
end

---
-- 设备输出指令结果回调（当本应用向其他应用设备进行数据写入，并需要处理反馈时使用此函数)
-- function my_app:on_output_result(app, priv, result, info)
-- end

--- 
-- 设备指令回调函数，当本应用生成的设备有设备指令时，使用此函数捕获指令调用
-- If your application has an output property this will be called if anybody wants to write value to it
--
-- app: 来源应用名称（实例名）[Source application instance name]
-- sn: 设备的序列号 [Device serial number e.g XXX.DEV1]
-- command: 指令名称 [Device command name. e.g switch1]
-- params: 指令参数 [Device command params. e.g {force=1}]
function my_app:on_command(app, sn, command, params)
	for _, dev in ipairs(self._devs) do
		if sn == dev:sn() then
			if output ~= 'cmd1' then
				self._log:error("Output name incorrect!")
			end
			self._log:debug("I am a output test!")
			return true
		end
	end
	return false, "There is no output handler"
end

---
-- 设备指令结果回调（当本应用向其他应用设备发送设备指令，并需要处理反馈时使用此函数)
-- function my_app:on_command_result(app, priv, result, info)
-- end

---
-- 应用启动函数
-- Application start callback
function my_app:on_start()
	--- 生成设备唯一序列号
	local sn = self:gen_sn('example_device_serial_number_key')

	--- 增加设备实例
	local inputs = {
		{name="input1", desc="input desc", unit="kg"},
		{name="input2", desc="input desc", vt="int"},
		{name="input3", desc="input desc", vt="string"}
	}
	local outputs = {
		{name="output1", desc="output desc"}
	}
	local commands = {
		{name="cmd1", desc="command desc"}
	}
	local meta = self._api:default_meta()
	meta.name = "Example Device"
	meta.description = "Example Device Meta"
	local dev = self._api:add_device(sn, meta, inputs)
	self._devs[#self._devs + 1] = dev

	return true
end

--- 应用退出函数
function my_app:on_close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function my_app:on_run(tms)
	for _, dev in ipairs(self._devs) do
		dev:dump_comm("IN", "XXXXXXXXXXXX")
		local random = math.random()
		dev:set_input_prop('input1', "value", random)
		dev:set_input_prop('input2', "value", math.floor(random * 1000))
		dev:set_input_prop('input3', "value", string.format("string %0.3f", random))
	end

	return 10000 --下一采集周期为10秒
end

--- 返回应用类
return my_app

