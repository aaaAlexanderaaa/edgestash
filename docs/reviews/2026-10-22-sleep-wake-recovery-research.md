---
doc_type: investigation
status: implemented_pending_owner_review
authority: informative
implementation: implemented
verification_status: partial
last_reconciled: 2026-10-22
---

# 休眠唤醒后丢失收纳：调查与下一版修改范围

Owner 确认的现象：真实机器为另一台 macOS 27 三屏 Mac。熄屏／休眠唤醒后，
窗口回到桌面，原边缘信号条消失；应用快捷键一次重新收纳一个窗口，没有快捷键
的应用需手工重新收纳。没有主动切换显示器布局。真实测试必须通过 Release 交付。

Owner 随后要求“实现一下”，已将采用的身份、等待和回退语义写回
`docs/contracts/screen-set-and-window-life.md` 后实现。本文件保留研究时的基线分析，
文中的“当前／提案”指当时状态；实现与验证状态见末节。没有关闭真实机器故障，
Owner 在知悉 CLT 验证范围、完整 Xcode 不可用和实机验收未完成后，要求发布版本。
本次按 v0.1.8 诊断测试版交付，沿用此前 GitHub 包的 ad-hoc 签名；不生成 Homebrew
Cask，不将本次测试版登记为已完成 Developer ID／公证验证的正式分发包。

## 结论

当前应修的核心是：**不能把控制接口暂时失效，直接升级成窗口身份死亡并删除
收纳意图。** 显示几何稳定、AX 引用有效、目标应用能响应写入是不同的证据。
“再等固定几秒”“所有窗口重新写一遍”都不能单独建立这些证据。

最有价值的具体缺口是 `invalidUIElement → windowDestroyed → forget everywhere`。
另一个独立缺口是展开窗口在同屏被非拖动方式挪离边缘时，策略仍返回 `detach`。
它们是可重放的代码行为；owner 现场到底触发了哪一个，尚无事件日志证明。

## 一手资料与同类案例

