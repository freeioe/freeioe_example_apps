local lfs = require 'lfs'
local base = require 'app.base'

local app = base:subclass("FREEIOE.APP.TOOLS.DNS_HOSTS")
app.static.API_VER = 9

local hosts_file = '/etc/hosts'

function app:on_start()
	return self:write_dns()
end

function app:write_dns()
	local f, err = io.open(hosts_file, 'w+')
	if not f then
		return nil, err
	end
	local str = f:read('*a')
	f:close()

	local exist_hosts = {}
	for ip, domains in  string.gmatch(str, '([^%s]+) (%w+)') do
		exist_hosts[domains] = ip
		print(domains, ip)
	end

	local conf = self:app_conf()

	for _, dns in pairs(conf.dns) do
		if not exist_hosts[dns.domain] then
			local s = string.format('%s %s #FREEIOE', dns.ip, dns.domain)
			os.execute('echo "'..s..'" >> '..hosts_file)
		else
			if exist_hosts[dns.domain] ~= dns.ip then
				return false, 'Domain '..dns.domain..' has different host value'..exists_hosts[dns.domain]
			end
		end
	end

	return true
end

function app:on_close(reason)
	os.execute([[sed '/FREEIOE/d' /etc/hosts >> /etc/hosts]])
end

function app:on_run(tms)
	local r, err = self:write_dns()
	if not r then
		log = self:log_api()
		log:error("Failed to write dns hosts file "..hosts_file)
	end

	return 1000 * 5 -- five seconds
end

return app
