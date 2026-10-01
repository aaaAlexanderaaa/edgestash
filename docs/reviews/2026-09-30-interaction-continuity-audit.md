# EdgeStash 连续交互与边缘状态审查

日期：2026-09-30。基线：`f28109a`，审查开始时工作区干净。
依据：当前产品、本地优先、窗口生命周期、接缝与玻璃轨契约，以及行为 grammar。
接续 9 月 23 日和 9 月 29 日的审查。审查阶段完成源码审查、隔离事件回放和现有检查，
当时未改应用代码或契约。owner 随后要求“帮我修一下”，修复与验证记录在本文末尾；
下面缺陷描述和源码行号记录审查前的基线。这份审查不是产品执行契约，现行规则见 contracts。

主要发现：恢复与显示器记忆已经有较多保护，但鼠标意图、合并条、焦点归还和动画期间的
连续输入没有统一仲裁。一次展开最终成功，不能证明此前的悬停及时，也不能证明后一次
点击得到处理。当前代码确实存在会拖延展开、撤销点击收起和干扰下一轮焦点的路径。
这些问题比单纯调整动画时长更值得先处理。

## 证据范围

- **隔离复现**：运行当前合并协调器原文与真实 Foundation Timer，替换窗口和绘制适配器；
  不调用跨进程 AX。窗口收起适配器立即完成，适用于检查同步接缝收起和 reduced motion
  收起的计时竞态，不能证明所有 slide 时序都会出现同样结果。
- **源码确认**：确定事件入口、门闩、状态字段和调用顺序。实际系统通知与可见像素尚未测量。
- **体验风险或待定规则**：指出代码允许的行为、覆盖缺口或体验取舍，不把它说成已在 owner
  的机器上复现的症状。

## 应优先修复的连续交互问题

### 合并条的悬停会被鼠标微动不断延后

**隔离复现，P1。** `StashMergeStripView.reportHover` 在每次 `mouseMoved` 时报告段 ID；
`StashMergeCoordinator.handleHover` 即使 ID 没变，也取消原 timer 并重新等待整个
`revealDelayMS`。因此判定实际变成“鼠标静止满一段时间”，而非“在同一个目标内停留”。
单轨的 `beginHoverReveal` 已有 pending timer 幂等保护，合并条却没有。

回放默认 150ms：在同一个段上报告十次 hover，事件之间运行 run loop 约 40ms，
实际累计约 494ms，`mergeReveal` 调用数仍为 0；停止报告后再等 200ms，才调用一次。
这能直接解释合并条比普通边缘迟钝，细小手抖也让它迟迟不打开。

补齐方式：同一目标不重新计时；换目标或离开才取消。timer 应绑定目标与交互 generation，
触发前核对该目标仍有效。加入“同段连续移动超过 dwell 仍只展开一次”的时间线证据。

源码：`Sources/EdgeStash/Overlay/StashMergeCoordinator.swift:126`、
`Sources/EdgeStash/Overlay/StashMergeStrip.swift:172`、
`Sources/EdgeStash/Engine/StashSessionWatch.swift:25`。

### 点击收起可以被旧悬停计时器撤销

**隔离复现，P1。** 合并条 `handleClick` 没有取消 `hoverTimers[key]`。
`clickLocked` 只在创建 timer 时检查，已排定的闭包只调用 `session.mergeReveal()`，
不再检查点击锁、当前 hover 目标或鼠标按钮。

回放：窗口原本展开；hover 排定 150ms timer；30ms 后点击收起；立即收起成功；
旧 timer 到期后再次展开。真实同步接缝收起和 reduced motion 存在这条路径。
普通 160ms merged slide 可能因为 timer 到期时仍 busy 而挡住这次展开，不能据此声称
每种隐藏方式都会反弹。普通单轨 `handleMarkerClick` 已取消自己的 hover timer。

补齐方式：点击先撤销 hover，再改变目标；timer 到期验证锁与 generation。
同时统一拖动门闩：普通轨的正延时回调检查 `pressedMouseButtons == 0`，合并条没有；
普通轨零延时路径也绕过该检查。避免拖动或按住按钮经过边缘时激活另一窗口。

源码：`Sources/EdgeStash/Overlay/StashMergeCoordinator.swift:139`、`:144`，
`Sources/EdgeStash/Engine/StashSessionWatch.swift:25`、`:54`。

### 上一轮收起的焦点回调可以干扰下一轮展开

