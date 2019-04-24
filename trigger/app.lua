local class = require 'middleclass'
local ioe = require 'ioe'
local event = require 'app.event'
local app_calc = require 'app.utils.calc'
local openweathermap = require 'openweathermap'
local frpc_http = require 'frpc_http'

--- 注册应用对象
local app = class("FREEIOE_EXAMPLE_TRIGGER_APP")
--- API版本4有我们需要的app.utils.calc
app.API_VER = 4

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如trigger(我们使用网关ID.name作为设备ID)
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

	--- 用作缓存上次报警事件的发生时间，防止不停上送事件
	self._events_last = {}

	-- 风扇自动控制触发函数，用于更新风扇自动控制参数
	self._auto_fan = nil

	-- 风扇改变模式暂停错误检测
	self._fan_mute = nil

	-- 自动控制温度漂移
	self._room_temp_offset = 0
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
	self._calc:start()

	local handler = create_handler(self)
	handler = self._calc:map_handler(handler)
	self._api:set_handler(handler, true)

	local inputs = {
		{ name = "weather_city", desc = "OpenWeatherMap规定的城市编号(广州:1809858)", vt = "int" },
		{ name = "weather_city_name", desc = "OpenWeatherMap规定的城市编号对应的名称", vt = "string" },
		{ name = "weather_temp", desc = "从OpenWeatherMap网站获取的天气温度", unit="℃" },
		{ name = "weather_poll_cycle", desc = "从OpenWeatherMap网站获取的的周期", vt = "int", unit="second" },
		{ name = "enable_weather", desc = "是否开启根据天气温度进行风扇调节", vt = "int"},

		{ name = "fan_ctrl_mode", desc = "风扇控制模式", vt="string"},
		{ name = "room_temp_alert", desc = "室温报警状态", vt="int"},
		{ name = "fan_error", desc = "风扇运行错误", vt="int"},
		{ name = "room_offset", desc = "风扇容积比例"},

		{ name = "T8600_SN", desc = "T8600控制器序列号", vt = "string"},
		{ name = "PLC1200_SN", desc = "PLC1200序列号", vt = "string"},
		{ name = "SPM91_SN", desc = "SPM91电表序列号", vt = "string"},

		{ name = "hot_policy", desc = "高温温度", unit="℃"},
		{ name = "very_hot_policy", desc = "超高温温度", unit="℃"},
		{ name = "critical_policy", desc = "临界(报警)温度", unit="℃"},
		{ name = "alert_cycle", desc = "报警周期(秒)", vt = "int", unit="秒"},
		{ name = "disable_alert", desc = "禁止报警", vt = "int" },
		{ name = "alert_cpu_temp", desc = "智能网关CPU预警温度", vt = "int", unit="℃"},
	}

	local outputs = {
		{ name = "hot_policy", desc = "高温温度", unit="℃" },
		{ name = "very_hot_policy", desc = "超高温温度", unit="℃" },
		{ name = "critical_policy", desc = "临界(报警)温度", unit="℃" },
		{ name = "alert_cycle", desc = "报警周期", vt = "int", unit="秒" },
		{ name = "disable_alert", desc = "禁止报警", vt = "int" },
		{ name = "alert_cpu_temp", desc = "智能网关CPU预警温度(摄氏度)", vt = "int", unit="℃"},
	}

	local dev_sn = self._sys:id()..'.'..self._name
	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "ShowBoxTrigger"
	meta.description = "FreeIOE Show Box Trigger"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	self._log:notice("Trigger Started!!!!")

	self:load_init_values()

	self:start_weather_temp_proc()

	--- 网关触发器
	self._calc:add('temp', {
		{ sn = self._dev_sn, input = 'weather_temp', prop='value' },
		{ sn = self._sys:id(), input = 'cpu_temp', prop='value' }
	}, function(weather_temp, cpu_temp)
		self._log:notice('TEMP:', weather_temp, cpu_temp)
		if weather_temp < 30 and cpu_temp > 60 then
			local info = "CPU温度过高"
			local data = {
				weather_temp = weather_temp,
				gateway_temp = cpu_temp
			}
			self:try_fire_event('cpu_temp', event.LEVEL_WARNING, info, data)
		end
	end)
	--end, 30)

	---容量触发器
	self._calc:add('plc_md64', {
		{ sn = self._plc1200, input = 'md64', prop='value' },
		{ sn = self._dev_sn, input = 'weather_temp', prop='value' },
	}, function(md64, weather_temp)
		self._log:notice('plc_md64:', md64, weather_temp)
		self._room_temp_offset = math.abs(weather_temp - 25) * md64
		self._dev:set_input_prop_emergency('room_temp_offset', 'value', self._room_temp_offset)
		if self._auto_fan then
			self._auto_fan()
		end
	end)


	--- 手动风扇控制
	self._calc:add('fan_control', {
		{ sn = self._t8600, input = 'mode', prop='value' },
		{ sn = self._t8600, input = 'fsh', prop='value' },
		{ sn = self._t8600, input = 'fsm', prop='value' },
		{ sn = self._t8600, input = 'fsl', prop='value' },
	}, function(mode, fsh, fsm, fsl)
		if mode == 3 then
			self._log:trace("T8600 in auto mode!")
			return
		end
		self:set_fan_control(fsh, fsm, fsl)
	end)

	self._calc:add('fan_mode_check', {
		{ sn = self._spm91, input = 'Ia', prop='value' }
	}, function(Ia)
		local fan_err = false
		--- 风扇转速错误检测（根据电流)
		local high_Ia = 0.2
		local middle_Ia = 0.1
		local low_Ia = 0.01

		fan_err = fan_err or Ia < high_Ia and self._fan_fsh == 1
		fan_err = fan_err or Ia > high_Ia and self._fan_fsh == 0

		fan_err = fan_err or Ia < middle_Ia and self._fan_fsm == 1
		fan_err = fan_err or Ia > middle_Ia and self._fan_fsm == 0

		fan_err = fan_err or Ia < low_Ia and self._fan_fsl == 1
		fan_err = fan_err or Ia > low_Ia and self._fan_fsl == 0

		--- 如果暂停检测，则认为是转速正确
		if self._fan_mute > ioe.time() then
			fan_err = false
		end

		--- 设定转速错误
		if (self._fan_error == 1) ~= fan_err then
			self._fan_error = fan_err and 1 or 0
			self._dev:set_input_prop_emergency('fan_error', 'value', self._fan_error)
		end

		--- 转速错误报警
		if self._fan_error then
			local info = '风扇转速错误'
			local data = { Ia = Ia, fsh = self._fan_fsh, fsm = self._fan_fsm, fsl = self._fan_fsl }
			self:try_fire_event('fan_ctrl_mode', event.LEVEL_WARNING, info, data)
		end
	end)

	--- 自动风扇控制
	self._auto_fan = self._calc:add('auto_fan', {
		{ sn = self._t8600, input = 'mode', prop='value' },
		{ sn = self._t8600, input = 'room_temp', prop='value' },
	}, function(mode, room_temp) 
		local new_mode = (mode == 3) and 'auto' or 'mannual'

		--- 模式切换报警
		if self._fan_ctrl_mode ~= new_mode then
			self._fan_ctrl_mode = new_mode
			info = 'Fan control mode switch to '..self._fan_ctrl_mode
			self:try_fire_event('fan_ctrl_mode', event.LEVEL_WARNING, info, data)
			self._dev:set_input_prop_emergency('fan_ctrl_mode', 'value', self._fan_ctrl_mode)
		end

		--- 室温超高报警
		local room_temp_alert = 0
		if room_temp > self._auto_critical then
			info = 'Room temperature reach critical'
			local data = {
				critical = self._auto_critical,
				room_temp = room_temp,
				fan_ctrl_mode = self._fan_ctrl_mode
			}
			self._dev:set_input_prop_emergency('fan_ctrl_mode', 'value', self._fan_ctrl_mode)
			self:try_fire_event('temp_critical', event.LEVEL_WARNING, info, data)
		end
		if self._room_temp_alert ~= room_temp_alert then
			self._dev:set_input_prop_emergency('room_temp_alert', 'value', self._room_temp_alert)
		end

		if self._fan_ctrl_mode ~= 'auto' then
			return
		end

		--- 自动控制
		local temp = room_temp + self._room_temp_offset
		if temp >= self._critical_policy then
			self._log:info("开启风扇高转速")
			self:set_fan_control(1, 0, 0)
		end

		if temp >= self._very_hot_policy and room_temp < self._critical_policy then
			self._log:info("开启风扇中转速")
			self:set_fan_control(0, 1, 0)
		end

		if temp >= self._hot_policy and room_temp < self._very_hot_policy then
			self._log:info("开启风扇低转速")
			self:set_fan_control(0, 0, 1)
		end

		if temp < self._hot_policy then
			self:set_fan_control(0, 0, 0)
		end
	end)

	return true
