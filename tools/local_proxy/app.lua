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
	if not info then
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
end

function app:uci_commit()
	sysinfo.exec('uci commit')
end

function app:uci_add(section)
	sysinfo.exec('uci add '..section)
end

function app:on_start()
	local ret, err = self:uci_show('network.lan1proxy')
	if not ret then
		self:uci_set('network.lan1proxy', 'interface')
		self:uci_set('network.lan1proxy.ifname', 'br-lan')
		self:uci_set('network.lan1proxy.proto', 'static')
		self:uci_set('network.lan1proxy.ipaddr', '200.200.200.100')
		self:uci_set('network.lan1proxy.netmask', '255.255.255.0')
		self:uci_commit()
	end

	local i = 0
	while true do
		local zn = string.format('firewall.@zone[%d]', i)
		local r, err = self:uci_show(zn)
		if not r then
			self:uci_add('firewall.zone')
			self:uci_set('firewall.@zone[-1].input', 'ACCEPT')
			self:uci_set('firewall.@zone[-1].output', 'ACCEPT')
			self:uci_set('firewall.@zone[-1].forward', 'ACCEPT')
			self:uci_set('firewall.@zone[-1].network', 'lan1proxy')
			self:uci_set('firewall.@zone[-1].subnet', '200.200.200.100/24')
			self:uci_commit()
			break
		end
		if r.name == 'lan1proxy' then
			break
		end
		i = i + 1
	end

	i = 0
	while true do
		local zn = string.format('firewall.@redirect[%d]', i)
		local r, err = self:uci_show(zn)
		if not r then
			self:uci_add('firewall.redirect')
			self:uci_set('firewall.@redirect[-1].target', 'DNAT')
			self:uci_set('firewall.@redirect[-1].name', 'lan1proxy')
			self:uci_set('firewall.@redirect[-1].src', 'lan1proxy')
			self:uci_set('firewall.@redirect[-1].src_dport', '80')
			self:uci_set('firewall.@redirect[-1].dest', 'lan')
			self:uci_set('firewall.@redirect[-1].dest_ip', '200.200.200.100')
			self:uci_set('firewall.@redirect[-1].dest_port', '8181')
			self:uci_commit()
			break
		end
		if r.name == 'lan1proxy' then
			break
		end
		i = i + 1
	end

	i = 0
	while true do
		local zn = string.format('firewall.@redirect[%d]', i)
		local r, err = self:uci_show(zn)
		if not r then
			self:uci_add('firewall.redirect')
			self:uci_set('firewall.@redirect[-1].target', 'DNAT')
			self:uci_set('firewall.@redirect[-1].name', 'lan1mqtt')
			self:uci_set('firewall.@redirect[-1].src', 'lan1proxy')
			self:uci_set('firewall.@redirect[-1].src_dport', '1883')
			self:uci_set('firewall.@redirect[-1].dest', 'lan')
			self:uci_set('firewall.@redirect[-1].dest_ip', '200.200.200.100')
			self:uci_set('firewall.@redirect[-1].dest_port', '3883')
			self:uci_commit()
			break
		end
		if r.name == 'lan1mqtt' then
			break
		end
		i = i + 1
	end

	local ret, err = self:uci_show('socat.lan1proxy')
	if not ret then
		self:uci_set('socat.lan1proxy', 'socat')
		self:uci_set('socat.lan1proxy.enable', '1')
		self:uci_set('socat.lan1proxy.SocatOptions', '-d -d TCP-LISTEN:8181,fork,bind=200.200.200.100 TCP4:ioe.thingsroot.com:80')
		self:uci_commit()
	end

	local ret, err = self:uci_show('socat.lan1mqtt')
	if not ret then
		self:uci_set('socat.lan1mqtt', 'socat')
		self:uci_set('socat.lan1mqtt.enable', '1')
		self:uci_set('socat.lan1mqtt.SocatOptions', '-d -d TCP-LISTEN:3883,fork,bind=200.200.200.100 TCP4:ioe.thingsroot.com:1883')
		self:uci_commit()
	end

	return true
end

function app:on_close(reason)
	--print(self._name, reason)
end

return app
