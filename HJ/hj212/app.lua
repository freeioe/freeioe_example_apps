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
local hisdb = require 'hisdb.hisdb'

--- lua_HJ212_version: 2021-01-29

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
		conf.local_timestamp = true
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

	local db_folder = sysinfo.data_dir() .. "/db_" .. self._name
	self._hisdb = hisdb:new(db_folder, {SAMPLE='1d'})
	local r, err = self._hisdb:open()
	if not r then
		log:error("Failed to open history database", err)
		return nil, err
	end

	conf.servers = conf.servers or {}
	if os.getenv("IOE_DEVELOPER_MODE") then
		self._min_interval = 1
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

	self._calc_mgr = calc_mgr:new()

	local inputs = {}
	local app_inst = self
	local map_dev_sn = function(sn)
		return string.gsub(sn, '^STATION(.*)$', conf.station..'%1')
	end
	local no_hisdb = conf.no_hisdb
	for sn, tags in pairs(tpl.devs) do
		local dev = {}
		local tag_list = {}
		for _, prop in ipairs(tags) do
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

			local tag = tag:new(self._hisdb, self._station, prop)
			local p_name = prop.name
			tag:set_value_callback(function(type_name, val, timestamp)
				local dev = app_inst._dev
				if not dev then
					-- log:warning('Device object not found', p_name, prop, value, timestamp)
					return
				end
				if type_name == 'SAMPLE' then
					dev:set_input_prop(p_name, 'value', val.value, timestamp)
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
						dev:set_input_prop(p_name, type_name, val_str, timestamp)
					else
						log:error('Value cannot serialized by cjson')
					end
				end
			end)
			tag_list[prop.name] = tag
		end
		local dev_sn = map_dev_sn(sn)
		self._devs[dev_sn] = dev
		self._station:add_meter(meter:new(sn, {}, tag_list))
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
		{ name = 'purge_hisdb', desc = "Purge history db" }
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
				if value and quality == 0 then
					for _, v in ipairs(tags) do
						if not v.src_prop or string.lower(v.src_prop) == 'value' then
							local val = (v.rate and v.rate ~= 1) and value * v.rate or value
							timestamp = self._local_timestamp and sys:time() or timestamp
							local r, err =self._station:set_tag_value(v.name, val, timestamp)
							if not r then
								self._log:error("Cannot set input value", v.name, val, err)
							end
						end
					end
				else
					--self._log:error("Cannot read input value", sn, input)
				end
				local value, timestamp, quality = dev_api:get_input_prop(input, 'RDATA')
				if value and quality == 0 then
					value = cjson.decode(value) or {}
					for _, v in ipairs(tags) do
						if v.src_prop == 'RDATA' then
							local val = (v.rate and v.rate ~= 1) and value.value * v.rate or value.value
							local val_z = (v.rate and v.rate ~= 1 and value.value_z ~= nil) and value.value_z * v.rate or value.value_z
							timestamp = self._local_timestamp and sys:time() or timestamp
							local r, err = self._station:set_tag_value(v.name, val, timestamp, val_z)
							if not r then
								self._log:warning("Failed set tag rdata", v.name, cjson.encode(value), err)
							end
						end
					end
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
	if prop ~= 'value' and prop ~= 'RDATA' then
		return
	end
	if prop == 'RDATA' then
		value, err = cjson.decode(value)
		if not value then
			self._log:warning("Failed to decode RDATA prop err: "..err)
			self._log:warning("Failed to decode RDATA prop value: "..value)
			value = {}
		end
	end

	timestamp = self._local_timestamp and self._sys:time() or timestamp

	if prop == 'value' then
		for _, v in ipairs(inputs) do
			if not v.src_prop or string.lower(v.src_prop) == 'value' then
				if quality ~= 0 then
					self._log:warning("Quality of "..v.name..".value is not good", quality, type(quality))
					value = 0 -- For to zero
				end
				local val = (v.rate and v.rate ~= 1) and value * v.rate or value
				local r, err = self._station:set_tag_value(v.name, val, timestamp)
				if not r then
					self._log:warning("Failed set tag value", v.name, val, err)
				end
				if quality ~= 0 then
					self._dev:set_input_prop(v.name, 'value', 0, timestamp, quality)
				end
			end
		end
	else
		for _, v in ipairs(inputs) do
			if v.src_prop == prop then
				if quality ~= 0 then
					self._log:warning("Quality of "..v.name..".RDATA is not good", quality, type(quality))
					value.value = 0  -- For to zero
					value.value_z = value.value_z and 0 or nil
				end
				local val = (v.rate and v.rate ~= 1) and value.value * v.rate or value.value
				local val_z = (v.rate and v.rate ~= 1 and value.value_z ~= nil) and value.value_z * v.rate or value.value_z
				local r, err = self._station:set_tag_value(v.name, val, timestamp, val_z)
				if not r then
					self._log:warning("Failed set tag rdata", v.name, cjson.encode(value), err)
				end
				if quality ~= 0 then
					self._dev:set_input_prop(v.name, 'value', 0, timestamp, quality)
				end
			end
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

function app:set_rdata_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "RData Interval missing")
	if interval > 0 and (interval < 30 or interval > 3600) then
		return nil, "Incorrect interval number"
	end

	self._rdata_interval = interval
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

