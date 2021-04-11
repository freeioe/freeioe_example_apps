--- 导入需求的模块
local date = require 'date'
local ioe = require 'ioe'
local cjson = require 'cjson.safe'
local app_base = require 'app.base'
local conf = require 'app.conf'
local sysinfo = require 'utils.sysinfo'
local timer = require 'utils.timer'

local meter = require 'hj212.client.meter'
local station = require 'hj212.client.station'
local calc_mgr = require 'hj212.calc.manager'
local hj212_logger = require 'hj212.logger'

local csv_tpl = require 'csv_tpl'
local conn = require 'conn'
local tag = require 'hjtag'
local info = require 'hjinfo'
local hisdb = require 'hisdb.hisdb'
local siridb = require 'siridb.hisdb'

--- lua_HJ212_version: 2021-04-04
--  comment: Hard coded the O2 to 0.209 when it is closed to 0.21

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_APP")
--- 设定应用最小运行接口版本, 7 has new api and lua5.4???
app.static.API_VER = 7

function app:on_init()
	self._devs = {}
	self._clients = {}
	self._childs = {}
	local log = self:log_api()
	hj212_logger.set_log(function(level, ...)
		assert(level and log[level], 'Level is incorrect: '..level)
		log[level](log, ...)
	end)
end

local cmd = [[
uci set system.@system[0].timezone='%s' && uci set system.@system[0].zonename='%s' && uci commit system
]]
function app:check_timezone(conf)
	local lfs = require 'lfs'
	if lfs.attributes('/sbin/uci', 'mode') then
		local tz = conf.timezone or 'CST-8'
		local tz_name = conf.timezone_name or 'Asia/Shanghai'
		local otz = sysinfo.exec([[uci get system.@system[0].timezone]])
		if otz ~=  tz then
			self._log:warning("Correct timezone to "..tz..' from '..otz)
			os.execute(string.format(cmd, tz, tz_name))
		end
	else
		self._log:warning("Timezone check and fixes only in OpenWRT")
	end
end

