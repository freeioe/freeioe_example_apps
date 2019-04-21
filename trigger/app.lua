local class = require 'middleclass'
local app_calc = require 'app.utils.calc'
local openweathermap = require 'openweathermap'
local frpc_http = require 'frpc_http'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("FREEIOE_EXAMPLE_TRIGGER_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

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

	--- 计算帮助类初始化
	self._calc = app_calc(self._sys, self._api, self._log)
end

--- 创建数据回调对象
-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local idx = app._idx
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app_src, sn, props)
			print('on_add')
			--- 获取对象目录
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app_src, sn)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app_src, sn, props)
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app_src, sn, input, prop, value, timestamp, quality)
		end,
		on_output = function(app_src, sn, output, prop, value)
			self._log:trace('on_output', app_src, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			self._log:info("Output required from:", app_src, sn, " as: ", output, prop, value)
			return self:handle_output(input, prop, value)
		end,
	}
end

--- 应用启动函数
function app:start()
	local handler = create_handler(self)
	handler = self._calc:map_handler(handler)
	self._api:set_handler(handler, true)

	local inputs = {
		{ name = "weather_city", desc = "OpenWeatherMap规定的城市编号(广州:1809858", vt = "int" },
		{ name = "weather_city_name", desc = "OpenWeatherMap规定的城市编号对应的名称", vt = "string" },
		{ name = "weather_temp", desc = "从OpenWeatherMap网站获取的天气温度" },
		{ name = "weather_poll_cycle", desc = "从OpenWeatherMap网站获取的的周期(秒)", vt = "int" },
		{ name = "enable_weather", desc = "是否开启根据天气温度进行风扇调节", vt = "int"},

		{ name = "T8600_SN", desc = "T8600控制器序列号", vt = "string"},
		{ name = "PLC1200_SN", desc = "PLC1200序列号", vt = "string"},
		{ name = "SPM91_SN", desc = "SPM91电表序列号", vt = "string"},

		{ name = "hot_policy", desc = "高温温度（摄氏度)" },
		{ name = "very_hot_policy", desc = "超高温温度（摄氏度)" },
		{ name = "critical_policy", desc = "临界(报警)温度（摄氏度)" },
		{ name = "alert_cycle", desc = "报警周期(秒)", vt = "int" },
		{ name = "disable_alert", desc = "禁止报警", vt = "int" },
		{ name = "alert_cpu_temp", desc = "智能网关CPU预警温度(摄氏度)", vt = "int"},
	}

	local outputs = {
		{ name = "hot_policy", desc = "高温温度（摄氏度)" },
		{ name = "very_hot_policy", desc = "超高温温度（摄氏度)" },
		{ name = "critical_policy", desc = "临界(报警)温度（摄氏度)" },
		{ name = "alert_cycle", desc = "报警周期(秒)", vt = "int" },
		{ name = "disable_alert", desc = "禁止报警", vt = "int" },
		{ name = "alert_cpu_temp", desc = "智能网关CPU预警温度(摄氏度)", vt = "int"},
	}

	local dev_sn = self._sys:id()..'.'..self._name
	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "FRPC Client"
	meta.description = "FRPC Client Running Status"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	self._log:notice("Started!!!!")

	self:load_init_values()

	self:start_weather_temp_proc()

	self._calc:add('temp', {
		{ sn = self._dev_sn, input = 'weather_temp', prop='value' },
		{ sn = self._sys:id(), input = 'cpuload', prop='value' }
	}, function(weather_temp, cpu_temp)
		self._log:notice('TEMP:', weather_temp, cpu_temp)
	end, 30)

	return true
end

--- 应用退出函数
function app:close(reason)
	if self._weather_temp_cancel then
		self._weather_temp_cancel()
	end
end

--- 应用运行入口
function app:run(tms)
	--self:on_post_device_ctrl('stop', true)

	self._dev:set_input_prop('hot_policy', 'value', self._hot_policy)
	self._dev:set_input_prop('very_hot_policy', 'value', self._very_hot_policy)
	self._dev:set_input_prop('critical_policy', 'value', self._critical_policy)
	self._dev:set_input_prop('alert_cycle', 'value', self._alert_cycle)
	self._dev:set_input_prop('disable_alert', 'value', self._disable_alert)
	self._dev:set_input_prop('alert_cpu_temp', 'value', self._alert_cpu_temp)

	self._dev:set_input_prop('T8600_SN', 'value', self._t8600)
	self._dev:set_input_prop('PLC1200_SN', 'value', self._plc1200)
	self._dev:set_input_prop('SPM91_SN', 'value', self._spm91)

	return 1000 * 5
end

