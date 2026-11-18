# Windows 对照清单 · RFC #362

核对基线：[RFC 与六项工作](https://github.com/ThinkFlowLab/OpenDirector/issues/362)；[对应的原版网页、服务与 CLI 源码](https://github.com/ThinkFlowLab/OpenDirector/tree/4360d9eb66b23598d3f637b2288745291e818862)。这是本分支的 Windows 验收记录，不代表上游已经接受或关闭这些 issue。

| 工作项 | Windows 处理方式 | 验证方法 / 不包含什么 |
| --- | --- | --- |
| [D1 桌面应用](https://github.com/ThinkFlowLab/OpenDirector/issues/363) | WebView2 加载由上游锁文件构建的完整 UI，而不是复刻界面或连接托管站点。Windows 原生宿主管理打包的 Python、Agent 和媒体进程；不用提案中的 Electron，不提供 JS → 原生执行桥。 | `scripts/package.py` 执行打包解释器的 import、Agent PE、rg 和 FFmpeg 检查；`scripts/agent-check.ps1` 用真实 Agent 加载内置 skill 并写入工程。 |
| D1 · 连接与同一工程 | 服务绑定 `127.0.0.1:0` 后通过私有管道报告端口。WebView2 内部把旧的浏览器 origin 映射到本次监听器，保留 localStorage / IndexedDB 命名空间。宿主用一次性随机挑战验证路由后才给本 origin 的请求附加凭据。CLI 从当前用户 DPAPI 票据读取本次端口并验证服务。 | `tests/test_transport.py` 检查认证、Host、Origin 和挑战不能充当凭据。`scripts/smoke.ps1` 占用旧端口；`scripts/smoke.mjs` 验证未认证请求被拒、不同编辑会话获得 409、CLI 读到同一 ID、升级前后浏览器标记仍在。 |
| D1 · 退出与恢复 | 主窗口 × 隐藏到托盘；再次启动或双击托盘恢复原窗口。托盘「退出」及「安装并重启」读取后端 Agent / 生成 / 工具运行数，并检查各窗口上游导出进度。检查失败显示状态未知；默认不退出。正常停机释放本次窗口的租约；崩溃用上游租约过期机制，绝不强占别人正在编辑的工程。 | 隐藏 ≠ 无窗口渲染服务；导出需要存活的渲染器，后台可能变慢。退出中断本地工作，不等于取消服务商已接单的远程任务。统计是确认前的快照，不承诺检测未来开始的任务。 |
| D1 · 命令 | 可直接调用打包的 CLI；托盘可选择注册 / 修复 / 移除 `OpenDirector-CLI.exe` 的当前用户 **App Paths**。可从 Win+R / ShellExecute 发现；不会安装同名全局 `opendirector`，也不更改 PATH。 | `OpenDirector-CLI.exe --help` 是上游 CLI 帮助。不同路径已占用注册名时不覆盖；卸载只删除匹配本安装路径的 CLI 注册。 |
| [D2 macOS](https://github.com/ThinkFlowLab/OpenDirector/issues/364) | 不在本次 Windows 委托内。 | 未构建、未签名、未测试；下载页无此包。 |
| [D3 Windows](https://github.com/ThinkFlowLab/OpenDirector/issues/365) | x64 每用户 NSIS `.exe`，带快捷方式、应用注册、分阶段替换、卸载保护。项目、密钥、WebView 配置不放进应用目录。 | 使用 Windows Server 2022 x64 托管 runner，应用 PATH 去除开发工具，用含中文及空格的数据路径测试；主机有系统 WebView2。目标是 Win10 22H2 / Win11 x64，不宣称两代消费系统、所有 GPU 和全新物理机都已测试。**无 Authenticode**。 |
| [D4 Linux](https://github.com/ThinkFlowLab/OpenDirector/issues/366) | 不在本次范围。 | 不提供 DEB、RPM 或 AppImage。HarmonyOS 同样不是本次交付。 |
| [D5 自动更新](https://github.com/ThinkFlowLab/OpenDirector/issues/367) | 固定稳定频道、签名清单与 EXE 散列校验、取消与重试、用户确认、等待旧进程、安装并重启。服务端草稿不会触发客户端更新。 | `tests/test_update.py` 检查版本、签名/摘要失败、中断、取消和不降级。`verification/update_handoff.py` 使用测试传输 + 真签名 + 真安装器验证等待和重启；不是一次公开推送。运行中拒绝替换、升级保留项目和凭据另由独立安装验收检查。未制造真实硬盘损坏或断电。 |
| [D6 下载入口](https://github.com/ThinkFlowLab/OpenDirector/issues/369) | `delivery/index.html`：中英文、响应式、平台与架构手选、无法确定时不猜，分别提示未提供构建/无稳定版/查询失败。仅在 GitHub 确实返回匹配的公开非预发行 EXE 时显示主下载按钮。草稿通过 README 单独标注维护者访问权限。 | `node verification/landing.mjs` 覆盖混合版本、草稿、错误资产、无发布和网络失败。这里是本 fork 的预览页，不冒充 [上游网站 / Pages #368](https://github.com/ThinkFlowLab/OpenDirector/issues/368)；公共域名、签名证书与正式发布需发行方决定。 |

## 最短复验路线

1. 空白 Windows 测试账号安装上一版，在中文窗口新建工程、导入图片、编辑提示词、保存并导出 `.canvas`。
2. 模拟宿主崩溃，覆盖安装新版，等待上游租约过期。旧端口另被占用时，验证同一工程 ID、节点、图片和窗口存储；切换英文。另一个写入会话应被拒绝，不能破坏原窗口。
3. 在这个工程的 **AI chat** 中发送请求。本地确定性模型只返回工具调用与文字：实际的 OpenCode 子进程、命令、写入回执、素材 ID 和持久化的回复均由应用生成。等待模型时检查真实 Agent 运行数；没有连接付费服务。
4. 通过同一窗口导入可编辑时间线、渲染并下载 MP4。打包的 ffprobe 应读到 H.264、640 × 400、约 1.5 秒。点 × 隐藏，再启动同一 EXE 应唤回原进程。
5. 尝试在窗口仍运行时覆盖安装，应被拒绝。用不可作为目录的路径模拟服务启动失败，检查双语错误和日志；卸载后检查工程文件、密钥文件散列与独立 CLI 注册。勿在真实用户账户运行破坏性安装测试。

核心命令、包来源、运行时版本与可下载产物见 [README](README.md)。
