-- Types
--
local _M = {}

_M.PROTOCOL = {
	V2005 = 0,
	V2017 = 1,
}

_M.SYSTEM = {
	Q_SURFACE_WATER		= 21,
	Q_AIR				= 22,
	Q_SOUND				= 23,
	Q_GROUND_WATER		= 24,
	Q_SOIL				= 25,
	Q_SEA_WATER			= 26,
	Q_VOLATILE_ORGANICS	= 27,
	S_AIR				= 31,
	S_SURFACE_WATER		= 32,
	S_GROUND_WATER		= 33,
	S_SEA				= 34,
	S_SOIL				= 35,
	S_SOUND				= 36,
	S_VIBRATION			= 37,
	S_RADIOACTIVITY		= 38,
	S_DUST				= 39,
	S_ELECTRO			= 41,
	E_FLUE_GAS			= 51,
	E_SEWAGE			= 52,
	REPLY				= 91,
}

_M.RESULT = {
	SUCCESS			= 1,
	ERR_UNKNOWN		= 2,
	ERR_CONDITION	= 3,
	ERR_TIMEOUT		= 4,
	ERR_BUSY		= 5,
	ERR_SYSTEM		= 6,
	ERR_NO_DATA		= 100,
}

_M.REPLY = {
	RUN			= 1,
	REJECT		= 2,
	ERR_PW		= 3,
	ERR_MN		= 4,
	ERR_ST		= 5,
	ERR_Flag	= 6,
	ERR_QN		= 7,
	ERR_CN		= 8,
	ERR_CRC		= 9,
	ERR_UNKNOWN = 100,
}

_M.FLAG = {
	Normal		= 'N',
	Stoped		= 'F',
	Maintain	= 'M',
	ByHand		= 'S',
	Error		= 'D',
	Calibration	= 'C',
	Overproof	= 'T',
	Connection	= 'B',
}

_M.RS = {
	Stoped = 0,
	Normal = 1,
	Calibration = 2,
	Maintain = 3,
	Alarm = 4,
	Clean = 5,
}

_M.COMMAND = {
	-- Setup
	SET_TIMEOUT_RETRY	= 1000,
	-- Settings
	GET_TIME			= 1011,
	SET_TIME			= 1012,
	REQ_TIME_CALIB		= 1013,
	GET_RDATA_INTERVAL	= 1061,
	SET_RDATA_INTERVAL	= 1062,
	GET_MIN_INTERVAL	= 1063,
	SET_MIN_INTERVAL	= 1064,
	SET_PASSWD			= 1072,
	READ_SETTING		= 1073,
	-- DATA
	RDATA_START			= 2011,
	RDATA_STOP			= 2012,
	RDATA_READ			= 2013,
	STATE_START			= 2021,
	STATE_STOP			= 2022,
	STATE_READ			= 2023,
	DAY_DATA			= 2031,
	DAY_STATUS			= 2041,
	MIN_DATA			= 2051,
	HOUR_DATA			= 2061,
	UPTIME				= 2081,
	-- Controls
	ZERO_CALIB			= 3011,
	SAMPLE_DATA			= 3012,
	CLEANUP				= 3013,
	SAMPLE_COMP			= 3014,
	OVERPROOF			= 3015,
	SET_SAMPLE_INTERVAL	= 3016,
	GET_SAMPLE_INTERVAL	= 3017,
	GET_SAMPLE_SPENT	= 3018,
	GET_METER_SN		= 3019,
	GET_METER_INFO		= 3020,
	SET_METER_INFO		= 3021,
	-- Replies
	REPLY				= 9011,
	RESULT				= 9012,
	NOTICE				= 9013,
	DATA_ACK			= 9014,
}

return _M
