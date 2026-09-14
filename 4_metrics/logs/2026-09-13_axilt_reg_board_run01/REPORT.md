# 寄存器板测 run01：现场失联，结果未确认

状态：REG_BOARD_UNCONFIRMED_CONNECTION_LOST；不是功能PASS。原视频恢复未完成。BRAM_NOT_STARTED。

## 已确认

- 用户明确上电并授权验证；测试前用户确认HDMI动态正常。
- preflight.log：PYNQ3.0.1、ARMv7、视频服务active、原BIT/HWH哈希匹配；VDMA内核驱动目录未列出绑定设备。
- boot_video.log：当前boot_id=261a43ac-f0c8-419f-9eea-d21932afa44b，视频帧/槽位持续增长；板端日期异常，首次preflight的journal混有历史记录，当前状态以-b日志为准。
- video_before.json：12.265秒61完整帧、61种CRC、丢帧0、无CRC/坏头/不完整帧错误。
- delivery_hashes.json与delivery快照：BIT/HWH/XSA按manifest本地核对；软件/BIT/HWH上传后逐文件SHA核对通过。板端独立目录 /home/xilinx/axilt_test_20260913_run01，未覆盖原摄像头文件。
- compile.log：ARM32 EABI5 MMIO动态库编译成功，SHA256=753b36efadfb1da6f626bd267b8d97da3d9e1d927a856852fca894e5b5429e23。

## 执行与异常

执行命令完整保存在register_test.log，使用sudo及XILINX_XRT=/usr运行board_test.py，1000轮/3次重载默认配置。
其后SSH会话超时；新连接先超时，后SSH协议banner异常；ping超时/host unreachable。未取回板端events.jsonl/result.json，不能确认是否完成下载、首次MMIO或多少轮命令。
remote.py原实现out.read()直到结束才落盘，超时后未能保留已部分接收的stdout；这是本次证据采集限制，不能将Windows日志只有命令解释为板端未执行。后续必须改为流式读取并逐块落盘后再开展新run。
COM6以115200/8N1、DTR/RTS关闭，做被动及空白行探测，uart_*.raw均无输出；未发送复位、下载或业务命令。不能单凭串口无输出证明Linux死机。
用户确认期间无拔插/复位/断电，摄像头cfg_done灯灭且HDMI黑屏。该现象与无摄像头/HDMI模块的独立Overlay相符，但不能证明AXI执行正确。

初始OpenSSH尝试先Host key verification failed，再accept-new后密钥认证失败；后用既有实验镜像认证方式和历史已知主机密钥成功登录。最初编译调用出现PowerShell引号解析错误，未执行板端命令；简化命令后compile.log记录成功。sudo -n无密码探测失败，正式命令使用sudo -S。所有失败保留，不算硬件功能失败依据。

## 恢复/下一步

当前无可用控制通道，需用户一次复位或断电重启恢复原SD启动；可能丢失尚未落盘缓冲，但禁止删除已有evidence。恢复后先读取 /home/xilinx/axilt_test_20260913_run01/evidence/register_run01/events.jsonl 及可能的result.json、上一启动日志、原服务状态，先定位再决定修复/新run。不得覆盖run01或直接自动重发。
还需确认新旧PS基础配置、GP0时钟复位/地址与运行中设备树兼容，必要时分离仅下载/身份读取诊断。未经证据不得认定根因是SD镜像或RTL。
未改变启动镜像、服务启用策略、原视频文件；未合并主工程，未进入BRAM。
