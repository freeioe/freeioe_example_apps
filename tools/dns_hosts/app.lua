local lfs = require 'lfs'
local base = require 'app.base'

local app = base:subclass("FREEIOE.APP.TOOLS.DNS_HOSTS")
app.static.API_VER = 9

local hosts_file = '/tmp/hosts/app_dns.hosts'

function app:on_start()
	return self:write_dns()
end

function app:write_dns()
	local f, err = io.open(hosts_file, 'w+')
	if not f then
		return nil, err
	end

	local conf = self:app_conf()

	for _, dns in pairs(conf.dns) do
		f:write(string.format("%s %s\n", dns.ip, dns.domain))
	end
	f:close()

	return true
end

function app:on_close(reason)
	os.execute('rm -f '..hosts_file)
end

function app:on_run(tms)
	if not lfs.attributes(hosts_file, 'mode') then
		local r, err = self:write_dns()
		if not r then
			log = self:log_api()
			log:error("Failed to write dns hosts file "..hosts_file)
		end
	end

	return 1000 * 5 -- five seconds
end

return app