| 证据 | 已核对的内容 | 适用范围 |
|---|---|---|
| [Apple AXUIElement.h](https://developer.apple.com/documentation/applicationservices/axuielement_h) | `invalidUIElement` 描述传入的 AX 引用无效；`cannotComplete` 可以来自消息通信失败、目标应用无响应或等待输入 | 不保证休眠一定让引用失效；也不能从该错误独立推出底层窗口已经关闭 |
| [Apple AX messaging timeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout) | 可设置本进程全局或单个 AX 对象的通信超时；单对象配置不自动作用于另一个相等对象 | 支持测量调用耗时、配置受控超时的设计，不支持凭空选择某个固定等待时长 |
| [Rectangle #640](https://github.com/rxhanson/Rectangle/issues/640) | 睡眠／登录界面恢复后，工具仍运行但无法获得窗口 id；讨论中另有 Magnet 等窗口工具的类似报告 | 是旧系统上的同类现象，不能据此认定 macOS 27 的根因；讨论中并没有一个可直接搬用的可靠修复 |
| [yabai #2783](https://github.com/asmvik/yabai/issues/2783) | 用户报告唤醒后 autofocus 丢失，重启工具恢复但丢失布局 | 证明窗口工具也面对唤醒后控制失效与重启丢状态的取舍；报告未证明与本项目同根因 |
| [yabai #2829](https://github.com/asmvik/yabai/issues/2829) | 报告者采样到主线程等待 AX 消息时，鼠标 tap 也受到影响 | 是同步 AX 调用影响事件处理的现场报告；本项目是否发生同类阻塞仍需耗时证据 |
| [Hammerspoon AX 文档](https://www.hammerspoon.org/docs/hs.axuielement.html) | 文档提示目标应用可不接受属性更改；需要确认时应读回属性 | 支持诊断中区分 API 返回、实际 frame/minimized 状态与会话提交 |
| [AeroSpace #1216](https://github.com/nikitabobko/AeroSpace/issues/1216) | 维护者说明 0.19.0 修了锁屏与死亡窗口检测之间导致整批窗口丢 workspace 的竞态；另有目标应用 AX 响应慢被误判为死亡的情况 | 是已确认并发布过修复的相似故障类型；其实现、显示模型和本项目不同，不搬用补丁 |
| [AeroSpace #2264](https://github.com/nikitabobko/AeroSpace/discussions/2264) | 2026-09 的 macOS 27 单内屏报告：唤醒后五个窗口在 10 ms 内被重新发现，旧 workspace／fullscreen 丢失；报告称所属应用没有关闭重开 | 与目标系统版本接近，且并不要求多屏布局变化；是报告者的观测，尚非维护者确认的唯一根因 |
| [AeroSpace #1875](https://github.com/nikitabobko/AeroSpace/discussions/1875) | 维护者确认屏外隐藏的并发问题：异步读取后状态已变化，可能覆盖保存的位置；已合入修改，有用户反馈 0.20.3-Beta 改善 | 说明隐藏位置与用户意图不能互相覆盖；本项目不使用相同 await 流程，不因此声称发现了同一个竞态 |
| [AeroSpace #2007](https://github.com/nikitabobko/AeroSpace/discussions/2007) | 另一报告展示管理工具自己的 PID 在锁屏前后改变，重启后丢 workspace 记忆 | 应记录 EdgeStash 自身进程运行标识；帖子对终止原因的判断不等于已证明 WindowServer 主动杀进程 |

另核对了 [Rectangle #1626](https://github.com/rxhanson/Rectangle/issues/1626)。标题涉及
休眠后 Emacs 无法移动，但报告者后来说明并非每次睡眠都出现，其他应用也正常；
维护者仍在区分 Emacs 行为与 visible frame 问题。因此不把它当作“已证实的通用
休眠 bug”。没有导入其他项目的参考代码或检查器。

## 本地可重放证据

重放源码：[policy-replay.swift](evidence/2026-10-22-sleep-wake/policy-replay.swift)。
结果：[policy-replay.json](evidence/2026-10-22-sleep-wake/policy-replay.json)。
它调用修复前（2026-10-22 调查时构建）的 `EdgeStashLogic`，不操作真实窗口，不模拟 macOS 已确认发生的
事件；`invalidUIElement` 对应的策略输入是注入条件。

| 注入序列／观察 | 修复前基线结果 |
|---|---|
| 三个进程仍在；三屏布局不变；三个缓存 AX 引用被标为 invalid | `syncEndEvent` 对三个窗口均返回 `windowDestroyed` |
| 按 live shutdown 的删除动作调用 `forgetting(everywhere: true)` 并移除 retry | 记忆成员从 3 降到 0；待恢复重试从 3 降到 0 |
| 同一布局再次 wake settle | `restore=0`、`refresh=0`，新的“同布局唤醒校正”也无目标可恢复 |
| 没有 role invalid 的同进程输入 | 不走这个死亡分支，不能把当前代码概括成“所有 AX 错误都删窗口” |
| expanded 窗口同屏移到中间，`wasDragged=false` | `externalGeometryAction` 仍返回 `detach`；它不等同于 owner 所有窗口原本均 collapsed 的场景 |

修复前测试甚至明确要求 role invalid 返回 windowDestroyed（`EdgeStashLogicTests.swift`
的 periodic sync 用例）。它把“AX 引用无效”和“窗口真的没了”放在了同一布尔量里，
所以绿测试无法发现这个语义缺口。

关键代码位置：

- `StashEngine.swift:555` 将 AX role 状态简化成 `windowRoleInvalid`；先结束会话，
  随后才 `discover`。新发现只按 `CFEqual` 去重，没有更换旧引用、保留会话的路径。
- `StashSession.swift:503` 的 shutdown 清 phase、edge、pin、marker；死亡分支可清
  rescue，且在 coordinator 之外删除所有屏幕集合里的该窗口 placement。
- `StashAX.swift:90` 将 AXWindows 查询失败和成功返回空数组都变成 `[]`。
- `ScreenSetCoordinator.swift:323` 的 refresh 失败进入 scatter，再通过
  `shutdown(.miniaturized)` 变成 idle；后续成功恢复依赖原身份和有限 retry 仍然存在。
- `AppDelegate.swift:143` 的权限 false 会让引擎释放整批会话；目前没有证据表明
  owner 的权限真的在睡眠时发生过变化，不能把它写成已确认原因。

还需要保留一个区别：`shutdown(.windowDestroyed)` 本身不恢复位置／透明度，
所以“引用失效误判”单独不一定能解释所有窗口为什么重新可见；系统重建／移动、
可见回退、权限暂停或引擎／应用重启可能参与其中。日志必须记录工具自己的
process/run identity。若 EdgeStash 确实退出重启，现行 INV-L9 本就不恢复收纳
成员；应查退出原因，而不是借修唤醒而静默引入跨进程自动继承收纳。

## 修改提案

### 1. 保留查询结果的含义

在 AX 适配层引入带错误码的读取结果，先覆盖窗口枚举、role、frame、minimized。
不能再用 `nil/false/[]` 同时表达“不可用”“没有值”“成功但为空”。策略需要区分：

- 有效引用、观测成功；
- 通信失败／超时，暂时没有可信观测；
- 引用失效，需要重新发现并校验身份；
- 有充分证据的窗口死亡或进程结束。

`cannotComplete` 不能升级成窗口死亡。`invalidUIElement` 也应先走重新发现，
而不是直接调用不可逆的全局 forget。成功返回空列表本身仍要结合当前用户会话、
隐藏／最小化状态和 WindowServer 所有者证据解释，不能新增一个更隐蔽的误删入口。

### 2. AX 引用可替换，收纳身份单独保留

将当前不可替换的 `windowElement`／observer binding 与收纳记录解耦。候选引用
必须核对同一应用／PID 的进程启动身份、精确窗口编号和 WindowServer 所有者，
再决定能否接回现有会话；标题相同、几何相似不能用作重新收纳依据。

绑定替换后重装 observer，并用单独的 binding generation 拒绝旧引用已排队的
destroyed/moved/minimized 回调。只递增动画 generation 不足以保护现有 AX 回调。
不确定时保留待确认状态；真正关闭、进程死亡、用户关闭开关时正常清理。
新窗口、重启后相同编号的窗口不得继承收纳，这仍受 INV-L9 限制。

关闭确认不能简化成“窗口列表没有它”。需要把有效销毁通知、成功的新鲜枚举、
当前窗口所有者、应用进程生命期组合起来，并对矛盾或不可用的证据保持保守。
尤其不能把 on-screen 列表缺失当作死亡，接缝最小化和别的 Space 都会影响它。

### 3. 唤醒先校验，按窗口恢复

保留现有 display settle 和闭盖／真正拔屏分类，但增加每个窗口的控制可用性检查。
同布局唤醒也要检查原收纳；已经符合预期的隐藏、最小化或展开状态尽量不重写。
有取消到一半的过渡、真实几何变化或隐藏状态丢失时，才执行所需的修复。
展开且未 pin 的窗口无论是否需要 AX 写入，都恢复 leave watcher 和新的离开 dwell。

每个窗口的恢复进度独立。失败不重做成功兄弟窗口，不把一次失败升级为整个应用
或整个屏幕集合重置。不能仅因 frame 写入失败就删除 placement、原 pin 和原目标
状态；若安全要求窗口先退回可见桌面，外观回退与保留恢复意图应是独立动作。
不能一边真实可见一边继续声称它已 collapsed。

暂不扩大既有 initial + 1/2/4 秒三次写入预算。先区分等待新鲜观测与真正写入失败，
记录恢复各阶段耗时。是否延长等待上限应依据现场数据进入明确契约，不能无限重试。
用户在恢复期间主动拖走、取消收纳、关闭窗口或退出应用，必须取消旧恢复目标。

### 4. 唤醒期系统移动不能变成用户退出

恢复尚未完成时，晚到的 AXMoved／AXResized 不能直接进入普通用户 detach 路径。
要根据 epoch、binding generation 和真实手势证据重新读取后处理。
当前 expanded 同屏非拖动返回 detach 的分支应拆开审查；本次优先修唤醒期间的
系统挪动，保留真正桌面拖出的退出语义，避免顺手改变其他日常移动行为。

### 5. 权限边界保持，记录实际是否触发

AX trust 为 false 时立即停止控制，不屏蔽权限检查、不修改 TCC、不自动重授权。
记录它和 power/wake/session 的先后关系。将“停止 AX 工作”与“永久忘记收纳”
拆开设计；如果后续要在同一进程生命期恢复暂停前的收纳，必须先重新验证窗口身份，
并明确处理真实权限撤销后的可见性恢复要求。现阶段不凭猜测改动这个独立分支。

### 6. Release 自带可用的受控诊断

把诊断开关与 Debug／Release 优化级别解耦。建议专门的诊断 Release 包在签名前
写入明确的诊断标志，启动即记录；普通 Release 默认关闭，不要求测试机安装开发
工具、从终端设置变量，或修改用户的产品偏好。

继续使用有大小上限、异步、限频的本地文件，不采集标题／内容／键盘输入、不联网。
只记录生命周期与状态变化，避免逐帧成功 AX 写入刷日志，也避免诊断本身显著加重
先前报告的后台／WindowServer 负载。需要补齐以下证据：

- 新的唯一版本／build 与实际二进制构建标识；不能继续用 0.1.7 (8) 冒充新发布；
- 工具自己的 PID、每次启动 run ID 与 start/stop 事件，区分同一进程内的状态丢失
  和工具重启后按 fresh 规则不继承成员；缺失 stop 事件本身不证明崩溃原因；
- 每次 wake 的 epoch、每个窗口的原收纳、原 pin、控制引用 generation、恢复结果；
- AX 调用状态和耗时；成功但空列表与查询失败的区别；
- 置信不足而延后、引用重绑、明确死亡、可见回退、真实 forget 的不同原因；
- 必要的写入前后 frame/minimized/alpha 观测，区分“调用成功”和“实际状态符合”；
- 整个恢复完成／等待／预算用尽的结果，保证复制日志后能知道还有哪些窗口未恢复。

## 发布顺序与验收

推荐先完成上述最小身份恢复路径及 Release 诊断，不把全量唤醒重写直接当作现成
修复发布。若身份判定还不能通过故障注入，下一次可发布的范围应退到基于已发布
行为的 Release 诊断包；不能把尚未验证的行为改动混进仅为取证的版本。

实现前将拟采用的具体身份／回退／等待语义写回当前或 owner 接受的目标契约。
本研究不自动将新的恢复外观、等待时间、权限恢复语义升级为接受状态。

至少需覆盖这些使用 live adapter 共用决策的故障序列：

1. 同布局睡眠／唤醒：健康的 collapsed、expanded、pinned 窗口保持原收纳和目标；
   正常窗口不收到多余 placement 写入，未 pin 的展开窗口恢复自动收回。
2. 旧 AX 引用 invalid，新引用指向同一经核对身份的窗口：成员、pin、placement 不丢，
   旧引用迟到的 destroyed 不能终止新 binding。
3. AXWindows 通信失败／空值／成功空数组：结果不混淆；暂时没有新鲜观测不能 forget。
4. 真关闭、进程退出、PID／窗口编号复用、应用关开关：正常清理，新窗口不得复活旧收纳。
5. 单窗口写入失败：其他窗口不动；回退保留恢复目标，预算有界且不被重复事件刷新。
6. 恢复期间用户拖走、退出或取消收纳：旧操作不能再次把窗口拉回边缘。
7. 唤醒期间非手势系统移动不 detach；普通真正拖出仍 detach；关闭 pin 不影响身份。
8. 空显示枚举、真外屏缺失、内屏闭盖 hold 与镜像／缩放往返保持既有契约。
9. trust false 时停止控制；记录而不猜测其与唤醒的关系。
10. 优化的 Release 包确实能记录诊断；关闭诊断时不求值快照；日志轮换有界，
    实际分发 ZIP 的版本、签名与构建标志一致。

代码完成后再运行 expectation check 和适当原生构建。当前重放只是旧策略缺口的
证据，不是修复测试通过；没有真实 Mac 复现或 AX 拒绝注入成功的结论。

## ChatGPT 交叉咨询

Owner 已授权使用 `chatgptbox.ask_chatgpt`。已提交不含源码／本机路径的通用机制
问题，给出必要症状与抽象控制流程。咨询已完成，其主要判断是“控制／观察失效
被升级为窗口死亡，恢复逻辑放大了问题”，建议将 Session 意图与 AX 句柄分开。
这是高优先级假设，与本地重放一致，仍不是 owner 现场因果证明。

咨询提供的 AeroSpace #2264、#1875、Amethyst #1282 已逐一读原帖核对；继续追查
到了更直接的 AeroSpace #1216。#888 本轮只能核对三屏睡眠后丢位置的报告正文，
没有据它转述未核实到的维护者原话。Amethyst #1282 涉及 DisplayLink 且最终的
绕法包括禁用睡眠，不能照搬成修复方案。

采纳的方向：保留收纳意图、重新验证身份并替换引用、按窗口恢复、拒绝迟到操作、
在 Release 中留下结构化证据。以下建议未直接采纳：

- 用窗口标题协助接回身份：本项目不新增标题采集或依赖，精确身份不明则不猜。
- 重试用尽后无限低频探测／自动恢复：现行契约的写入预算有界，不能自行扩展。
- 所有失败都禁止回桌面：当前契约仍要求 visibility/rescue 安全回退；应保留恢复
  意图，不能为保留逻辑 phase 留下不可见且不可操作的窗口。
- 屏蔽权限变化或新增自动重新授权提示：违反现有权限／效果边界；先记录实情。
- 跨 EdgeStash 重启持久化并复活成员：现行 fresh 契约不允许，本轮不顺手改变。

没有导入外部参考代码或执行对方帖子里的系统修改。结论依据是原帖、Apple API
语义和本地策略重放；AI 意见只用于交叉检查和找到应核对的证据。


## 实现与验证记录（2026-10-22）

已实现：

- `WindowRecoveryPolicy` 将 transport wait、唯一精确重绑、已确认死亡分开；
  live discovery 不再将 role invalid 直接映射为 windowDestroyed。进程元数据缺失
  不是已知进程重启；workspace 未列出的 PID 用零信号存在性查询交叉核对。
- Native session 可更换 window/app AX 引用和 observer；回调同时核对 binding
  generation 与环境 lifecycle generation。重绑不创建第二个 idle 会话。
- 相同布局唤醒检查 minimized/frame/alpha；健康状态不写 placement。失控引用先
  保留收纳与 pin／几何，通过既有发现循环恢复。缺少观测不能当作窗口死亡。
- 恢复队列保留独立 intent；可见 idle 回退不覆盖它。只有实际写入失败消耗首次加
  三次预算，等待可读不耗次数，耗尽后重绑／重复通知不能重新启动预算，快速恢复可读也不提前消费退避等待。用户拖动、
  重新收纳、关闭／禁用／退出和新环境取消旧目标。真实显示离开时，未验证的引用
  先保留桌面落点，重绑后完成可见回退。
- 优化的 Release 通过签名前包元数据启用本地诊断，普通 Release 关闭；版本
  0.1.8 (9)。启动记录实际载入二进制 UUID、PID、run；AX 错误与慢调用、身份判定、
  写入前后观测、剩余写入预算与耗尽结果可追溯。

已执行 `./scripts/check-expectations.sh`：12 个 presentation anchors 全部声明，
1 个 executable／11 个 structural-only 的展示基数覆盖保持原状；全部逻辑测试通过。
新增 `Tests/WindowRecoveryTests.swift` 使用 live 共用决策重放三窗口不变布局、旧引用
失效、真关闭／编号复用、旧回调、等待与预算耗尽、pin／几何保留和健康外观不写入。
打包工具 10 项测试通过，覆盖诊断 Release 仍选 Release 优化、普通 Release 关闭
诊断、错误参数和失败不替换原包、签名／公证顺序及 ZIP 元数据一致。

原生元数据解码探针通过：没有 bounds 的窗口仍保留 id/pid；缺失／非数值 alpha
保持未知；不完整身份返回 unavailable，而成功空数组保持 empty。源码保存在
`evidence/2026-10-22-sleep-wake/metadata-probe.swift`；编译时与 live
`StashSurface.swift`、`StashDiagnostics.swift` 及当前 logic objects 共同链接，
不操作真实窗口。这防止把筛掉的不可读元数据误写成“窗口不存在”。

CLT 原生 Debug 和 Release 构建通过；最终 `dist` 为 0.1.8 (9)、arm64、Release，
诊断标志为 true。staged app 与从 ZIP 全新解压的 app 都通过本地签名校验，
Info.plist 与可执行文件一致。包为 ad-hoc 本地签名，没有走 Developer ID／公证发布。
SHA-256、二进制 UUID 和验证范围记录在
`evidence/2026-10-22-sleep-wake/verification.json`。优化构建的本地探针
核对包标志开／关、普通 Release 不求值快照，以及 Release writer 可写合法 JSON；
另验证轮换上限、当前／前一日志、目录 0700／文件 0600 和相同错误限频。
探针只写 `.build`，没有向用户日志目录写测试事件。

完整 Xcode 未安装，调用
Xcode 工程 Debug gate 返回 CLT-only 错误。上述检查不等同真实 AX 通知／写入成功，
也不证明 owner 的 macOS 27 故障已在现场修复。原始基线重放文件只作为历史调查
证据保留，不冒充新代码的回归测试。


## Owner 授权的测试发布

Owner 在本地包与验证范围已说明后要求“那发一个版吧”。发布目标为
[v0.1.8](https://github.com/aaaAlexanderaaa/edgestash/releases/tag/v0.1.8)，标记为
prerelease，保留当前稳定版入口。发布说明随包列出真实验证范围、日志位置和
实机复现步骤。完整 Xcode 工程 gate 仍未完成，记录此限制，不将 CLT 构建记作
该 gate 通过；与此前 0.1.7 的测试分发采用同一签名方式。
