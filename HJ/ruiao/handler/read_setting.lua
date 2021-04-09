local base = require 'hj212.server.handler.base'
local cjson = require 'cjson.safe'

local handler = base:subclass('hj212.server.handler.rdata_start')

local attrs = {
	CurrZero = '', -- same with ZeroOrigin
	DemCoeff = 'i13006',
	ScaleGasNd = 'i13008',
	CailDate = 'i13007',
	ZeroRange = '',
	FullRange = 'i13013',
	ZeroDev = 'i13005',
	CailDev = 'i13010',
	ZeroCail = 'i13003',
	ZeroOrigin = 'i13004',
	CailOrigin = 'i13009',
	RealOrigin = 'i13011',
	Rtd = '',
	Mol = '',
}

local dlist = {
	ZeroDate = 'i13001',
	CellPressure = '',
	CellTemp = '',
	SpecEnergy = '',
}

local tag_names = {
	S01 = 'a19001',
	S02 = 'a01011',
	S03 = 'a01012',
	S04 = 'a01017',
	S05 = 'a01014',
	S06 = 'a01015',
	S07 = 'a01016',
	S08 = 'a01013',
	['01'] = 'a23013',
	['02'] = 'a21026',
	['03'] = 'a21002',
	['04'] = 'a21005',
	['100'] = 'a00000',
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

	local common_info = {}
	for key, name in pairs(dlist) do
		local v = params:get(key)
		if v and string.len(name) > 0 then
			common_info[name] = v
		end
	end

	if params:has_tags() then
		local tags = params:tags()

		if tags[data_time] == nil then
			return nil, "Tags not found"
		end

		local ttlist = {}
		local ilist = {}
		for _, tag in pairs(tags[data_time]) do
			--- Tag name
			local tag_name = tag_names[tag:tag_name()]

			--- Get exists list
			local tt = ttlist[tag_name]
			local it = ilist[tag_name]

			-- Create initial lists
			if not tt then
				tt = {}
				it = {}
				ttlist[tag_name] = tt
				ilist[tag_name] = it

				for info, val in pairs(common_info) do
					it[info] = val
				end
			end

			assert(tt and it)
			for key, name in pairs(attrs) do
				local v = tag:get(key)
				if v then
					if string.len(name) == 0 then
						tt[key] = v
					else
						it[name] = v
					end
				end
			end
		end
		for k, v in pairs(ttlist) do
			v.SampleTime = data_time
			--print(k, v.Rtd)
			self._client:on_rdata(k, v)
		end
		for k, v in pairs(ilist) do
			self._client:on_info(k, v)
		end
	end

	return true
end

return handler
