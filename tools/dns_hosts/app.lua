local lfs = require 'lfs'
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
		log = self:log_api()
		log:error("Failed to write dns hosts file "..hosts_file)
	end

	return 1000 * 5 -- five seconds
end

function app:uci_get(section)
	local info, err = sysinfo.exec('uci show '..section)
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


function app:init_proxy_net()
	local ret, err = self:uci_get('network.lan1scr')
	if not ret then
		self:uci_set('network.lan1scr', 'interface', {
			ifname = 'br-lan',
			proto = 'static',
			ipaddr = '10.200.200.200',
			netmask = '255.255.255.0'
		})
		sysinfo.exec([[uci set network.lan.ifname="eth0 eth1 symbridge"]])
		sysinfo.exec([[uci set network.net1.ifname='br-lan']])
		sysinfo.exec([[uci set network.net1.proto='dhcp']])
		sysinfo.exec([[uci delete network.net1.netmask]])
		sysinfo.exec([[uci delete network.net1.ipaddr]])
		sysinfo.exec('uci commit')
		sysinfo.exec('/etc/init.d/network reload')
	end
end

return app