function app:load_init_values()
	-- 设定温度城市
	self._weather_city = self._conf.weather_city or 1809858
	self._weather_poll_cycle = self._conf.weather_poll_cycle or 10 * 60
	self._enable_weather = self._conf.enable_weather or 0


	-- 温度预警初始值
	self._hot_policy = self._conf.hot_policy or 25
	self._very_hot_policy = self._conf.very_hot_policy or 29
	self._critical_policy = self._conf.critical_policy or 32
	self._alert_cycle = self._conf.alert_cycle or 300 -- (5 * 60)
	self._disable_alert = self._conf.disable_alert or 0
	self._alert_cpu_temp = self._conf.alert_cpu_temp or 70

	self._dev:set_input_prop('hot_policy', 'value', self._hot_policy)
	self._dev:set_input_prop('very_hot_policy', 'value', self._very_hot_policy)
	self._dev:set_input_prop('critical_policy', 'value', self._critical_policy)
	self._dev:set_input_prop('alert_cycle', 'value', self._alert_cycle)
	self._dev:set_input_prop('disable_alert', 'value', self._disable_alert)
	self._dev:set_input_prop('alert_cpu_temp', 'value', self._alert_cpu_temp)


	-- 设备关联序列号
	self._t8600 = self._sys:id()..'.'..(self._conf.T8600 or 'T8600')
	self._t8600_values = {}
	self._plc1200 = self._sys:id()..'.'..(self._conf.PLC120 or 'PLC1200')
	self._plc1200_values = {}
	self._spm91 = self._sys:id()..'.'..(self._conf.SPM91 or 'SPM91')
	self._spm91_values = {}

	self._dev:set_input_prop('T8600_SN', 'value', self._t8600)
	self._dev:set_input_prop('PLC1200_SN', 'value', self._plc1200)
	self._dev:set_input_prop('SPM91_SN', 'value', self._spm91)
end

function app:start_weather_temp_proc()
	if self._weather_temp_cancel then
		return
	end

	local temp_proc = nil
	temp_proc = function()
		local timeout = self._weather_poll_cycle
		self._weather_temp_cancel = self._sys:cancelable_timeout(timeout * 1000, temp_proc)
		self._log:trace("Fetch weather from openweathermap.org")

		local temp, city_name = openweathermap.get_temp(self._weather_city)
		if not temp then
			self._log:warning("Failed to fetch temperature for city: "..self._weather_city)
			return
		end

		self._dev:set_input_prop('weather_city', 'value', self._weather_city)
		self._dev:set_input_prop('weather_city_name', 'value', city_name)
		self._dev:set_input_prop('weather_temp', 'value', temp)
		self._dev:set_input_prop('enable_weather', 'value', self._enable_weather)
	end

	-- First time start after 1 second
	self._weather_temp_cancel = self._sys:cancelable_timeout(1000, temp_proc)
end


function app:handle_output(output, prop, value)
	if prop ~= 'value' then
		return nil, "Only support value property"
	end

	if output == 'weather_poll_cycle' then
		self._weather_poll_cycle = value
		self._dev:set_input_prop_emergency('weather_poll_cycle', 'value', value)
	end
	if output == 'enable_weather' then
		self._enable_weather = value
		self._dev:set_input_prop_emergency('enable_weather', 'value', value)
	end

	if output == 'hot_policy' then
		self._hot_policy = value
		self._dev:set_input_prop_emergency('hot_policy', 'value', value)
		return true
	end
	if output == 'very_host_policy' then
		self._very_hot_policy = value
		self._dev:set_input_prop_emergency('very_hot_policy', 'value', value)
		return true
	end
	if output == 'critical_policy' then
		self._critical_policy = value
		self._dev:set_input_prop_emergency('critical_policy', 'value', value)
		return true
	end

	if output == 'alert_cycle' then
		self._alert_cycle = value
		self._dev:set_input_prop_emergency('alert_policy', 'value', value)
		return true
	end

	if output == 'disable_alert' then
		self._disable_alert = value
		self._dev:set_input_prop_emergency('disable_alert', 'value', value)
		return true
	end

	if output == 'alert_cpu_temp' then
		self._alert_cpu_temp = value
		self._dev:set_input_prop_emergency('alert_cpu_temp', 'value', value)
		return true
	end

	--[[
	self._sys:post('service_ctrl', 'restart')
	]]--

	return false, "Ouput "..output.." not supported!"
end

function app:handle_input(sn, input, prop, value)
	if prop ~= 'value' then
		return
	end

	if sn == self._t8600 then
		self._t8600_values[input] = value
	end
	if sn == self._spm91 then
		self._spm91_values[input] = value
	end
	if sn == self._plc1200 then
		self._plc1200_values[input] = value
	end
end

function app:on_post_device_ctrl(sn, output, prop, value)
	local device, err = self._api:get_device(sn)
	if not device then
		self._log:error("Cannot find device: "..sn)
		return nil, "missing device"
	end
	device:set_output_prop(output, prop, value)
end



--- 返回应用对象
return app

