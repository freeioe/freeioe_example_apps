local base = require 'hj212.server.handler.base'
local cjson = require 'cjson.safe'

local handler = base:subclass('hj212.server.handler.rdata_start')

local attrs = {
	'CurrZero', 'DemCoeff', 'ScaleGasNd', 'CailDate', 'ZeroRange', 'FullRange', 'ZeroDev', 'CailDev', 'ZeroCail', 'ZeroOrigin', 'CailOrigin', 'RealOrigin', 'Rtd', 'Mol'
}

local dlist = {
	'ZeroDate',
	'CellPressure',
	'CellTemp',
	'SpecEnergy'
}

function handler:process(request)
	local params = request:params()
	if not params then
		return nil, "Params missing"
	end
	local data_time = params:get('DataTime')
	if not data_time then
		return nil, "DataTime missing"
	end

	for _, name in ipairs(dlist) do
		local rdata = {
			SampleTime = data_time,
			Rtd = params:get(name)
		}
		self._client:on_rdata(name, rdata)

	end

	if params:has_tags() then
		local tags = params:tags()

		if tags[data_time] == nil then
			return nil, "Tags not found"
		end

		local ttlist = {}
		for _, tag in pairs(tags[data_time]) do
			local tt = ttlist[tag:tag_name()]
			if not tt then
				tt = {}
				ttlist[tag:tag_name()] = tt
			end
			for _, name in ipairs(attrs) do
				local v = tag:get(name)
				if v then
					tt[name] = v
				end
			end
		end
		for k, v in pairs(ttlist) do
			v.SampleTime = data_time
			self._client:on_rdata(k, v)
		end
	end

	return true
end

return handler
