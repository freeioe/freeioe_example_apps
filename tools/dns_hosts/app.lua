local base = require 'app.base'
local sysinfo = require 'utils.sysinfo'

local app = base:subclass("FREEIOE.APP.TOOLS.DNS_HOSTS")
app.static.API_VER = 9

local hosts_file = '/etc/hosts'

function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()

	sys:sleep(3000)

	if conf.local_proxy then
		self:init_proxy_net()
		local found = false
		for _, dns in pairs(conf.dns) do
			if dns.domain == 'ioe.thingsroot.com' or dns.domain == 'thingsroot.com' then
				found = true
			end
		end
		if not found then
			table.insert(conf.dns, {
				domain = 'ioe.thingsroot.com',
				ip = '10.200.200.100'
			})
		end
	end

	self:clean_dns()
	return self:write_dns()
end

function app:on_close(reason)
	return self:clean_dns()
end

function app:write_dns()
	local f, err = io.open(hosts_file, 'r')
	if not f then
		return nil, err
	end

	local exist_hosts = {}
	for line in f:lines() do
		--print(line)
		local ip, domains = string.match(line, '^([^%s#]+)%s+(.+)$')
		if ip and domains then
			local comment_index = string.find(domains, '#', 1, true)
			if comment_index then
				domains = string.sub(domains, 1, comment_index - 1)
			end
			--print(ip, domains)
			for domain in string.gmatch(domains, '([^%s#]+)') do
				--print(domain, ip)
				exist_hosts[domain] = ip
			end
		end
	end

	f:close()

	local conf = self:app_conf()

	for _, dns in pairs(conf.dns) do
		if not exist_hosts[dns.domain] then
			local s = string.format('%s %s #FREEIOE', dns.ip, dns.domain)
			--print('echo "'..s..'" >> '..hosts_file)
			os.execute('echo "'..s..'" >> '..hosts_file)
		else
			if exist_hosts[dns.domain] ~= dns.ip then
				return false, 'Domain '..dns.domain..' has different host value'..exist_hosts[dns.domain]
			end
		end
	end

	return true
end

function app:clean_dns()
	os.execute([[sed '/FREEIOE/d' /etc/hosts > /etc/hosts.new]])
	os.execute([[mv /etc/hosts.new /etc/hosts]])
	os.execute('sync')
end

function app:on_run(tms)
	local r, err = self:write_dns()
	if not r then
		self._log:error("Failed to write dns hosts file "..hosts_file)
	end

	return 1000 * 5 -- five seconds
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
			for _, vv in ipairs(v) do
				sysinfo.exec('uci add_list '..section..'.'..k..'=\''..tostring(vv)..'\'')
			end
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
			for _, vv in ipairs(v) do
				sysinfo.exec('uci add_list '..key..'.'..k..'=\''..tostring(vv)..'\'')
			end
		end
	end
	sysinfo.exec('uci commit')
end


function app:init_proxy_net()
	local ret, err = self:uci_get('network.lan1scr')
	if not ret then
		local lan_dev = self:uci_get('network.lan.device')
		if lan_dev and string.find(lan_dev, 'br-lan', 1, true) then
			self:init_proxy_net_new()
		else
			self:init_proxy_net_old()
		end
	end
end

function app:init_proxy_net_old()
	self:uci_set('network.lan1scr', 'interface', {
		ifname = 'br-lan',
		proto = 'static',
		ipaddr = '10.200.200.200',
		netmask = '255.255.255.0'
	})
	sysinfo.exec([[uci set network.lan.ifname="eth0 eth1 symbridge"]])
	sysinfo.exec('uci commit')
	sysinfo.exec('/etc/init.d/network reload')
end

function app:init_proxy_net_new()
	local eths = {}
	for i = 0, 10 do
		local name = self:uci_get(string.format('network.@device[%d].name', i))
		if name == 'br-lan' then
			local ports = self:uci_get(string.format('network.@device[%d].ports', i))
			if string.sub(ports, -4) == 'eth0' then
				eths = {'eth0', 'eth1'}
				break
			end
			if string.match(ports, 'eth0%s+') then
				local eth1_found = false
				for dev in string.gmatch(ports, "%w+") do
					table.insert(eths, dev)
					if dev == 'eth1' then
						eth1_found = true
					end
				end
				if not eth1_found then
					table.insert(eths, 'eth1')
				end
				break
			end
			--- insert all device ports into eths
			for dev in string.gmatch(ports, "%w+") do
				table.insert(eths, dev)
			end
		end
	end

	self:uci_add('network', 'device', {
		name = 'br-lan1scr',
		['type'] = 'bridge',
		ports = eths
	})

	self:uci_set('network.lan1scr', 'interface', {
		device = 'br-lan1scr',
		proto = 'static',
		ipaddr = '10.200.200.200',
		netmask = '255.255.255.0'
	})

	sysinfo.exec('uci commit')
	sysinfo.exec('/etc/init.d/network reload')
end

return app
