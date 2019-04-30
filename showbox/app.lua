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


ALERT_INFO = {
	passive = "工作正常",
	critical = "温度过高",
}

CTRL_MODE = {
	auto = '自动',
	mannual = '手动',
}

FAN_SPEED_VAL = {
	'high', 'middle', 'low', 'auto', 'none'
}

FAN_MODE = {
	auto = '自动',
	mannual = '手动',
}

FAN_SPEED = {
	high = '高',
	middle = '中',
	low = '低',
	auto = '自动',
	none = '关闭',
}

OPERATION_MODE_VAL = {
	'cool', 'heat', 'vent', 'none'
}
OPERATION_MODE = {
	none = '未知',
	cool = '制冷',
	heat = '制热',
	vent = '通风',
}

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

	-- 风机手动控制触发函数
	self._fan_ctrl = nil
	
	-- 风机自动模式触发函数，用于更新风机自动控制参数
	self._auto_fan = nil

	--- 工作模式控制触发函数
	self._auto_operation = nil

	-- 风机改变模式暂停错误检测
	self._fan_mute = nil

	-- 自动控制温度漂移
	self._room_temp_offset = 0

	-- 控制结果等待
	self._wait_ops = {}
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
		on_output = function(app_src, sn, output, prop, value, timestamp, priv)
			log:trace('on_output', app_src, sn, output, prop, value, timestamp, priv)
			if sn ~= app._dev_sn then
				log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			log:info("Output required from:", app_src, sn, " as: ", output, prop, value)
			return app:handle_output(output, prop, value)
		end,
		on_output_result = function(app_src, priv, result, err)
			--- 
		end,
	}
end

--- 应用启动函数
function app:start()

	local handler = self._calc:start(create_handler(self))
	self._api:set_handler(handler, true)

	local inputs = {
		--[[
		{ name = "T8600_SN", desc = "T8600控制器序列号", vt = "string"},
		{ name = "PLC1200_SN", desc = "PLC1200序列号", vt = "string"},
		{ name = "SPM91_SN", desc = "SPM91电表序列号", vt = "string"},
		]]--

		{ name = "weather_city", desc = "OpenWeatherMap规定的城市编号(广州:1809858)", vt = "int" },
		{ name = "weather_city_name", desc = "OpenWeatherMap规定的城市编号对应的名称", vt = "string" },
		{ name = "weather_temp", desc = "从OpenWeatherMap网站获取的天气温度", unit="℃" },
		{ name = "weather_poll_cycle", desc = "从OpenWeatherMap网站获取的的周期", vt = "int", unit="second" },

		{ name = "work_temp", desc = "当前温度", unit="℃"},

		{ name = "ctrl_mode", desc = "控制模式", vt="string"},

		{ name = "operation_mode", desc = "工作模式", vt="string"},
		{ name = "cool_policy", desc = "开启制冷的温度", unit="℃"},
		{ name = "heat_policy", desc = "开启制热的温度", unit="℃"},

		{ name = "fan_mode", desc = "风机模式", vt="string"},
		{ name = "fan_speed", desc = "风机转速", vt="string"},
		{ name = "hot_policy", desc = "高温温度", unit="℃"},
		{ name = "very_hot_policy", desc = "超高温温度", unit="℃"},
		{ name = "critical_policy", desc = "临界(报警)温度", unit="℃"},

		{ name = "alert_info", desc = "报警信息", vt="string"},
		{ name = "alert_cycle", desc = "报警周期(秒)", vt = "int", unit="秒"},
		{ name = "disable_alert", desc = "禁止报警", vt = "int" },
	}

	local outputs = {
		{ name = "hot_policy", desc = "高温温度", unit="℃" },
		{ name = "very_hot_policy", desc = "超高温温度", unit="℃" },
		{ name = "critical_policy", desc = "临界(报警)温度", unit="℃" },

		{ name = "alert_cycle", desc = "报警周期", vt = "int", unit="秒" },
		{ name = "disable_alert", desc = "禁止报警: 0-报警 1-禁止报警", vt = "int" },

		{ name = "ctrl_mode", desc = "控制模式: 0-自动模式 1-手动模式", vt="int"},
		--{ name = "fan_mode", desc = "风机模式: 0-自动模式 1-手动模式", vt="int"},
		{ name = "fan_speed", desc = "风机转速控制: 0-关闭 1-低 2-中 3-高 4-自动", vt="int"},
		{ name = "operation_mode", desc = "工作模式控制: 1-制冷 2-制热 3-通风 ", vt="int"},
	}

	local dev_sn = self._sys:id()..'.'..self._name
	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "ShowBox"
	meta.description = "FreeIOE Show Box"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	self._log:notice("Show Box Started!!!!")

	self:load_init_values()

	self:start_weather_temp_proc()

	self:start_calc()

	return true
