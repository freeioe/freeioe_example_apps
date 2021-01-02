--- 导入需求的模块
local ioe = require 'ioe'
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

--- lua_HJ212_version: 2020-12-15

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
		if not log[level] then
			log.info(...)
		else
			log[level](log, ...)
		end
	end)
end

--- 应用启动函数
function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()
	conf.station = conf.station or 'HJ212'
	self._last_samples_save = sys:now()
	self._last_retain_check = sys:now()

	local sint = tonumber(conf.samples_interval) or 120 -- seconds
	self._samples_interval = sint > 0 and sint or 120

	self._rdata_interval = tonumber(conf.rdata_interval) or 30
	self._min_interval = tonumber(conf.min_interval) or 10

	local db_folder = sysinfo.data_dir() .. "/db_" .. self._name
	self._hisdb = hisdb:new(db_folder, {SAMPLE='1d'})
	local r, err = self._hisdb:open()
	if not r then
		self._log:error("Failed to open history database", err)
		return nil, err
	end

	conf.servers = conf.servers or {}
	if #conf.servers == 0 then
		table.insert(conf.servers, {
			name = 'localhost',
			host = '127.0.0.1',
			port = 16000,
			passwd = '123456',
		})
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example'

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			self._log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end
	self._log:info("Loading template", tpl_file)

	-- 加载模板
	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file, function(...) self._log:error(...) end)

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
			tag:set_value_callback(function(prop, value, timestamp)
				local dev = app_inst._dev
				if not dev then
					-- self._log:warning('Device object not found', p_name, prop, value, timestamp)
					return
				end
				dev:set_input_prop(p_name, prop, value, timestamp)
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
			self._log:error("Start connection failed", err)
		end
		table.insert(self._clients, client)
	end

	sys:timeout(10, function()
		--- Start timers
		self:start_timers()
		self._station:init(self._calc_mgr, function(...)
			self._log:error("Init tag failed", ...)
		end)
		self:read_tags()
		self._inited = true
	end)

	self._log:info("Register station", conf.station, self:app_name())
	ioe.env.set('HJ212.STATION', conf.station or 'HJ212', self:app_name())

	return true
end

function app:read_tags()
	local api = self:data_api()
	local sys_id = self:sys_api():id()

	for sn, dev in pairs(self._devs) do
		local dev_api = api:get_device(sn)
		if not dev_api then
			dev_api = api:get_device(sys_id..'.'..sn)
		end
		if dev_api then
			for input, tags in pairs(dev) do
				local value, timestamp = dev_api:get_input_prop(input, 'value')
				if value then
					for _, v in ipairs(tags) do
						local r, err =self._station:set_tag_value(v.name, value, timestamp)
						if not r then
							self._log:error("Cannot set input value", v.name, value, err)
						end
					end
				else
					--self._log:debug("Cannot read input value", sn, input)
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

	if quality ~= 0 or prop ~= 'value' then
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

	for _, v in ipairs(inputs) do
		local r, err = self._station:set_tag_value(v.name, value, timestamp)
		if not r then
			self._log:warning("Failed set tag value", v.name, value, err)
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

function app:upload_rdata(now, save)
	local data = self._station:rdata(now, save)
	self:for_earch_client('upload_rdata', data)
end

function app:upload_min_data(now)
	local data = self._station:min_data(now, now)
	self:for_earch_client('upload_min_data', data)
end

function app:upload_hour_data(now)
	local data = self._station:hour_data(now, now)
	self:for_earch_client('upload_hour_data', data)
end

function app:upload_day_data(now)
	local data = self._station:day_data(now, now)
	self:for_earch_client('upload_day_data', data)
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
			self:upload_rdata(now, true)
		end, self._rdata_interval)
		self._rdata_timer:start()
	end
end

function app:set_min_interval(interval)
	local interval = tonumber(interval)
	assert(interval, "Min Interval missing")
	if 60 % interval ~= 0 then 
		return nil, "Interval number incorrect"
	end

	self._min_interval = interval

	if self._min_timer then
		self._min_timer:stop()
		self._min_timer = nil
	end

	self._min_timer = timer:new(function(now)
		self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval)
		self:upload_min_data(now)
	end, self._min_interval * 60, true)
	self._min_timer:start()
end

function app:start_timers()
	if self._rdata_interval > 0 then
		self._rdata_timer = timer:new(function(now)
			self:upload_rdata(now, true)
		end, self._rdata_interval, true)
		self._rdata_timer:start()
	end

	self._min_timer = timer:new(function(now)
		self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval * 60)
		self:upload_min_data(now)
		if now % 3600 == 0 then
			self._calc_mgr:trigger(calc_mgr.TYPES.HOUR, now, 3600)
			self:upload_hour_data(now)
		end
		if now % (3600 * 24) == 0 then
			self._calc_mgr:trigger(calc_mgr.TYPES.DAY, now, 3600 * 24)
			self:upload_day_data(now)
		end
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

	--[[
	self._hour_timer = timer:new(function(now)
		self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval)
		self._calc_mgr:trigger(calc_mgr.TYPES.HOUR, now, 3600)
		self:upload_hour_data(now)
	end, 3600, true)
	self._hour_timer:start()

	self._day_timer = timer:new(function(now)
		self._calc_mgr:trigger(calc_mgr.TYPES.MIN, now, self._min_interval)
		self._calc_mgr:trigger(calc_mgr.TYPES.HOUR, now, 3600)
		self._calc_mgr:trigger(calc_mgr.TYPES.ALL, now, 3600 * 24)
		self:upload_day_data(now)
	end, 3600 * 24, true)
	self._day_timer:start()
	]]--
end

--- 返回应用对象
return app