end

function app:set_fan_control(fsh, fsm, fsl)
	self._fan_fsh, self._fan_fsm, self._fan_fsl = fsh, fsm, fsl

	--- 暂停错误检测5秒钟
	self._fan_mute = ioe.time() + 5

	--- 输出风扇控制
	local device = self._api:get_device(self._plc1200)
	if not device then
		self._log:warning("PLC1200 is not ready!")
		return
	end

	device:set_output_prop('Q0_0', 'value', fsh)
	device:set_output_prop('Q0_1', 'value', fsm)
	device:set_output_prop('Q0_2', 'value', fsl)
end

--- 发送事件信息，次函数通过alert_cycle来控制上送平台的次数
function app:try_fire_event(name, level, info, data)
	if self._disable_alert == 1 then
		self._log:warning("Alert disabled, skip event: "..info)
		return
	end

	if (ioe.time() - (self._events_last[name] or 0)) >= self._alert_cycle then
		self._log:warning("Fire event: "..info)
		self._dev:fire_event(event.LEVEL_WARNING, event.EVENT_APP, info, data)
		self._events_last[name] = ioe.time()
	end
end

--- 应用退出函数
function app:close(reason)
	if self._weather_temp_cancel then
		self._weather_temp_cancel()
	end
	if self._calc then
		self._calc:stop()
	end
