local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson'

local app = class("FREEIOE_APP_NETWORK_CLASS")
app.static.API_VER = 2

function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	self._api = self._sys:data_api()
	self._log = sys:logger()
end

local function parse_value(value)
	local ret = {}
	for val in string.gmatch(value, "'([^']+)'") do
		ret[#ret + 1] = val
	end
	if #ret == 1 then
		return ret[1]
	end
	return ret
end

function app:uci_show(section)
	local info, err = sysinfo.exec('uci show '..section)
	if not info or string.len(info) == 0 then
		return nil, err
	end

	local ret = {}
	local r_section = string.gsub(section, '%.', '%%.')
	for line in string.gmatch(info, '(.-)\n') do
		local option, value = string.match(line, '^'..r_section..'%.(.+)=(.+)$')
		--self._log:debug('UCI.SHOW', section, option, value)
		if option and value then
			ret[option] = parse_value(value)
		end
	end

	return ret 
end

function app:uci_set(section, value)
	for k,v in pairs(value) do
		if type(v) ~= 'table' then
			sysinfo.exec('uci set '..section..'.'..k..'='..tostring(v))
		else
			sysinfo.exec('uci add_list '..section..'.'..k..'='..tostring(v))
		end
	end
	sysinfo.exec('uci commit')
end

function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value, timestamp, priv)
			self._log:trace('on_output', app, sn, output, prop, value)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end
			if output == 'ntp' or output == 'network_lan' then
				if type(value) ~= 'table' then
					local conf, err = cjson.decode(value)
					if not conf then
						self._log:error('Incorrect configuration value found, value:', value)
						return false, "Incorrect configuration value found"
					end
					value = conf
				end
				self._log:notice('Try to change NTP configuration, value:', cjson.encode(value))

				self._sys:post('change_apply', output, value)

				return true
			end
			return true, "done"
		end,
		on_command = function(app, sn, command, param, priv)
			if sn ~= self._dev_sn then
				self._log:error('device sn incorrect', sn)
				return false, 'device sn incorrect'
			end

			-- command: refresh 
			local commands = { refresh = 1, ntp_reload = 1, network_reload = 1, reload = 1}
			local f = commands[command]
			if f then
				self._sys:post('command', command)
				return true
			else
				self._log:error('device command not exists!', command)
				return false, 'device command not exists!'
			end
		end,
		on_ctrl = function(app, command, param, priv)
			self._log:trace('on_ctrl', app, command, param, priv)
		end,
	})

	local dev_sn = self._sys:id()..'.'..self._name
	local inputs = {
		{
			name = "ntp",
			desc = "NTP current settings",
			vt = "string",
		},
		{
			name = "network_lan",
			desc = "NETWORK LAN current settings",
			vt = "string",
		},
	}
	local outputs = {
		{
			name = "ntp",
			desc = "ntp configuration (json)",
			vt = "string",
		},
		{
			name = "network_lan",
			desc = "network lan configuration (json)",
			vt = "string",
		},
	}
	local cmds = {
		{
			name = "refresh",
			desc = "Force uploading NTP/NETWORK information",
		},
		{
			name = "ntp_reload",
			desc = "Force NTP service reload configurations",
		},
		{
			name = "network_reload",
			desc = "Force NETWORK service reload configurations",
		},
	}

	self._dev_sn = dev_sn 
	local meta = self._api:default_meta()
	meta.name = "UCI Network"
	meta.description = "UCI Network Status"
	meta.series = "X"
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs, cmds)

	return true
end

function app:close(reason)
	--print(self._name, reason)
end

function app:read_ntp(emergency_fire)
	local ntp, err = self:uci_show('system.ntp')
	if ntp then
		if not emergency_fire then
			self._dev:set_input_prop('ntp', 'value', cjson.encode(ntp))
		else
			self._dev:set_input_prop_emergency('ntp', 'value', cjson.encode(ntp))
		end
	else
		if not emergency_fire then
			self._dev:set_input_prop('ntp', 'value', '', self._sys:time(), 1)
		else
			self._dev:set_input_prop_emergency('ntp', 'value', '', self._sys:time(), 1)
		end
	end
end

function app:read_network_lan(emergency_fire)
	local network, err = self:uci_show('network.lan')
	if network then
		if not emergency_fire then
			self._dev:set_input_prop('network_lan', 'value', cjson.encode(network))
		else
			self._dev:set_input_prop_emergency('network_lan', 'value', cjson.encode(network))
		end
	else
		if not emergency_fire then
			self._dev:set_input_prop('network_lan', 'value', '', self._sys:time(), 1)
		else
			self._dev:set_input_prop_emergency('network_lan', 'value', '', self._sys:time(), 1)
		end
	end
end

function app:run(tms)
	self:read_ntp()
	self:read_network_lan()
	return 1000 * 5 -- five seconds
end

function app:on_post_change_apply(output, value)
	if output == 'ntp' then
		self:uci_set('system.ntp', value)
		self._sys:sleep(500)
		self:read_ntp(true)
	end
	if output == 'network_lan' then
		self:uci_set('network.lan', value)
		self._sys:sleep(500)
		self:read_network_lan(true)
	end
	return true
end


function app:on_post_command(action, force)
	if action == 'refresh' then
		self:read_ntp(true)
		self:read_network_lan(true)
	end
	if action == 'ntp_reload' then
		local info, err = sysinfo.exec('/ect/init.d/sysntpd reload')
		log.info('ntp_reload result', info, err)
		self:read_ntp(true)
	end
	if action == 'network_reload' then
		local info, err = sysinfo.exec('/ect/init.d/network reload')
		log.info('network_reload result', info, err)
		self:read_network_lan(true)
	end
	return true
end

return app
