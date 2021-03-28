return {
	--- PLC
	{
		name = "plc_state",
		desc = "PLC State", -- 43996
		vt = "int",
	},
	--- 900UV
	{
		name = "error",
		desc = "分析仪故障", -- 30011 HIGH
		vt = "int",
	},
	{
		name = "adjust",
		desc = "系统校正", -- 30011 LOW
		vt = "int",
	},		
	{
		name = "maintain",
		desc = "系统维护", -- 30012
		vt = "int",
	},
	{
		name = "SO2",
		desc = "SO2 测量浓度", -- 30013/14
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO",
		desc = "NO 测量浓度", -- 30015/16
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "O2",
		desc = "O2 测量浓度", -- 30017/18
		vt = "float",
		unit = "%",
	},
	{
		name = "NO2",
		desc = "NO2 测量浓度", -- 30019/20
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NOx",
		desc = "NOx 测量浓度负值不累加分子量46", -- 30021/22 -- Minus invalid???
		vt = "float",
		unit = "mg/m3",
	},
	--[[
	{
		name = "SO2_K1",
		desc = "SO2 斜率K1", -- 30023/24
		vt = "float",
	},
	{
		name = "SO2_raw",
		desc = "SO2 原始值", -- 30025/26
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "SO2_range", -- 30027
		desc = "SO2 量程",
		vt = "int",
	},
	{
		name = "SO2_s",		-- 30028/29
		desc = "SO2 标气浓度",
		vt = "float",
		unit = "mg/m3",
    },
	{
		name = "SO2_zero_offset_d", -- 30036/27
		desc = "SO2 零点漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "SO2_range_offset_d", -- 30038/39
		desc = "SO2 量程漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "SO2_zero_offset", -- 30040/41
		desc = "SO2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "SO2_range_offset", -- 30042/43
		desc = "SO2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "NO_K1", -- 30044/45
		desc = "NO 斜率K1",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "NO_raw", -- 30046/47
		desc = "NO 原始值",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO_range", -- 30048
		desc = "NO 量程",
		vt = "int",
	},
	{
		name = "NO_s",		-- 30049/50
		desc = "NO 标气浓度",
		vt = "float",
		unit = "mg/m3",
    },
		{
		name = "NO_zero_offset_d", -- 30057/58
		desc = "NO 零点漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO_range_offset_d", -- 30059/60
		desc = "NO 量程漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO_zero_offset", -- 30061/62
		desc = "NO 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "NO_range_offset", -- 30063/64
		desc = "NO 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "O2_range", -- 30065
		desc = "O2 量程",
		vt = "int",
	},
	{
		name = "O2_s",		-- 30066/67
		desc = "NO 标气浓度",
		vt = "float",
		unit = "mg/m3",
    },
		{
		name = "O2_zero_offset_d", -- 30074/75
		desc = "O2 零点漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "O2_range_offset_d", -- 30076/77
		desc = "O2 量程漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "O2_zero_offset", -- 30078/79
		desc = "O2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "O2_range_offset", -- 30080/81
		desc = "O2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "O2_zero_B1", -- 30082
		desc = "O2 零点初值 B1",
		vt = "int",
	},
	{
		name = "O2_zero_K2", -- 30083/84
		desc = "O2 线性系数 K2",
		vt = "float",
	},
	{
		name = "O2_raw_adc", -- 30085
		desc = "O2 传感器电压A/D采集原始值",
		vt = "int",
	},
	{
		name = "O2_zero_K2", -- 30086/87
		desc = "O2 线性系数 K2",
		vt = "int",
	},
	{
		name = "NO2_K1", -- 30094/95
		desc = "NO2 斜率K1",
		vt = "float",
	},
	{
		name = "NO2_raw", -- 30096/97
		desc = "NO2 原始值",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO2_range", -- 30098
		desc = "NO2 量程",
		vt = "int",
	},
	{
		name = "NO2_s",		-- 30099/100
		desc = "NO2 标气浓度",
		vt = "float",
		unit = "mg/m3",
    },
		{
		name = "NO2_zero_offset_d", -- 30107/108
		desc = "NO2 零点漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO2_range_offset_d", -- 30109/110
		desc = "NO2 量程漂移",
		vt = "float",
		unit = "mg/m3",
	},
	{
		name = "NO2_zero_offset", -- 30111/112
		desc = "NO2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "NO2_range_offset", -- 30113/114
		desc = "NO2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	]]--
}

