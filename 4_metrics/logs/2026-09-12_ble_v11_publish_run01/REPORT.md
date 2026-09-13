# BLE Console v1.1 与用户双向复现确认：发布范围

用户要求：更新相关文件、日志并上传自己的分支。
目标：codex/full/pipidandan-superman；已有 PR #5，base=main。不直接push/合并main。

## 原因与范围

将已验证的未配对 GATT 接入流程同步到实际GUI，避免仅连接返回成功便宣称链路可用；
增加三次无缓存读取/保持门控、自动通知、异常/取消处理，并解释TX和HEX旁文本预览。
本次同时记录用户明确反馈“OK，双向通信成功”。

- 3_host/ble_console：v1.1源码、配置、构建入口、31项离线/Tk测试、操作说明。
- 1_docs/doc：方案v1.2（只更新状态，不改变CSR/BRAM设计及正式B0/B1/B2门槛）、
  蓝牙状态/复现；README与HANDOFF新增最新入口。
- 7_logs/2026-09-12：在原精选发布四份日记顶部增补v1.1和手动确认，
  不用摘要覆盖本机完整多任务日记。
- selected_copy_paths.txt 明确列出源工作区复制项。HANDOFF和日记只在发布worktree
  定点增补，保留该分支其他内容；.gitattributes新增仅本次证据的字节保留规则。

## 验证及边界

本次发布worktree回归：[unit_tests.txt](unit_tests.txt)，31项通过；
44个内容文件的范围/凭据模式/8个关键入口/三轮双向原始字节审计通过。
最终提交另外包含本次回归输出，共45个变更文件。精确暂存清单、哈希及
BLE_V11_PUBLICATION_AUDIT_PASS回执保存在本机发布run，未混入无关文件。

- 既有v1.1交付：31项离线/Tk测试、独立EXE自检通过；
  新后端三轮双向各18字节、ready后60.5秒保持、最终无缓存读取通过。
- 实际发布EXE按钮：TX55AA3132→COM4收到相同数据，
  COM4写AA553231→EXE RX NOTIFY收到相同数据。
- 用户另行手动确认通过；未提供新的完整原始收发日志，不新增轮数、误码率或时长。
- 首次未广播失败保留：用户确认当时未上电/未下载，重新上电后复测通过。
- 本次上传只做源码离线回归/文件与证据审查，没有重新板测或改变设备状态。
- 长期压力、每方向1000帧、CRC/分片、十分钟并行、重连/复位、
  MLT主机/BT24机械臂互通及正式AXI/BRAM控制仍未验收。

证据入口：
[构建与原始验证](../2026-09-12_ble_console_v11_run01/REPORT.md)、
[新版后端/实际EXE收发](../2026-09-12_ble_console_v11_board_run02/REPORT.md)、
[用户确认](../2026-09-12_ble_manual_confirmation_run01/REPORT.md)。

## 明确排除与本地资产

不上传PIN采集、配对截图、周边设备扫描日志、缓存/venv/wheelhouse、生成Vivado树、
bit/ltx、EXE/DLL/_internal依赖树、原工作区无关改动。本次不上传新的二进制文件。
原始run报告中的完整本地包/截图/其他未列入清单文件是**本地证据引用**，
不是声称全部原件随Git上传；决定性字节事件、控制台记录、结果和脚本已精选上传。
构建时的source_final_hashes.json是当时快照，随后本次只增加文档解释；
本轮文件哈希由copy_manifest.json与Git提交记录。

本地EXE：8_tools/EES331_BLE_Console_v1.1/EES331_BLE_Console.exe，
SHA-256 82BDD94C77F2090A4A4086EB10D6706443BDE21E216B02AB93A87DD5E0C93381。
旧v1.0完整保留作为工具回退；冻结视频/FPGA BIT/XSA/ELF/source完全不改。
后续若需要再次构建，必须新BuildRun和空发布目标，不覆盖已有发布包。

## 发布与恢复

原 E:/competition 保持原有脏工作区；已有个人分支worktree只显式暂存本任务文件，
4个原有未跟踪历史文件不动。原main是个人分支祖先，不需要重复合并。
普通push、不force。已有PR用于审阅，新提交不是main验收。
本报告为推送前的范围声明；实际远端SHA、ahead/behind及PR回执由本机
push_receipt.json/pr_after.json确认，不能仅凭本报告认定推送成功。
