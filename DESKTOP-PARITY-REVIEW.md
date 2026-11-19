# 网页版 ⇄ Windows 版：体验对照、差异清单与迭代建议

> 面向 RFC #362（D1/D3）的评审文档。基线：上游 `ThinkFlowLab/OpenDirector@d05a56d`（0.1.4）与 `main`@2026-11-19；
> 桌面侧基线：本仓库 `desktop.7`（WebView2 + 打包 Python），本次 `desktop.8` 修复。
> 本文所有「网页版」结论都来自对锁定基线源码的逐行核对与在沙箱中实际运行的上游 Web 应用；
> 「Windows 版」结论来自宿主/安装器源码、CI 装机验收录像与你提供的截图。物理 Win10/Win11 桌面机上仍需按
> [WINDOWS-AUDIT.md](WINDOWS-AUDIT.md) 的清单逐项人工复验的条目已单独标注。

---

## 0. desktop.8：时间线「失败卡」关闭问题（本次修复）

### 症状与根因

你的截图：空时间线点「导出视频」后，画布上出现失败卡「请先向时间线加入素材。」，只有「重试输出」，
无法关闭。逐行核对后确认这是 **上游 UI 的缺陷，不是 Windows 适配引入的**——网页版同样卡死：

1. 失败卡（`TimelinePendingVideo`，`src/canvas/TimelineOutput.tsx`）是一个 **虚拟覆盖层节点**：
   `selectable:false, draggable:false, deletable:false, focusable:false`。选中不了 → `Delete` 删不掉，
   焦点进不去 → `Esc` 无从谈起，双击/F2/右键也被 capture 掉了（防误改名）。
2. 「取消合成」按钮只在 `rendering/publishing` 阶段存在；`cancel()` 也只中断 `rendering`。
   失败态（`failed`）没有任何一条路径把 state 置空：
   只有换工程、或 **删掉来源时间线节点** 才会顺带清掉它。
3. 「重试输出」对「时间线为空」这条错误永远是同一个错——点一次失败一次，形成事实上的死角。
4. 附带伤害：发布失败（`CreationCommandError`）时挂起的 `pending` 会 **阻塞其它时间线的导出**
   （`blockedItemId`），失败卡关不掉 → 其它时间线也导不了，直到重试成功。

### 修复（patches/timeline-output-dismiss.patch）

- 失败卡右上角现在是两个按钮：`重试输出` + `关闭`（英文 `Retry output` / `Dismiss`，双语键
  `timeline.output.dismiss` 进入 i18n 目录，`check:i18n` 通过）。
- `useTimelineOutput` 新增 `dismiss()`：中断在途渲染、丢弃缓存的渲染结果、清空覆盖层。
  覆盖层是虚拟节点，`timelinePublication` 之前不落库 → 关闭即无痕，不留孤儿视频节点。
- 关闭同时清掉 `pending`，**解除了上面第 4 点的连带阻塞**。
- 「发布中」按钮保持原样（禁用取消），避免与发布命令竞态——这是上游刻意的设计，没有动。
- 「重试复用已渲染片段」的原语义保留：不点关闭、直接点重试，仍然跳过重渲染只补发布。

### 验证

- 网页版回归：`verification/timeline_output_dismiss.mjs`（Playwright 旅程）已挂进 canvas 车道：
  空时间线 → 工具栏导出 → 失败卡出现 → `Dismiss` → 卡片从 DOM 移除、后端无孤儿 video、
  再次导出仍能正常进入失败态并可再次关闭。
- 装机验收：`scripts/smoke.ps1` 在 **真实安装版 WebView2 窗口** 里跑同一场景
  （`verification/render.mjs` 新增断言 + `delivery/windows-timeline-failed.png` 证据帧），
  随后继续原有的「导入时间线 → 渲染 → ffprobe 校验」链路。
- `tsc --noEmit`、`npm test`（838 通过）、`npm run build` 全绿；补丁按 `package.py` 顺序
  （placement → agent → dismiss）在纯净上游树上演练可干净套用。
- 宿主兼容：`Host.cs` 的退出确认用 `.cw-timeline-pending:not(:has(.cw-timeline-pending-error))`
  区分「正在渲染」与「失败卡」，类名未改 → 行为不变，且失败卡现在对用户可自助关闭后，
  「状态未知」的弹窗频率理应下降。

