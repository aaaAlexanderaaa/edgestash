# 休眠与自动隐藏：Release 诊断包

此前发行包没有完整的休眠、收纳会话与自动收回事件日志，不能回溯安装前的故障。
[v0.1.8 测试版](https://github.com/aaaAlexanderaaa/edgestash/releases/tag/v0.1.8)
提供启动即记录的 app，无需下载独立诊断工具。
本次 0.1.8 (9) 将诊断开关与优化配置分开：

```bash
./scripts/stage-app.sh Release --diagnostics
```

这是使用 Release 优化的诊断包。`dist/CURRENT.txt` 应同时显示
`configuration: Release`、`diagnostics: true`。包内 Info.plist 的
`EdgeStashRuntimeDiagnostics` 在签名前写入；无需终端启动、环境变量或开发工具。
普通 `./scripts/stage-app.sh Release` 关闭诊断，Debug 默认开启。

先退出正在运行的 EdgeStash，再打开 `dist/EdgeStash.app`。传到另一台机器使用
`dist/EdgeStash.zip`，解压后先退出旧进程，再打开新 app。不要仅覆盖磁盘上的 app
而继续使用旧进程。`app.start` 记录版本、build、配置和实际载入 Mach-O 的 UUID，
可识别“磁盘包已换，旧进程仍在运行”。

1. 正常收纳窗口，照平时方式熄屏／休眠并唤醒；无需切换显示器布局。
2. 如果复现，记下大致时间，以及窗口／边缘信号条的状态；可以照常按快捷键。
3. 在 Finder 的“前往文件夹”打开 `~/Library/Logs/EdgeStash/`，复制或压缩整个
   文件夹提供分析。请及时复制，长期运行会轮换覆盖较早记录。

文件是逐行 JSON：`runtime.jsonl`、`runtime.previous.jsonl`，各最多 2 MiB，总计
约 4 MiB。跨启动保留；每条有墙上时间、uptime、EdgeStash 的 PID 与本次 run ID。
目录权限 0700，新文件 0600。写入使用串行 utility 队列，退出时排空队列；不依赖
Console 是否开启。磁盘写入失败只在系统日志提示一次；缺日志不证明没收到事件。

## 能区分的路径

| 事件 | 用途 |
|---|---|
| `workspace.*` / `power.*` / `screens.*` | 系统睡眠和屏幕电源分别记录；同布局唤醒、显示稳定判定、恢复计划与重试 |
| `session.role-check-failed` / `ax.failure` | AX 错误码与目标引用；错误不再直接当作窗口死亡 |
| `session.control-wait` / `session.binding-check` / `session.control-rebound` | 原引用不可用、枚举成功或失败／是否读全、精确候选数、服务器归属、原／当前进程启动时间、等待或重绑 |
| `session.stale-ax-callback` | 老引用或老环境的迟到通知被拒绝；binding/lifecycle generation 也在会话快照中 |
| `session.recovery-observed` / `session.recovery-unchanged` | 写入前的 frame/minimized/alpha；健康窗口跳过写入 |
| `session.recovery-readback` | 实际写后观测是否符合目标；API 返回成功不单独作为修复成功 |
| `session.restore-result` / `session.refresh-result` / `session.retry-result` | succeeded、waitingForControl 或 failed；remainingAttempts 是剩余写入次数，成功移出队列后为 -1 |
| `session.scatter-fallback` / `session.fallback-waits-for-control` | 可见桌面回退，或引用尚未验证而暂缓回退；恢复意图与 idle 外观分开 |
| `session.recovery-exhausted` | 首次加三次实际恢复写入均失败，停止自动写入，保留可用回退与原目标 |
| `session.shutdown` / `session.shutdown-result` / `memory.forget` | 解除收纳的真实原因、可见性恢复结果、是否删除记忆 |
| `session.leave-gate` / `session.auto-collapse` | 离开自动收回的阻挡原因变化与尝试；0.1 秒观察不逐帧刷日志 |
| `shortcut.*` | 按键当时 idle/collapsed/expanded 数量，以及是否重新收纳了 idle 窗口 |
| `engine.trust-lost` / `engine.start` / `app.start` / `app.stop` | 权限暂停与恢复、EdgeStash 本身是否重新启动；缺 stop 本身不能确定崩溃原因 |

`ax.slow` 记录超过 0.25 秒的调用；只改变记录，不改变 AX timeout。
相同目标／操作／属性／错误码最多每 5 秒一条。普通快速成功调用不逐帧输出。
会话快照记录原应用 PID、进程启动时间、窗口编号、收纳几何、pin、隐藏方式、
leave watcher、恢复与引用代次。不采集标题、文件名、文档、键盘输入或像素；
不联网、不自动上传。普通 Release 不求值诊断快照、不创建诊断目录。

## 修复边界与验证

本次删除“AX 引用无效即全局忘记窗口”的路径；精确身份不明则保留意图并等待。
已核对的新引用接回同一个窗口，不新建 idle 副本。销毁需进程死亡、归属已变，
或销毁通知加完整成功枚举与服务器缺席的交叉证据。进程元数据暂缺不当作已退出。真正关闭／禁用仍清理记忆。
同布局唤醒先观察健康状态，原来展开且未固定的窗口恢复离开 watcher；失败回退
保留原位置／展开／pin。原有 5 秒发现循环恢复可读后唤醒同一预算，不能无限重写。
实际拖走或重新收纳会取消旧目标，休眠前／旧绑定的迟到操作不能覆盖新状态。

真实权限撤销仍停止引擎；EdgeStash 退出／崩溃后的 fresh 规则仍不复活收纳成员。
新的 start/run/UUID 证据用于区分这些情况，不能仅凭相似症状声称现场原因已确认。
完整 Xcode 不在本机，CLT 原生构建不替代 Xcode 工程 gate；真实 macOS 27
多屏休眠验收仍需使用本次 Release 包。完整验证记录见
`docs/reviews/2026-10-22-sleep-wake-recovery-research.md`。