end

function app:load_init_values()
	-- 设定温度城市
	self._weather_city = self._conf.weather_city or 1809858
	self._weather_poll_cycle = tonumber(self._conf.weather_poll_cycle) or 10 * 60

	-- 当前温度显示
	self._work_temp = 0

	-- 控制模式
	self._ctrl_mode = tonumber(self._conf.ctrl_mode) == 1 and CTRL_MODE.mannual or CTRL_MODE.auto

	-- 操作控制初始值
	self._operation_mode = OPERATION_MODE.none
	self._cool_policy = tonumber(self._conf.cool_policy) or 35
	self._heat_policy = tonumber(self._conf.heat_policy) or 10

	-- 风机控制初始
	self._fan_mode = FAN_MODE.auto
	self._fan_speed = FAN_SPEED.none
	self._hot_policy = tonumber(self._conf.hot_policy) or 20
	self._very_hot_policy = tonumber(self._conf.very_hot_policy) or 30
	self._critical_policy = tonumber(self._conf.critical_policy) or 40

	-- 报警初始
	self._alert_info = ALERT_INFO.passive
	self._alert_cycle = tonumber(self._conf.alert_cycle) or 300 -- (5 * 60)
	self._disable_alert = tonumber(self._conf.disable_alert) or 0

	-- 设备关联序列号
	self._t8600 = self._sys:id()..'.'..(self._conf.T8600 or 'T8600')
	self._plc1200 = self._sys:id()..'.'..(self._conf.PLC1200 or 'PLC1200')
	self._spm91 = self._sys:id()..'.'..(self._conf.SPM91 or 'SPM91')
end


--- 应用运行入口
function app:run(tms)
	--self:on_post_device_ctrl('stop', true)
	--
	--[[
	self._dev:set_input_prop('T8600_SN', 'value', self._t8600)
	self._dev:set_input_prop('PLC1200_SN', 'value', self._plc1200)
	self._dev:set_input_prop('SPM91_SN', 'value', self._spm91)
	]]--

	self._dev:set_input_prop('weather_city', 'value', self._weather_city)
	--self._dev:set_input_prop('weather_city_name', 'value', self._weather_city_name)
	--self._dev:set_input_prop('weather_temp', 'value', self._weather_temp)
	self._dev:set_input_prop('weather_poll_cycle', 'value', self._weather_poll_cycle)

	self._dev:set_input_prop('work_temp', 'value', self._work_temp or 0)

	self._dev:set_input_prop('ctrl_mode', 'value', self._ctrl_mode)

	self._dev:set_input_prop('operation_mode', 'value', self._operation_mode)
	self._dev:set_input_prop('cool_policy', 'value', self._cool_policy)
	self._dev:set_input_prop('heat_policy', 'value', self._heat_policy)

	self._dev:set_input_prop('fan_mode', 'value', self._fan_mode)
	self._dev:set_input_prop('fan_speed', 'value', self._fan_speed)
	self._dev:set_input_prop('hot_policy', 'value', self._hot_policy)
	self._dev:set_input_prop('very_hot_policy', 'value', self._very_hot_policy)
	self._dev:set_input_prop('critical_policy', 'value', self._critical_policy)

	self._dev:set_input_prop('alert_info', 'value', self._alert_info)
	self._dev:set_input_prop('alert_cycle', 'value', self._alert_cycle)
	self._dev:set_input_prop('disable_alert', 'value', self._disable_alert)

	--[[ 自动模式测试 
	self._hot_policy = self._hot_policy + 1
	self._very_hot_policy = self._very_hot_policy + 1
	self._critical_policy = self._critical_policy + 1
	self._cool_policy = self._cool_policy + 1
	self._heat_policy = self._heat_policy + 1
	]]--

	return 1000 * 5
end

function app:calc_work_temp(temp)
	return math.floor((temp * 10000) / 32767) / 100
