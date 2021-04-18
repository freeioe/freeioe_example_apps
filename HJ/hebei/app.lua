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
local hjpoll = require 'hjpoll'
local hjinfo = require 'hjinfo'
local station_info = require 'station_info'
local siridb = require 'siridb.hisdb'

--- lua_HJ212_version: 2021-04-18
--  comment: Fixed a few things for HeBei HJ

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_HJ212_HeBei_APP")
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

	self._command_wait = {}
	self._command_token = 0

	self._rs_map = {}

	-- Register tags
	local tags = require 'hebei.tags'
	local exinfo = require 'hj212.tags.exinfo'
	for k, v in pairs(tags) do
		exinfo.add(k, v.desc, v.format, v.org_id, v.unit, v.cou_unit)
	end

	--- Register types
	local types = require 'hj212.types'
	types.COMMAND.HB_GATE_ADD_PERSON = 4024
	types.COMMAND.HB_GATE_OPEN = 4022
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
		--conf.local_timestamp = true
		--conf.using_siridb = true
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
		assert(false, "Only siridb supported")
		--[[
		self._hisdb = hisdb:new(db_folder, durations, def_duration)
		local r, err = self._hisdb:open()
		if not r  then
			return nil, err
		end
		]]--
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
				port = 16000,
				passwd = '123456',
				retry = 1,
				resend = 'Yes',
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
	local settings = ioe.env.wait('HJ212.SETTINGS', conf.station)
	log:info("Loaded settings:", cjson.encode(settings))
	self._station:set_settings(settings)
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
		local dev = {
			RS = {} -- Handle the meter connection status
		}
		local poll_list = {}
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

			local poll = hjpoll:new(self._hisdb, self._station, prop, function(poll)
				local obj = hjinfo:new(self._hisdb, poll, {}, prop.no_hisdb)
				local r, err = obj:init_db()
				if not r then
					log:error(err)
					return nil, err
				end
				obj:set_value_callback(function(value, timestamp, quality)
					self:upload_poll_info(poll, obj, value, timestamp, quality)
				end)
				return obj
			end)

			local p_name = prop.name
			poll:set_value_callback(function(type_name, val, timestamp, quality)
				local dev = app_inst._dev
				if not dev then
					-- log:warning('Device object not found', p_name, prop, value, timestamp)
					return
				end
				if type_name == 'SAMPLE' then
					dev:set_input_prop(p_name, 'value', val.value, timestamp, quality)
					if val.value_z then
						dev:set_input_prop(p_name, 'value_z', val.value_z, timestamp, quality)
					end
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
						dev:set_input_prop(p_name, type_name, val, timestamp, quality)
					else
						log:error('Value cannot serialized by cjson')
					end
				end
			end)
			poll_list[p_name] = poll
		end

		local dev_sn = map_dev_sn(sn)
		self._devs[dev_sn] = dev
		self._station:add_meter(meter:new(sn, poll_list))
	end

	if true then
		local poll_list = {}
		local station_prop = { name = "__STATION__", src_prop = 'INFO' }
		local gate_prop = { name = "__STATION.GATE__", src_prop = 'INFO' }
		poll_list[station_prop.name] = hjpoll:new(self._hisdb, self._station, station_prop, function(poll)
			return self:create_station_info(poll)
		end)
		poll_list[gate_prop.name] = hjpoll:new(self._hisdb, self._station, gate_prop, function(poll)
			local obj = hjinfo:new(self._hisdb, poll, {}, false)
			local r, err = obj:init_db()
			if not r then
				log:error(err)
				return nil, err
			end
			obj:set_value_callback(function(value, timestamp, quality)
				self:upload_gate_info(obj, value, timestamp, quality)
			end)
			self._gate_info = obj
			return obj
		end)

		self._devs[map_dev_sn('STATION.SETTINGS')] = {
			info = {station_prop}
		}

		self._devs[map_dev_sn('STATION.GATE')] = {
			info = {gate_prop}
		}

		local sys_id = self._sys:id()
		self._station:add_meter(meter:new(sys_id, poll_list))
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
			log:error("Init poll failed", ...)
		end)
		self:read_polls()
		self._inited = true
	end)

	log:info("Register station", conf.station, self:app_name())
	ioe.env.set('HJ212.STATION', conf.station or 'HJ212', self:app_name())

	return true
