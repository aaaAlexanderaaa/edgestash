# 2026-10-20 — WindowServer 持续占用调查

状态：发现上一轮验证遗漏的机制，已交付现场诊断；macOS 27 三屏故障尚未定位到
唯一根因，未发布“已修复”版本。

Owner 现场：最新 Release 0.1.6，macOS 27，三个显示器，多个窗口正在收纳，
WindowServer 持续高占用；具体触发时刻尚不明确。

## 已有修复为什么不足以关闭问题

`a6e0379`（0.1.5）合并同一轮查询并跳过未变化的面板重绘、frame、alpha、排序
写入；0.1.6 保留了这些修复。原生 unchanged probe 证明重复适配器调用没有多余
写入，但没有测量目标系统的合成成本，也没有证明被收纳应用已经停止图形更新。
0.1.6 的 Nudge/Fade 改变过渡过程，没有改变最终外侧隐藏位置和零透明度。

因此，“EdgeStash 自己低 CPU”“没有重复 needsDisplay”“逻辑测试通过”都不能
证明这次用户报告已经解决。

## 新的原生证据：零透明度仍是可见窗口

独立探针只创建和操作自己的一个 AppKit 窗口。每个状态静置 1.5 秒，核对最终
实际 frame，读取窗口自己的 `occlusionState` 和 WindowServer 元数据；不读取
像素，不操作其他应用窗口。

本机 macOS 15.7.9、单屏 1920×1080@60Hz 的结果：

| 状态 | 实际位置符合实验 | occlusion visible | 元数据 on-screen 标志 |
|---|---|---|---|
| 仅 2pt 留在屏内，CGS alpha=0 | 是 | 是 | 是 |
| 同一位置，AppKit alpha=0 | 是 | 是 | 是 |
| 完全移出所有显示器，alpha=1 | 是 | 否 | 是 |
| 完全移出所有显示器，alpha=0 | 是 | 否 | 是 |
| orderOut | 是 | 否 | 否 |
| 系统最小化 | 是 | 否 | 否 |

原始证据：[occlusion-macos15.json](evidence/2026-10-20-windowserver/occlusion-macos15.json)。
探针源码：[WindowServerDiagnostic.swift](../../scripts/WindowServerDiagnostic.swift)。

实验首先遇到 AppKit 将标题栏约束回屏内的问题。最终探针显式重写自有窗口的
`constrainFrameRect`，并为每个状态输出 expected/actual frame 和 geometryMatches。
表中只使用修正后的结果；第一次定位错误的试验不构成 2pt/完全屏外证据。

