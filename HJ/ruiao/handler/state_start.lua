local base = require 'hj212.server.handler.base'
local types = require 'hj212.types'

local handler = base:subclass('hj212.server.handler.rdata_start')

local function map_state_alarm(state, alarm)
	if alarm ~= nil then
		return types.RS.Alarm
	end

	if state == '0001' then
		return types.RS.Normal
	end
	if state == '0002' then
		return types.RS.Maintain
	end
	if state == '0004' then
		return types.RS.Calibration
	end
	if state == '0008' then
		return types.RS.Clean
	end
	if state == '0010' then
		return types.RS.Calibration
	end
	if state == '0020' then
		return types.RS.Calibration
	end
	if state == '0040' then
		return types.RS.Calibration
	end
	return types.RS.Stoped
end

function map_alarm(alarm)
	return tonumber('0x'..alarm)
end

function handler:process(request)
	local params = request:params()
	if not params then
		return nil, "Params missing"
	end
	local data_time = params:get('DataTime')
	if not data_time then
		return nil, "DataTime missing"
	end

	if params:has_states() then
		local devs = params:devices()

		if devs[data_time] == nil then
			return nil, "Devices not found"
		end

		for _, t in pairs(devices[data_time]) do
			local rs = t:get('RS')
			if rs then
				self._client:set_meter_rs(rs)
			else
				--- Hacked in another way please!!!!
				local state = t:get('InstrState') or '0001'
				local alarm = t:get('Ala')
				local rs = map_state_alarm(state, alarm)
				self._client:set_meter_rs(rs)
			end
		end
	end

	return true
end

return handler
