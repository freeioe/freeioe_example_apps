--- 900CPM
--
return {
	{
		name = "RS",
		desc = "设备工作状态",
		vt = "int",
	},
	{
		name = "state",
		desc = "运行状态(原始值)", -- 40015
		vt = "int",
	},
	{
		name = "a34013",
		desc = "烟尘", -- 40001
		vt = "float",
		unit = "mg/m^3",
	},
	{
		name = "a34013-i12001",
		desc = "工作状态",
		vt = "int",
	},
	{
		name = "a34013-i12002",
		desc = "报警状态",
		vt = "int",
	},
	{
		name = "a34013-i12003",
		desc = "报警详情",
		vt = "int",
	},
	--[[
	{
		name = "a34013-i13013_a",
		desc = "量程1", -- 40003
		vt = "float",
	},
	{
		name = "a34013-i13013_b",
		desc = "量程2", -- 40005
		vt = "float",
	},
	]]--
	{
		name = "a34013-i13006",
		desc = "斜率（数据修正斜率）", -- 40007
		vt = "float",
	},
	{
		name = "a34013-i13002",
		desc = "截距（数据修正截距）", -- 40009
		vt = "float",
	},
	{
		name = "a34013-i13013",
		desc = "当前量程", -- 40011
		vt = "float",
	},
	{
		name = "a34013-i13011",
		desc = "烟尘原始值", -- 40013
		vt = "float",
	},
}