end

function app:get_fan_speed_by_temp(work_temp)
	local new_speed = FAN_SPEED.auto

	local temp = work_temp + self._room_temp_offset
	if temp >= self._critical_policy then
		new_speed = FAN_SPEED.high
	end

	if temp >= self._very_hot_policy and work_temp < self._critical_policy then
		new_speed = FAN_SPEED.middle
	end

	if temp >= self._hot_policy and work_temp < self._very_hot_policy then
		new_speed = FAN_SPEED.low
	end

	if temp < self._hot_policy then
		new_speed = FAN_SPEED.none
	end

	return new_speed
end

function app:get_op_mode_by_temp(temp)
	local mode = OPERATION_MODE.vent
	if temp >= self._cool_policy then
		mode = OPERATION_MODE.cool
	end
	if temp <= self._heat_policy then
		mode = OPERATION_MODE.heat
	end
	return mode
end

function app:start_calc()
	--- 网关触发器
	self._calc:add('temp', {
		{ sn = self._dev_sn, input = 'weather_temp', prop='value' },
		{ sn = self._sys:id(), input = 'cpu_temp', prop='value' }
	}, function(weather_temp, cpu_temp)
		self._log:notice('TEMP:', weather_temp, cpu_temp)
		if cpu_temp > 70 and  weather_temp < 30 then
			local info = "CPU温度过高"
			local data = {
				weather_temp = weather_temp,
				gateway_temp = cpu_temp
			}
			self:try_fire_event('cpu_temp', event.LEVEL_WARNING, info, data)
		end
	end)
	--end, 30)	

	self._calc:add('work_temp', {
		{ sn = self._plc1200, input = 'temp', prop='value' },
	}, function(temp)
		self._work_temp = self:calc_work_temp(temp)
		self._dev:set_input_prop_emergency('work_temp', 'value', self._work_temp)
	end)

	self._auto_mode = self._calc:add('set_p_and_lock', {
		{ sn = self._t8600, input = 'set_p', prop='value' },
		{ sn = self._t8600, input = 'lock', prop='value' },
	}, function(set_p, lock)
		if self._ctrl_mode == CTRL_MODE.auto then
			--[[
			if set_p < 35 then
				self._log:notice('更改显示面板设置温度为35')
				local r, err = self:set_temp_pre(35)
				if not r then
					self._log:error('更改显示面板设置温度失败', err)
				end
			end
			]]--
			if lock ~= 0 then
				self._log:notice('修改锁定到0')
				local r, err = self:set_lock_display(0)
				if not r then
					self._log:error('更改锁定失败', err)
				end
			end
		else
			if lock == 0 then
				self._log:notice('修改锁定到1')
				local r, err = self:set_lock_display(1)
				if not r then
					self._log:error('更改锁定失败', err)
				end
			end
		end
	end)

	--- 手动风机控制
	self._fan_ctrl = self._calc:add('fan_control', {
		{ sn = self._plc1200, input = 'temp', prop='value' },
		{ sn = self._t8600, input = 'set_f', prop='value' },
		{ sn = self._t8600, input = 'fan_high', prop='value' },
		{ sn = self._t8600, input = 'fan_middle', prop='value' },
		{ sn = self._t8600, input = 'fan_low', prop='value' },
	}, function(temp, set_f, fsh, fsm, fsl)
		local temp = self:calc_work_temp(temp)
		--- 计算当前风机状态
		local new_speed_val = FAN_SPEED.none
		if fsl == 1 then
			new_speed_val = FAN_SPEED.low
		end
		if fsm == 1 then
			new_speed_val = FAN_SPEED.middle
		end
		if fsh == 1 then
			new_speed_val = FAN_SPEED.high
		end

		--- 获取当前风机应该处于的状态
		local new_speed_temp = self:get_fan_speed_by_temp(temp)

		--- 报警信息
		local info = '控制模式错误'
		local data = {
			temp = temp,
			fan_mode = set_f,
			fan_high = fsh,
			fan_middle = fsm,
			fan_low = fsl
		}

		--- 当控制模式为自动时，风机模式显示自动
		if self._ctrl_mode == CTRL_MODE.auto then
			self._log:trace("Showbox in auto mode!", temp, set_f, fsh, fsm, fsl)
			if self._fan_mode ~= FAN_MODE.auto then
				self._log:trace('风机设定模式显示错误，修正显示')
				local r, err = self:set_fan_mode_display(FAN_MODE.auto)
				if r then
					self._fan_mode = FAN_MODE.auto
					self._dev:set_input_prop_emergency('fan_speed', 'value', self._fan_speed)
				else
					info = '风机设定模式显示修正失败:'..err
					self:try_fire_event_and_clear('fan_speed', event.LEVEL_WARNING, info, data)
				end
			end
		else
			if set_f == 3 then
				-- 当前输入自动模式，则根据设定进行风机速度计算
				new_speed = new_speed_temp
			else
				-- 当前输入的非自动模式，则按照输入的模式进行风神速度控制
				new_speed = new_speed_val
			end

			--- 风机转速不变
			if self._fan_speed == new_speed then
				return
			end

			-- 控制风机速度
			self._log:info("风机转速手动切换至:"..new_speed)
			local r, err = self:set_fan_speed(new_speed)
			if not r then
				info = '风机速度控制失败:'..err
				self:try_fire_event_and_clear('fan_speed', event.LEVEL_WARNING, info, data)
				return
			end

			--- 控制成功
			info = '风机转速手动切换至:'..new_speed_val
			self:try_fire_event_and_clear('fan_speed', event.LEVEL_WARNING, info, data)

			self._fan_speed = new_speed
			self._dev:set_input_prop_emergency('fan_speed', 'value', self._fan_speed)

			local new_mode = set_f == 3 and FAN_MODE.auto or FAN_MODE.mannual
			if self._fan_mode ~= new_mode then
				self._fan_mode = new_mode 
				self:set_fan_mode_display(new_mode)
				self._dev:set_input_prop_emergency('fan_mode', 'value', self._fan_mode)
			end
		end
	end)

	--- 温度报警、温度自动风机控制
	self._auto_fan = self._calc:add('auto_fan', {
		{ sn = self._t8600, input = 'set_f', prop='value' },
		{ sn = self._t8600, input = 'temp', prop='value' },
		{ sn = self._plc1200, input = 'temp', prop='value' },
	}, function(set_f, room_temp, work_temp) 
		local work_temp = self:calc_work_temp(work_temp)

		--- 温度超高报警
		local alert_info = ALERT_INFO.passive
		local alert_data = {
			critical = self._critical_policy,
			room_temp = room_temp,
			work_temp = work_temp,
			fan_mode = self._fan_mode
		}
		if work_temp >= self._critical_policy then
			alert_info = ALERT_INFO.critical
			info = '温度超过预设报警值'
			self:try_fire_event('temp_critical', event.LEVEL_WARNING, info, alert_data)
		else
			info = '温度恢复正常'
			if self._alert_info ~= alert_info then
				self:try_fire_event_and_clear('temp_critical', event.LEVEL_WARNING, info, alert_data)
			end
		end

		if self._alert_info ~= alert_info then
			self._alert_info = alert_info
			self._dev:set_input_prop_emergency('alert_info', 'value', self._alert_info)
		end

		--- 当前非自动控制模式，则跳过自动控制 
		if self._ctrl_mode ~= CTRL_MODE.auto then
			self._log:trace("Showbox in mannual mode!")
			return
		end
		
		--- 自动风机控制模式
		local new_speed = self:get_fan_speed_by_temp(work_temp)
		if self._fan_speed == new_speed then
		    return
		end

		--- 风机模式显示切换
		local r, err = self:set_fan_speed_display(new_speed)
		if not r then
			self._log:errro("风机设定模式显示修正失败:"..new_speed)
		end

		--- 自动控制控制风机转速
		self._log:info("风机转速自动切换至:"..new_speed)
		local r, err = self:set_fan_speed(new_speed)
		if r then
			self._fan_speed = new_speed
			self._dev:set_input_prop_emergency('fan_speed', 'value', self._fan_speed)
		else
			info = '风机转速切换错误:'..err
			self:try_fire_event_and_clear('fan_speed', event.LEVEL_WARNING, info, data)
		end
	end)

	--- 自动操作模式切换
	self._auto_operation = self._calc:add('operation_mode', {
		{ sn = self._plc1200, input = 'temp', prop='value' },
		{ sn = self._t8600, input = 'temp', prop='value' },
		{ sn = self._t8600, input = 'mode', prop='value' }
	}, function(work_temp, room_temp, mode)
		local work_temp = self:calc_work_temp(work_temp)

		--- 面板模式
		local new_mode_val = OPERATION_MODE[OPERATION_MODE_VAL[mode]]

		if self._ctrl_mode == CTRL_MODE.auto then
			--- 如果是自动控制模式, 计算工作模式
			local new_op_mode = self:get_op_mode_by_temp(work_temp)
			if self._operation_mode ~= new_op_mode then
				self._operation_mode = new_op_mode
				self._dev:set_input_prop_emergency('operation_mode', 'value', self._operation_mode)
			end

			--- 设定工作模式显示
			if new_mode_val ~= new_op_mode then
				self:set_op_mode_display(new_op_mode)
			end
		else
			self._log:trace("Showbox in mannual mode!")

			--- 手动模式获取面板输入
			if self._operation_mode ~= new_mode_val then
				self._operation_mode = new_mode_val
				self._dev:set_input_prop_emergency('operation_mode', 'value', self._operation_mode)
			end
		end
	end)
