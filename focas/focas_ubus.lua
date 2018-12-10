
local lfs = require 'lfs'
local sysinfo = require 'utils.sysinfo'
local class = require 'middleclass'

local focas_ubus = class('FANUC_FOCAS_UBUS_S')

---
function focas_ubus:initialize(app_dir)
	assert(app_dir)
	self._app_dir = app_dir

	local arch = sysinfo.cpu_arch_short()
	assert(arch == 'arm', 'Currently only arm is supported! '..arch)
	self._arch = arch
end

function focas_ubus:prepare()
	assert(self._arch)
	if self._arch == 'arm' then
		local sysroot = '/usr/focas_armhf_rootfs/sysroot'
		if lfs.attributes(sysroot .. '/bin', 'mode') ~= 'directory' then
			return nil, "Focas armhf rootfs is not installed"
		end
		return self:prepare_armhf_rootfs(sysroot)
	end
	return nil, string.format("CPU archture: %s is not supported.", self._arch)
end

function focas_ubus:prepare_armhf_rootfs(sysroot)
	local cp_chroot = string.format('cp "%s/bin/arm/arch-chroot" %s/bin/arch-chroot', self._app_dir, sysroot)
	local cp_focas_ubus = string.format('cp "%s/bin/arm/focas_ubus" %s/bin/focas_ubus', self._app_dir, sysroot)
	os.execute(cp_chroot)
	os.execute(cp_focas_ubu)

	local init_d_script = '/etc/init.d/focas_ubus'
	if lfs.attributes(init_d_script, 'mode') then
		os.execute(init_d_script..' stop')
	else
		os.execute(string.format('ln -s %s/init.d/arm/focas_ubus '..init_d_script, self._app_dir))
	end
end

function focas_ubus:start()
	local init_d_script = '/etc/init.d/focas_ubus'
	os.execute(init_d_script..' start')
end

function focas_ubus:stop()
	local init_d_script = '/etc/init.d/focas_ubus'
	os.execute(init_d_script..' stop')
end

function focas_ubus:remove()
	self:stop()
	local init_d_script = '/etc/init.d/focas_ubus'
	os.execute('rm -f '..init_d_script)
end

function focas_ubus:__gc()
	self:remove()
end

return focas_ubus
