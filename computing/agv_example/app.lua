local app_base = require 'app.base'
local ioe = require 'ioe'
local summation = require 'summation'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson.safe'

--- 注册应用对象
local app = app_base:subclass("FREEIOE_COMPUTING_EXAMPLE_APP")
app.static.API_VER = 5 -- require app.conf module


--- 应用初始化回调函数
function app:on_init()
	--- 计算帮助类初始化
	local calc = self:create_calc()
	--- calc对象为计算帮助类对象，creaet_calc也会将calc对象赋值给 self._calc变量

	--- 初始化统计计算模块(文档参考：https://github.com/freeioe/freeioe_app_api_book/blob/master/other/summation.md)
	self._sum = summation:new({
		file = true, --- 是否保存文件
		save_span = 60 * 5, --- 文件保存的周期（请勿使用过小的周期，会缩减设备存储的使用寿命)
		key = self._name .. '_quantity',  --- 文件唯一名称，建议使用self._name(应用实例名) + 功能名称
		span = 'day',  --- 数据统计重置周期，
		path = sysinfo.data_dir(), --- 不建议修改，除非设备有其他文件存储区域
	})
	self._sum_hour = summation:new({
		file = true,
		save_span = 60 * 5,
		key = self._name .. '_quantity_hour',
		span = 'hour',
		path = sysinfo.data_dir(),
	})
end

function app:load_init_values(sys_id)
	-- 读取应用配置中的设备关联序列号
	local dsn = self._conf.dsn or 'i_am_a_fake_sn'
	self._dsn = sys_id..'.'..dsn
	self._log:notice("Reading data source from device", dsn)

	--- 记录当前时间
	self._last_time = ioe.time() 
end

function app:on_start()
	local sys_id = self._sys:id()

	self:load_init_values()

	--- 数据计算点
	local inputs = {
		{ name = 'agv_run_time', desc = 'AGV运行时长', vt = 'int', unit = '秒'},
		{ name = 'agv_run_distance', desc = 'AGV运行距离', vt = 'float', unit = '米'},

		{ name = 'agv_day_firing', desc = 'AGV日放电次数', vt = 'int'},
		{ name = 'agv_hour_firing', desc = 'AGV小时放电次数', vt = 'int'},
	}

	--- 设备指令，这里支持一个重置当前基数的指令
	local commands = {
		{ name = "reset_sum", desc = '重置统计数据（重新计数)' }
	}

	local dev_sn = self._conf.device_sn or 'i_am_a_fake_sn'
	self._dev_sn = sys_id..'.'..dev_sn 

	local meta = self._api:default_meta()
	meta.name = "AGV Computing"
	meta.description = "AGV Device Data Computing"
	meta.series = "AGV"

	self._dev = self._api:add_device(dev_sn, meta, inputs, nil, commands)

	self:start_calc()

	local timezone = sysinfo.TZ and sysinfo.TZ() or sysinfo.cat_file('/tmp/TZ') or "UTC"
	--- 显示当前系统的时区，当设备销售区域非国内时，请在网关设备中设定正确的时区
	self._log:notice(string.format("OEE Application started! TimeZone: %s", timezone))

	return true
end

--- 处理设备指令
function app:on_command(app_src, sn, command, param)
	self._log:notice("Received command", command, param)
	if command == 'reset_sum' then
		self._sum:reset()
		self._sum:save()
		self._sum_hour:reset()
		self._sum_hour:save()
		return true
	end
	return false, "No such command"
end

function app:start_calc()
	local current_run_state = nil -- 记录当前小车状态
	local begin_time = nil
	local begin_distance = nil
	--- 添加运行时长的计算
	self._calc:add('run_state_calc', {
		{ sn = self._dsn, input = 'state', prop='value' }, -- 这里假设AGV设备的运行状态点名称为state,请修改为正确的点名称。
		{ sn = self._dsn, input = 'run_time', prop='value' }, -- 假设AGV设备中的运行时长名称为run_time
		{ sn = self._dsn, input = 'run_distance', prop='value' } -- 假设AGV设备的运行距离点名为run_distance
	}, function(state, run_time, run_distance)
		--- 假设state数据是0或者1， 0标记停止，1标记启动
		--
		if current_run_state ~= state then
			--- 当状态发生变化
			if state == 1 then
				--- 记录开启时间
				begin_time = run_time
				begin_distance = run_distance
			end

			--- 当状态从运行 1 切换到 停止 0
			if state == 0 and current_run_state == 1 then
				--- 上报数据
				self._dev:set_input_prop('agv_run_time', 'value', run_time - begin_time)
				self._dev:set_input_prop('agv_run_distance', 'value', run_distance - begin_distance)
			end

			--- 记录状态
			current_run_state = state
		end

		--- 如需实时更新运行距离、运行时长 则开启以下代码
		--[[
		self._dev:set_input_prop('agv_run_time', 'value', run_time - begin_time)
		self._dev:set_input_prop('agv_run_distance', 'value', run_distance - begin_distance)
		]]--
	end)

	--- 添加放电次数统计
	self._calc:add('firing_count', {
		{ sn = self._dsn, input = 'firing', prop='value' }, -- 假设AGV设备中的放电次数点名为firing
	}, function(firing)
		self._sum:set('firing', firing) -- 日统计
		self._sum_hour:set('firing', firing) -- 小时统计

		--- 
	end)
end

local function get_time_day_string(ts)
	-- os.date('%F', ts) 会输出字符串 2019-09-26
	return os.date('%F', math.ceil(ts))
end

function app:on_run(tms)
	--- 比较时间
	local now = ioe.time()
	--local now = ioe.time() + 1 如果想在23:59:59发送数据则使用 +1
	local last_day = get_time_day_string(self._last_time)
	local cur_day = get_time_day_string(now)

	if cur_day ~= last_day then
		--- 凌晨切换
		self._last_time = now

		--- TODO: 发送日统计数据
		--self._dev:set_input_prop('input_name', 'value', val, now, 0)
	end

	--- 其他运算数据
	self:update_dev()

	return 1000
end

function app:update_dev()
	if not self._dev then
		return
	end

	local day_firing = self._sum:get('firing')
	local hour_firing = self._sum:get('hour_firing')

	self._dev:set_input_prop('agv_day_firing', 'value', day_firing)
	self._dev:set_input_prop('agv_hour_firing', 'value', hour_firing)
end

--- 应用退出函数
function app:on_close(reason)
	-- save the summation counts
	self._sum:save()
	self._sum_hour:save()
end

--- 返回应用对象
return app

