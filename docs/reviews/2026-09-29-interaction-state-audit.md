# EdgeStash 交互状态与边缘状态复查

日期：2026-09-29。范围：当前未提交工作区，接续 9 月 23 日的状态机审查。
以 `docs/contracts/edgestash.md`、`docs/contracts/screen-set-and-window-life.md`
和 `docs/contracts/behavior-grammar.md` 为行为依据。源码与无界面测试能证明策略和调用路径；
不能代替真实 AX、Dock、Space 或多显示器的体感验证。

## 本次修复

| 场景 | 发现与修复 | 证据 |
|---|---|---|
| 重复显示器观察与恢复失败 | 同一待恢复目标被每次新观察立即重试，提前耗尽本应在 1/2/4 秒执行的预算。`beginApplication` 现在保留相同目标但不提前返回它，定时重试仍由 `retryRestoration` 执行。 | `ScreenSetRestorationRetry`；20 次重复观察和三次定时失败的边界测试 |
| 重复观察与稳定窗口 | 原协调器除 `increment` 外会刷新所有在场窗口；相同观察也反复发 AX frame/alpha/minimize 写入。现在只在显示器 frame、scale 或边缘邻接策略实际变化时要求刷新；被取消的会话仍通过 `needsScreenSetRepair` 修复。 | `ScreenSetMemoryCoordinator.transition`；相同观察的无刷新断言 |
| 悬停接缝失败与一次性说明 | Space 准备或最终校验失败会从 `failSharedReveal` 自动弹提示，包括悬停和 0.5 秒轮询路径。这既会打断鼠标流，也提前消耗“点击禁用接缝标记才解释”的一次机会。失败仍禁用标记，但说明只由标记点击触发。 | `StashSession.failSharedReveal`、`StashMarkerWindow.mouseDown`；展示入口结构检查 |
| 多应用显示所有窗口 | Owned activation 原先只保存全局最后一个 bundle；A、B 连续展开时，A 的异步激活回调可被误判为 Dock/Cmd-Tab。现在按 bundle 分开记录并一次性消费。 | `OwnedActivationLedger`；交错回调测试 |
| 折叠后的焦点归还 | 0.3 秒延迟期间用户若已切到别的应用，旧回调仍会激活记住的应用。现在仅在本次受控应用仍是前台时归还焦点，跳过时清掉旧记忆。 | `FocusReturnPolicy.shouldReturnFocus`；前台未变／已变的边界测试 |

## 2026-09-30 评审后修复

- 恢复重试现在为每个失败目标保存到期时间。重复显示器观察沿用剩余时间，最短计时器触发时只重试已到期目标；交错的 1 秒和 4 秒目标有独立边界断言。
- 已收起窗口先识别目标屏幕，再判定重新隐藏、换边或退出。跨屏隐藏窄边要求与目标屏幕有正宽度交集，避免把刚好贴边的窗口误判为跨屏。
- 使用 15.5 SDK 和临时 SwiftPM 沙箱参数的完整 expectation check 通过；本机只有 Command Line Tools，Xcode 工程 Debug 构建仍无法运行，也未做真实多屏 AX 复核。

## 仍需处理的缺口（按体验影响排序）

1. **多窗口连续操作仍共用一个焦点记忆。** `StashFocusReturn.rememberedPID` 是全局单值；同一批多应用展开／折叠可互相覆盖，多个延迟回调也只有第一个能消费记忆。新增的前台门闩防止抢掉用户后来的切换，但不保证“显示所有窗口”后每个窗口都按预期归还焦点。应在真机明确批量操作的焦点规则，再按操作批次管理。
2. **“显示所有窗口”输入覆盖不完整。** 运行时只监听 Control-Up/Control-Down 键。触控板手势、独立 Mission Control 键和 Dock 的“显示所有窗口”没有可靠识别路径；契约却要求这些入口打开对应 stash。需要先记录系统实际事件/AX 身份，再接入，避免把普通 Space 切换误判为 show-all。位置：`StashEngine.observeShowAllKeys`、`ShowAllWindowsKeyPolicy`。
3. **Dock 缩略图目标不确定。** `StashDock` 读取标题，`StashEngine.applyActivation` 在同应用中取第一个同标题 collapsed 会话。同名文档/Terminal 窗口会打开错的 stash；Dock 点击与应用激活的先后也未在真机覆盖。位置：`StashDock.hit`、`StashEngine.applyActivation`。
4. **快捷键范围与接受的契约不一致。** 契约说应用 stash 快捷键处理该应用每个已收纳窗口；目前只要发现任何 idle 窗口，`handleAppShortcut` 会先收纳一个 idle 窗口并直接返回，即使有已收纳窗口。逻辑测试明确维护了这一行为，但合同没有写出这个优先级。需由 owner 决定快捷键应优先操作已收纳集合，还是更新契约，把“当前桌面窗口先被收纳”的行为明确呈现给用户。
5. **局部接缝刷新仍偏粗。** 目前 `ScreenSetMemoryCoordinator` 用整条边的邻接策略决定 `refresh`；一个新显示器只接触该边的一小段，也可能刷新同边其他不相交的窗口。真实隐藏策略已经按窗口纵向区间判断，刷新判定也应使用会话 frame。稳定窗口的多余 AX 写入会表现为轻微跳动。

## 需要真机事件序列的边界

- 接缝反复展开／离开／再次展开、Space 改变与 deminimize 同时发生、全屏禁用标记、以及 AX 拒绝 frame 或 minimize 的补偿路径。
- 插屏、拔屏、合盖、纯显示器熄灭和镜像来回；特别记录系统通知、枚举快照、重试 deadline、每个窗口最终 AX frame/minimized/alpha。
- Cmd-\` 是否跳过透明停边窗口；当前没有键盘循环拦截，也没有原生验证。
- owner 的玻璃轨和焦点感受复核。无界面逻辑检查不会证明透明边唇无像素、标记可触达或动画连贯。

## 验证状态

- 展示入口结构检查：12 个入口全部已声明；仍只有 1 项有可执行次数证据，11 项是 `structural-only`。
- 完整 `./scripts/check-expectations.sh` 通过：使用 `MacOSX15.5.sdk`，并通过临时 PATH wrapper 给 SwiftPM 加 `--disable-sandbox`，以避开当前执行环境的嵌套沙箱限制。没有改动仓库脚本。单独运行的逻辑套件也通过。
- 直接运行该脚本在这台机器上不能完成行为部分：SwiftPM 嵌套沙箱被拒，默认 26.0 SDK 与本机 CLT Swift 编译器版本不匹配。该失败属于工具链环境，不是行为测试断言。
- 原生 Debug 编译尝试使用 15.5 SDK，但缺少 `NSGlassEffectView`；本机没有完整 Xcode。Xcode 工程 Debug gate 仍开放。这不是本次逻辑测试失败。
- 未做真实 AX 或多显示器体感复核；未提交，也未覆盖现有未提交改动。
