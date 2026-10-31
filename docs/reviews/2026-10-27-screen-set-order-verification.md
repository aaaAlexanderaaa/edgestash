---
doc_type: verification
status: complete_with_explicit_scope
authority: informative
verification_status: partial
last_reconciled: 2026-10-27
---

# 多显示器连接顺序：执行验证

Owner 问：熄屏唤醒、显示器插拔的自动恢复，是否忽略了连接顺序可以变化，
而最终显示器组合不变。本次实际执行回放，没有复现“顺序变化损坏最终已配置
组合的收纳成员／显示器／边缘／记忆”。先前回答仅指出缺少覆盖，未先执行验证；
不能将缺少测试直接当作已发现的运行时缺陷或旧故障根因。

没有修改产品运行时代码、等待时间或重试预算。新增回归测试并保存适配器证据。

## 共用策略验证

`Tests/ScreenSetOrderTests.swift` 已加入现有 `EdgeStashLogicTests` 入口，
由 `./scripts/check-expectations.sh` 一起执行。

- **18,432 条三屏往返时间线全部通过。** 三种最终保留单屏、各两种移除和添加
  顺序、64 种中间子集配置组合、8 种中间观察是否单独稳定的组合，以及成功／
  单窗口失败／全部恢复失败三种中间恢复结果。中间可以出现原点平移、排列暂变
  或分辨率变化，穿插 wake 标记。每条最终都回到同一份已配置三屏目标，检查
  完整成员与显示器／边缘相等、所有配置记忆不变，以及后续重复观察没有新的
  restore／release／refresh。
- **1,512 条任意非空子集返回路径全部通过。** 七种已配置最终目标
  （三个单屏、三个双屏、一个三屏），分别经过三个其他非空组合后返回。
- 六种显示器输入排列得到相同完整观察与 fingerprint；唤醒子集宽限的边界
  使用 live 共用策略验证。中间配置故意包含重新分配的窗口和最终应移除的
  额外成员，检查的是完整目标，而非只验证原成员包含于结果。

这些时间线调用实际 `ScreenSetMemoryCoordinator`。窗口写入结果由内存桌面
注入，不能单独证明 AppKit adapter 的调用次序或真实 AX 完成。

## 实际协调器回放

[adapter-replay.swift](evidence/2026-10-27-screen-set-order/adapter-replay.swift)
追加到未经修改的 live `ScreenSetCoordinator.swift` 后编译，执行其真实
apply、finishSettle、finishWake、retryRestoration 等方法。替换的边界是
显示器枚举、session／AX 结果、偏好存储与诊断；不重写协调器的决策。

**61 条时间线、266 项断言全部通过：**

- 48 条往返：两种拔屏顺序 × 两种接回顺序 × 中间配置有／无 × 中间 session
  成功／失败／等待控制 × 普通／wake 应用。最终没有旧目标重试或旧 session
  recovery 残留，完整成员和所有配置记忆一致。
- 10 条 power／settle：显示器熄屏与系统睡眠、空枚举、两种外屏到达顺序、
  中间子集在宽限前／后稳定、通知与 timer 之间再次变化，以及 timer 跨睡眠
  长度延迟。timer 交付和 elapsed 时间戳是注入的，实际决策没有替换。
- 3 条 retry：两个外屏顺序下等待发现的目标恢复，以及一次使用真实墙钟
  1／2／4 秒间隔的写入失败预算。重复观察不消耗预算，成功兄弟窗口不被
  重做，耗尽后保留记忆，后来离开并返回配置可再次恢复。

运行方式（macOS，使用本仓库源码和本地 Swift 工具链）：

```bash
python3 docs/reviews/evidence/2026-10-27-screen-set-order/run-adapter-replay.py
```

结果写到 `.build/screen-set-order-replay/result.json`。本次结果和源码 SHA-256
保存在 [adapter-result.json](evidence/2026-10-27-screen-set-order/adapter-result.json)。

## 验证范围

`./scripts/check-expectations.sh` 通过：12 个展示 anchors 全部声明，完整逻辑
套件通过。展示基数覆盖仍为 1 executable／11 structural-only，未提升其证据等级。

本次验证支持“这些显示器观察／故障时间线最终恢复同一份已配置目标”，
不证明真实硬件返回的显示器身份始终稳定、真实 macOS 27 通知一定属于其中
一种输入，或真实 AX 写入成功。它也没有执行原生 StashSession、真实窗口的
pin／外观／几何恢复或真实物理插拔，不关闭此前的实机验收。
未配置组合的 quiet increment 仍按契约保留现有成员；本次不将所有未配置终点
强行定义成与路径无关的新产品规则。
