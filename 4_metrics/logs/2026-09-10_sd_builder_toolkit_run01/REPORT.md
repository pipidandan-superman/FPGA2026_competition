# EES-331 XSA SD Builder 0.1 交付记录

## 结果

Windows GUI原型、后端和可双击EXE已完成。用户新增“必须提供包含比特流的 XSA”已作为强制输入规则实现。程序可导出配套SD启动ZIP和完整IMG，不直接写卡。

EXE：`distribution/EES331SDBootBuilder.exe`。使用说明：`E:/competition/3_host/pynq/sd_boot_builder/README.md`。生产源码：同目录 app.py / builder.py / hardware.py / images.py / fdt_reader.py / assets。

## 已完成验证

| 测试 | 结果与证据 |
|---|---|
| 10项输入/GUI测试 | tests_console.txt：10 tests，OK；含缺bit、错误器件、错误UART管脚、截断bit拒绝，FCLK与USB差异分类、DTB使能匹配、GUI创建 |
| 当前XSA预检 | inspect_reference.json：xc7z020clg484-1，XSA SHA b3343e2161fdfc4aa744a211e65059346ae48e0f7ea5f1b41b945e4f9124576a，bit/hwh均存在，PS无变化 |
| 手动加载模式真实构建 | ../2026-09-10_sd_builder_165549_b92f74/output；BOOT/FIT/ZIP完成。后续增加了发布目录暂存机制，此早期run未包含该机制 |
| 从XSA生成平台/BSP | test_generate_fsbl_console.txt：SD_BUILDER_PLATFORM_GENERATED；明确proc/os后不再出现旧default-domain-empty错误 |
| FSBL重建＋Linux自动加载＋完整IMG | ../2026-09-10_sd_builder_165718_5e2d15/output/result.json：SD_PACKAGE_STATIC_PASS；fsbl_provenance.json证明从输入XSA重建；IMG完整读回PASS，7858807808字节 |
| 上述测试IMG SHA256 | 8673ef8329d2a6ad7dec4a70f5138fdd1d53e5b04a98cb45c8b68d3ee4e119c5；这是工具测试生成的Linux自动加载版本，不替代此前已板测的手工修复版本 |
| FSBL阶段加载PL | ../2026-09-10_sd_builder_170008_760643：4分区BOOT打包通过，输入bit载荷及其字序转换与BOOT中的PL载荷比对通过 |
| EXE打包 | pyinstaller_console.txt：完成，distribution/EES331SDBootBuilder.exe |
| EXE GUI/依赖自检 | frozen_self_test.json：FROZEN_GUI_SELF_TEST_PASS，pyfatfs1.1.0、fs2.4.16 |
| EXE真实XSA构建 | frozen_build_config.json.result.json；../2026-09-10_sd_builder_170040_95e111/output：成功；验证不依赖源码形式启动 |

输出文件哈希记录在delivery_manifest.json。没有本轮新XSA/自动加载版本板测；软件PASS与硬件PASS严格分开。未写卡，未修改2_fpga冻结工程。

## 能力边界

XSA主要入口和整条文件生成链已落实。第一版是当前EES-331/PYNQ3.0.1/2025.2配置的应用，不是任意XSA自动移植Linux：UART/SD/DDR等不兼容关键配置直接拒绝；影响PS外设的未知变化要求补充适配DTB。FCLK和部分AXI参数变化可走已有板级模板路径。缺内核驱动、PHY外部连线和自定义PL驱动不会自动猜测生成。

支持Linux后PYNQ自动加载、FSBL加载和手动加载三种模式。默认手动加载是明确的界面选项，切换为Linux或FSBL模式才会更改自动加载行为。原版内核与根分区保留；完整IMG输入必须为已知原版镜像。

构建先写.pending-output，所有所选校验成功后才发布output目录；失败保留日志，result标为BUILD_FAILED。toolkit支持Windows本机现装Vitis，EXE内含Python/Tk和板级资产；基础7.86GB镜像与Vitis安装均为外部依赖。

后续若希望所有PS外设变化也只输入一个XSA，就需要逐项建立EES-331板级外设profile（包括PHY复位、USB、时钟、驱动和DT生成规则），并对应真实板测。这是明确的扩展范围，不在当前原型中冒称已自动完成。
