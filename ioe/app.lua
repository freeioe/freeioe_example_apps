local class = require 'middleclass'
local snax = require 'skynet.snax'
local datacenter = require 'skynet.datacenter'
local sysinfo = require 'utils.sysinfo'
local leds = require 'utils.leds'
local event = require 'app.event'
local lte_wan = require 'lte_wan'
local sbat = require 'standby_battery'
local ioe = require 'ioe'
local lfs = require 'lfs'
-- own libs
local disk = require 'disk'

local app = class("FREEIOE_SYS_APP_CLASS")
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf or {}
	self._api = self._sys:data_api()
	self._log = sys:logger()
	self._cancel_timers = {}
	self._apps_cache = {}
	self._lte_wan = lte_wan:new(self, sys, self._conf.lte_wan_freq)
	self._sbat = sbat:new(self, sys)
end

function app:start()
	self._api:set_handler({
		on_output = function(app_src, sn, output, prop, value, timestamp, priv)
			self._log:trace('on_output', app_src, sn, output, prop, value)
			return true, "done"
		end,
		on_command = function(app_src, sn, command, param, priv)
			if command == 'cfg_crash_ack' then
				return self:cfg_crash_ack()
			end
			if command == 'ext_auto_clean' then
				return self:ext_auto_clean(param)
			end
			if command == 'ext_upgrade' then
				return self:ext_upgrade(param)
			end
			if command == 'disable_symlink' then
				return self:disable_symlink(param)
			end
			if command == 'reboot_device' then
				return self:reboot_device(param)
			end
			self._log:trace('on_command', app_src, sn, command, param)
			return true, "eee"
		end,
		on_ctrl = function(app_src, command, param, priv)
			self._log:trace('on_ctrl', app_src, command, param, priv)
		end,
	})

	local inputs = {
		{
			name = 'cpuload',
			desc = 'CPU load avg_1'
		},
		{
			name = 'cpu_temp',
			desc = 'CPU temperature',
			unit = 'Celsius',
		},
		{
			name = 'mem_total',
			desc = 'Memory total size',
			vt = 'int';
			unit = 'KB',
		},
		{
			name = 'mem_used',
			desc = 'Memory used size',
			vt = "int",
			unit = 'KB',
		},
		--[[
		{
			name = 'mem_free',
			desc = 'System memory free size',
			vt = "int",
		},
		]]--
		{
			name = "uptime",
			desc = "System uptime in UTC",
			vt = "int",
			unit = 'sec'
		},
		{
			name = "starttime",
			desc = "FreeIOE start time in UTC",
			vt = "int",
		},
		{
			name = "version",
			desc = "FreeIOE Version",
			vt = "int",
		},
		{
			name = "skynet_version",
			desc = "Skynet Version",
			vt = "int",
		},
		{
			name = "platform",
			desc = "Platform type",
			vt = "string",
		},
		{
			name = "firmware_version",
			desc = "OS firmware version",
			vt = "string",
		},
		{
			name = "data_upload",
			desc = "Data upload option",
			vt = "int",
		},
		{
			name = "data_upload_max_dpp",
			desc = "Data upload max data per packet",
			vt = "int",
		},
		{
			name = "data_upload_cov",
			desc = "Data upload COV option",
			vt = "int",
		},
		{
			name = "data_upload_cov_ttl",
			desc = "Data upload COV TTL",
			vt = "int",
			unit = 'sec'
		},
		{
			name = "data_upload_period",
			desc = "Data upload period",
			vt = "int",
			unit = 'ms'
		},
		{
			name = "upload_period_limit",
			desc = "Data upload period buffer limit",
			vt = "int",
		},
		{
			name = "data_cache",
			desc = "Data cache option",
			vt = "int",
		},
		{
			name = "data_cache_per_file",
			desc = "Data cache count per file",
			vt = "int",
		},
		{
			name = "data_cache_limit",
			desc = "Data cache file limit",
			vt = "int",
		},
		{
			name = "data_cache_fire_freq",
			desc = "Data cache fire frequency",
			vt = "int",
			unit = 'ms'
		},
		{
			name = "stat_upload",
			desc = "Statictis data upload option",
			vt = "int",
		},
		{
			name = "comm_upload",
			desc = "Communication data upload end time",
			vt = "int",
		},
		{
			name = "log_upload",
			desc = "Logs upload end time",
			vt = "int",
		},
		{
			name = "event_upload",
			desc = "Event upload min level",
			vt = "int"
		},
		{
			name = "enable_beta",
			desc = "Device beta mode",
			vt = "int",
		},
		{
			name = "symlink_service",
			desc = "Symlink service enabled",
			vt = "int",
		},
		--[[
		{
			name = 'disk_tmp_used',
			desc = "Disk /tmp used percent",
		}
		]]--
	}

	local wan_inputs = self._lte_wan:inputs()
	for _,v in ipairs(wan_inputs) do
		inputs[#inputs + 1] = v
	end

	local sbat_inputs = self._sbat:inputs()
	for _,v in ipairs(sbat_inputs) do
		inputs[#inputs + 1] = v
	end

	-- for apps
	local apps = datacenter.get("APPS")
	for k, v in pairs(apps) do
		self._apps_cache[k] = {
			name = v.name,
			version = v.version,
			sn = v.sn,
			auto = v.auto
		}
		inputs[#inputs + 1] = {
			name = 'app_run_'..k,
			desc = 'Running status of '..k,
			vt = "int",
		}
	end
	--[[
	if not self._apps_cache['ioe'] then
		self._apps_cache['ioe'] = {
			name = 'freeioe',
		}
	end
	]]--
	self._apps_cache['ioe'] = nil

	local cmds = {
		{
			name = "cfg_crash_ack",
			desc = "Configuration file crash acknowledgement",
		},
		{
			name = "ext_upgrade",
			desc = "Upgrade extension witch specified name",
		},
		{
			name = "ext_auto_clean",
			desc = "Auto cleanup extensions",
		},
		{
			name = "disable_symlink",
			desc = "Disable Symlink Service",
		},
		{
			name = "reboot_device",
			desc = "Reboot hardware device",
		},
	}

	local meta = self._api:default_meta()
	meta.name = "ThingsLink"
	meta.description = "FreeIOE Edge-Computing Gateway"
	meta.series = sysinfo.board_name()
	--
	meta.platform = sysinfo.platform() or "unknown"
	meta.firmware = sysinfo.firmware_version()
	meta.version = sysinfo.version()
	meta.skynet = sysinfo.skynet_version()

	local sys_id = self._sys:id()
	self._dev = self._api:add_device(sys_id, meta, inputs, nil, cmds)
	self._dev:cov({ttl=60})

	if leds.cloud then
		leds.cloud:brightness(0)
	end

	-- detect ubus
	if lfs.attributes('/var/run/ubus.sock', 'mode') then
		local lsocket_loaded, lsocket = pcall(require, 'lsocket')
		if lsocket_loaded  then
			--- Ubus is depends on lsocket
			self._log:notice("Starts ubus service!!!")
			local ubus = snax.uniqueservice('ubus')
		else
			self._log:notice("Module lsocket is not found, ubus service will not be started!!!")
		end
	else
		self._log:notice("Unix socket for ubus not found, ubus service will not be started!!!")
		--local ubus = snax.uniqueservice('ubus', '172.30.11.230', 11000)
		--local ubus = snax.uniqueservice('ubus', '/tmp/ubus.sock')
	end

	self._sys:fork(function()
		self._lte_wan:start(self._dev)
		self._sbat:start(self._dev)
	end)
	return true
end

function app:close(reason)
	--print(self._name, reason)
	self._sbat:stop()
	self._lte_wan:stop()
	for name, cancel_timer in pairs(self._cancel_timers) do
		cancel_timer()
	end
	self._cancel_timers = {}
end

function app:cfg_crash_check()
	if 'file' == lfs.attributes("cfg.json.crash", 'mode') then
		local err = "System configuration file error found!"
		self._log:error(err)

		local report_crash = nil
		report_crash = function()
			self._log:debug("Fire cfg crash event")
			local sys_id = self._sys:id()
			self._dev:fire_event(event.LEVEL_FATAL, event.EVENT_SYS, err, {sn=sys_id})
			-- Reset timer
			self._cancel_timers['cfg_crash'] = self._sys:cancelable_timeout(60 * 60 * 1000, report_crash)
		end
		report_crash()
	end
end

function app:cfg_crash_ack()
	os.execute("rm cfg.json.crash")
	if self._cancel_timers.cfg_crash then
		self._cancel_timers.cfg_crash()
		self._cancel_timers.cfg_crash = nil
	end
	return true
end

function app:first_run()
	self._start_time = self._sys:start_time()
	local v, gv = sysinfo.version()
	self._log:notice("System Version:", v, gv)
	local sv, sgv = sysinfo.skynet_version()
	self._log:notice("Skynet Platform Version:", sv, sgv)
	local plat = sysinfo.platform() or "unknown"
	self._version = v
	--self._git_version = gv
	self._skynet_version = sv
	--self._skynet_git_version = sgv
	self._plat = plat

	self._firmware_version = sysinfo.firmware_version()

	--- Calculate uptime/mem stuff/cpu_temp/tmp_disk for earch 60 seconds
	local calc_tmp_disk = nil
	local tmp_disk_freq = self._conf.tmp_disk_freq or (1000 * 60)
	calc_tmp_disk = function()
		-- Reset timer
		self._cancel_timers['tmp_disk'] = self._sys:cancelable_timeout(tmp_disk_freq, calc_tmp_disk)

		--- System uptime
		local uptime = sysinfo.uptime()
		self._dev:set_input_prop('uptime', "value", uptime)

		--- System memory usage
		local mem = sysinfo.meminfo()
		self._dev:set_input_prop('mem_total', 'value', mem.total)
		self._dev:set_input_prop('mem_used', 'value', mem.used)
		--self._dev:set_input_prop('mem_free', 'value', mem.free)

		--- CPU temperature
		local cpu_temp = sysinfo.cpu_temperature() or nil
		if cpu_temp then
			self._dev:set_input_prop('cpu_temp', "value", cpu_temp)
		else
			self._dev:set_input_prop('cpu_temp', "value", 0, nil, 1)
		end

		-- temp disk usage
		local r, err = disk.df('/tmp')
		if r then
			--self._dev:set_input_prop('disk_tmp_used', 'value', r.used_percent)

			if self._tmp_event_fired then
				if os.time() - self._tmp_event_fired > 3600 then
					self._tmp_event_fired = nil
				end
			end
			-- Check used percent limitation
			if not self._tmp_event_fired and r.used_percent > 98 then
				local info = "/tmp disk is nearly full!!!"
				self._log:error(info)
				self._dev:fire_event(event.LEVEL_ERROR, event.EVENT_SYS, info, r)
				self._tmp_event_fired = os.time()
			end
		end

		--- time check
		--
		self:check_time_diff()
	end
	calc_tmp_disk()

	self._sys:timeout(100, function()
		self._log:debug("Fire system started event")
		local sys_id = self._sys:id()
		self._dev:fire_event(event.LEVEL_INFO, event.EVENT_SYS, "System Started!", {sn=sys_id})
	end)

	self._sys:timeout(100, function()
		self:cfg_crash_check()
	end)

	local check_cloud = nil
	local cloud_freq = self._conf.cloud_freq or (1000 * 3)
	check_cloud = function()
		self:check_cloud_status()
		-- Reset timer
		self._cancel_timers['cloud_led'] = self._sys:cancelable_timeout(cloud_freq, check_cloud)
	end
	check_cloud()
end

function app:check_time_diff()
	--- pause and resume current coroutine
	self._sys:sleep(1)
	--- check the time right after the coroutine resume
	local os_time = os.time()
	local sys_time = self._sys:time()

	if math.abs(os_time - sys_time) < 1.49 then
		return
	end

	self._log:error("Time diff found, FreeIOE is trying to fix this. ", os_time, sys_time)
	self._sys:fix_time()

	--- Fire event
	local data = {
		os_time = os_time,
		time=sys_time,
	}
	self._dev:fire_event(event.LEVEL_FATAL, event.EVENT_SYS, "Time diff found!", data, os_time)
end

function app:check_symlink()
	if self._symlink == nil then
		if lfs.attributes("/etc/rc.d/S22symlink", 'mode') then
			self._symlink = true
		else
			self._symlink = false
		end
	end
	return self._symlink
end

--- For cloud led
function app:check_cloud_status()
	local cloud = snax.queryservice('cloud')
	local cloud_status, cloud_status_last = cloud.req.get_status()

	-- Cloud status info
	if self._cloud_status ~= cloud_status or self._cloud_status_last ~= cloud_status_last then
		self._cloud_status = cloud_status
		self._cloud_status_last = cloud_status_last
		local r, err = sysinfo.update_cloud_status(cloud_status, cloud_status_last)
		if not r then
			self._log:warning("Update cloud status failed", err)
		end
	end

	--- Skip cloud led control if symlink is there
	if self:check_symlink() then
		return
	end

	-- Cloud LED
	if leds.cloud then
		leds.cloud:brightness(cloud_status and 1 or 0)
	end
end

function app:run(tms)
	if not self._start_time then
		self:first_run()
		--self._log:debug("System started!!!")
	end
	--- LTE WAN
	self._lte_wan:run()
	-- self._sbat:run() -- there is no run in sbat module

	self._dev:set_input_prop('starttime', "value", self._start_time)
	self._dev:set_input_prop('version', "value", self._version)
	--self._dev:set_input_prop('version', "git_version", self._git_version)
	self._dev:set_input_prop('skynet_version', "value", self._skynet_version)
	--self._dev:set_input_prop('skynet_version', "git_version", self._skynet_git_version)
	self._dev:set_input_prop('platform', "value", self._plat)
	--- System Firmware Version
	self._dev:set_input_prop('firmware_version', "value", self._firmware_version or "UNKNOWN")

	--- CPU load avg
	local loadavg, err = sysinfo.loadavg()
	if loadavg then
		self._dev:set_input_prop('cpuload', "value", loadavg.lavg_1)
	else
		self._log:debug("Failed to read load avg")
	end

	-- cloud flags
	--
	local enable_data_upload = datacenter.get("CLOUD", "DATA_UPLOAD")
	local data_upload_max_dpp = datacenter.get("CLOUD", "DATA_UPLOAD_MAX_DPP") or 1024
	local data_upload_cov = datacenter.get("CLOUD", "COV") or true
	local data_upload_cov_ttl = datacenter.get("CLOUD", "COV_TTL") or 300
	local data_upload_period = datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD") or (enable_data_upload and 1000 or 60 * 1000)
	local upload_period_limit = datacenter.get("CLOUD", "DATA_UPLOAD_PERIOD_LIMIT") or 10240
	local enable_data_cache = datacenter.get("CLOUD", "DATA_CACHE")
	local data_cache_per_file = datacenter.get("CLOUD", "DATA_CACHE_PER_FILE") or 4096
	local data_cache_limit = datacenter.get("CLOUD", "DATA_CACHE_LIMIT") or 1024
	local data_cache_fire_freq = datacenter.get("CLOUD", "DATA_CACHE_FIRE_FREQ") or 1000
	local enable_stat_upload = datacenter.get("CLOUD", "STAT_UPLOAD")
	local enable_comm_upload = datacenter.get("CLOUD", "COMM_UPLOAD")
	local enable_log_upload = datacenter.get("CLOUD", "LOG_UPLOAD")
	local enable_event_upload = datacenter.get("CLOUD", "EVENT_UPLOAD")
	local enable_beta = ioe.beta()

	self._dev:set_input_prop('data_upload', 'value', enable_data_upload and 1 or 0)
	self._dev:set_input_prop('data_upload_max_dpp', 'value', data_upload_max_dpp)
	self._dev:set_input_prop('data_upload_cov', 'value', data_upload_cov and 1 or 0)
	self._dev:set_input_prop('data_upload_cov_ttl', 'value', data_upload_cov_ttl)
	self._dev:set_input_prop('data_upload_period', 'value', data_upload_period)
	self._dev:set_input_prop('upload_period_limit', 'value', upload_period_limit)

	self._dev:set_input_prop('data_cache', 'value', enable_data_cache and 1 or 0)
	self._dev:set_input_prop('data_cache_per_file', 'value', data_cache_per_file)
	self._dev:set_input_prop('data_cache_limit', 'value', data_cache_limit)
	self._dev:set_input_prop('data_cache_fire_freq', 'value', data_cache_fire_freq)

	self._dev:set_input_prop('stat_upload', 'value', enable_stat_upload  and 1 or 0)
	self._dev:set_input_prop('comm_upload', 'value', enable_comm_upload or 0)
	self._dev:set_input_prop('log_upload', 'value', enable_log_upload or 0)
	self._dev:set_input_prop('event_upload', 'value', enable_event_upload or 99)
	self._dev:set_input_prop('enable_beta', 'value', enable_beta and 1 or 0)
	self._dev:set_input_prop('symlink_service', 'value', self._symlink and 1 or 0)

	-- Application run status
	local appmgr = snax.queryservice('appmgr')
	local applist = appmgr.req.list()
	applist['ioe'] = nil
	for k, v in pairs(applist) do
		if not self._apps_cache[k] then
			local app = datacenter.get("APPS", k) or {name='REMOVED', version=0, sn='REMOVED'}
			self._apps_cache[k] = {
				name = app.name,
				version = app.version,
				sn = app.sn,
				auto = app.auto
			}
			self._dev:add({{name = "app_run_"..k, desc = 'Application status for '..k, vt="int"}})
		end
		local run = 0
		if v.inst and (self._sys:time() - v.last < 180) then
			run = 1
		end
		self._dev:set_input_prop('app_run_'..k, 'value', run)
	end
	for k, v in pairs(self._apps_cache) do
		if not applist[k] then
			self._dev:set_input_prop('app_run_'..k, 'value', 0)
		end
	end

	--- fifteen seconds by default
	return self._conf.run_freq or 1000
end

function app:on_post_fire_event(msg, lvl, tp, data)
	assert(msg and lvl and tp and data)
	data.time = data.time or self._sys:time()
	self._dev:fire_event(lvl, tp, msg, data)
end

function app:ext_upgrade(param)
	local skynet = require 'skynet'
	return skynet.call(".ioe_ext", "lua", "upgrade_ext", '__from_ioe_app'..os.time(), param)
end

function app:ext_auto_clean(param)
	local skynet = require 'skynet'
	return skynet.call(".ioe_ext", "lua", "auto_clean", '__from_ioe_app'..os.time(), {})
end

function app:disable_symlink(param)
	if lfs.attributes("/etc/rc.d/S22symlink", 'mode') then
		os.execute("/etc/init.d/symlink stop")
		os.execute("/etc/init.d/symlink disable")
	end
	if lfs.attributes("/etc/rc.d/S22symlink", 'mode') then
		return false, "Disable Symlink service failed!"
	else
		self._symlink = false
		return true, "Disable Symlink service done!"
	end
end

function app:reboot_device(param)
	local restful = require('http.restful')
	local http_api = restful("127.0.0.1:8808")
	local user = param.user or 'admin'
	local passwd = param.pwd or ''
	local status, body = http_api:post("/user/login", nil, {username=user, password=passwd})
	if status == 200 then
		self._sys:timeout(3000, function()
			os.execute("reboot &")
		end)
		self._log:warning("Reboot is authed with correct password!!!")
		self._log:warning("Device will be reboot after threee seconds")
		return true, "Device will be reboot after three seconds"
	else
		self._log:error("Auth failed", body)
		self._log:error("Invalid pwd provied:", pwd)
		return false, "Invalid pwd provided"
	end
end

return app
