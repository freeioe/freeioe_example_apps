local class = require 'middleclass'

local id = class('hj212.monitor_id')

id.static.TYPES = {
	WATER	= 'e',
	AIR		= 'g',
}

id.static.CATES = {
	--- WATER
	WATER_IN			= 0x01, --污水处理厂进口污水流量及污染
	WATER_OUT			= 0x02, --污水处理厂出口污水流量及污染
	ACTIVETED_SLUDGE	= 0x03, --传统活性污泥法 
	O_DITCH_AS			= 0x04, --氧化沟法 
	AO_A2O_AS			= 0x05, --AO 法—A2O
	SBR_AS				= 0x06, --SBR
	BCO					= 0x07, --生物接触氧化法 	
	ORGANISM			= 0x08, --生物滤池法
	DESIGN_PARAM		= 0x09, --污水处理厂设计参数 
	RESERVED_A			= 0x0a,
	RESERVED_B			= 0x0b,
	--- AIR
	SFTL				= 0x01, ---湿法脱硫（石灰石/石灰-石膏法
	BGFTL				= 0x02, -- 半干法脱硫（循环硫化床法） 
	SCR					= 0x03,	-- SCR
	SNCR				= 0x04, -- SNCR
	COTTRELL			= 0x05, --电除尘 
	BDCC				= 0x06, --布袋除尘 
	--- 7-8 RESERVED
}

---
-- type: TYPES
-- cate: 
function id:initialize(type, cate, index, dev_no)
	self._type = type
	self._cate = cate
	self._index = index
	self._dev_no = dev_no
end

function id:__tostring()
	string.format('%s%01x%02d%02d', self._type, self._cate, self._index, self._dev_no)
end

return id
