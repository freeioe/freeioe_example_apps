# 武汉华日精密激光设备

此应用不主动发送闻讯指令，而是使用网关的两个串口进行设备控制软件指令中转，并在中转的同时监听设备数据。


## 配置


## 屏蔽HMI并读取数据

支持从平台下发force_read指令，接收到此指令后，屏蔽中转HMI的指令，并等待五秒后发送laser?\n指令。 在接收到数据后，解除对HMI的屏蔽。


