# 手势模型开发环境：Windows x64 / Python 3.12 / CPU

此目录维护长期可复用的环境定义、固定启动入口和离线重建脚本。开发环境不使用系统site-packages，不依赖终端激活状态，不自动更新依赖。

## 固定入口

在PowerShell中运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/3_host/model_env/run_python.ps1 -c "import sys,torch; print(sys.executable); print(torch.__version__)"
```

基线解释器：`E:/competition/4_metrics/logs/2026-09-12_model_env_run01/venv/Scripts/python.exe`。

根据项目证据路径规则，环境、wheel安装包和运行日志统一保留于上述基线目录。该目录是长期保留的环境资产，不能按普通临时日志清理；`run_python.ps1`提供稳定入口。虚拟环境不要直接跨机器复制或移动，应重新创建。

VS Code等编辑器选择上述基线解释器。GPU/CUDA/NPU加速应另建环境，先验证再切换，不在CPU基线上直接升级。

## 固定版本

- CPython 3.12.10，Windows AMD64。
- Ultralytics 8.4.142，与队友MODEL.md记录一致。
- PyTorch 2.10.0+cpu / torchvision 0.25.0+cpu。
- NumPy 2.2.6 / OpenCV 4.12.0.88。
- ONNX 1.20.1 / ONNX Runtime 1.23.2。
- pip 25.0.1；其他间接依赖以`requirements-win-py312-cpu.lock`为准。

`requirements.in`只用于解释初次版本选择，不用于日常重建。所有依赖的版本与具体wheel的SHA256均锁定在`.lock`文件中。该锁只用于Windows x64 CPython 3.12，不宣称跨操作系统复现。

## 离线重建

前提：本机安装CPython 3.12.10 AMD64，并保留基线`wheelhouse`与锁定清单。`-BasePython`可指向另一台机器安装的同版本解释器。

基线目录同时归档`python-3.12.10-amd64.exe`，来自python.org，已验证Python Software Foundation的有效数字签名；安装器SHA256见`python_installer.json`。本轮没有执行安装器或更改系统Python。跨机器恢复时先安装该版本，再运行重建脚本。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File E:/competition/3_host/model_env/rebuild_environment.ps1 -EvidenceDir E:/competition/4_metrics/logs/2026-09-12_model_env_rebuild_run02
```

必须指定新的运行目录。脚本拒绝覆盖已有目录，使用`--no-index --require-hashes --only-binary=:all:`安装，随后执行`pip check`和环境冒烟检查。再次重建请使用新的run编号。缺失wheel、哈希不一致、版本冲突、DLL加载失败、模型哈希/张量不符均停止，不通过换源、取消哈希、修改模型或使用系统包绕过。

重建成功后若要将新环境设为长期入口，应审查验证结果并更新`run_python.ps1`的基线路径；旧环境保留至切换验收完成。

## 验证范围

`verify_environment.py`检查独立解释器、导入依赖、CPU后端、torchvision NMS本地算子、ONNX结构、模型SHA256、7类标签、输入输出形状、合成图像的前后处理和有限数值输出。使用合成数据，不打开摄像头。

`MODEL_ENV_SMOKE_PASS`仅表示环境和基本执行链路可用；不代表手势识别精度、PT/ONNX数值等价、实时性能或目标AI PC适配通过。摄像头验证由后续阶段单独执行。

完整证据和安装来源：`E:/competition/4_metrics/logs/2026-09-12_model_env_run01/`中的下载日志、wheel_manifest.json、install_report.json、environment_check.json与REPORT.md。

2026-09-12验收：主环境检查通过；最终离线重建在`E:/competition/4_metrics/logs/2026-09-12_model_env_rebuild_run02`通过。首次检查发现Ultralytics配置目录未预建导致回退，现已修复并增加路径断言。最终一致性结果见`final_audit.json`。50个wheel共287511546字节，需与Python安装器一起纳入本地备份；Git仅保留脚本、锁定清单和精选证据。

PyTorch/torchvision配对来源：https://pytorch.org/get-started/previous-versions/ 。安装锁定方式参考：https://pip.pypa.io/en/stable/topics/repeatable-installs/ 。Ultralytics指定版本元数据：https://pypi.org/pypi/ultralytics/8.4.142/json 。
