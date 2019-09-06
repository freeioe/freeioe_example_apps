# Modbus Master application

Export device sensors data via modbus protocol (rtu, tcp, ascii), over Serial or Socket connection.
通过Modbus协议发布设备数据，支持RTU, TCP, ASCII协议，支持串口、TCP套接字连接

## 设备模板说明

模板有两种数据：META和PROP。 共享Modbus Master电表格式，使用同样的格式，不同点在于rate的含义

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

设备属性点寄存器数据类型(将数据转换成为寄存器内容的方式)，可用:

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

运算系数，将设备数据除以rate后，再按照数据类型(data_type)保存为Modbus寄存器内容。缺省为1

#### offset

数据偏移量，从零开始

在03, 04功能码读取寄存器时，可以指定offset. （01, 02不支持指定offset操作)

在data_type为bit的时候offset是指位偏移个数，其他类型时是指字节便宜个数。

#### write_function_code

Slave模式下不使用

#### string_length

当data_type 为string/raw时使用此参数标记长度