end

function app:create_station_info(poll)
	assert(poll)
	if self._station_info then
		return self._station_info
	end

	self._station_info = station_info:new(self._hisdb, poll, {}, false)
	local r, err = self._station_info:init_db()
	if not r then
		log:error(err)
		return nil, err
	end

	self._station_info:set_value_callback(function(value, timestamp, quality)
		self:upload_station_info(self._station_info, value, timestamp, quality)
	end)

	local poll_list = {}
	for sn, val in pairs(self._rs_map) do
		local dev = self._devs[sn]

		for k, inputs in pairs(dev) do
			for _, v in ipairs(inputs) do
				table.insert(poll_list, v.name)
			end
		end
		self._station_info:set_conn_list(poll_list, table.unpack(val))
	end

	return self._station_info
end

function app:set_station_rs(sn, dev, value, timestamp, quality)
	self._log:info("Meter state changed", sn, value, timestamp, quality)
	self._rs_map[sn] = { value, timestamp, quality }

	if not self._station_info then
		self._log:warning("Station info missing!")
		return
	end

	local poll_list = {}
	for k, inputs in pairs(dev) do
		for _, v in ipairs(inputs) do
			table.insert(poll_list, v.name)
		end
	end

	return self._station_info:set_conn_list(poll_list, value, timestamp, quality)
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
			local r, err = self._station:set_poll_value(v.name, val, timestamp, val_z, flag, quality)
			if not r then
				self._log:error("Cannot set poll value", v.name, val, err)
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
			local ex_vals = nil
			if value.value_src then
				ex_vals = {
					['i13115-Info'] = value.value_src
				}
			end

			local r, err = self._station:set_poll_value(v.name, val, timestamp, val_z, v.flag, quality, ex_vals)
			if not r then
				self._log:warning("Failed set poll value from rdata", v.name, cjson.encode(value), err)
			end
		end
	end
end

function app:set_station_prop_info(props, value, timestamp, quality)
	local dt = value.DT or 0
	value.DT = nil -- clean up DT in info data

	local sys = self:sys_api()
	local quality = quality ~= nil and quality or 0
	if quality ~= 0 then
		self._log:warning("Value quality(INFO) is not good", quality, type(quality))
	end
	for _, v in ipairs(props) do
		local poll, err = self._station:find_poll(v.name)
		if poll then
			local r, err = poll:set_info_value(value, timestamp, quality)
			if not r then
				self._log:warning("Failed set info value from rdata", v.name, cjson.encode(value), err)
			end
		end
	end
end

function app:read_polls()
	local api = self:data_api()
	local sys = self:sys_api()
	local sys_id = sys:id()

	for sn, dev in pairs(self._devs) do
		local dev_api = api:get_device(sn)
		if not dev_api then
			dev_api = api:get_device(sys_id..'.'..sn)
		end
		if dev_api then
			for input, polls in pairs(dev) do
				local value, timestamp, quality = dev_api:get_input_prop(input, 'value')
				if value then
					if input == 'RS' then
						self:set_station_rs(sn, dev, value, timestamp, quality)
					end
					self:set_station_prop_value(polls, value, timestamp, quality)
				else
					--self._log:error("Cannot read input value", sn, input)
				end
				local value, timestamp, quality = dev_api:get_input_prop(input, 'RDATA')
				if value then
					if type(value) == 'string' then
						local val, err = cjson.decode(value)
						if not val then
							self._log:warning("Value of RDATA decode failed", err)
						else
							value = val
						end
					end
					self:set_station_prop_rdata(polls, value, timestamp, quality)
				else
					--self._log:error("Cannot read input value", sn, input)
				end
				local value, timestamp, quality = dev_api:get_input_prop(input, 'INFO')
				if value then
					self:set_station_prop_info(polls, value, timestamp, quality)
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

	-- TODO: Update status

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
		if input == 'RS' then
			self:set_station_rs(sn, dev, value, timestamp, quality)
		end
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
		for poll_id, poll in pairs(meter:poll_list()) do
			--self._log:debug("Saving sample data for poll:"..poll_id)
			local r, err = poll:save_samples()
			if not r then
				self._log:error("Failed saving sample data for poll:"..poll_id, err)
			end

			self._sys:sleep(10)

			local info, err = poll:info()
			if info then
				local r, err = info:save_samples()
				if not r then
					self._log:error("Failed saving sample info for poll:"..poll_id, err)
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