这与 Apple 的公开定义一致：全透明窗口也可能被判定为可见；应用应在自己的
窗口真正被遮挡时停止无用工作。[NSWindow.OcclusionState.visible](https://developer.apple.com/documentation/appkit/nswindow/occlusionstate-swift.struct/visible)，
[Notify Your App When Visibility Changes](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/WorkWhenVisible.html)。

**推断，尚非用户现场因果证明：** 当前外侧隐藏保留 2pt 几何 lip。即便视觉上
完全隐藏，依赖遮挡状态节流的应用仍可能继续工作、提交图形更新；窗口数量增加
时成本可能放大。零透明度也没有公开的“WindowServer 零成本”保证。
这个实验既没有测量其他应用窗口的渲染提交，也没有证明 macOS 27 与本机行为相同。
元数据 on-screen 标志尤其不能代替遮挡状态或逐帧合成证据。

## 本地 CPU 对照的适用范围

开发机运行中的 EdgeStash 实际为 0.1.5（线程采样头部），启动于 10 月 15 日；
磁盘文件已经被 0.1.6 替换。只读 `Info.plist` 会误把旧进程当成新版。
现场诊断同时记录启动时间、磁盘版本和 executableChangedSinceLaunch，并保存
线程采样供复核。

本机没有救援记录或桌面收纳信号窗，仅有 Settings 和菜单栏窗口。
5 秒采样中主线程一直在事件循环等待，没有观察到活动 display link。
一次 4 秒 × 3 阶段的 WindowServer 区间 CPU 为：

| 正常运行 | EdgeStash SIGSTOP 期间 | 恢复运行 |
|---|---|---|
| 36.7% | 37.9% | 36.7% |

暂停区间每次观测 EdgeStash 均为 `T`，CPU 时间未增长；恢复后为 `S`。
计数来自累计 CPU 时间差 / 单调经过时间，100% 表示一个核。
[正常](evidence/2026-10-20-windowserver/developer-baseline.json)、
[暂停](evidence/2026-10-20-windowserver/developer-engine-paused.json)、
[恢复](evidence/2026-10-20-windowserver/developer-resumed.json)。

这验证诊断方法能区分进程执行，并说明开发机本身存在其他显示负载。它没有复现
owner 的收纳场景，不能排除或证实 EdgeStash 在目标机器上的任何隐藏路径。
暂停进程也不会移除其静态面板，或停止已经交给系统执行的动画。

## 代码审查与当前排查优先级

| 方向 | 已知事实 | 仍需什么证据 |
|---|---|---|
| 外侧透明窗口继续被当作可见 | `visualHiddenOrigin` 保留 lip，collapse 完成检查 alpha=0；原生探针显示该状态仍可见 | 在 macOS 27 上区分外侧/接缝并控制应用内容；记录客户端提交及 WindowServer 栈/图形轨道 |
| 静态信号窗影响系统合成 | 细 rail/merge 自绘，固定 mainMenu/all-Spaces 面板；只有 Glass pin 可使用系统玻璃 | 不能从面板自身无重绘推断合成免费；需要相同客户端更新条件下的有/无面板对照 |
| 后台观察或窗口反馈循环 | 每 5 秒发现；每 0.5 秒 seam 检查；每轮 Space 查询按显示器合并，但每个 seam 窗口仍有 AX 检查 | macOS 27 异常现场的暂停/恢复对照和调用栈；现有 query-count 测试不覆盖系统调用成本 |
| 展开窗口的 leave watch | 0.1 秒定时器只在展开时工作，可能查 AX frame、窗口列表与 sibling focus；collapse 会失效它 | 故障现场是否仍有展开/固定窗口，以及是否有高频异步几何反馈 |
| 全屏 sheen 面板 | 仅画 5×220pt，但面板设为屏幕大小；0.42 秒内 orderOut 并移除 sublayers | 这是过渡期成本/资源方向，正常清理下不足以解释持续空闲 CPU；不能当成已找到根因 |

`StashAnimator` 在 begin 才创建 display link，finish/cancel 停止它；没有发现代码
明示的空闲动画时钟。Space poll 不会主动搬迁窗口；迁移只属于命名 reveal。
鼠标移动另有 seam approach 路径，其成本必须与真正静止时分开观察。

这轮没有改变隐藏、Space、激活或材质行为。尤其没有复活被否决的接缝 clipped
slide；没有把外侧收纳静默改成系统最小化。完全屏外值得做后续受控实验，但会
涉及位置约束、显示归属、Space 可达性、外部几何修复与救援；现有 2pt 规则不能
只改一个常量就删除。产品行为变更仍需当前或 owner 接受的目标契约。

## 现场工具和下一条证据

[使用说明](../windowserver-diagnostic.md)。
独立工具不链接进产品，不改偏好，不请求 AX/录屏权限，不读取窗口标题或内容，
不联网。打包后的 Apple Silicon 二进制可在没有 CLT 的机器上运行。

1. 保持三屏和当前多个收纳窗口，在高占用仍持续时运行诊断包。
2. 获得 12 秒正常 / 12 秒暂停 EdgeStash / 12 秒恢复对照、对应进程采样、
   前后窗口/显示器元数据。救援匹配的应用主进程也计入 CPU 样本，渲染辅助
   进程和 GPU 活动仍需另外调查。
3. 同包执行自有窗口遮挡探针，确认 macOS 27 的机制观测；它不改真实收纳窗口。
4. 若暂停/恢复没有可重复差异，再在相同显示配置和同一应用静止内容下，
   分别只保留外侧或接缝收纳并增加数量。退出前后数据同时改变窗口/内容状态，
   不能单独归因于信号窗。
5. 必要时在异常持续时取得 WindowServer 线程采样，以及 Instruments 的
   CPU/GPU 图形时间线。Apple 的 [Metal developer workflows](https://developer.apple.com/documentation/xcode/metal-developer-workflows)
   说明 Metal System Trace 可关联 CPU/GPU 与内存；本轮普通 CPU 诊断没有
   测量 CA commits、Metal presents 或 GPU 时间。

本机缺少完整 Xcode；WindowServer 属于系统用户，普通 `sample` 权限不足，
`sudo -n sample` 提示需要密码，未取得系统线程栈。工具不会索取或保存密码，
也不会终止 WindowServer。目标环境数据是下一步定位所需的实际缺口。

## 辅助调查和验证

chatgptbox 已完成通用 AppKit 机制咨询。含项目内部背景的第一条请求被自动审批
拒绝，未据此向外发送内部背景；后续问题只询问公开 API 语义和通用实验方法。
其意见用于交叉检查，具体事实仍以本地原生观测和 Apple 一手资料为准。

- 独立原生 helper 编译成功；完整诊断流程、几何核对、实际停止/恢复通过。
- 暂停期间向脚本发送 SIGTERM，脚本以 143 退出，EdgeStash 恢复为 `S`，通过。
  独立 watchdog 另绑定 PID/启动时间，以防脚本本身被强杀。
- Shell 语法和 `git diff --check` 通过。
- `./scripts/check-expectations.sh` 通过：12 个 presentation anchors，
  1 项 executable cardinality、11 项 structural-only，完整逻辑测试通过。
  首次受限运行被 SwiftPM 缓存/子沙箱阻止，使用正常本机权限重跑后通过；
  没有修改语法契约来掩盖工具环境失败。
- 产品窗口行为没有改变；发布准备将应用版本同步为 0.1.7（build 8）。
- `stage-app.sh Debug` 和 `stage-app.sh Release` 的 Apple Command Line Tools
  构建通过，最终本地包为 Release。完整 Xcode 未安装，Xcode 工程 Debug
  验证仍待完成；CLT 构建不关闭该项。
- `python3 scripts/check-distribution-tooling.py` 的七项发布工具测试通过。
- 应用与独立诊断 ZIP 均通过解压内容比对、签名完整性、arm64 架构与
  macOS 12 最低版本核对；应用包版本为 0.1.7（build 8）。
- 独立复核使用一次性自有进程验证 SIGTERM 退出清理与 SIGKILL 后 watchdog
  恢复，均通过；该验证不操作用户的收纳窗口。
- 本次沿用已有版本的 ad-hoc 签名；Developer ID 签名、公证与 Homebrew
  安装仍待凭据配置。0.1.7 提供诊断工具，不宣称 macOS 27 三屏问题已修复。
