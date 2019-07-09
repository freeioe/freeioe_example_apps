return {
	{
		name = "Set_Working_Mode",
		desc = "设定激光器的操作状态",
		vt = "int",
		cmd = "state",
		decode_mode = 1,
	},
	{
		name = "Set_Frequency",
		desc = "设定出光频率",
		vt = "int",
		cmd = "tf",
		decode_mode = 1,
	},		
	{
		name = "Set_Trigger_Mode",
		desc = "设定trig模式",
		vt = "int",
		cmd = "trig",
		decode_mode = 1,
	},
	{
		name = "Set_Scaling_down",
		desc = "设置分频功能",
		vt = "int",
		cmd = "eaomdiv",
		decode_mode = 1,
	},
	{
		name = "Set_Power",
		desc = "设置功率",
		vt = "int",
		cmd  ="pf",
		decode_mode = 1,
    }
}