--- 应用启动函数
function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()
	local log = self:log_api()

	if os.getenv("IOE_DEVELOPER_MODE") then
		-- conf.min_interval = 1
		conf.local_timestamp = true
		conf.using_siridb = true
	end

	if string.len(conf.dev_id or '') <= 0 or string.len(conf.dev_id) > 24 then
		return false, "Device ID (MN) length incorrect"
	end

	self:check_timezone(conf)

	conf.station = conf.station or 'HJ212'
	self._last_samples_save = sys:now()
	self._last_retain_check = sys:now()

	local sint = tonumber(conf.samples_interval) or 120 -- seconds
	self._samples_interval = sint > 0 and sint or 120
	--self._samples_interval = 10

	self._rdata_interval = tonumber(conf.rdata_interval) or 30
	self._min_interval = tonumber(conf.min_interval) or 10
	if (60 % self._min_interval) ~= 0 then
		log:error("Minutes Interval Error, reset to 10")
		self._min_interval = 10
	end
	self._calc_delay = tonumber(conf.calc_delay) or 1000
	self._local_timestamp = conf.local_timestamp or false
	if self._local_timestamp then
		log:warning("Using local timestamp instead of input value's source timestamp")
	end

	local max_duration = conf.using_siridb and 121 or 4
	local def_duration = math.abs(conf.duration or max_duration)
	if def_duration > max_duration then
		def_duration = max_duration
		log:warning("History database duration cannot bigger than "..max_duration.." months")
	end
	def_duration = 0
	def_duration = def_duration..'m'
	local durations = {
		SAMPLE='14d',
		--INFO='1m', -- INFO Saved duration is same as history data
	}

	local db_folder = sysinfo.data_dir() .. "/db_" .. self._name
	if not conf.using_siridb then
		self._hisdb = hisdb:new(db_folder, durations, def_duration)
		local r, err = self._hisdb:open()
		if not r  then
			return nil, err
		end
	else
		local i = 1
		local max_retry = 10
		self._hisdb = siridb:new(self._name, durations, def_duration)
		while true do
			local r, err = self._hisdb:open()
			if r then
				break
			end
			log:error("Failed to open history database", err)
			if i > max_retry then
				return nil, err
			end
			self._sys:sleep(1000)
		end
	end

	conf.servers = conf.servers or {}
	if os.getenv("IOE_DEVELOPER_MODE") then
		if #conf.servers == 0 then
			--[[
			table.insert(conf.servers, {
			name = 'city',
			host = '127.0.0.1',
			port = 6000,
			passwd = '123456',
			})
			]]--
			table.insert(conf.servers, {
				name = 'ministry',
				host = '127.0.0.1',
				port = 16005,
				passwd = '123456',
				retry = 1,
				resend = 'Yes',
				version = '2005',
				value_tpl = 'TaiAn',
			})
		end
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'test'

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end
	log:info("Loading template", tpl_file)

	-- 加载模板
	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file, function(...) log:error(...) end)

	self._tpl = tpl
	self._devs = {}

	self._station = station:new(conf.system, conf.dev_id, function(ms)
		sys:sleep(ms)
	end)
	self._station:set_handlers({
		rdata_interval = function(interval)
			return self:set_rdata_interval(interval)
		end,
		min_interval = function(interval)
			return self:set_min_interval(interval)
		end
	})
	self._station:set_rdata_interval(self._rdata_interval)
	self._station:set_min_interval(self._min_interval)

	self._calc_mgr = calc_mgr:new()

	local inputs = {}
	local app_inst = self
	local map_dev_sn = function(sn)
		return string.gsub(sn, '^STATION(.*)$', conf.station..'%1')
	end
	local no_hisdb = conf.no_hisdb
	for sn, d in pairs(tpl.devs) do
		local dev = {}
		local tag_list = {}
		for _, prop in ipairs(d) do
			inputs[#inputs + 1] = {
				name = prop.name,
				desc = prop.desc,
				unit = prop.unit,
				vt = prop.vt
			}
			if dev[prop.input] then
				table.insert(dev[prop.input], prop)
			else
				dev[prop.input] = {prop}
			end

			if no_hisdb then
				prop.no_hisdb = true
			end

			local tag = tag:new(self._hisdb, self._station, prop, function(tag)
				local obj = info:new(self._hisdb, tag, {}, prop.no_hisdb)
				local r, err = obj:init_db()
				if not r then
					log:error(err)
					return nil, err
				end
				return obj
			end)

			local p_name = prop.name
			tag:set_value_callback(function(type_name, val, timestamp, quality)
				local dev = app_inst._dev
				if not dev then
					-- log:warning('Device object not found', p_name, prop, value, timestamp)
					return
				end
				if type_name == 'SAMPLE' then
					dev:set_input_prop(p_name, 'value', val.value, timestamp, quality)
				else
					local val_str, err = cjson.encode(val)
					if not val_str then
						log:error('JSON ENCODE ERROR', p_name)
						for k,v in pairs(val) do
							if tostring(v) == '-nan' then
								log:warning('Value corrected:',k,v)
								val[k] = 0
							end
							if tostring(v) == 'inf' then
								log:warning('Value corrected:',k,v)
								if k == 'avg' then
									val[k] = 0xFFFFFFFF
								else
									val[k] = 0
								end
							end
						end
						val_str, err = cjson.encode(val)
					end
					if val_str then
						dev:set_input_prop(p_name, type_name, val_str, timestamp, quality)
					else
						log:error('Value cannot serialized by cjson')
					end
				end
			end)
			tag_list[p_name] = tag
		end

		local dev_sn = map_dev_sn(sn)
		self._devs[dev_sn] = dev
		self._station:add_meter(meter:new(sn, tag_list))
	end

	local meta = self._api:default_meta()
	meta.name = 'HJ212' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'HJ212 Smart Device' 
	meta.series = 'N/A'

	local sys_id = self._sys:id()
	local station_sn = sys_id..'.'..conf.station
	self._dev_sn = station_sn

	local commands = {
		{ name = 'purge_hisdb', desc = "Purge history db" },
		{ name = 'upload_rdata', desc = "Force upload RDATA data" },
		{ name = 'upload_min', desc = "Force upload MIN data" },
		{ name = 'upload_hour', desc = "Force upload HOUR data" },
		{ name = 'upload_day', desc = "Force upload DAY data" },
		{ name = 'upload_all', desc = "Force upload ALL data by range" },
	}

	self._dev = self._api:add_device(self._dev_sn, meta, inputs, nil, commands)

	--- initialize connections
	self._clients = {}
	for _, v in ipairs(conf.servers) do
		local client = conn:new(self, v, self._station, self._dev_sn)
		local r, err = client:start()
		if not r then
			log:error("Start connection failed", err)
		end
		table.insert(self._clients, client)
	end

	sys:timeout(10, function()
		--- Start timers
		self:start_timers()
		self._station:init(self._calc_mgr, function(...)
			log:error("Init tag failed", ...)
		end)
		self:read_tags()
		self._inited = true
	end)

	log:info("Register station", conf.station, self:app_name())
	ioe.env.set('HJ212.STATION', conf.station or 'HJ212', self:app_name())

	return true