---

## 1. 我是如何做对照的（方法）

- 把锁定基线（`d05a56d`）的上游 **原样跑起来**（同一 `package-lock.json`、同一 Python 服务、
  不套任何桌面壳），在沙箱里以生产构建 + API 的方式实际进入画布、创建时间线、触发导出失败路径；
  并留了一份 **未打补丁** 的同源实例做 A/B。桌面壳（`Host.cs`/`service.py`/NSIS/更新器）逐行读源码，
  对照 `desktop.7` 的装机录像与你的截图推断 Windows 侧行为。
- 结论口径：UI 层「两个版本」本就是 **同一份 React bundle**（打包时上游树上只多了 3 个补丁），
  所以体验差异 ≈ 宿主环境差异（WebView2/窗口/生命周期）+ 桌面壳新增行为，而不是界面差异。
  这符合「完全等同原项目」的目标，也意味着 **修复应尽量做进补丁而不是 fork 里另写 UI**。

## 2. 体验差异矩阵（按用户旅程）

图例：✓ 等同（且已验证或有测试） · △ 有意为之的桌面差异（文档已解释） · ⚠ 需要跟进的差距 · ✗ 缺陷

| # | 旅程环节 | 网页版 | Windows 版 | 判定 |
| --- | --- | --- | --- | --- |
| 1 | 打开即用 | 要自备 Node/Python/服务器环境 | 双击安装，随包 CPython/FFmpeg/OpenCode/MinGit | ✓（交付目标本身） |
| 2 | 创建项目/画布操作/素材导入 | 浏览器标签页 | 同 bundle，同一 `~/.opendirector` 数据根 | ✓ |
| 3 | 空时间线导出失败 | 失败卡无法关闭（同一缺陷） | 同一缺陷 → desktop.8 已修 | ✓（修复后） |
| 4 | 导出/渲染进行中关页面 | **无 beforeunload 守卫**，直接丢任务 | ×隐藏到托盘，退出需确认且枚举 Agent/生成/导出计数 | ✓（桌面比网页更防误丢，网页反而值得借鉴） |
| 5 | 渲染期间窗口可见性 | 后台标签被节流，渲染变慢 | 隐藏到托盘后同样可能被节流（README 已声明「导出需存活渲染器」） | ⚠（见 §4.1 离屏渲染） |
| 6 | 文件保存/下载 | 浏览器默认下载目录、`chrome://downloads` 可见 | WebView2 默认「另存为」弹窗；无下载管理入口 | ⚠（见 §4.3） |
| 7 | 右键上下文 | 浏览器菜单 | **默认浏览器菜单全开**（重新加载/打印/查看源/检查；DevTools 默认可用） | ⚠（见 §4.2） |
| 8 | 页面缩放/状态栏 | 浏览器地址栏天然存在 | 状态栏（悬停显示 URL）、Ctrl+滚轮页面缩放仍开启，与画布自身 zoom 叠加 | ⚠（同上） |
| 9 | 多窗口/多会话 | 多标签共享同一后端；409 锁 | 子窗口（NewWindowRequested→原生多窗）+ 同一 409 锁 | ✓（升级：真·原生窗口） |
| 10 | IME/键盘 | 浏览器原生 | 同 Chromium 内核；Alt+Enter/Ctrl+Enter/Shift+1 等快捷键无浏览器冲突 | ✓（Win 机 IME 候选窗定位建议实机复验） |
| 11 | 高 DPI | 浏览器处理 per-monitor | `SetProcessDPIAware()`（仅 System-aware），混合 DPI 多屏会糊 | ⚠（见 §4.4） |
| 12 | 窗口记忆 | 无此概念 | 固定 1440×900 居中启动，不记忆尺寸/位置 | ⚠（见 §4.4） |
| 13 | 崩溃恢复 | 刷新即可；租约 60s | Job Object 兜底杀进程树；重启唤起同一窗口数据；租约同 60s | ✓ |
| 14 | 模型配置与密钥 | 后端按用户存盘 | 同一文件；桌面另加 DPAPI 会话凭据、任意本机进程 403 | ✓ + 更强隔离（有意差异） |
| 15 | CLI/工程互操作 | 无 | App Paths 注册 `OpenDirector-CLI.exe`，GUI/CLI 同一把锁 | ✓（桌面独有） |
| 16 | 更新 | 永远是服务器上的最新版 | Sigstore 校验 + 12h 后台检查 + 确认式重启 | △（差异合理；失败面已测） |
| 17 | 卸载 | 删文件夹 | 卸载保留工程/凭据/CLI 注册；运行中拒绝（exit 2） | ✓（语义正确） |
| 18 | SmartScreen/来源 | HTTPS 站点 | 无 Authenticode，README 教核对 SHA-256 | ⚠（发行前决策，见 §6） |

