# 国家电网101协议采集应用

通过国家电力101协议，采集设备中的数据

## 设备模板说明

模板有两种数据：META和PROP

### META

* name - 设备名称
* descrition - 设备描述
* series - 设备系列


### PROP

设备属性点定义，包含寄存器地址，读取方式等等


#### name

设备属性点名称

#### description

设备属性点描述

#### unit

设备属性点数值单位， 如mA Hz 

#### RW

设备属性点读写标志

* RO - 只读
* WO - 只写
* RW - 读写


#### data_type

设备属性点寄存器数据类型(解析modbus寄存器的类型)，可用:

* bit
* int8
* uint8
* int16
* uint16
* int32
* int32_r
* uint32
* uint32_r
* float
* float_r
* double
* double_r
* string

其中int32_r uint32_r float_r double_r表示使用内存数据是反向排序（排序单位是两个字节)，例如:
int32的值为A1B2C3D4
int32_r的值为D4C3B2A1

#### vt

设备属性点数值类型，FreeIOE制定的类型，有int, float, string三种类型


#### function_code

Modbus读取指令码的十进制，支持01, 02, 03, 04。 01, 02功能码的data_type只能是bit


#### data_address

寄存器地址，从零开始


#### rate

运算系数，将获取的modbus数据按照数据类型(data_type)进行解析后，乘以rate作为属性数据。缺省为1

#### offset

数据偏移量，从零开始

在03, 04功能码读取寄存器时，可以指定offset. （01, 02不支持指定offset操作)

在data_type为bit的时候offset是指位偏移个数，其他类型时是指字节便宜个数。

#### wwrite_functin_code

指定写操作的功能码，默认情况下，与function_code的对应关系如下:

01 -> 05
03 -> 06

#### string_length

当按照裸字符串进行读写(data_type 为 string或raw)时，需要指定此长度。

