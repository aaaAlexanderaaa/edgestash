# WindowServer 本地诊断

适用于仍有多个窗口收纳、WindowServer 持续占用的现场。它是独立诊断工具，
不是修复版 EdgeStash。保留当前场景，不需要退出 EdgeStash。

解压 `WindowServerDiagnostic.zip`，双击 `Run Diagnostic.command`，约 50 秒完成。
各测量阶段请停止操作鼠标、键盘，保持显示器、Space、其他应用和播放内容不变。
第二阶段暂停 EdgeStash 约 12 秒，此时收纳交互暂不可用，随后自动恢复。
工具有退出清理和独立恢复看门狗；不修改偏好、收纳位置或其他应用窗口。

输出在桌面 `EdgeStash-WindowServer-日期-时间` 文件夹。没有自动上传，
不请求屏幕录制或辅助功能权限，不读取窗口标题或像素。结果包括显示器逻辑尺寸、
像素尺寸、刷新率、窗口编号/几何/透明度、收纳应用标识、CPU 区间测量、
EdgeStash 线程采样；线程采样可能含本机路径。请提供整个文件夹用于对照。

从仓库运行（需要 Apple Command Line Tools）：

```bash
./scripts/diagnose-windowserver.sh --pause-engine --occlusion-probe
```

打包无需开发工具的 Apple Silicon 版本：

```bash
./scripts/stage-windowserver-diagnostic.sh
```

## 如何读结果

`baseline.json`、`engine-paused.json`、`resumed.json` 记录累计进程 CPU 时间
的差值除以单调时钟的经过时间，100% 表示占用一个 CPU 核。它不是 `ps %cpu`
的长期衰减值。每两秒记录一个区间，同时记录进程状态。暂停区间应当是 `T`。
短区间波动很大，需要多次同场景复测，不能拿一个下降数值当因果结论。
同时测量救援记录匹配的应用主进程；其渲染辅助进程和 GPU 工作不在这个 CPU
计数里，所以主进程低占用也不能排除该应用仍在提交图形更新。

- 暂停后持续下降、恢复后重现：优先检查 EdgeStash 持续执行的查询、写入和动画。
- 暂停后保持高占用：持续的主进程执行不足以解释负载；静态信号窗、其他应用
  仍在提交帧、系统显示合成等都还没有排除。暂停主进程不会移除它留下的面板。
  已经提交给系统的 Core Animation 动画也可能继续执行。
- `before.json` / `after.json` 区分显示器配置、EdgeStash 面板和救援记录对应的
  候选窗口。救援记录不等于活跃会话，缺少元数据不等于已最小化。
- `EdgeStash.sample.txt` 的头部帮助核实正在运行的版本。磁盘版本和进程已加载的
  版本可能不同；替换 app 文件不能证明旧进程已经重启。
- `occlusion-probe.json` 只控制诊断工具自己的临时窗口。它对照零透明度的 2pt
  外侧位置、完全屏外、orderOut 和最小化，并记录实际几何是否符合实验。
  `occlusionVisible` 与 `onScreenListFlag` 是不同观测。这个实验不证明被收纳
  应用会响应遮挡，也不证明真实 WindowServer CPU 的来源。

工具不会取得系统 WindowServer 的线程栈；读取这个系统进程通常需要管理员权限。
若现有对照仍不能定位，可以在异常持续时用“活动监视器”对 WindowServer 执行
“取样进程”，保留报告。不要结束或强制退出 WindowServer。

## 进一步区分隐藏路径与信号窗

先用上述工具获得可重复基线。随后在同一显示器配置分别只收纳一个外侧窗口、
只收纳一个接缝窗口，再增加数量，记录每次结果。使用同一应用和静止内容，
保持 Space、刷新率和其他应用不变。这样才可判断成本是否跟外侧隐藏、
系统最小化、面板数量或显示配置有关。完整退出 EdgeStash 会恢复收纳窗口并
清除会话，不能把退出前后的差值单独解释为“信号条开销”。
