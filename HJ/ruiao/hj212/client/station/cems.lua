local class = require 'middleclass'
local logger = require 'hj212.logger'
local waitable = require 'hj212.client.station.waitable'
local cems = class('hj212.client.station.cems')

local CEMS_TM = {
	-- CEMS 安装地点的环境大气压值，Pa
	Ba = {
		name = 'a01006',
		--name = 'i23001',
		default = 101.325,
		rate = 1000
	},
	-- CEMS 测量的烟气静压值，Pa
	Ps = {
		name = 'a01013',
		default = 101.325,
		rate = 1000
	},
	-- CEMS 测量的烟气温度，℃
	ts = {
		name = 'a01012',
	},
	-- CEMS 最大间隔 5s 采集测量的烟气流速值，m/s
	Vp = {
		name = 'a01011',
	},
	-- CEMS 安装点位烟囱或烟道断面的面积，m2
	F = {
		name = 'a01016',
		default = 1
	},
	-- 烟气绝对湿度（又称水分含量），%
	Xsw = {
		name = 'a01014',
		rate = 0.01,
	},
	-- 排放烟气中含氧量干基体积浓度，%
	Cvo2 = {
		name = 'a19001',
		rate = 0.01
	},
	-- CEMS 设置速度场系数
	Kv = {
		name = 'Kv',
		default = 1
	},
	-- CEMS 排放标准中规定的该行业标准过量空气系数
	As = {
		name = 'As',
		default = 1.7 --
	},
	Co2s = {
		name = 'Co2s',
		default = 0.1 -- ????
	},
	-- Mno 一氧化氮摩尔质量
	Mno = {
		name = 'Mno',
		default = 30,
	},
	-- Mno2 一氧化氮摩尔质量
	Mno2 = {
		name = 'Mno2',
		default = 46,
	},
}

function cems:initialize(station)
	self._station = station

	self._tag_map = {}
	for k, v in pairs(CEMS_TM) do
		local tag_v = {
			name = v.name,
			rate = v.rate,
			default = v.default or 0
		}
		self._tag_map[k] = tag_v

		local wtag = waitable:new(station, tag_v.name)

		self[k] = function(self, timeout)
			local value, timestamp = wtag:value(timeout)
			if not value then
				local err = string.format("Failed to get %s. error:%s", k, timestamp)
				logger.warning(err)
				return tag_v.default, os.time()
			end
			if tag_v.rate then
				return value * tag_v.rate, timestamp
			else
				return value, timestamp
			end
		end
	end
end

function cems:set_default(name, default)
	local tag_v = assert(self._tag_map[name])
	if default == nil then
		tag_v.default = CEMS_TM[name].default or 0
	else
		tag_v.default = default
	end
end

function cems:set_rate(name, rate)
	local tag_v = assert(self._tag_map[name])
	if rate == nil then
		tag_v.rate = CEMS_TM[name].rate or nil
	else
		tag_v.rate = rate
	end

end

function cems:get(name)
	local tag_v = assert(self._tag_map[name])
	return self._station:find_tag(tag_v.name)
end

function cems:rate(name)
	local tag_v = assert(self._tag_map[name])
	return tag_v.rate or 1
end

return cems
