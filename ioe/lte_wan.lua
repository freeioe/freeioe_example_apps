local class = require 'middleclass'
local sum = require 'summation'
local netinfo = require 'netinfo'

local lte_wan = class("FREEIOE_WAN_SUM_CLASS")

function lte_wan:initialize(app, sys)
	self._app = app
	self._sys = sys
	self._3ginfo = false
	self._gcom = false
	self._gcom_freq = app._conf.gcom_freq

	self._wan_sum = sum:new({
		file = true,
		save_span = 60 * 5, -- five minutes
		key = 'wan',
		span = 'month',
		path = '/root', -- Q102's data/cache partition
	})
end

function lte_wan:inputs()
	local sys_id = self._sys:hw_id()
	local id = self._sys:id()
	if string.sub(sys_id, 1, 8) == '2-30002-' or string.sub(sys_id, 1, 8) == '2-30102-' then
		self._gcom = true
		return {
			{
				name = 'ccid',
				desc = 'SIM card ID',
				vt = "string",
			},
			{
				name = 'csq',
				desc = 'GPRS/LTE sginal strength',
				vt = "int",
			},
			{
				name = 'cpsi',
				desc = 'GPRS/LTE work mode',
				vt = "string",
			},
			{
				name = 'wan_s',
				desc = 'GPRS/LET send this month',
				vt = 'int',
				unit = 'KB'
			},
			{
				name = 'wan_r',
				desc = 'GPRS/LET receive this month',
				vt = 'int',
				unit = 'KB'
			},
		}
	end
	if lfs.attributes("/tmp/sysinfo/3ginfo", "mode") == 'file' then
		self._3ginfo = true
		-- TODO: 3Ginfo export
		return {
			{
				name = 'ccid',
				desc = 'SIM card ID',
				vt = "string",
			},
			{
				name = 'csq',
				desc = 'GPRS/LTE sginal strength',
				vt = "int",
			},
			{
				name = 'cpsi',
				desc = 'GPRS/LTE work mode',
				vt = "string",
			},
			{
				name = 'wan_s',
				desc = 'GPRS/LET send this month',
				vt = 'int',
				unit = 'KB'
			},
			{
				name = 'wan_r',
				desc = 'GPRS/LET receive this month',
				vt = 'int',
				unit = 'KB'
			},
		}
	end

	return {}
end

--- For wan statistics
function lte_wan:read_wan_sr()
	if self._gcom then
		local info, err = netinfo.proc_net_dev('3g-wan')
		if info and #info == 16 then
			self._wan_sum:set('recv', math.floor(info[1] / 1000))
			self._wan_sum:set('send', math.floor(info[9] / 1000))
		end
	end
	if self._3ginfo then
	end
end


function lte_wan:start()
	if self._gcom then
		self:read_wan_sr()
		local calc_gcom = nil
		local gcom_freq = self._gcom_freq or (1000 * 60)
		calc_gcom = function()
			-- Reset timer
			self._cancel_timers['gcom'] = self._sys:cancelable_timeout(gcom_freq, calc_gcom)

			local ccid, err = gcom.get_ccid()
			if ccid then
				self._dev:set_input_prop('ccid', "value", ccid)
			end
			local csq, err = gcom.get_csq()
			if csq then
				self._dev:set_input_prop('csq', "value", csq)
				self:lte_strength(csq)
			end
			local cpsi, err = gcom.get_cpsi()
			if cpsi then
				self._dev:set_input_prop('cpsi', "value", cpsi)
			end

			self._dev:set_input_prop('wan_r', "value", self._wan_sum:get('recv'))
			self._dev:set_input_prop('wan_s', "value", self._wan_sum:get('send'))
			--- GCOM core dump file removal hacks
			os.execute("rm -rf /tmp/gcom*.core")
		end
		--- GCOM takes too much time which may blocks the first run too long
		self._sys:timeout(1000, function() calc_gcom() end)
	end
	if self._3ginfo then
	end
end

function lte_wan:run()
	self:read_wan_sr()
end

return lte_wan
