local app_base = require 'app.base'
local ioe = require 'ioe'
local event = require 'app.event'
local app_calc = require 'app.utils.calc'
local summation = require 'summation'
local date = require 'date'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson.safe'

--- 注册应用对象
local app = app_base:subclass("FREEIOE_EXAMPLE_TRIGGER_APP")
local ft_times = {
	'run',
	'idle',
	'warnning',
	'error',
	'maintainence',
}

function app:on_init()
	--- 计算帮助类初始化
	self:create_calc()

	self._sum = summation:new({
		file = true,
		save_span = 60 * 5,
		key = self._name .. '_quantity',
		span = 'day',
		path = sysinfo.data_dir(),
	})
end

function app:on_start()
	self._uptime = sysinfo.uptime()

	--- 用作缓存上次报警事件的发生时间，防止不停上送事件
	self._events_last = {}

	local inputs = {
		{ name = 'up_time', desc = '开机时间', vt = 'int', unit = '秒'},
		{ name = 'run_time', desc = '运行时间', vt = 'int', unit = '秒'},
		{ name = 'idle_time', desc = '空闲时间', vt = 'int', unit = '秒'},
		{ name = 'error_time', desc = '故障时间', vt = 'int', unit = '秒'},

		{ name = 'quantity', desc = '产量', vt = 'int'},
		{ name = 'defectives_quantity', desc = '不良品数量', vt = 'int'},
		{ name = 'energy_consumption', desc = '能耗', vt = 'int', unit = ''},

		{ name = 'up_rate', desc = '开机率', vt = 'float'},
		{ name = 'run_rate', desc = '稼动率', vt = 'float'},
		{ name = 'good_rate', desc = '良率', vt = 'float'},
		{ name = 'oee', desc = 'OEE', vt = 'float'},

		{ name = 'processing_parameters', desc = '工艺参数(JSON)', vt = 'string' },
	}

	local commands = {
		{ name = "reset_sum", desc = '重置统计数据（重新计数)' }
	}

	local sys_id = self._sys:id()
	local dev_sn = self._conf.device_sn
	if self._conf.with_ioe_sn then
		dev_sn = sys_id..'.'..dev_sn
	end
	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "OEE"
	meta.description = "OEE"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, nil, commands)

	local timezone = sysinfo.TZ and sysinfo.TZ() or sysinfo.cat_file('/tmp/TZ') or "UTC"
	self._log:notice(string.format("OEE Application started! TimeZone: %s", timezone))

	self:load_init_values()

	self:start_calc()

	return true
end

function app:on_command(app_src, sn, command, param)
	self._log:notice("Received command", command, param)
	if command == 'reset_sum' then
		self._sum:reset()
		self._sum:save()
		return true
	end
	return false, "No such command"
end

function app:load_init_values()
	-- 设备关联序列号
	self._dsn = self._conf.dsn or (self._sys:id()..'.'..'UN200A5')
end