end

function app:set_station_prop_value(props, value, timestamp, quality)
	local sys = self:sys_api()
	local quality = quality ~= nil and quality or 0
	if quality ~= 0 then 
		self._log:warning("Value quality is not good", quality, type(quality))
	end

	for _, v in ipairs(props) do
		if not v.src_prop or string.lower(v.src_prop) == 'value' then
			local val = (v.rate and v.rate ~= 1) and value * v.rate or value
			timestamp = self._local_timestamp and sys:time() or timestamp

			local flag = quality ~= 0 and types.FLAG.Connection or nil
			local val_z = nil
			local r, err = self._station:set_tag_value(v.name, val, timestamp, val_z, flag, quality)
			if not r then
				self._log:error("Cannot set tag value", v.name, val, err)
			end
		end
	end
end

function app:set_station_prop_rdata(props, value, timestamp, quality)
	local sys = self:sys_api()
	local quality = quality ~= nil and quality or 0
	if quality ~= 0 then
		self._log:warning("Value quality(RDATA) is not good", quality, type(quality))
	end
	for _, v in ipairs(props) do
		if v.src_prop == 'RDATA' then
			local val = (v.rate and v.rate ~= 1) and value.value * v.rate or value.value
			local val_z = (v.rate and v.rate ~= 1 and value.value_z ~= nil) and value.value_z * v.rate or value.value_z
			timestamp = self._local_timestamp and sys:time() or timestamp

			local r, err = self._station:set_tag_value(v.name, val, timestamp, val_z, v.flag, quality)
			if not r then
				self._log:warning("Failed set tag value from rdata", v.name, cjson.encode(value), err)
			end
		end
	end
end

function app:set_station_prop_info(props, value, timestamp, quality)
	local sys = self:sys_api()
	local quality = quality ~= nil and quality or 0
	if quality ~= 0 then
		self._log:warning("Value quality(INFO) is not good", quality, type(quality))
	end
	for _, v in ipairs(props) do
		local tag, err = self._station:find_tag(v.name)
		if tag then
			local r, err = tag:set_info_value(value, timestamp, quality)
			if not r then
				self._log:warning("Failed set info value from rdata", v.name, cjson.encode(value), err)
			end
		end
	end
end

