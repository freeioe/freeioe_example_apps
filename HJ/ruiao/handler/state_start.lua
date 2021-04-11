local base = require 'hj212.server.handler.base'
local types = require 'hj212.types'
local cjson = require 'cjson.safe'

local handler = base:subclass('hj212.server.handler.rdata_start')

local function map_state_alarm(state)
	local state = tonumber(state)

	if state == 0 then
		return types.RS.Normal
	end
	if state == 1 then
		return types.RS.Maintain
	end
	if state == 3 then
		return types.RS.Clean
	end

	return types.RS.Calibration
end

local function map_alarm(state, alarm)
	local alarm = tonumber(alarm)
	local infos = {
		a19001 = {},
		a21002 = {},
		a21005 = {},
		a21026 = {}
	}

	for k, v in pairs(infos) do
		v.i12001 = state
		v.i12002 = alarm == 0 and 0 or 1
	end

	local set_all = function(val)
		for k, v in pairs(infos) do
			v.i12003 = val
		end
	end

	if alarm == 0 then
		set_all(0)
	end

	if 0x1 == (alarm & 0x1) then
		set_all(1)
	end

	if 0x2 == (alarm & 0x2) then
		set_all(5)
	end

	if 0x4 == (alarm & 0x4) then
		set_all(4)
	end

	if 0x8 == (alarm & 0x8) then
		set_all(7)
	end

	if 0x10 == (alarm & 0x10) then
		set_all(9)
	end

	if 0x20 == (alarm & 0x20) then
		set_all(6)
	end

	if 0x40 == (alarm & 0x40) then
		infos.a19001.i12003 = 8
	end

	if 0x80 == (alarm & 0x80) then
		infos.a21026.i12003 = 2
	end

	if 0x100 == (alarm & 0x100) then
		infos.a21026.i12003 = 3
	end

	if 0x200 == (alarm & 0x200) then
		infos.a21002.i12003 = 2
	end

	if 0x400 == (alarm & 0x400) then
		infos.a21002.i12003 = 3
	end

	if 0x800 == (alarm & 0x800) then
		infos.a19001.i12003 = 2
	end

	if 0x1000 == (alarm & 0x1000) then
		infos.a19001.i12003 = 3
	end

	return infos
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
		local stss = params:statess()

		if stss[data_time] == nil then
			return nil, "Devices not found"
		end

		local state = nil
		local alarm = nil
		local rs = nil

		for _, sts in pairs(stss[data_time]) do
			--- Hacked in another way please!!!!
			local s = sts:get('InstrState')
			if s ~= nil then
				state = s
			end

			local a = sts:get('Ala')
			if a ~= nil then
				alarm = a
			end
		end

		local rs = map_state_alarm(state)
		self._client:set_meter_rs(rs)

		local infos = map_alarm(state, alarm)
		for k, v in pairs(infos) do
			self._client:on_info(k, v)
		end
	end

	return true
end

return handler