**源码确认，P1。** `scheduleFocusRelease` 在 300ms 后只检查
`focusReleaseGeneration`。新一轮鼠标点击／hover 展开没有递增这个 generation，
`shutdown` 也没有让它失效。9 月 29 日增加的前台检查只挡住“用户已切到其他应用”；
用户重新打开同一个应用的 stash，仍满足 `frontmostPID == sourcePID`。

危险序列：收起成功并安排归还焦点 → 300ms 内再次点击／hover 展开 → 旧回调依然有效。
它可以在新展开动画期间或之后激活另一个应用。后续 `finishExpand` 又激活目标应用，
还可能形成两次焦点跳转。该路径尚未用真实 AX 验证。

补齐方式：让焦点回调属于一次操作；新 reveal、明确窗口交互和 session 结束都撤销旧回调。
回调还应核对原操作及其预期阶段，不能只核对 PID。新增“收起后马上再打开”的时间线。

另有规则需要 owner 判断：快捷键、show-all 和部分 Dock 路径都以 `fromDock: true`
展开，完成后 300ms 自动归还焦点。即使用户已经在目标窗口点击或打字，只要仍在同应用，
现有门闩也不会阻止归还。这个行为由当前 policy 明确选择，不能作为纯缺陷修复擅自删除。

源码：`Sources/EdgeStash/Engine/StashSessionWatch.swift:147`、
`Sources/EdgeStash/Engine/StashSession.swift:744`、`:985`，
`Sources/EdgeStashLogic/ShortcutRuntimePolicy.swift:45`。

### 鼠标是否仍在使用同应用窗口的判断忽略遮挡

**隔离复现，P1。** `StashSurface.isPointerInSiblingWindow` 扫描所有在屏窗口，
只要同 PID 的 sibling 的矩形包含鼠标就返回 true。它没有判定鼠标实际命中的最上层窗口。
因此浏览器覆盖了一个 Terminal sibling，鼠标停在浏览器上，仍会被认为在使用 Terminal。
每次 100ms leave 检查又刷新 `lastSiblingInteractionAt`，展开 stash 可以一直不收起。

回放将有序元数据设为“上层其他应用窗口，下层同应用 sibling”，两者同样覆盖鼠标点；
运行当前函数体，仅替换元数据查询，结果仍为 `counts_as_inside = true`。
这证明判断缺口，不代表已量测真实 WindowServer 行为。

补齐方式：从鼠标实际命中的可交互顶层窗口判定 sibling，排除覆盖在下方的窗口、
不可见的 stash 及装饰窗口。保留接受的 sibling 使用宽限，避免把修复变成跨窗口过早收起。

源码：`Sources/EdgeStash/Engine/StashSurface.swift:62`、
`Sources/EdgeStash/Engine/StashSessionWatch.swift:273`、
`Sources/EdgeStashLogic/LeaveCollapsePolicy.swift:18`。

### 动画期间的新输入会被直接丢弃

**源码确认，P2；目标仲裁规则需要明确。** `expand` 和 `collapse` 都在 busy 时直接返回，
没有保存目标、排队或反向完成机制。快速双击、连续快捷键、A 展开途中转向合并段 B，
后一个操作可以被吞掉。合并协调器只把已经提交的 `isExpanded` 算作 active，
不会把仍在展开的 A 纳入切换仲裁。

需要补的不是无限输入队列，而是每次操作的目标及失效关系。建议以最后一次明确点击／
快捷键意图作为目标，单个 session 最多保留一个待执行目标；hover 切换另行规定。
Space／屏幕集合变化仍优先取消旧坐标操作。具体反向动画或等待后执行方案属于新的
体验取舍，应先落入接受的规则，不能只把 `busy` guard 删除。

源码：`Sources/EdgeStash/Engine/StashSession.swift:633`、`:750`，
`Sources/EdgeStash/Overlay/StashMergeCoordinator.swift:59`。

## 合并与窗口几何还有的缺口

