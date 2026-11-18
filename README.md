# OpenDirector for Windows

面向 Windows x64 的非官方桌面发行版。安装后从开始菜单打开 **OpenDirector**，无需命令行、Python 环境或本地开发服务器。不是网页快捷方式，也不连接某个托管的 OpenDirector 网站。

**[下载 Windows EXE（仓库维护者可见的草稿）](https://github.com/hanyingHY/For-OpenDirector/releases/tag/untagged-cdd2487eff2f548350cf)** · **[Actions 备用下载](https://github.com/hanyingHY/For-OpenDirector/actions/runs/44265737164/artifacts/14410985542)** · **[观看 Windows 原生窗口录像](delivery/windows-demo.mp4)** · [时间线导出的 MP4](delivery/timeline-export.mp4) · [可导入的示例画布](examples/Blue%20Hour.canvas)

登录有仓库维护权限的 GitHub 账号，可从草稿中直接下载 EXE。Actions 备用下载需要登录，解压得到 `OpenDirector-0.1.4-desktop.4-x64-Setup.exe`，双击即可按当前用户安装。用 `Get-FileHash .\OpenDirector-0.1.4-desktop.4-x64-Setup.exe -Algorithm SHA256` 对照 [SHA256SUMS.txt](delivery/SHA256SUMS.txt)。安装程序**没有 Authenticode 签名**，可能触发 SmartScreen。请核对来源和 SHA-256，不要关闭系统安全防护。无管理员权限要求；安装和首次启动请预留约 2 GB 空间。

**本次结果**：[构建及本机测试通过](https://github.com/hanyingHY/For-OpenDirector/actions/runs/44265737164)，[相同 EXE 的独立 Windows 验收通过](https://github.com/hanyingHY/For-OpenDirector/actions/runs/44267734067)。中文画布录像来自升级前的 desktop.3；[英文窗口 Agent → 渲染实录](delivery/windows-workflow.mp4)、[Agent 写入截图](delivery/windows-agent-en.png)和 1.5 秒 H.264 输出来自升级后的 desktop.4。逐项结果与边界见 [Windows 核对清单](WINDOWS-AUDIT.md)。

## 桌面版与网页版是什么关系？

固定基线是 [ThinkFlowLab/OpenDirector `4360d9e`](https://github.com/ThinkFlowLab/OpenDirector/tree/4360d9eb66b23598d3f637b2288745291e818862)（0.1.4）。使用其 `package-lock.json` 构建完整的 React/Vite UI，原样加载其 API、画布、时间线、字幕字体、双语消息、模型配置和 Agent skills。打包时对 Windows CLI 启动脚本、非交互 Git 初始化的标准输入和只读任务计数接入点做适配，不改画布的写入、渲染或模型业务规则。WebView2 提供 Edge 的文件选择、下载、剪贴板和 WebCodecs，不用另一套 UI 模仿原版。

| 项目 | 本次交付 |
| --- | --- |
| 目标 | Windows 11 x64 / Windows 10 22H2 x64，.NET Framework 4.8+ 及 Evergreen WebView2；不含 Windows ARM64、x86、macOS、Linux |
| 实测系统 | GitHub-hosted **Windows Server 2022 x64**。这是原生 Windows 构建和 GUI 测试，不是 Win10、Win11 各硬件机型的认证 |
| 打包 | 每用户 NSIS 安装 / 卸载；开始菜单、桌面快捷方式、App Paths；桌面版 `0.1.4-desktop.4` |
| 随应用安装 | CPython 3.12.16、上游 Python 依赖、OpenCode 1.19.5 x64 baseline、MinGit 2.56.1、ripgrep 15.1.0、FFmpeg/ffprobe 9.0.2（含 libx264）、编译后的 Web UI |
| 系统组件 | WebView2 SDK 1.0.2903.40；实际浏览器由系统 Evergreen Runtime 提供并更新。若被移除，请从[微软](https://developer.microsoft.com/microsoft-edge/webview2/)安装 x64 运行时。未捆绑完整浏览器或模型权重 |

### 第一次使用

1. 安装后打开应用；可以先不配模型，创建项目、上传本地素材、编辑、导入和导出。点上方「中文 / EN」切换语言。
2. 可用「导入画布」打开 `examples/Blue Hour.canvas`。它是由原版界面实际导出的含图像和视频提示词的工程，不需要 API 密钥。
3. 用 AI 时，在原版模型设置中配置自己的服务地址、模型 ID 和认证。第三方服务、价格、账号权限、可选的外部 Agent CLI 与网页版本一样，不随安装包附赠。
4. **导出时保持应用运行**。MP4 在渲染器内编码，需要 WebView2 和系统的 H.264 编码能力。不要在导出、生成或 Agent 正在工作时退出。主窗口 × 隐藏到托盘；双击托盘或重新从开始菜单启动会唤回原窗口。选择托盘「退出」才会检查运行中的任务、显示确认并停止本地进程树；远端提供商已经接受的任务未必随之取消。

### 文件、CLI 和升级

| 内容 | 默认位置 |
| --- | --- |
| 应用资源 | `%LOCALAPPDATA%\Programs\OpenDirector\app` |
| 工程、目录索引及模型配置 | `%USERPROFILE%\.opendirector`，或使用与上游 CLI 相同的 `OPENDIRECTOR_ROOT`。模型密钥由原版后端按用户保存，请勿共享整个目录 |
| 浏览器配置、诊断 | `%LOCALAPPDATA%\OpenDirector\Desktop`，日志为 `desktop.log` |

GUI 和 CLI 使用同一个项目 ID、会话租约、文件锁及版本规则。GUI 运行时，在 PowerShell 里执行：

```powershell
& "$env:LOCALAPPDATA\Programs\OpenDirector\app\OpenDirector-CLI.exe" project list
```

CLI 支持上游命令及 `--help`。托盘可选注册、修复或移除 `OpenDirector-CLI.exe` 的 App Paths（Win+R）；PowerShell 中直接用上面的绝对路径，不覆盖系统 `PATH` 或其他 CLI。每次启动的桌面凭据受 Windows 当前用户 DPAPI 保护。原版 HTTP API 不直接对任意浏览器或未认证的本机进程开放。

**自动更新（默认开启，自 desktop.3 起）**：desktop.2 及更早版本需要手动覆盖安装一次。此后应用在启动时及每 12 小时从本仓库的公开 Windows x64 稳定发布检查新版并在后台下载。无需 GitHub 登录；离线或检查失败不阻塞编辑。草稿、预发布、其他平台及同版/旧版本不会安装。

- 在 Windows 通知区域右键 **OpenDirector** 图标，可「检查更新」、取消进行中的下载、关闭或重新开启自动更新。开关按当前用户保存。
- 下载完成后点击通知或「安装并重启」。**保存工程、等待导出和 Agent 任务完成后再确认**；选择“否”不会关闭应用。没有授权就不安装，不强制重启。
- 更新使用 Sigstore 发布清单验证，不是只匹配下载站提供的校验和。客户端验证固定 GitHub Actions 工作流身份和透明日志证明，再校验 EXE 的签名清单大小与 SHA-256。安装前再次验证，等待旧宿主及后台服务退出后替换资源并重启。
- 出错时查看 `desktop.log`；网络恢复后右键托盘重试。下载缓存位于 `%LOCALAPPDATA%\OpenDirector\Desktop\updates`。也可从下方验证过的渠道手动覆盖安装，工程和模型配置保留。

**卸载**：使用 Windows 设置中的「已安装的应用」。工程、模型设置和 WebView2 配置默认保留；如需彻底删除，先备份，再手动处理数据目录（包括自定义的根目录）。

### 无法启动或重开？

- 检查 WebView2 Evergreen x64 是否可用；查看 `desktop.log`。desktop.4 改由系统分配本机端口；无需腾出 48765 或开放防火墙。日志可从托盘直接打开。
- 异常退出后，上游编辑租约最多保留约 **60 秒**。等待后重新连接，不要删除 SQLite 索引或锁文件。
- Agent 不工作时，先检查模型配置、网络和诊断；不要在错误报告中包含密钥、完整项目目录或会话凭据。

## 复现 Windows 构建

构建机需要 Windows x64、Python 3.12、Node.js 24.22.1/npm、NSIS 3、.NET Framework 自带的 x64 C# 编译器和网络。**这些是构建机依赖，不是最终用户的开发环境要求。**

```powershell
python scripts/package.py
& "${env:ProgramFiles(x86)}\NSIS\makensis.exe" /INPUTCHARSET UTF8 desktop\setup.nsi
Get-FileHash delivery\*-Setup.exe -Algorithm SHA256
```

产物在 `delivery/`。大二进制不进 Git。打包脚本固定上游提交和依赖版本，并校验 Python、Git、ripgrep、FFmpeg 归档 SHA-256 和 OpenCode 的 npm 锁文件完整性。安装中保留上游 LICENSE/NOTICE、字体许可、Python 包元数据、Git/FFmpeg 发行说明及许可证。来源：[OpenDirector](https://github.com/ThinkFlowLab/OpenDirector)、[Python standalone](https://github.com/astral-sh/python-build-standalone/releases/tag/20261110)、[Git for Windows](https://github.com/git-for-windows/git/releases/tag/v2.56.1.windows.1)、[FFmpeg Windows 构建](https://github.com/GyanD/codexffmpeg/releases/tag/9.0.2)。

### 维护者：发布更新到稳定频道

1. 递增 `desktop/VERSION`（格式 `X.Y.Z-desktop.N`），在授权分支构建。客户端只信任本仓库 `.github/workflows/windows.yml` 在 `main` 或当前桌面工作分支的 Sigstore 签名，验证不依赖维护者向用户分发密钥。
2. Windows 测试通过后，单独的 OIDC 签名作业生成 `windows-update.json` 和 `windows-update.json.sigstore.json`；Windows handoff 测试用真实签名和 EXE 验证重启流程。候选验收工作流会把它们与同一 EXE 放进草稿。
3. **仅当决定对用户推送时**，将标签 `windows-x64-X.Y.Z-desktop.N` 的草稿发布为普通 Release（不要标记 pre-release）。发布前核对三份资产齐全。不要替换既有版本；修复应递增版本号。过期信任根等验证失败时不会退回未验证安装，应通过可信手动渠道重新引导安装。

## 验证

- `python -m unittest discover -s tests -v`：桌面私有传输、Host/Origin 检查和 ASGI 生命周期。
- [Windows 构建记录](https://github.com/hanyingHY/For-OpenDirector/actions/runs/44265737164)：编译 PE、运行打包的 OpenCode/媒体工具，安装后通过 CDP 操作**已经打开的原生 WebView2 窗口**，不是另外启动 Chrome。CDP 只由测试父进程启用。
- [候选安装包独立验收](https://github.com/hanyingHY/For-OpenDirector/actions/runs/44267734067)：在另一台 Windows runner 下载相同 EXE，隔离开发工具 PATH，使用带空格及中文的工作目录，导入图片、编辑提示词、导出 `.canvas`、从 desktop.3 覆盖升级到 desktop.4、英文重开、从聊天框驱动原生 Agent 写入同一项目并验证凭据保留、导入时间线、渲染 MP4 并用 ffprobe 检查编码、尺寸和时长。
- `scripts/smoke.ps1` **仅在空白测试账号 / VM 中运行**：会安装、终止和卸载应用。`scripts/agent-check.ps1` 运行上游包含真实 OpenCode 子进程的回归，用确定性的本地模型响应，既不伪造 Agent 程序也不发送付费请求。
- `delivery/candidate.json` 指向当前分支上要复验的既有构建。候选工件通过 GUI 验收后才回存小型证据，并把原始 EXE 附加到该提交对应的维护者 **draft release**（须事先用 `gh release create <tag> --draft --target <完整构建提交>` 创建，标签写入 `draftTag`），不会向上游推送或公开发布。

本仓库只处理 [RFC #362](https://github.com/ThinkFlowLab/OpenDirector/issues/362) 的 Windows 范围。生产 Authenticode 签名、真实付费模型与各 Windows 客户端 / GPU 组合仍需单独验收。