function app:read_tags()
	local api = self:data_api()
	local sys = self:sys_api()
	local sys_id = sys:id()

	for sn, dev in pairs(self._devs) do
		local dev_api = api:get_device(sn)
		if not dev_api then
			dev_api = api:get_device(sys_id..'.'..sn)
		end
		if dev_api then
			for input, tags in pairs(dev) do
				local value, timestamp, quality = dev_api:get_input_prop(input, 'value')
				if value then
					self:set_station_prop_value(tags, value, timestamp, quality)
				else
					--self._log:error("Cannot read input value", sn, input)
				end
				local value, timestamp, quality = dev_api:get_input_prop(input, 'RDATA')
				if value then
					value = cjson.decode(value) or {}
					self:set_station_prop_rdata(tags, value, timestamp, quality)
				else
					--self._log:error("Cannot read input value", sn, input)
				end
			end
		else
			self._log:debug("Cannot find device", sn)
		end
	end
end

function app:on_run(tms)
	self:for_earch_client('on_run')

	local sys = self:sys_api()
	local now = sys:now()
	if now - self._last_retain_check > 60 * 1000 then
		self._last_retain_check = now
		self._hisdb:retain_check()
	end

	if (now - self._last_samples_save) > (self._samples_interval * 1000) then
		if sys:time() % 60 > 3 then
			self._last_samples_save = now
			self:save_samples()
		end
	end

	return 1000
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	self._inited = false
	--- Close the client connections
	for _, v in ipairs(self._clients) do
		v:close()
	end
	self._clients = {}

	--- Stop timers
	if self._rdata_timer then
		self._rdata_timer:stop()
		self._rdata_timer = nil
	end
	if self._min_timer then
		self._min_timer:stop()
		self._min_timer = nil
	end
	-- Save samples before
	self:save_samples()

	self._hisdb:close()
	self._hisdb = nil

	return true
end

function app:on_ctrl(app_src, command, param, priv)
	self._log:debug('on_ctrl', app_src, command, param, priv)
	if command == 'ping' then
		return true
	end
	if command == 'reg' then
		self._childs[app_src] = param
		return true
	end
	if command == 'unreg' then
		self._childs[app_src] = nil
		return true
	end
	return true
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl_outputs) do
		if v.name == output then
			-- TODO: write
		end
	end

	return nil, "Output not found!"
end