## 3. 「失败/卡住」状态盘点（网页版共有的生成工艺问题）

这次「关不掉的失败卡」不是孤例，值得做成一个 **统一的失败呈现规范**：

| 状态 | 现状 | 是否可脱困 | 建议 |
| --- | --- | --- | --- |
| 时间线失败卡 | desktop.8 前只有重试 | ✗ → ✓（已修） | — |
| 发布被 `blockedItemId` 阻塞 | 其它时间线导出按钮禁用 + `otherPending` 提示 | 间接（重试成功后恢复） | ✓ desktop.8 的关闭可立即解除 |
| 图像/视频/音频节点生成失败 | 节点是真实节点，可删除/重试，错误在卡内 | ✓ | 失败文案统一化（见下） |
| 后端 503 / 服务掉线 | `desktop-error-contract.patch` 已给双语修复指引（日志路径） | ✓ | 保持 |
| WebCodecs 不可用（N 版 Windows 无媒体包） | 渲染中途抛原始错误文本 | 能关（desktop.8 后） | 预检 `VideoEncoder.isConfigSupported` + 「装 Media Feature Pack」双语指引 |
| 渲染到一半宿主被杀 | 状态归零，无「上次被中断」标记 | 重开手动重来 | 见 §4.1 |

**规范建议（可提上游）**：一切「进行中卡片」必须满足三条——① 必有出口（成功→产物、失败→重试+关闭、
取消→还原）；② 关闭即释放全部互斥（如 `blockedItemId`）；③ 错误文本可复制、含可行动下一步。
本次补丁已经满足，建议把 `TimelineOutput.tsx` 的模式回给上游做组件级约束（配一个 lint/测试守卫：
`failed` 相必须渲染带 `dismiss` 的按钮行）。

## 4. desktop.9 候选改进（Windows 侧，代码级方案都已核对可行）

### 4.1 导出与窗口存活解耦（最大的体验差）
现状：MP4 编码发生在渲染器（WebView2 页面）里，README 明确要求「导出时保持应用运行」；隐藏/最小化后
可能被系统节流。方案对比：
1. **离屏窗口继续渲染（小改）**：渲染开始时若主窗被隐藏，宿主创建隐藏的 `WebView2` 子窗（同一 origin）
   接管渲染上下文；或简单粗暴地在导出期间给主窗持有 `PowerCreateRequest(POWER_REQUEST)`（防系统睡眠）。
2. **进度可见性**：导出中托盘图标显示进度环（`NotifyIcon` 换帧），完成/失败弹 toast
   （宿主已有 `/__desktop/activity` 计数接入点 + `Updates` 已有 toast 通道，加一个 `ExportState` 监听即可）。
3. 长期：把渲染移入打包 Python + 捆绑 FFmpeg（服务端合成）——**不建议**，等于复刻一套第二渲染管线，
   违背「体验完全等同原项目」的第一原则；保持浏览器内 WebCodecs 单一事实源，宿主只负责「别让它死」。

### 4.2 像应用，而不是像网页（设置三项 + 一个菜单）
```csharp
core.Settings.AreDefaultContextMenusEnabled = false;   // 保留「粘贴」等输入框菜单由内核兜底
core.Settings.IsStatusBarEnabled = false;
core.Settings.IsZoomControlEnabled = false;            // 画布有自己的 58% 缩放，页面缩放是干扰项
core.Settings.AreDevToolsEnabled = false;               // 诊断走 desktop.log；排查时可临时开
```
风险：关右键菜单会影响「图片另存为」习惯——用 `DownloadStarting` 统一接管（见 4.3）即可补回。
每项都有真实验收路径（装机冒烟加 2 条断言即可）。