function app:start_calc()
	--- 时间统计触发器
	
	self._calc:add('forming_time', {
		{ sn = self._dsn, input = 'CurrentState', prop='value' },
	}, function(current_state)
		self._log:debug("Current_state changed to ", current_state)
		if current_state == -1 then
			current_state = 3 -- error state
		end

		local now = ioe.time()
		if self._last_state ~= nil then
			self._sum:add(ft_times[self._last_state + 1], now - self._last_state_time)
		end
		self._last_state = current_state
		self._last_state_time = now
	end)
	--end, 30)	
	--
	local last_mould = nil
	local begin_count = nil
	local begin_def_count = nil
	self._calc:add('quantity', {
		{ sn = self._dsn, input = 'MouldName', prop='value' },
		{ sn = self._dsn, input = 'CurrentCount', prop='value' },
		{ sn = self._dsn, input = 'DefectivesCount', prop='value' }
	}, function(mould_name, current_count, defectives_count)
		assert(mould_name ~=  nil)
		assert(current_count ~= nil)
		assert(defectives_count ~= nil)
		if mould_name ~= last_mould or last_mould == nil then
			self._log:debug("Mould changed", mould_name, current_count, defectives_count)
			last_mould = mould_name
			begin_count = current_count
			begin_def_count = defectives_count
		else
			self._log:debug("Count changed", begin_count, current_count, begin_def_count, defectives_count)
			if current_count > begin_count and self._last_state == nil then
				self._last_state = 0 -- set the run state
				self._last_state_time = ioe.time()
			end

			if current_count < 1 or current_count < begin_count then
				begin_count = current_count
			end
			self._sum:set('quantity', current_count - begin_count)
			self._log:debug('Quantity now is', self._sum:get('quantity'))

			if defectives_count < 1 or defectives_count < begin_def_count then
				begin_def_count = defectives_count
			end
			self._sum:set('defectives', defectives_count - begin_def_count)
			self._log:debug('Defectives now is', self._sum:get('defectives'))

			self:update_dev()
		end
	end)

	local pp_last_count = 0
	self._calc:add('processing_parameters', {
		{ sn = self._dsn, input = 'MouldName', prop='value' },
		{ sn = self._dsn, input = 'MaterialType', prop='value' },
		{ sn = self._dsn, input = 'CurrentCount', prop='value' }
	}, function(mould_name, material_type, current_count)
		if current_count ~= pp_last_count then
			local dev = self._api:get_device(self._dsn)
			local BarrelTemp1_Current = dev:get_input_prop('BarrelTemp1_Current', 'value')
			local BarrelTemp2_Current = dev:get_input_prop('BarrelTemp2_Current', 'value')
			-- TODO: more

			local str, err = cjson.encode({
				mould = mould_name,
				material = material_type,
				count = current_count,
				barreltemp1 = BarrelTemp1_Current,
				barreltemp2 = BarrelTemp2_Current,
				-- TODO: more
			})
			if str then
				self._dev:set_input_prop('processing_parameters', 'value', str)
			end
		end
	end)
end

function app:on_run(tms)
	--- First run???
	if self._last_state ~= nil then
		local now = ioe.time()
		if self._last_state_time < now then
			self._sum:add(ft_times[self._last_state + 1], (now - self._last_state_time))
			self._last_state_time = now
		else
			-- TODO: what's happened???
		end
	end

	self:update_dev()

	return 5000
end

function app:update_dev()
	self._sum:set('uptime', sysinfo.uptime() - self._uptime)

	--- TODO: update time calculation
	local up_time = self._sum:get('uptime') or 0
	local run_time = self._sum:get('run') or 0
	local idle_time = self._sum:get('idle') or 0
	local error_time = self._sum:get('idle') or 0
	local warn_time = self._sum:get('warning') or 0
	local maintainence_time = self._sum:get('maintainence') or 0
	self._log:debug('Time:', up_time, run_time, idle_time, error_time, warn_time, maintainence_time)

	self._dev:set_input_prop('up_time', 'value', up_time)
	self._dev:set_input_prop('idle_time', 'value', idle_time)
	self._dev:set_input_prop('run_time', 'value', run_time + warn_time)
	self._dev:set_input_prop('idle_time', 'value', idle_time)
	self._dev:set_input_prop('error_time', 'value', idle_time)

	local quantity = self._sum:get('quantity') or 0
	local defectives = self._sum:get('defectives') or 0

	self._dev:set_input_prop('quantity', 'value', quantity)
	self._dev:set_input_prop('defectives_quantity', 'value', defectives)
	--{ name = 'energy_consumption', desc = '能耗', vt = 'int', unit = ''},

	if up_time > 0 then
		local this_day_seconds = date(os.date('%T')):spanseconds()
		local up_rate = up_time / this_day_seconds
		local run_rate = (run_time + warn_time) / up_time

		local good_rate = quantity > 0 and (1 - (defectives / quantity)) or 1
		local oee = up_rate * run_rate * good_rate

		self._dev:set_input_prop('up_rate', 'value', up_rate)
		self._dev:set_input_prop('run_rate', 'value', run_rate)
		self._dev:set_input_prop('good_rate', 'value', good_rate)
		self._dev:set_input_prop('oee', 'value', oee)
	end

	return 5000
end

--- 应用退出函数
function app:on_close(reason)
	-- save the summation counts
	self._sum:save()
end

--- 返回应用对象
return app

