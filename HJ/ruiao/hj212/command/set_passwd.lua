local base = require 'hj212.command.base'
local types = require 'hj212.types'

local cmd = base:subclass('hj212.command.set_passwd')

function cmd:initialize(passwd)
	local passwd = passwd or '123456'
	base.initialize(self, types.COMMAND.SET_PASSWD, {
		NewPW = passwd
	})
end

return cmd
