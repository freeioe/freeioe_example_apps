# AB PLC

## 支持的设备型号

这个应用基于 [libplctag](https://github.com/kyle-github/libplctag), 支持的设备型号在libplctag的介绍里面有详细的说明

## 设备模板

### Meta字段

* name - 设备名称
* description - 设备描述
* series - 设备系列名称


### PROP 字段

* name - 属性名称
* desc - 属性描述
* unit - 属性的数值单位
* RW - 属性读写标志 RW:读写 RO: 只读 WO: 只写
* data_type - PLC数据类型，支持 uint8/16/32/64 int8/16/32/64 float32/64
* vt - FreeIOE数据类型（int/float/string)
* elem_name - PLC数据名称
* offset - 数据偏移量（针对PLC数据是数组的情况, 从0开始, 单位是数据类型的长度)
* rate - 数据计算系数，默认为1
* path - 数据路径，默认为应用中配置的数据路径。


## 应用配置

## 处理器型号

### PLC

plc5, plc, slc, slc500


### LGX_PCCC

lgxpccc, logixpccc, lgxplc5, logixplc5, lgx-pccc, logix-pccc, lgx-plc5, logix-plc5

### MLGX800

micrologix800, mlgx800, micro800

### MLGX

mricrologix, mlgx

### LGX

compactlogix, clgx, lgx, controllogix, contrologix, flexlogix, flgx