| 问题 | 已有证据与体验影响 | 建议补齐 |
|---|---|---|
| hover 提示没有立即更新 | `handleHover` 只改字段；标签和高亮依赖后续 `reconcile` 才传给 view。隔离 hover 后 `present` 增量为 0。正在展开的窗口又不能立即提交，输入反馈可能跟在动画结束后；若没有其他事件，可等到 5 秒 sync。 | hover 目标变化立即更新展示，不重新启动 dwell；离开立即清掉标签。 |
| 合并后接缝接近带消失 | engine 构造 seam approach segments 时排除 `markerSuppressed`；合并会 suppress 所有成员。合并 panel 只有 21pt 命中带，失去原有 28pt 内侧 + 12pt overshoot 的接近路径。`MergeMember` 也没有隐藏方式字段。 | 给合并后的接缝建立稳定的分段命中与接近策略，并明确接近如何选段。需要补充合并契约。 |
| hover 标签重新使用宽 panel | resting 是 21pt；`showingLabels` 时实际窗口宽度恢复到 240–384pt，仍 `ignoresMouseEvents = false`。view 的 `hitTest` 返回 nil 不能作为跨进程点击穿透的完成证据。回放确认 21 → 240pt 几何转换。 | 真机验证标签区域点击能落到下方应用。建议标签另用忽略鼠标的展示 panel，让互动 panel 始终保持 21pt。这实现已有 paint-only 契约。 |
| 合并轨没有接缝几何类型 | 统一 `edgeOverhang = 6`。逻辑回放中，左轨实际桌面 x 为 `-2…3`，5pt 中有 2pt 在所属显示器外；右轨对称。源码无法区分外缘合并与接缝合并。 | 接缝合并的摆放、密度和命中语义需明确；真实跨显示器效果待验证，不把普通外缘 overhang 一概删掉。 |
| resize 后保存几何可以过期 | session 仅注册 moved、minimize 与 destroyed，没有 resized；`refreshPinControl`、merge member 和 marker 用 `restoreFrame`。纯 resize 未伴随 moved 时，pin 与轨仍跟旧几何。再次 collapse 还把不超过 15pt 的宽度变化当作原 lockedWidth。 | 区分用户 resize 和自有动画的 relayout；纯 resize 更新保存几何与覆盖层，不能强拉回旧宽度。验证改窄、改高、固定后 resize、缩放与 zoom。 |
| 最近窗口实际只记住部分入口 | `lastPreferredSession` 只在拖动 capture 成功和 `.openMostRecent` 分支写入；hover、合并、thumbnail、快捷键使用均不更新。设置中的“打开最近一个”可以选到早先 capture 的窗口。 | 先明确“最近”是最近使用还是最近收纳；统一更新位置并验证 A 收纳 → B 收纳 → 使用 A → Dock。 |

源码分别对应：`StashMergeCoordinator.swift:74/126`、`StashEngine.swift:280`、
`MergeGroupPolicy.swift:209/262`、`StashMergeStrip.swift:42/91`、
`StashSessionWatch.swift:165/216`、`StashSession.swift:673`、`StashEngine.swift:437/730/836`。

## 流畅度还需要量测的地方

默认外缘 hover 路径已经包含 150ms 意图等待和 260ms reveal，约 410ms 后才完成展开，
还没计入排队和 AX 耗时。连续 leave 的阈值是 220ms，但 timer 每 100ms 采样一次，
通常需要首次 outside sample 后约 300ms，再加 180ms slide；从跨出缓冲区到完成收起
约 480–580ms，正常调度下成立。60pt 几何缓冲和 1.5s sibling 宽限又决定何时开始计时。
这些数字是代码预算推算，不是对 owner 机器的实测。

更大的潜在停顿来自共用主线程：动画的 AX position／size、leave 的 frame／focus 查询、
5 秒窗口发现、Dock 查询和屏幕恢复都在那里执行。一个目标应用回复慢，其他 stash 的
输入与 timer 也会迟到。`maxWriteRate = 90` 约束的是单 animator 的位置节奏；每第三次
还写 size，多窗口各有 animator，没有全局 RPC 预算。目标允许成功，也不等于中间帧流畅。
源码没有设置 AX messaging timeout；本地 SDK 的 `AXUIElement.h` 提供该 API，
不能据此臆测系统默认等待秒数。

建议先测输入到首个反馈、输入到首个可见窗口帧、AX 单次耗时、主线程长任务与同时
active 的 animator 数。只使用本地时序或开发期 signpost，遵守现有本地优先与无截屏契约。
根据量测调整每进程串行写入、可合并查询及预算。简单把动画都缩短，会掩盖失效的输入，
也不会消除主线程上的跨进程等待。

## 前两次审查尚未关闭的问题