function app:upload_poll_info(poll, info, value, timestamp, quality)
	if quality ~= 0 then
		-- TODO: upload station info
		return
	end

	local poll_id = poll:id()
	local state, status = info:info_data(value, timestamp, quality)

	if string.sub(poll_id, 1, 1) == 'a' then
		if state then
			self:upload_meter_info(2, poll_id, state)
		end
		if status then
			self:upload_meter_info(3, poll_id, status)
		end
	elseif string.sub(poll_id, 1, 1) == 'w' then
		if state then
			self:upload_meter_info(2, poll_id, state)
		end
		if status then
			self:upload_meter_info(3, poll_id, status)
		end
	end
end

function app:upload_meter_info(dt, poll_id, data, timestamp)
	assert(#data > 0, 'PolId:'..(poll_id or 'STATION')..' DT:'..dt)
	self._log:debug("Upload meter info", dt, poll_id, timestamp)
	self:for_earch_client_async('upload_meter_info', dt, poll_id, data, timestamp)	
end

function app:upload_station_info(info, value, timestamp, quality)
	assert(info)
	assert(value)
	assert(timestamp)
	assert(quality)

	if quality ~= 0 then
		--- TODO:
		return
	end

	local data, err = info:data(timestamp)
	if data then
		self._log:info("Station info data upload")
		self:upload_meter_info(1, nil, data, timestamp)
	else
		self._log:error("Station info data error", err)
	end
end

function app:upload_gate_info(info, value, timestamp, quality)
	if quality ~= 0 then
		--- TODO:
		return
	end
	local state = info:data(timestamp)
	if state then
		self:upload_meter_info(0, nil, state, timestamp)
	end
end

function app:upload_rdata(now)
	local data = self._station:rdata(now, false)
	if #data == 0 then
		self._log:warning("No RDATA!!!")
		return
	end
	self:for_earch_client_async('upload_rdata', data)
end

function app:upload_min_data(now)
	local data = self._station:min_data(now, now)
	if #data == 0 then
		self._log:warning("No MIN DATA!!!")
		return
	end
	self:for_earch_client_async('upload_min_data', data)
end

function app:upload_hour_data(now)
	local data = self._station:hour_data(now, now)
	if #data == 0 then
		self._log:warning("No HOUR DATA!!!")
		return
	end
	self:for_earch_client_async('upload_hour_data', data)
end

function app:upload_day_data(now)
	local data = self._station:day_data(now, now)
	if #data == 0 then
		self._log:warning("No DAY DATA!!!")
		return
	end
	self:for_earch_client_async('upload_day_data', data)
end

function app:diff_data(data, diff_hour)
	for _, v in ipairs(data) do
		local dt = v:data_time()
		dt = dt + (diff_hour * 3600)
		--print(v:data_time(), diff_hour, dt)
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

function app:send_command(dev_sn, cmd, params, timeout)
	local timeout = timeout or 5000 -- five seconds
	local conf = self:app_conf()
	local sys_id = self._sys:id()

	local dev_sn = string.gsub(dev_sn, '^STATION(.*)$', conf.station..'%1')

	local device, err = self._api:get_device(sys_id..'.'..dev_sn)
	if not device then
		return nil, 'Device not found!!'
	end

	local priv = self._command_token
	self._command_token = (self._command_token + 1) % 0xFFFF
	self._command_wait[priv] = {}

	local r, err = device:send_command(cmd, params or {}, priv)
	if not r then
		self._command_wait[priv] = nil
		self._log:error('Device command execute failed!', err)
		return nil, err
	end

	self._sys:sleep(timeout, self._command_wait[priv])

	local r = self._command_wait[priv]

	self._command_wait[priv] = nil

	if r.result ~= nil then
		return r.result, r.msg
	end

	return nil, 'Command timeout!!!'
end

function app:on_command_result(app_src, priv, result, err)
	local priv_o = self._command_wait[priv]
	if priv_o then
		priv_o.result = result
		priv_o.msg = err
		self._sys:wakeup(priv_o)
	else
		self._log:error("No result waitor for command!")
	end
end

--- 返回应用对象
return app

