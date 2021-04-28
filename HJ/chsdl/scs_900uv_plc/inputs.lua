return {
	--- PLC
	{
		name = "RS",
		desc = "设备工作状态",
		vt = "int",
	},
	{
		name = "status",
		desc = "PLC工作状态（原始值)", -- 43996
		vt = "int",
	},
	{
		name = "a01014",
		desc = "烟气湿度", -- 44005
		vt = "int",
		unit = "%",
	},
	{
		name = "a01014-i13011",
		desc = "烟气湿度原始值", -- 44005
		vt = "int",
		unit = "%",
	},
	{
		name = "a34013",
		desc = "烟尘", -- 44006
		vt = "int",
		unit = "mg/m3",
	},
	{
		name = "a34013-i13011",
		desc = "烟尘原始值", -- 44006
		vt = "int",
		unit = "mg/m3",
	},
	{
		name = "a01011",
		desc = "烟气流速", -- 30013/14
		vt = "float",
		unit = "m/s",
	},
	{
		name = "a01011-i13011",
		desc = "烟气流速原始值", -- 30013/14
		vt = "float",
		unit = "m/s",
	},
	{
		name = "a01012",
		desc = "烟气温度", -- 30013/14
		vt = "float",
		unit = "C",
	},
	{
		name = "a01012-i13011",
		desc = "烟气温度原始值", -- 30013/14
		vt = "float",
		unit = "C",
	},
	{
		name = "a01013",
		desc = "静压", -- 30013/14
		vt = "float",
		unit = "Pa",
	},
	{
		name = "a01013-i13011",
		desc = "静压原始值", -- 30013/14
		vt = "float",
		unit = "Pa",
	},
}