end

function app:set_fan_speed(speed)
	--- 输出风机控制
	local device = self._api:get_device(self._plc1200)
	if not device then
		self._log:warning("PLC1200 is not ready!")
		return nil, "找不到控制器"
	end

	local val = speed == FAN_SPEED.high and 1 or 0
	if device:get_input_prop('q0_0', 'value') ~= val then
		local r, err = device:set_output_prop('q0_0', 'value', val)
		if not r then
		    self._log:warning("PLC 高档位输出失败!", val)
		else
		    self._log:warning("PLC 高档位输出成功!", val)
	    end
	end

	val = speed == FAN_SPEED.middle and 1 or 0
	if device:get_input_prop('q0_1', 'value') ~= val then
		local r, err = device:set_output_prop('q0_1', 'value', val)
		if not r then
		    self._log:warning("PLC 中档位输出失败!", val)
		else
		    self._log:warning("PLC 中档位输出成功!", val)
	    end
	end

	val = speed == FAN_SPEED.low and 1 or 0
	if device:get_input_prop('q0_2', 'value') ~= val then
		local r, err = device:set_output_prop('q0_2', 'value', val)
		if not r then
		    self._log:warning("PLC 低档位输出失败!", val)
		else
		    self._log:warning("PLC 低档位输出成功!", val)
	    end
	end

	--- 切换转速2秒钟
	self._fan_mute = ioe.time() + 2
	return true