- **应用快捷键语义**：当前发现任何 idle 窗口就 capture 一个并返回，即使已有 managed
  窗口；与接受的“操作该应用全部 stash”规则不一致。需要 owner 决定优先收纳当前窗口
  还是操作已有集合，随后同时统一契约、设置文案与实现。
- **show-all 输入覆盖**：Control-Up／Down 有路径，触控板、独立 Mission Control 键与
  Dock show-all 尚无可靠覆盖；策略函数的存在不等于这些入口接通。
- **Dock 身份**：同标题窗口用 `first` 匹配，目标不唯一；同应用已在前台时，不应只依赖
  `didActivateApplication` 回调获得 thumbnail 意图。真实 Dock 事件顺序待验证。
- **activation 来源**：没有 recent Dock click 时都被归成 Cmd-Tab；notification、file drop
  等能让应用激活的来源没有独立证据。默认 leave-closed 风险较小，但 all-stashed 设置
  为打开时可能对错误来源执行打开策略。
- **焦点批量操作**：全局 `rememberedPID` 仍会互相覆盖；owned activation ledger 每个
  bundle 一个可消费标记，也未证明同 bundle 的多次交错激活和无回调激活不会错分来源。
- **局部接缝变化**：refresh 判定仍按整条边的邻接，而实际 hide 按窗口纵向区间判断；
  同边不相交窗口仍可能有多余 frame 写入。