### 4.3 下载体验
`CoreWebView2.DownloadStarting` → 默认目录改 `%USERPROFILE%\Downloads\OpenDirector\`，
完成 toast 附「打开所在文件夹」动作。顺带解决「另存为」打断工作流的问题。
网页版保持浏览器原状——这属于 **桌面增值**，不违背等同原则（等同的是 UI/业务，不是宿主默认值）。

### 4.4 窗口质感
- 改 Per-Monitor V2：无 app.manifest，用 `SetProcessDpiAwarenessContext(DPI_AWARE_PER_MONITOR_V2)` 于
  `Main()` 首行（需 Win10 1703+，与声明的系统版本兼容），混合 DPI 副屏不再模糊；WebView2 自动跟随缩放。
- 记忆窗口位置/尺寸：写 `%LOCALAPPDATA%\OpenDirector\Desktop\window.json`，启动时恢复并钳制到在线显示器
  工作区（防拔屏后窗口丢在外面）。
- 「× 隐藏到托盘」加一次性气泡说明（已有 `Hidden()` 提示，可加「可在设置改为直接退出」的远期选项）。

### 4.5 安装体积（可选组件）
~2GB 里 OpenCode/MinGit/ripgrep/ripgrep 与字体占比可观。NSIS 已支持分段：把「AI Agent 运行环境」
做成可选组件（默认装），纯剪辑用户可减 ~35%。需要在 WINDOWS-AUDIT 的「不包含什么」里同步语义。

## 5. 网页版值得反向借鉴的两点（可提上游 PR）

1. **本次 dismiss 补丁**：`main@2026-11-19` 的 `TimelineOutput.tsx` 与锁定基线 **逐字节相同**，
   即缺陷在最新上游仍存在。补丁文件是干净的 `git diff`，可直接转 PR（建议连同一个精简版浏览器旅程）。
2. **导出中的 `beforeunload`**：上游桌面文档强调「导出保持运行」，但网页版关标签页没有任何拦截。
   `useTimelineOutput.busy` 时注册一次 `beforeunload.preventDefault()` 即可，几行代码。

## 6. 需要你拍板的问题（按优先级）

| # | 问题 | 选项 | 我的倾向 |
| --- | --- | --- | --- |
| D1 | desktop.8 的发布方式 | 只出 CI artifact / 建 draft release 附 EXE+SHA256 / 直接推稳定频道 | draft release：更新频道信任 `main`，候选分支不应进入公开推送 |
| D2 | §4.2/4.3/4.4 是否进 desktop.9 | 全收 / 只收 4.2+4.3 / 逐项讨论 | 4.2+4.3 先做（改动小、观感提升最大），4.4 的 DPI 需要多屏实机验证再放行 |
| D3 | dismiss 修复是否回贡上游 | PR / 仅 fork 补丁 / 等上游自己修 | PR：这是网页版也中枪的 P1 交互缺陷，上游会需要；fork 继续留补丁直到上游合并 |
| D4 | 渲染节流（§4.1） | PowerRequest 保活（小）/ 离屏 WebView（中）/ 暂不做 | 先做 PowerRequest + 托盘进度，离屏方案等 desktop.9 装机反馈 |
| D5 | WebCodecs 缺失的指引文案 | 归入失败卡文案（前端）/ 宿主预检（后端探针） | 前端：与双语目录一起维护，桌面壳不掺业务文案 |
| D6 | 签名 | 继续无签名+SHA256 文档 / 申请代码签名证书 | 分发对象若含非技术用户，证书优先级要提上来 |

---

### 附：desktop.8 变更清单

- `patches/timeline-output-dismiss.patch`（新）：失败卡 `关闭/Dismiss` + `useTimelineOutput.dismiss()`，
  双语键 `timeline.output.dismiss`；不触碰渲染、发布、存储与互斥的既有业务语义。
- `scripts/package.py`：打包时追加应用新补丁。
- `verification/timeline_output_dismiss.mjs`（新）+ `.github/workflows/canvas.yml`：网页版回归旅程进 canvas 车道。
- `verification/render.mjs`：装机验收先复现「空时间线导出 → 失败卡 → 关闭」，证据帧 `delivery/windows-timeline-failed.png`。
- `desktop/VERSION` → `0.1.4-desktop.8`。
