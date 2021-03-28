return {
	--- 900CPM
	{
		name = "state",
		desc = "工作状态", -- 30013
		vt = "int",
	},
	{
		name = "error",
		desc = "烟尘仪故障", -- 30014
		vt = "int",
	},
	{
		name = "dust",
		desc = "颗粒物浓度", -- 30001
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "temp",
		desc = "烟气温度", -- 30003
		vt = "float",
	},
	{
		name = "flow",
		desc = "烟气流速", -- 30005
		vt = "float",
		unit = "m/s",
	},
	{
		name = "PaS",
		desc = "烟气静压", -- 30007
		vt = "float",
		unit = "Pa",
	},
	{
		name = "PaD",
		desc = "烟气动压", -- 30009
		vt = "float",
		unit = "Pa",
	}
}
