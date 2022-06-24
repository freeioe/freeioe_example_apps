local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inifile = require 'inifile'
local cjson = require 'cjson'
local app_base = require 'app.base'

local app = app_base:subclass("FREEIOE_APP_FREETUN_CLASS")
app.static.API_VER = 10

local function get_default_conf(sys, conf, file_name)
	local root = {}
	local id = sys:id()

	local server_addr = conf.server_addr or 'tun.iiot8.com:8765'
	local auth_key = conf.auth_key or 'FreeTUN'
	local log_level = conf.log_level or 'info'
	local log_file = conf.log_file or 'freetun.log'

	local common = {}
	table.insert(common, 'client_id: ' .. id)
	table.insert(common, 'server: ' .. server_addr)
	table.insert(common, 'auth_key: ' .. auth_key)

	local log = {}
	table.insert(log, 'dir: /var')
	table.insert(log, 'level: ' .. log_level)
	table.insert(log, 'filename: ' .. log_file)

	table.insert(root, 'common: ')
	table.insert(root, table.concat(common, '\n\t'))
	table.insert(root, 'log: ')
	table.insert(root, table.concat(log, '\n\t'))

	local str = table.concat(root, '\n')

	local f, err = io.open(file_name, '+w')
	if not f then
		return nil, err
	end
	f:write(str)
	f:close()
	return true
end


function app:on_init()
	local sys = self:sys_api()
	self._yaml_file = sys:app_dir()..".config.yaml"

	local r, err = save_yaml_conf(sys, self:app_conf(), self._yaml_file)

	local freetun_bin = sys:app_dir().."/bin/freetun-client"
	self._service = services:new(self._name, freetun_bin, {'-c', self._yaml_file})
end

function app:on_start()	
	local sys = self:sys_api()
	local api = self:data_api()
	local dev_sn = sys:id()..'.'..self.app_name()

	local inputs = {
		{
			name = "starttime",
			desc = "start time in UTC",
			vt = "int",
		},
		{
			name = "uptime",
			desc = "process uptime",
			vt = "int",
		},
		{
			name = "run",
			desc = "process running status",
			vt = "int",
		},
		{
			name = "br_lan_ipv4",
			desc = "IP Address of br_lan interface",
			vt = "string",
		},
		{
			name = "br_lan_ipv6",
			desc = "IPv6 Address of br_lan interface",
			vt = "string",
		},
	}
	local cmds = {
		{
			name = "start",
			desc = "start freetun process",
		},
		{
			name = "stop",
			desc = "stop freetun process",
		},
		{
			name = "restart",
			desc = "restart freetun process",
		},
	}

	self._dev_sn = dev_sn 
	local meta = api:default_meta()
	meta.name = "FreeTUN Client"
	meta.description = "FreeTUN Client"
	meta.series = "X"
	self._dev = api:add_device(dev_sn, meta, inputs, nil, cmds)

	local r, err = self._service:create()
	if not r then
		self._log:error("Service create failure. Error:", err)
		return nil, "Service create failure. Error: "..err
	end

	return true
end

function app:on_command(app, sn, command, param, priv)
	-- command: start, stop, restart
	local commands = { start = 1, stop = 1, restart = 1 }
	local f = commands[command]
	if f then
		self._sys:post('service_ctrl', command)
		return true
	else
		self._log:error('device command not exists!', command)
		return false, 'device command not exists!'
	end
end

function app:close(reason)
	self:on_post_service_ctrl('stop', true)
	self._service:remove()
end

function app:on_freetun_start()
	if self._start_time then
		self:on_freetun_stop()
	end

	self._start_time = self._sys:time()
	self._uptime_start = self._sys:now()

	self:set_run_inputs()

	local calc_uptime = nil
	calc_uptime = function()
		self._cancel_uptime_timer = self._sys:cancelable_timeout(1000 * 60, calc_uptime)
		self._dev:set_input_prop('uptime', 'value', self._sys:now() - self._uptime_start)
	end
	calc_uptime()
end

function app:on_freetun_stop()
	if self._cancel_uptime_timer then
		self._cancel_uptime_timer()
		self._cancel_uptime_timer = nil
		self._start_time = nil
		self._uptime_start = nil
	end
	self._service:cleanup()
end

function app:set_run_inputs()
	--- br-lan network status
	local info = sysinfo.network_if('br-lan')

	if info and info.ipv4 then
		self._br_lan_ipv4 = info.ipv4
		self._dev:set_input_prop('br_lan_ipv4', 'value', info.ipv4)
	end
	if info and info.ipv6 then
		self._br_lan_ipv6 = info.ipv6
		self._dev:set_input_prop('br_lan_ipv6', 'value', info.ipv6)
	end

	--- Starttime
	self._dev:set_input_prop('starttime', 'value', self._start_time or 0)
end

function app:run(tms)
	if not self._first_start then
		self:on_post_service_ctrl('stop', true)

		if self._conf.auto_start then
			self:on_post_service_ctrl('start')
		end
		self._first_start = true
	end

	local status = self._service:status()
	self._dev:set_input_prop('run', 'value', status and 1 or 0)

	self:set_run_inputs()

	return 1000 * 5 -- five seconds
end

function app:on_post_service_ctrl(action, force)
	if self._in_service_ctrl then
		self._log:warning("an operation is blocking, please wait..")
		return nil, 'blocking'
	end
	self._in_service_ctrl = true
	if action == 'restart' then
		self._log:debug("restart service")

		--- Try to stop service(freetun)
		if self._start_time then
			local r, err = self._service:stop()
			if not r then
				self._log:warning("stop service failed. ", err)
			end
			self:on_freetun_stop()
		end

		--- Try to start service(freetun)
		local r, err = self._service:start()
		if r then
			self:on_freetun_start()
		else
			self._log:error("start service failed. ", err)
			return nil, err
		end
	end
	if action == 'stop' then
		--- check whether it start or not
		if not force and not self._start_time then
			self._log:error("service already stoped!")
			self._in_service_ctrl = nil
			return nil, err
		end

		self._log:debug("Stop service")
		local r, err = self._service:stop()
		if not r and not force then
			self._log:warning("Stop service failed. ", err)
		end
		--- stop cleanup always
		self:on_freetun_stop()
	end
	if action == 'start' then
		--- check whether it start or not
		if not force and self._start_time then
			self._log:error("service already started!")
			self._in_service_ctrl = nil
			return nil, err
		end

		self._log:debug("Start service")
		local r, err = self._service:start()
		if r then
			self:on_freetun_start()
		else
			self._log:error("start service failed. ", err)
			return nil, err
		end
	end
	self._in_service_ctrl = nil
	return true, 'done'
end

return app