end

function app:set_fan_speed_display(speed)
	--- 更新T8600显示
	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return nil, "找不到控制器"
	end

	val = 3 -- auto
	val = speed == FAN_SPEED.high and 0 or val
	val = speed == FAN_SPEED.middle and 1 or val
	val = speed == FAN_SPEED.low and 2 or val

	return device:set_output_prop('set_f', 'value', val)
end

function app:set_fan_mode_display(mode)
	--- 更新T8600显示
	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return nil, "找不到控制器"
	end

	self._log:info("更改风机设定模式切换至:"..mode)

	-- TIPS: 不写入set_f
	if mode == FAN_MODE.auto then
		return device:set_output_prop('set_f', 'value', 3)
	else
		return self:set_fan_speed_display(self._fan_speed)
	end
	return true
end


function app:set_operation_mode(mode)
	local r, err  self:set_op_mode_display(mode)
	if not r then
		return nil, err
	end

	self._operation_mode = mode
	self._dev:set_input_prop_emergency('operation_mode', 'value', self._operation_mode)

	return true
end

function app:set_op_mode_display(mode)
	--- 输出操作模式
	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return nil, "找不到控制器"
	end

	self._log:info("工作模式切换至:"..mode)

	local val = 0 
	val = mode == OPERATION_MODE.cool and 1 or val
	val = mode == OPERATION_MODE.heat and 2 or val
	val = mode == OPERATION_MODE.vent and 3 or val

	return device:set_output_prop('mode', 'value', val)
end

function app:set_ctrl_mode_display(mode)
	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return nil, "找不到控制器"
	end

	self._log:info("控制模式切换至:"..mode)
	
	return device:set_output_prop('status', 'value', mode == CTRL_MODE.auto and 0 or 1)
end

