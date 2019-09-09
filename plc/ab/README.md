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


## Tag path attributes

### path

当CPU类型为PLC时，有path时表明是使用了 DTH+桥的数据点
当CPU类型为LGX时，path是必备的属性。


### elem_type

指定element type 代替element size。 支持LGX, MLGX800(??)


* lint/ulint - 64-bit integer
* dint/udint - 32-bit integer
* int/int	 - 16-bit integer
* sint/usint - 8-bit interger
* bool		 - bit boolean
* bool array - bit array
* real		 - 32-bit float
* lreal		 - 64-bit float
* string	 - string (elem_size 88, type AB_TYPE_STRING)
* short string - short string (elem_size 256??, type AB_TYPE_SHORT_STRING


### elem_size

指定element 的大小, 字节数量。


### name

数据点名称，在PLC, LGX_PCCC, MLGX上前两个字符决定了数据类型。 (如下表，暂时不可用)

| --- | --- | --- | --- | --- |
| 第一字符 | 第二个字符 | elem_size | elem_type | 说明 |
| [Bb] | * | 1 | AB_TYPE_BOOL | boolean数值 |
| [Cc] | * | 6 | AB_TYPE_COUNTER | 计数器 |
| [Ff] | * | 4 | AB_TYPE_FLOAT32 | 32位浮点数 |
| [Nn] | * | 2 | AB_TYPE_INT16 | 16位整数 |
| [Rr] | * | 6 | AB_TYPE_CONTROL | 控制点 |
| [Ss] | [Tt] | 84 | AB_TYPE_STRING | 字符串 |
| [Ss] | [^Tt] | 2 | AB_TYPE_INT16 | 状态数值 |
| [Tt] | * | 6 | AB_TYPE_TIMER | 计时器 |


### elem_count

数组长度。



### Examples

#### LGX

protocol=ab_eip&gateway=10.206.1.27&path=1,0&cpu=LGX&elem_size=4&elem_count=1&name=testDINT
protocol=ab_eip&gateway=10.17.45.37&path=1,0&cpu=LGX&elem_size=4&elem_count=1&name=DataIn_Frm_Sched[1]&read_cache_ms=100
protocol=ab-eip&gateway=192.168.56.121&path=1,5&cpu=LGX&elem_size=4&elem_count=200&name=TestBigArray&debug=4
protocol=ab_eip&gateway=192.168.1.42&path=1,0&cpu=LGX&elem_size=4&elem_count=10&name=myDINTArray
protocol=ab_eip&gateway=10.206.1.39&path=1,0&cpu=LGX&elem_size=4&elem_count=10&name=TestDINTArray&debug=1
protocol=ab_eip&gateway=10.206.1.39&path=1,2,A:27:1&cpu=plc5&elem_count=4&elem_size=4&name=F8:0&debug=1

protocol=ab_eip&gateway=10.206.1.39&path=1,0&cpu=LGX&elem_size=4&elem_count=1&name=TestDINTArray[4]&debug=4
protocol=ab_eip&gateway=10.206.1.39&path=1,0&cpu=LGX&elem_size=4&elem_count=1&name=TestDINTArray[%d]&debug=3
protocol=ab_eip&gateway=10.206.1.27&path=1,0&cpu=LGX&elem_size=88&elem_count=48&debug=1&name=Loc_Txt
protocol=ab-eip&gateway=10.206.1.39&path=1,5&cpu=LGX&elem_size=4&elem_count=1&name=TestBigArray&debug=4
protocol=ab_eip&gateway=10.206.1.27&path=1,0&cpu=LGX&elem_size=1&elem_count=1&debug=1&name=pcomm_test_bool
protocol=ab_eip&gateway=10.206.1.27&path=1,0&cpu=LGX&elem_size=88&elem_count=6&debug=1&name=Loc_Txt


protocol=ab-eip&gateway=10.206.1.39&path=1,4&cpu=lgx&elem_type=DINT&elem_count=1&name=TestDINTArray
protocol=ab-eip&gateway=10.206.1.39&path=1,4&cpu=lgx&elem_type=INT&elem_count=1&name=TestINTArray
protocol=ab-eip&gateway=10.206.1.39&path=1,4&cpu=lgx&elem_type=SINT&elem_count=1&name=TestSINTArray
protocol=ab-eip&gateway=10.206.1.39&path=1,4&cpu=lgx&elem_type=SINT&elem_count=1&name=TestBOOL

枚举数据点列表
protocol=ab-eip&gateway=10.206.1.39&path=1,4&cpu=lgx&name=@tags


#### PLC5
protocol=ab_eip&gateway=10.206.1.28&cpu=PLC5&elem_size=4&elem_count=1&name=F8:10
protocol=ab_eip&gateway=10.206.1.39&path=1,2,A:27:1&cpu=plc5&elem_count=1&elem_size=2&name=N7:0&debug=4
protocol=ab_eip&gateway=10.206.1.38&cpu=PLC5&elem_size=4&elem_count=5&name=F8:10&debug=4
protocol=ab_eip&gateway=10.206.1.38&cpu=PLC5&elem_size=2&elem_count=1&name=N7:0&debug=4

#### SLC/MLGX
protocol=ab_eip&gateway=10.206.1.26&cpu=SLC&elem_size=2&elem_count=1&name=N7:0&debug=1

