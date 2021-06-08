local base = require 'app.base'
local sysinfo = require 'utils.sysinfo'

local app = base:subclass("FREEIOE.APP.TOOLS.LOCAL_PROXY")
app.static.API_VER = 9

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

function app:on_start()
	local tz, err = self:uci_get('system.@system[0].timezone')
	if tz ~= 'CST-8' then
		sysinfo.exec([[uci set system.@system[0].timezone='CST-8']])
		sysinfo.exec([[uci set system.@system[0].zonename='Asia/Shanghai']])
		sysinfo.exec('uci commit')
	end

	sysinfo.exec([[uci set system.ntp=timeserver]])
	sysinfo.exec([[uci set system.ntp.server="ntp.aliyun.com ntp1.aliyun.com ntp2.aliyun.com ntp3.aliyun.com"]])
	sysinfo.exec('uci commit')

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

	sysinfo.exec([[sed -i "s/downloads.openwrt.org/mirrors.tuna.tsinghua.edu.cn\/lede/g" /etc/opkg/distfeeds.conf]])
	sysinfo.exec([[sed '/kooiot/d' /etc/opkg/customfeeds.conf > /etc/opkg.customfeeds.conf.new]])
	sysinfo.exec([[echo src/gz kooiot http://thingscloud.oss-cn-beijing.aliyuncs.com/freeioe-openwrt/19.07-snapshot/arm_cortex-a7_neon-vfpv4/kooiot >> /etc/opkg/customfeeds.conf.new]])
	sysinfo.exec([[mv /etc/opkg/customfeeds.conf.new /etc/opkg/customfeeds.conf]])
	sysinfo.exec([[sed -i "s/option check_signature/# option check_signature/g" /etc/opkg.conf]])

	return true
end

return app
