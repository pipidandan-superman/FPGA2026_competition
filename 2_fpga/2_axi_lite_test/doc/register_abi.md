# AXLT ABI 1.0：寄存器阶段

身份0x41584C54（AXLT），版本0x00010000，CAPS=1表示仅寄存器执行器。
这是独立测试ABI，与既有蓝牙EESC方案不同；不混用两套驱动。
所有地址为字节偏移，32位、小端、4字节对齐。

| 偏移 | 名称 | 属性 | 复位值及含义 |
|---|---|---|---|
| 0x00 | IP_ID | RO | 0x41584C54 |
| 0x04 | ABI_VERSION | RO | 0x00010000 |
| 0x08 | CAPS | RO | 1，bit0寄存器执行；BRAM未实现 |
| 0x0C | SCRATCH | RW | 0，支持WSTRB逐字节写 |
| 0x10 | TEST_INPUT | RW | 0，支持WSTRB；可在执行时修改，不改变快照 |
| 0x14 | CMD_SEQ | RW | 0，完整字写；BUSY或DONE时禁止修改 |
| 0x18 | ACTION | WO/读0 | 1=START；2=ACK；其他值拒绝 |
| 0x1C | STATUS | RO | READY=bit0，BUSY=bit1，DONE=bit2 |
| 0x20 | ACCEPT_SEQ | RO | 0，最近锁存的命令序号 |
| 0x24 | DONE_SEQ | RO | 0，最近完成序号 |
| 0x28 | TEST_RESULT | RO | 0，锁存输入按位取反 |
| 0x2C | ERROR_CODE | RO | 0，当前执行器无业务错误类型 |
| 0x30 | EXEC_COUNT | RO | 0，完成时递增，32位模运算 |

READY在复位退出后为1。ACK只清DONE；保留结果、完成序号和执行计数以便诊断。

## 事务规则

- AXI-Lite五通道独立握手；每方向最多一个未完成事务。写地址、写数据可先后任意到达。
- 读写可以并行；B/R反压时VALID、RESP和RDATA稳定保持。
- 上游地址完整保留12位；不截去低两位来静默接受非对齐访问。
- 对普通RW寄存器，WSTRB=0是OKAY无操作。CMD_SEQ/ACTION必须WSTRB=0xF。
- 非法/非对齐地址、RO写、错误命令或状态冲突返回SLVERR，状态无副作用。
- 无效地址读取同时返回0。ACTION读取返回0/OKAY。
- 同周期**寄存器层请求握手**读写同一普通寄存器，读到写入前的值。
  AXI外部AW/AR同时到达不等于内部同周期生效。
- START时锁存输入和CMD_SEQ并置BUSY；仅允许非零且大于ACCEPT_SEQ的序号。
- BUSY或DONE未ACK时拒绝START。最大序号0xFFFFFFFF之后必须重载/复位，
  驱动不自动触发复位。相同序号不再次执行。
- 寄存器测试执行器固定等待16个执行周期再产生结果，便于验证BUSY，
  不将此诊断延迟用作产品性能承诺。
- 完成时更新TEST_RESULT/DONE_SEQ/EXEC_COUNT并置DONE、清BUSY。
  结果先于软件观察DONE可见，DONE一直保持至ACK。
- 复位清除挂起AXI事务和执行状态。软件只在停止访问后重载Overlay。
  复位中断的命令不续跑、不自动重发。
- 总线访问错误通过BRESP/RRESP报告，不写ERROR_CODE，以满足错误访问无副作用。

## 可复用内部接口

写请求：wr_valid/wr_ready、wr_addr[11:0]、wr_data[31:0]、wr_strb[3:0]。
写响应：wr_rsp_valid/wr_rsp_ready、wr_rsp[1:0]。
读请求：rd_valid/rd_ready、rd_addr[11:0]。
读响应：rd_rsp_valid/rd_rsp_ready、rd_data[31:0]、rd_rsp[1:0]。

请求或响应VALID成立后，其负载保持到READY握手。AXI协议层不检查寄存器地址或命令。
寄存器层通过exec_start、exec_input[31:0]和exec_done、exec_result[31:0]连接执行器。
exec_start/exec_done均为同一控制时钟域的单周期脉冲。
更换业务执行器时保留协议层；跨时钟属于后续设计，不直接跨接这些脉冲。

## PYNQ访问顺序

PYNQ Overlay解析HWH，OrderedMMIO持有设备映射，通过ARM C函数读写32位数据。
C访问前后执行DSB SY，并带编译器memory clobber。
不把普通NumPy内存当设备映射；本期不对BRAM提供伪接口。

execute：检查READY/序号 -> 写TEST_INPUT -> 写CMD_SEQ -> START -> 有界轮询DONE
-> 检查ACCEPT_SEQ/DONE_SEQ/结果/计数 -> ACK -> 检查READY。
任一步提交后失败锁住驱动，不自动重发或清理未知状态。
软件重复提交检查不等价于板端SLVERR测试；SLVERR由RTL仿真验收。

## 第二阶段已确定但尚未启用的接口

BRAM 4096B：输入0x000–0x7FF、输出0x800–0xFFF；长度1..2048B。
32位TDP端口、4路字节使能，控制器只占A口、PL使用B口。
增加OPCODE、BYTE_LEN、DONE_LEN和CAPS bit1；现有寄存器偏移保持不变。
尾字仅写有效字节；不得破坏相邻哨兵字节。完成前PS不修改输入。
进入第二阶段时补齐可执行ABI与驱动，并单独验收。

