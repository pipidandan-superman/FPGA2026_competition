# 失联恢复与定位

用户重新上电后恢复SSH/PYNQ/原视频服务，boot_id16a29455-49ad-4ba6-99ac-e3ad6432096b。取回run01_events.raw，只有首条PREFLIGHT完整，尾部NUL，result.json不存在。保留原始文件，不推断确切最后指令。

逐步诊断：parse_only.log解析HWH成功；stop_only/stop_verified证明摄像头服务正常停机、VDMA_HALTED/BUFFER_FREED；load_only.log证明shutdown/gen_cache/FPGA manager/XRT加载均返回成功、PS寄存器状态正常、未访问CSR且SSH正常。restore_camera及video_restored_before_build证明原服务重新加载后帧持续增长。

实际BD/HWH显示proc_sys_reset的C_AUX_RESET_HIGH=0，aux_reset_in接const_zero，足以令CSR和互连一直复位。后续official-IP仿真验证该缺陷，接高后的同一RTL通过板测，详见../2026-09-13_axilt_reg_board_run02/REPORT.md。

时钟读数说明：PYNQ ps.py的Zynq默认参考时钟50MHz，板级晶振33.333MHz；API显示75MHz不能当板上原FCLK频率实测。SLCR IO_PLL=0x1e000，旧FCLK0分频5x4、新5x2，按实际晶振分别50/100MHz。未修改系统PLL。

未对旧错误位流执行第二次CSR读取。未修改原视频文件。前次journal -b -1选到不同历史启动，带连字符boot ID查询也报错，均保留；正确无连字符ID日志查询单列，不能把历史摄像头失败混成本次状态。

远程日志工具改为分块读取stdout/stderr并即时写盘，显式总时限。密码未记录；不将本机认证辅助脚本作为公开发布素材。