function app:set_temp_pre(temp)
	local temp = tonumber(temp)

	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return
	end

	self._log:info("设定设置温度至:"..temp)
	return device:set_output_prop('set_p', 'value', temp)
end

function app:set_lock_display(lock)
    local lock = lock == 1 and 1 or 0

	local device = self._api:get_device(self._t8600)
	if not device then
		self._log:warning("T8600 is not ready!")
		return
	end

	self._log:info("设置锁定键:"..lock)
	return device:set_output_prop('lock', 'value', lock)
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

--- 发送事件清除
function app:try_fire_event_and_clear(name, level, info, data)
	if self._disable_alert == 1 then
		self._log:warning("Alert disabled, skip event: "..info)
		return
	end

	self._log:warning("Fire event: "..info)
	self._dev:fire_event(event.LEVEL_WARNING, event.EVENT_APP, info, data)
	self._events_last[name] = 0
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
		self._weather_poll_cycle = tonumber(value) or 600
		self._dev:set_input_prop_emergency('weather_poll_cycle', 'value', value)
	end

	if output == 'hot_policy' then
		self._hot_policy = tonumber(value) or 25
		self._dev:set_input_prop_emergency('hot_policy', 'value', value)
		if self._auto_fan then self._auto_fan() end
		return true
	end
	if output == 'very_host_policy' then
		self._very_hot_policy = tonumber(value) or 45
		self._dev:set_input_prop_emergency('very_hot_policy', 'value', value)
		if self._auto_fan then self._auto_fan() end
		return true
	end
	if output == 'critical_policy' then
		self._critical_policy = tonumber(value)  or 75
		self._dev:set_input_prop_emergency('critical_policy', 'value', value)
		if self._auto_fan then self._auto_fan() end
		return true
	end

	if output == 'alert_cycle' then
		self._alert_cycle = tonumber(value) or 300
		self._dev:set_input_prop_emergency('alert_policy', 'value', value)
		return true
	end

	if output == 'disable_alert' then
		self._disable_alert = tonumber(value) == 1 and 1 or 0
		self._dev:set_input_prop_emergency('disable_alert', 'value', value)
		return true
	end

	if output == 'ctrl_mode' then
		value = tonumber(value) == 0 and CTRL_MODE.auto or CTRL_MODE.mannual
		self._ctrl_mode = value
		self._dev:set_input_prop_emergency('ctrl_mode', 'value', value)

		if self._auto_mode then self._auto_mode() end
		if self._auto_fan then self._auto_fan() end
		if self._auto_operation then self._auto_operation() end
		return true
	end

	if output == 'fan_speed' then
		if self._ctrl_mode == CTRL_MODE.auto then
			return false, "控制模式为自动模式，不能手动调节速度"
		end

		if tonumber(value) == 0 then
			value = FAN_SPEED.close
		end
		if tonumber(value) == 1 then
			value = FAN_SPEED.low
		end
		if tonumber(value) == 2 then
			value = FAN_SPEED.middle
		end
		if tonumber(value) == 3 then
			value = FAN_SPEED.high
		end
		if tonumber(value) == 4 then
			value = FAN_SPEED.auto
		end

		local valid = false
		for _, v in pairs(FAN_SPEED) do
			if v == value then
				valid = true
			end
		end
		if not valid then
			return false, "不合法的风机转速模式"
		end
		self._log:info("风机转速远程切换至:"..value)
		local r, err =self:set_fan_speed(value)
		if not r then
			return nil, err
		end
		self._fan_speed = value
		self._dev:set_input_prop_emergency('fan_speed', 'value', self._fan_speed)

		local mode = (value == FAN_SPEED.auto) and FAN_MODE.auto or FAN_MODE.mannual
		if self._fan_mode ~= mode then
			self._fan_mode = mode
			self:set_fan_mode_display(mode)
			self._dev:set_input_prop_emergency('fan_mode', 'value', self._fan_mode)
		end
	end

	if output == 'operation_mode' then
		if self._ctrl_mode == CTRL_MODE.auto then
			return false, "工作模式为自动模式，不能手动调节制冷"
		end

		if tonumber(value) == 1 then
			value = OPERATION_MODE.cool
		end
		if tonumber(value) == 2 then
			value = OPERATION_MODE.heat
		end
		if tonumber(value) == 3 then
			value = OPERATION_MODE.vent
		end
		return self:set_operation_mode(value)
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

