--- 900UV
return {
	{
		name = "RS",
		desc = "设备工作状态",
		vt = "int",
	},
	{
		name = "i12101",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "i12103",
		desc = "报警详情",
		vt = "int",
	},
	{
		name = "alarm",
		desc = "分析仪故障(原始值)", -- 30011 HIGH
		vt = "int",
	},
	{
		name = "adjust",
		desc = "系统校正(原始值)", -- 30011 LOW
		vt = "int",
	},		
	{
		name = "maintain",
		desc = "系统维护(原始值)", -- 30012
		vt = "int",
	},
	{
		name = "a21026",
		desc = "SO2 测量浓度", -- 30013/14
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a21003",
		desc = "NO 测量浓度", -- 30015/16
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a19001",
		desc = "O2 测量浓度", -- 30017/18
		vt = "float",
		unit = "%",
	},
	{
		name = "a21004",
		desc = "NO2 测量浓度", -- 30019/20
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a21002",
		desc = "NOx 测量浓度负值不累加分子量46", -- 30021/22 -- Minus invalid???
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a21026-i12001",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "a21026-i12002",
		desc = "报警状态",
		vt = "int",
	},
	{
		name = "a21026-i12003",
		desc = "报警详情",
		vt = "int",
	},
	{
		name = "a21026-i13006",
		desc = "SO2 斜率", -- 30023/24
		vt = "float",
	},
	{
		name = "a21026-i13011",
		desc = "SO2 原始值", -- 30025/26
		vt = "float",
	},
	{
		name = "a21026-i13013", -- 30027
		desc = "SO2 量程",
		vt = "int",
		vt = "mg/m^3",
	},
	{
		name = "a21026-i13008",		-- 30028/29
		desc = "SO2 标气浓度",
		vt = "float",
		unit = "mg/m^3",
    },
	{
		name = "a21026-i13007",		-- 30030/32
		desc = "SO2 量程校准时间",
		vt = "int"
	},
	{
		name = "a21026-i13001",		-- 30033/35
		desc = "SO2 零点校准时间",
		vt = "int"
	},
	{
		name = "a21026-i13005", -- 30040/41
		desc = "SO2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a21026-i13010", -- 30042/43
		desc = "SO2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a21003-i12001",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "a21003-i12002",
		desc = "报警状态",
		vt = "int",
	},
	{
		name = "a21003-i12003",
		desc = "报警详情",
		vt = "int",
	},
	{
		name = "a21003-i13006", -- 30044/45
		desc = "NO 斜率",
		vt = "float",
	},
	{
		name = "a21003-i13011", -- 30046/47
		desc = "NO 原始值",
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a21003-i13013", -- 30048
		desc = "NO 量程",
		vt = "int",
		vt = "mg/m^3",
	},
	{
		name = "a21003-i13008",		-- 30049/50
		desc = "NO 标气浓度",
		vt = "float",
		unit = "mg/m^3",
    },
	{
		name = "a21003-i13007",		-- 30051/53
		desc = "NO 量程校准时间",
		vt = "int"
	},
	{
		name = "a21003-i13001",		-- 30054/56
		desc = "NO 零点校准时间",
		vt = "int"
	},
	{
		name = "a21003-i13005", -- 30061/62
		desc = "NO 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a21003-i13010", -- 30063/64
		desc = "NO 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a19001-i12001",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "a19001-i12002",
		desc = "报警状态",
		vt = "int",
	},
	{
		name = "a19001-i12003",
		desc = "报警详情",
		vt = "int",
	},
	{
		name = "a19001-i13013", -- 30065
		desc = "O2 量程",
		vt = "int",
		unit = "%",
	},
	{
		name = "a19001-i13008",		-- 30066/67
		desc = "O2 标气浓度",
		vt = "float",
		unit = "%",
    },
	{
		name = "a19001-i13007",		-- 30068/70
		desc = "O2 量程校准时间",
		vt = "int"
	},
	{
		name = "a19001-i13001",		-- 30071/73
		desc = "O2 零点校准时间",
		vt = "int"
	},
	{
		name = "a19001-i13005", -- 30078/79
		desc = "O2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a19001-i13010", -- 30080/81
		desc = "O2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a19001-i13004", -- 30082
		desc = "O2 零点校准原始值",
		vt = "int",
	},
	{
		name = "a19001-i13006", -- 30083/84
		desc = "O2 斜率",
		vt = "float",
	},
	{
		name = "a19001-i13011", -- 30085
		desc = "O2 传感器电压A/D采集原始值",
		vt = "int",
	},
	{
		name = "a19001-i13011_b", -- 30086/87
		desc = "光源能量",
		vt = "int",
	},
	{
		name = "a21004-i12001",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "a21004-i12002",
		desc = "报警状态",
		vt = "int",
	},
	{
		name = "a21004-i12003",
		desc = "报警详情",
		vt = "int",
	},
	{
		name = "a21004-i13006", -- 30094/95
		desc = "NO2 斜率",
		vt = "float",
	},
	{
		name = "a21004-i13011", -- 30096/97
		desc = "NO2 原始值",
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a21004-i13013", -- 30098
		desc = "NO2 量程",
		vt = "int",
	},
	{
		name = "a21004-i13008",		-- 30099/100
		desc = "NO2 标气浓度",
		vt = "float",
		unit = "mg/m^3",
    },
	{
		name = "a21004-i13007",		-- 30101/103
		desc = "NO2 量程校准时间",
		vt = "int"
	},
	{
		name = "a21004-i13001",		-- 30104/106
		desc = "NO2 零点校准时间",
		vt = "int"
	},
	{
		name = "a21004-i13005", -- 30111/112
		desc = "NO2 零点漂移",
		vt = "float",
		unit = "%F.S.",
	},
	{
		name = "a21004-i13010", -- 30113/114
		desc = "NO2 量程漂移",
		vt = "float",
		unit = "%F.S.",
	},
}

