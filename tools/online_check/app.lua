local base_app = require 'app.base'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.ONLINE_CHECK")
my_app.static.API_VER = 15

function my_app:on_init()
	local conf = self:app_conf()
	self._host = conf.host or 'ioe.thingsroot.com' -- host address
end

function my_app:on_start()
	return ioe.set_online_check_host(self._host)
end

--- 应用退出函数
function my_app:on_close(reason)
	ioe.set_online_check_host(nil)
end

--- 返回应用类
return my_app

