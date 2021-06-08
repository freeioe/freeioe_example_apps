local base = require 'app.base'
local sysinfo = require 'utils.sysinfo'

local app = base:subclass("FREEIOE.APP.TOOLS.LOCAL_PROXY")
app.static.API_VER = 9

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

function app:uci_get(section)
	local info, err = sysinfo.exec('uci get '..section)

	if info and  string.sub(info, -1) == '\n' then
		info = string.sub(info, 1, -2)
	end

	if not info or string.len(info) == 0 then
		return nil, err
	end

	return info
end

function app:uci_set(section, name, value)
	sysinfo.exec('uci set '..section..'='..name)
	for k,v in pairs(value) do
		if type(v) ~= 'table' then
			sysinfo.exec('uci set '..section..'.'..k..'=\''..tostring(v)..'\'')
		else
			sysinfo.exec('uci add_list '..section..'.'..k..'=\''..tostring(v)..'\'')
		end
	end
	sysinfo.exec('uci commit')
end

function app:uci_add(config, section, value)
	sysinfo.exec('uci add '..config..' '..section)
	local key = string.format('%s.@%s[-1]', config, section)
	for k,v in pairs(value) do
		if type(v) ~= 'table' then
			sysinfo.exec('uci set '..key..'.'..k..'=\''..tostring(v)..'\'')
		else
			sysinfo.exec('uci add_list '..key..'.'..k..'=\''..tostring(v)..'\'')
		end
	end
	sysinfo.exec('uci commit')
end

function app:on_start()
	local ret, err = self:uci_get('network.lan1proxy')
	if not ret then
		self:uci_set('network.lan1proxy', 'interface', {
			ifname = 'br-lan',
			proto = 'static',
			ipaddr = '10.200.200.100',
			netmask = '255.255.255.0'
		})
		sysinfo.exec('/etc/init.d/network reload')
	end

	local firewall_changes = false
	local i = 0
	while true do
		local zn = string.format('firewall.@zone[%d].name', i)
		local r, err = self:uci_get(zn)
		if not r then
			self._log:info("Creating lan1proxy Firewall.Zone")
			self:uci_add('firewall', 'zone', {
				name = 'lan1proxy',
				input = 'ACCEPT',
				output = 'ACCEPT',
				forward = 'ACCEPT',
				network = 'lan1proxy',
				subnet = '200.200.200.100/24'
			})
			firewall_changes = true
			break
		end
		if r == 'lan1proxy' then
			break
		end
		i = i + 1
	end

	i = 0
	while true do
		local zn = string.format('firewall.@redirect[%d].name', i)
		local r, err = self:uci_get(zn)
		if not r then
			self:uci_add('firewall', 'redirect', {
				target = 'DNAT',
				name = 'lan1proxy',
				proto = 'tcp',
				src = 'lan1proxy',
				src_dport = '80',
				dest = 'lan',
				dest_ip = '200.200.200.100',
				dest_port = '8181'
			})
			firewall_changes = true
			break
		end
		if r == 'lan1proxy' then
			break
		end
		i = i + 1
	end

	i = 0
	while true do
		local zn = string.format('firewall.@redirect[%d].name', i)
		local r, err = self:uci_get(zn)
		if not r then
			self._log:info("Creating lan1proxy Firewall.Redirect")
			self:uci_add('firewall', 'redirect', {
				target = 'DNAT',
				name = 'lan1mqtt',
				proto = 'tcp',
				src = 'lan1proxy',
				src_dport = '1883',
				dest = 'lan',
				dest_ip = '200.200.200.100',
				dest_port = '3883'
			})
			firewall_changes = true
			break
		end
		if r == 'lan1mqtt' then
			break
		end
		i = i + 1
	end
	if firewall_changes then
		sysinfo.exec('/etc/init.d/firewall reload')
	end

	local socat_changes = false
	local ret, err = self:uci_get('socat.lan1proxy')
	if not ret then
		self._log:info("Creating lan1proxy in Socat CFG")
		self:uci_set('socat.lan1proxy', 'socat', {
			enable = '1',
			SocatOptions = '-d -d TCP-LISTEN:8181,fork,bind=200.200.200.100 TCP4:ioe.thingsroot.com:80'
		})
		socat_changes = true
	end

	local ret, err = self:uci_get('socat.lan1mqtt')
	if not ret then
		self._log:info("Creating lan1mqtt in Socat CFG")
		self:uci_set('socat.lan1mqtt', 'socat', {
			enable = '1',
			SocatOptions = '-d -d TCP-LISTEN:3883,fork,bind=200.200.200.100 TCP4:ioe.thingsroot.com:1883'
		})
		socat_changes = true
	end
	if socat_changes then
		sysinfo.exec('/etc/init.d/socat reload')
	end

	return true
end

return app