- **原生边界**：Cmd-` 是否跳过透明窗口、AX 最终写入是否被目标应用钳制、Space 取消、
  full-screen、合盖唤醒、镜像和插拔慢枚举，继续保留实机义务。

## 建议补齐的状态与验证顺序

保留“一个窗口一个 membership”和显示器记忆模型，优先让下面几层各有明确 owner：

| 层 | 需要显式记录或判断的内容 | 当前不足 |
|---|---|---|
| 交互意图 | hover 的同目标 dwell、点击／快捷键的目标、拖动中禁止 reveal、离开再武装 | 单轨、approach 与 merge 各维护不同 timer／lock |
| 执行事务 | 操作 ID、开始／完成／取消／失败、最新待执行目标、屏幕与 Space 的取消优先级 | phase + busy 无法保留下一次意图 |
| 焦点归属 | 哪次操作获得焦点、何时可归还、用户后续窗口操作使旧回调失效 | 全局 PID 与 session 的延迟 callback 没有共同归属 |
| 实际使用区域 | 顶层窗口命中、sheet／menu／sibling、pin corridor、真实 resize 后几何 | 矩形包含、旧 restoreFrame 和 PID 判断不够 |
| 覆盖层展示 | outer／seam／merged／disabled、可点击区与 paint-only 标签区分离 | merge 丢失隐藏类型，hover 展示可以扩大实际 panel |

第一批应修复已有规则下的缺陷：同目标 dwell 不重启、点击撤销旧 hover、失效焦点 callback、
hover 反馈更新和被覆盖 sibling 的错误命中。第二批补连续点击／快捷键的目标规则、resize、
合并接缝命中和宽标签的点击穿透。第三批才依据测量调动画、AX 调度与使用宽限。

最低时间线验收应覆盖：同段微动；A→B→A；按住鼠标经过边缘；点击收起后停留；收起后
300ms 内再展开；展开后立即点击／输入；同应用 sibling 被别的应用覆盖；标签出现时点击
下方应用；纯 resize；展开中按两次快捷键；接缝准备中换 Space；显示器 quiet 中的新意图。
重点检查每次意图是否兑现及旧动作是否失效，再看最终 phase。

sheet、系统菜单、打开文件对话框、拖放、secure input、run-loop tracking 与应用响应慢
也应进入原生序列。它们目前缺少明确的联合证据，不能仅因没有独立 enum 就断言实现有错。

## 本轮检查结果

- 12 个展示入口全部声明；1 项 executable cardinality，11 项 structural-only，覆盖情况未变。
- 直接 expectation check 因默认 26.0 SDK／当前编译器不匹配及受限缓存路径未完成行为部分。
  使用 15.5 SDK、临时缓存／scratch 路径和临时 Swift wrapper 加 `--disable-sandbox` 后，
  原仓库 `./scripts/check-expectations.sh` 完整通过；仓库脚本未改。
- 当前合并协调器原文通过隔离编译和 Timer 回放，确认同段移动延迟、旧 hover 撤销点击收起、
  hover 无即时展示更新。当前 sibling 函数体通过注入元数据回放，确认遮挡判定缺口。
- 现有 `MergeGroupPolicy` 回放确认 21／240pt panel 切换和轨道 overhang。
  没有进行真实跨进程 AX、鼠标点击穿透、多显示器、owner 体感或 app-target Debug 验证。
- 临时回放位于 `/private/tmp/edgestash-20260930-audit`；其窗口／绘制适配器是测试替身，
  不把该结果称为原生端到端验证。没有新增产品权限、网络、采集或外部代码，没有提交。

## 修复后记录

owner 授权修复后，已补齐前两批可确定的连续交互问题，并同步更新产品、窗口生命周期、
玻璃表面和 behavior grammar 契约。没有改变既有隐藏方式、Dock／快捷键焦点归还选择，
也没有缩短动画时长来替代输入修复。

| 问题 | 本轮处理 | 验证范围 |
|---|---|---|
| 同段微动重启 dwell、点击后旧 hover 反弹 | `HoverRevealCoordinator` 保留同目标 deadline；目标／点击／拖动使旧 ticket 失效；一个 visit 只触发一次 | 共享时间线 + 当前原生协调器和真实 Timer 的隔离回放 |
| 零延时或按钮按住时 reveal、松手后不再武装 | 单轨与合并条都检查按钮；mouse-up 重新判断目标；单轨 callback 绑定 lifecycle | 时间线 + 原生入口检查；真实拖放序列待验 |
| 旧归还焦点干扰新操作或后续点击输入 | `FocusReturnCoordinator` 绑定操作和阶段；新操作、pin、输入、Space、屏幕集合、结束使回调及未来排定权失效；完成时先排定本轮回调再通知协调器 | 共享时间线 + 原生接线检查；跨应用焦点时序待验 |
| 被遮挡 sibling 让 stash 长驻 | 按前后有序元数据只认最上层 layer-0 可见窗口；排除零 alpha；移除误伤最大化文档的屏幕尺寸猜测 | 有序元数据时间线；真实 WindowServer／sheet 组合待验 |
| 动画吞掉后一个目标 | `StashPresentationCoordinator` 最多保留一个最新目标；toggle 按目标而非未提交 phase；写入完成后执行；失败、环境取消、release 清除；较新同步操作优先 | 连续 toggle、百次合并、取消和 revision 时间线；实际 AX 动画待验 |
| 合并 hover 没有立即反馈、宽标签抢点击 | 目标变化立即更新；互动 NSPanel 常驻 21pt；标签放在独立 `ignoresMouseEvents=true` 的 panel；两者统一隐藏 | 协调器回放 + 真实 NSPanel 属性／显隐检查；跨应用点击穿透待验 |
| 合并接缝丢失 approach、轨道越界与密度 | member 保留 hide 类型；合并 slot 生成 approach segment，参与 engine 单目标选择；seam group 内移、2pt inset、半强度与内隙 | 左右边缘几何时间线 + approach 协调器回放；多显示器像素待验 |
| 纯 resize 和小宽度变化丢失 | 监听 AXResized；gesture settle 后采纳实际 frame，更新 rescue、marker、merge、pin，不为刷新信号再写 frame；移除 15pt 回退 | 完整编译 + 接线／写入检查；真实目标应用 resize 待验 |
| “最近窗口”遗漏实际展开和使用 | 成功 capture／expand 和 focused expanded window 更新；失败 capture 不更新 | 原生入口检查与编译；Dock 输入身份仍按下方限制待验 |

修复后隔离回放（`/private/tmp/edgestash-20260930-fix`）使用当前
`StashMergeCoordinator.swift` 原文、真实 Foundation Timer 和替身 session/overlay：

- 同段移动累计约 492ms，默认 150ms dwell 内已触发一次 reveal，后续微动没有重复触发。
- 展开状态下排定 hover，30ms 后 click-collapse，再等 200ms，仍 collapsed，reveal 调用数 0。
- hover 目标变化立即触发一次绘制模型更新并显示 labels。
- 两个 merged seam 生成两个 approach segment；选中 B 后仅 B 的 reveal 调用一次。

真实 AppKit surface 回放使用当前 merge-strip / glass 原文，只实例化自己的窗口和视图，
不接触外部应用 AX：hover 后 rail 实际 width=21，label width=180，
labels ignore mouse=true，rail canBecomeKey=false；离开／orderOut 均隐藏标签。
该 Mac 的 optional pin glass 走 painted fallback；macOS 26 的 system-glass 分支尚未运行。
属性检查不是跨应用点击或像素体感证明。

验证和交付：

- 最终 `./scripts/check-expectations.sh` 完整通过：12 presentation anchors；
  1 executable presentation cardinality、11 structural-only，未虚增覆盖。
  `Tests/InteractionContinuityTests.swift` 已接入原有可执行套件。
- 通过原有 `./scripts/stage-app.sh Debug` 和 `./scripts/stage-app.sh` 的 CLT
  Debug／Release 全量编译。15.5 SDK 与临时缓存解决当前 26.0 SDK／编译器不匹配；
  不改变仓库构建脚本。现有通知字符串 cast 的两个 compiler warning 不影响匹配，
  四种通知的隔离匹配回放确认 move／resize 进入 geometry 分支。
- Xcode-project Debug gate 未关闭：本机只有 Command Line Tools，`xcodebuild`
  无法使用完整 Xcode。CLT 编译不能替代这个 gate。
- Release 交付于 `dist/EdgeStash.app`、`dist/EdgeStash.zip`、`dist/CURRENT.txt`，
  2026-09-30 09:12:03 +0800；签名验证、Info.plist 检查、zip 完整性和 diff 空白检查通过。
  owner 需退出正在运行的 EdgeStash，再打开该 app。

未关闭：应用快捷键的 capture-versus-managed 优先级取舍；show-all 的所有原生入口；
Dock 同标题身份与事件顺序；activation 来源；全局焦点来源账本；局部邻接 refresh；
Cmd-`、sheet／菜单、Space／显示器／唤醒的原生联合序列；慢 AX 和主线程时序量测。
这些仍保留此前的证据边界和 owner 义务。没有新增权限、网络、内容采集、外部代码或提交。