end

--- 应用运行入口
function app:run(tms)
	--self:on_post_device_ctrl('stop', true)
	--
	self._dev:set_input_prop('weather_city', 'value', self._weather_city)
	self._dev:set_input_prop('weather_poll_cycle', 'value', self._weather_poll_cycle)
	self._dev:set_input_prop('enable_weather', 'value', self._enable_weather)

	self._dev:set_input_prop('hot_policy', 'value', self._hot_policy)
	self._dev:set_input_prop('very_hot_policy', 'value', self._very_hot_policy)
	self._dev:set_input_prop('critical_policy', 'value', self._critical_policy)
	self._dev:set_input_prop('alert_cycle', 'value', self._alert_cycle)
	self._dev:set_input_prop('disable_alert', 'value', self._disable_alert)
	self._dev:set_input_prop('alert_cpu_temp', 'value', self._alert_cpu_temp)

	self._dev:set_input_prop('T8600_SN', 'value', self._t8600)
	self._dev:set_input_prop('PLC1200_SN', 'value', self._plc1200)
	self._dev:set_input_prop('SPM91_SN', 'value', self._spm91)

	self._dev:set_input_prop('fan_ctrl_mode', 'value', self._fan_ctrl_mode)
	self._dev:set_input_prop('room_temp_alert', 'value', self._room_temp_alert)
	self._dev:set_input_prop('fan_error', 'value', self._fan_error)
	self._dev:set_input_prop('room_temp_offset', 'value', self._room_temp_offset)

	return 1000 * 5
end

function app:load_init_values()
	-- 设定温度城市
	self._weather_city = self._conf.weather_city or 1809858
	self._weather_poll_cycle = tonumber(self._conf.weather_poll_cycle) or 10 * 60
	self._enable_weather = tonumber(self._conf.enable_weather) or 0

	self._fan_ctrl_mode = ''
	self._room_temp_alert = 0
	self._fan_fsh, self._fan_fsm, self._fan_fsl = 0, 0, 0
	self._fan_error = 0

	-- 温度预警初始值
	self._hot_policy = tonumber(self._conf.hot_policy) or 25
	self._very_hot_policy = tonumber(self._conf.very_hot_policy) or 29
	self._critical_policy = tonumber(self._conf.critical_policy) or 32
	self._alert_cycle = tonumber(self._conf.alert_cycle) or 300 -- (5 * 60)
	self._disable_alert = tonumber(self._conf.disable_alert) or 0
	self._alert_cpu_temp = tonumber(self._conf.alert_cpu_temp) or 70

	self._dev:set_input_prop('weather_city', 'value', self._weather_city)
	self._dev:set_input_prop('weather_poll_cycle', 'value', self._weather_poll_cycle)
	self._dev:set_input_prop('enable_weather', 'value', self._enable_weather)

	self._dev:set_input_prop('hot_policy', 'value', self._hot_policy)
	self._dev:set_input_prop('very_hot_policy', 'value', self._very_hot_policy)
	self._dev:set_input_prop('critical_policy', 'value', self._critical_policy)
	self._dev:set_input_prop('alert_cycle', 'value', self._alert_cycle)
	self._dev:set_input_prop('disable_alert', 'value', self._disable_alert)
	self._dev:set_input_prop('alert_cpu_temp', 'value', self._alert_cpu_temp)


	-- 设备关联序列号
	self._t8600 = self._sys:id()..'.'..(self._conf.T8600 or 'T8600')
	self._plc1200 = self._sys:id()..'.'..(self._conf.PLC120 or 'PLC1200')
	self._spm91 = self._sys:id()..'.'..(self._conf.SPM91 or 'SPM91')

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

		self._dev:set_input_prop('weather_city_name', 'value', city_name)
		self._dev:set_input_prop('weather_temp', 'value', temp)
	end

	-- First time start after 1 second
	self._weather_temp_cancel = self._sys:cancelable_timeout(1000, temp_proc)
end

--- 处理数据输出
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
		if self._auto_fan then self._auto_fan() end
		return true
	end
	if output == 'very_host_policy' then
		self._very_hot_policy = value
		self._dev:set_input_prop_emergency('very_hot_policy', 'value', value)
		if self._auto_fan then self._auto_fan() end
		return true
	end
	if output == 'critical_policy' then
		self._critical_policy = value
		self._dev:set_input_prop_emergency('critical_policy', 'value', value)
		if self._auto_fan then self._auto_fan() end
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