function app:on_command(app_src, sn, command, param, priv)
	if command == 'purge_hisdb' then
		if param.pwd == self:app_name() then
			return self._hisdb:purge_all(), "History database has been purged"
		else
			return false, "Password incorrect"
		end
	end
	local func_name = command..'_data'
	if command == 'upload_rdata' then
		func_name = 'upload_rdata'
	end
	if command == 'upload_rdata' or command == 'upload_min' or command == 'upload_hour' or command == 'upload_day' then
		if not param.time then
			return false, "Time is mising"
		end
		local r, dt = pcall(date, param.time)
		if not r then
			return false, dt
		end
		local dts  = date.diff(dt:toutc(), date(0)):spanseconds()

		self._log:warning('Time for '..command..' is '..param.time, date(dts):tolocal())

		local func = assert(self[func_name])
		func(self, dts)
		return true, string.format('Command %s triggered with time: %s', command, tostring(date(dts):tolocal()))
	end
	if command == 'upload_all' then
		if not param.stime then
			return false, "Start time is mising"
		end
		if not param.etime then
			return false, "End time is missing"
		end
		local r, dt = pcall(date, param.stime)
		if not r then
			return false, dt
		end
		local dts  = date.diff(dt:toutc(), date(0)):spanseconds()

		local r, dt = pcall(date, param.etime)
		if not r then
			return false, dt
		end
		local dte  = date.diff(dt:toutc(), date(0)):spanseconds()

		local diff_hour = nil
		if param.diff then
			diff_hour = tonumber(param.diff)
			if not diff_hour then
				return false, "Diff must be number in hours"
			end
		end
		if self._upload_all_in then
			return false, 'Upload all in progress!'
		end

		self._sys:fork(function()
			self._upload_all_in = true
			local r, err = xpcall(self.upload_all, debug.traceback, self, dts, dte, diff_hour)
			if not r then
				self._log:error("Upload_all failed", err)
			end
			self._upload_all_in = nil
		end)

		self._log:warning('Time for '..command..' from '..param.stime..' to '..param.etime, date(dts):tolocal(), date(dte):tolocal())

		return true, string.format('Upload all data time:', tostring(date(dts):tolocal()), tostring(date(dte):tolocal()))

	end
	return false, "Unknown command"
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	if not self._inited then
		return
	end

	local sys_id = self._sys:id()..'.'
	if string.find(sn, sys_id, 1, true) == 1 then
		sn = string.sub(sn, string.len(sys_id) + 1)
	end
	if string.len(sn) == 0 then
		return
	end

	local dev = self._devs[sn]
	if not dev then
		return
	end

	local inputs = dev[input]
	if not inputs then
		return
	end

	--- Decode the prop RDATA
	if prop ~= 'value' and prop ~= 'RDATA' and prop ~= 'INFO' then
		return
	end
	if prop == 'RDATA' and type(value) == 'string' then
		value, err = cjson.decode(value)
		if not value then
			self._log:warning("Failed to decode RDATA prop err: "..err)
			self._log:warning("Failed to decode RDATA prop value: "..value)
			value = {}
		end
	end

	if prop == 'INFO' and type(value) == 'string' then
		value, err = cjson.decode(value)
		if not value then
			self._log:warning("Failed to decode INFO prop err: "..err)
			self._log:warning("Failed to decode INFO prop value: "..value)
			value = {}
		end
	end

	timestamp = self._local_timestamp and self._sys:time() or timestamp

	if prop == 'value' then
		self:set_station_prop_value(inputs, value, timestamp, quality)
	else
		if prop == 'RDATA' then
			self:set_station_prop_rdata(inputs, value, timestamp, quality)
		end
		if prop == 'INFO' then
			self:set_station_prop_info(inputs, value, timestamp, quality)
		end
	end
end

function app:save_samples()
	local start = self._sys:time()
	self._log:notice("Saving sample data start", start)

	local station = self._station
	for _, meter in ipairs(station:meters()) do
		--self._log:debug("Saving sample data for meter:"..meter:sn())
		for tag_name, tag in pairs(meter:tag_list()) do
			--self._log:debug("Saving sample data for tag:"..tag_name)
			local r, err = tag:save_samples()
			if not r then
				self._log:error("Failed saving sample data for tag:"..tag_name, err)
			end

			self._sys:sleep(10)

			local info, err = tag:info()
			if info then
				local r, err = info:save_samples()
				if not r then
					self._log:error("Failed saving sample info for tag:"..tag_name, err)
				end

				self._sys:sleep(10)
			end
		end
	end

	local now = self._sys:time()
	self._log:notice("Saving sample data done", now, now - start)
end

function app:for_earch_client(func, ...)
	for _, v in ipairs(self._clients) do
		v[func](v, ...)
	end
end

function app:for_earch_client_async(func, ...)
	for _, v in ipairs(self._clients) do
		self._sys:fork(function(...)
			v[func](v, ...)
		end, ...)
	end
end

function app:upload_rdata(now)
	local data = self._station:rdata(now, false)
	self:for_earch_client_async('upload_rdata', data)
end

function app:upload_min_data(now)
	local data = self._station:min_data(now, now)
	self:for_earch_client_async('upload_min_data', data)
end

function app:upload_hour_data(now)
	local data = self._station:hour_data(now, now)
	self:for_earch_client_async('upload_hour_data', data)
end

function app:upload_day_data(now)
	local data = self._station:day_data(now, now)
	self:for_earch_client_async('upload_day_data', data)
end

