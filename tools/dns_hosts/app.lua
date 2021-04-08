local lfs = require 'lfs'
local base = require 'app.base'

local app = base:subclass("FREEIOE.APP.TOOLS.DNS_HOSTS")
app.static.API_VER = 9

local hosts_file = '/etc/hosts'

function app:on_start()
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
				return false, 'Domain '..dns.domain..' has different host value'..exists_hosts[dns.domain]
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

return app