## 独立 review 的两项修复

owner 要求修复 review 确认的两条联合事件缺陷：

- **旧合并偏好撤销后来明确展开：已修复。** `MergeRevealSelection` 保存统一选择；
  session 的 `onRevealRequested` 在接受新展开或排队请求时通知 engine，更新合并组。
  Dock、shortcut、AX system-unminimize 都经过同一个展开入口。较早排队的请求在执行时
  使用 `recordsRequest: false`，不重新覆盖后来另一窗口的请求；pin 优先级保持原规则。
- **mouse-up hover 覆盖快捷键收起：已修复。** `HoverRevealPolicy` 同时检查 phase 和
  busy，原生单轨创建 dwell 与 timer 到期都使用它。点击已经开始展开时，mouse-up
  不再启动第二个 dwell；拖动结束后的稳定 collapsed 目标仍可以正常武装。

持久测试补在 `Tests/InteractionContinuityTests.swift` 的
`marker_mouse_up preserves explicit target invariants` 和
`merge_reveal named entry point invariants`；相应产品规则和 grammar 说明同步更新。
这些是交互策略与联合时间线证据，不升级 native presentation cardinality 的覆盖等级。

复跑原 review 回放：

- `ReviewMouseUpFixed.swift` 使用现行 marker 方法原文和真实 Timer，替身保留 260ms
  展开的 busy 状态：快捷键后 `desired_open=false`，200ms 内仍 false，completion 的
  pending collapse 存在。此前同回放为 true 且 pending collapse 丢失。
- `ReviewPreferredFixed.swift` 使用现行合并协调器原文和替身 session：B 先展开并离开
  rail，再接受 A 的明确展开，结果 A expanded、B collapsed。此前结果相反。
- `ReviewRevealRequest.swift` 使用现行展开入口／排队 prologue、Dock helper、shortcut
  helper 和 pending replay 原文，替换实际 AX 执行与完成适配器：三个命名入口均通知选择；
  A 排队之后 B 被请求，A 后续 replay 没有产生第二个通知，最新选择仍是 B。
  回放替身曾遗漏完成时清理 active request，已补上该适配器再通过；不是应用缺陷或原生 AX E2E。

最终 expectation check 再次完整通过。原 staging 脚本的 CLT Debug 和 Release 全量编译
均通过；Release 更新于 **2026-09-30 11:35:16 +0800**，三个输出仍为
`dist/EdgeStash.app`、`dist/EdgeStash.zip`、`dist/CURRENT.txt`。
签名、Info.plist、zip 和 diff 空白检查通过。完整 Xcode 工程 gate 与多显示器原生 review
仍未关闭；owner 先退出运行中的 EdgeStash，再打开新 app。没有提交。
