local cURL = require 'lcurl'

return function (ip)
	local _M = {
		_host = ip
	}

	--[[
	_M._s = cURL.share()
		:setopt_share(cURL.LOCK_DATA_COOKIE      )
		]]--

	-- create first easy handle to fetch cookie
	_M._c1 = cURL.easy()
		--:setopt_share(_M._s)
		:setopt_timeout(1)
		:setopt_url(string.format("http://%s/", ip))
		:setopt_cookiefile(string.format("/tmp/cookie_%s.txt", ip))
		:setopt_cookiejar(string.format("/tmp/cookie_%s.txt", ip))

	-- create second easy handle to let cookie inited
	_M._c2 = cURL.easy()
		--:setopt_share(_M._s)
		:setopt_timeout(1)
		:setopt_url(string.format("http://%s/init.boa?view_mode=standard", ip))
		:setopt_cookiefile(string.format("/tmp/cookie_%s.txt", ip))
		:setopt_cookiejar(string.format("/tmp/cookie_%s.txt", ip))

	-- create second easy handle to do reboot
	--local post_data = cURL.form()
	--	:add_content("reboot", "Reboot System")

	_M._reboot = cURL.easy()
		--:setopt_share(_M._s)
		:setopt_timeout(1)
		:setopt_url(string.format("http://%s/system/reboot.boa", ip))
		:setopt_cookiefile(string.format("/tmp/cookie_%s.txt", ip))
		:setopt_cookiejar(string.format("/tmp/cookie_%s.txt", ip))
		:setopt_postfields('reboot=Reboot+System')

	function _M.reboot()
		local ok, err = _M._c1:perform()
		if not ok then
			return nil, err
		else
			--return nil, string.format("code: "..easy:getinfo_effective_url().." url: "..easy:getinfo_response_code())
		end
		ok, err = _M._c2:perform()
		if not ok then
			return nil, err
		end
		return _M._reboot:perform()
	end

	return _M
end