function app:diff_data(data, diff_hour)
	for _, v in ipairs(data) do
		local dt = v:data_time()
		dt = dt + (diff_hour * 3600)
		print(v:data_time(), diff_hour, dt)
		v:set_data_time(dt)
	end
	return data
end

function app:upload_all(stime, etime, diff_hour)
	self._log:warning('Upload all data from '..stime..' to '..etime, 'Diff Hour', diff_hour)
	if diff_hour then
		stime = stime - (diff_hour * 3600)
		etime = etime - (diff_hour * 3600)
	end
	local now = stime
	while now <= etime do
		local data = self._station:min_data(now, now)
		self._log:warning('Upload min data '..now, #data)
		if diff_hour then
			data = self:diff_data(data, diff_hour)
		end
		if #data > 0 then
			self:for_earch_client('upload_min_data', data)
		end
		now = now + (self._min_interval * 60)
	end
	now = stime
	while now <= etime do
		self._log:warning('Upload hour data '..now)
		local data = self._station:hour_data(now, now)
		if diff_hour then
			data = self:diff_data(data, diff_hour)
		end

		if #data > 0 then
			self:for_earch_client('upload_hour_data', data)
		end
		now = now + 3600
	end

	local data = self._station:day_data(stime, etime)
	if diff_hour then
		data = self:diff_data(data, diff_hour)
	end

	if #data > 0 then
		self:for_earch_client('upload_day_data', data)
	end
end

function app:set_rdata_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "RData Interval missing")
	if interval > 0 and (interval < 30 or interval > 3600) then
		return nil, "Incorrect interval number"
	end

	self._rdata_interval = interval
	self._station:set_rdata_interval(self._rdata_interval)

	if self._rdata_timer then
		self._rdata_timer:stop()
		self._rdata_timer = nil
	end

	if self._rdata_interval > 0 then
		self._rdata_timer = timer:new(function(now)
			self:upload_rdata(now)
		end, self._rdata_interval)
		self._rdata_timer:start()
	end
end

function app:set_min_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "Min Interval missing")
	if (60 % interval) ~= 0 then
		return nil, "Interval number incorrect"
	end

	self._min_interval = interval
	self._station:set_min_interval(self._min_interval)

	if self._min_timer then
		self._min_timer:stop()
		self._min_timer = nil
	end

	self._min_timer = timer:new(function(now)
		self:min_timer_func(now)
	end, self._min_interval * 60, true)
	self._min_timer:start()
end

function app:min_timer_func(now)
	self._sys:sleep(self._calc_delay)
	self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval * 60)
	self:upload_min_data(now)
	--- If HH:00:00
	if now % 3600 == 0 then
		self._calc_mgr:trigger(calc_mgr.TYPES.HOUR, now, 3600)
		self:upload_hour_data(now)

		local d = date(now):tolocal() --- To local time
		-- 00:00:00
		if d:gethours() == 0 then
			assert(d:getminutes() == 0 and d:getseconds() == 0)
			self._calc_mgr:trigger(calc_mgr.TYPES.DAY, now, 3600 * 24)
			self:upload_day_data(now)
		end
	end
end

function app:start_timers()
	if self._rdata_interval > 0 then
		self._rdata_timer = timer:new(function(now)
			self:upload_rdata(now)
		end, self._rdata_interval, true)
		self._rdata_timer:start()
	end

	-- If HH:MM:00 and min_interval
	self._min_timer = timer:new(function(now)
		self:min_timer_func(now)
	end, self._min_interval * 60, true)
	self._min_timer:start()

	self._sys:timeout(10, function()
		--- Trigger old data
		local now = os.time()
		now = (now // (self._min_interval * 60)) * self._min_interval * 60
		self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval * 60)
		now = (now // 3600) * 3600
		self._calc_mgr:trigger(calc_mgr.TYPES.HOUR, now, 3600)
	end)
end

--- 返回应用对象
return app

