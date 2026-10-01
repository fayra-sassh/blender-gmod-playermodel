# 第一步：工具链检测与安装方式选择

转换前运行 `scripts/detect_gmod_toolchain.ps1 -Json`。检测是只读的；`ReadyScope=file_discovery_only`、`AcceptanceVerified=false`。使用返回路径，不再猜可执行文件位置。发现真正缺失的必需工具后，先提供“用户自行安装 / Codex 安装”两个选项，等待明确选择再处理缺失项。用户已在本次会话选择过时沿用该授权，不重复询问。

本机已用 PowerShell 7 运行辅助脚本。脚本保持 UTF-8 BOM 以兼容 Windows PowerShell 的中文路径解析；若旧版 PowerShell 的执行策略禁止脚本，记录该限制并用已获准的执行环境，不修改安全策略来绕过限制。

## 检查对象与就绪证据

| 对象 | 用途 | 可用证据 |
|---|---|---|
| Garry's Mod | 参考模型、编译目标；成品由用户游戏验收 | 正确 Steam 库中的 `garrysmod` 和 `bin`，不为检测启动游戏 |
| Blender | 建模、绑定和导出 | 程序存在，版本与所用插件兼容 |
| Python 3.10+ | 辅助验证脚本 | `--version`；可使用 Blender 自带 Python，排除 WindowsApps 占位符 |
| 官方 Blender Lab MCP | 实时场景读写 | 工具已暴露，成功读取目标场景；配置段不是连接证明 |
| Blender Source Tools | SMD 导入/导出 | 插件代码已安装且当前 Blender 已启用；实际任务导入/导出无错误，ZIP 不算安装 |
| Crowbar | MDL 反编译/编译前端 | 程序及依赖可用，能反编译选定参考 |
| StudioMDL | Source 模型编译 | 来自 GMod/兼容 SDK；实际任务编译输出与日志无未处理错误 |
| VTFCmd | VTF 转换 | 实际任务转换产生完整输出；转换日志、纹理尺寸与格式符合输入要求 |
| HLMV | 可选的用户模型查看工具 | 文件发现仅记录可用位置，不作为生产必需项，不默认启动 |

HLMV 与 VTFEdit GUI 是可选查看工具；VPK 仅在参考位于归档时需要；GMad 仅在要生成 GMA 时需要；GMPublisher 只在用户要求发布 Workshop 时需要。不要把可选查看/发布工具的缺失当作转换阻塞。检测器的 `LiveChecksRequired` 只列生产工具检查，`UserChecksSuggested` 是交给用户的验收建议。

## 先找已有安装，再确认缺失项

检测器接受 `-ToolRoot`、`-GModRoot`、`-SteamRoots`、`-BlenderPath`、`-PythonPath`、`-CrowbarPath`、`-SourceToolsPath`、`-VTFCmdPath`、`-StudioMDLPath`、`-HLMVPath`。指定 `-GModRoot` 时不得悄悄改用另一个游戏目录；其余显式工具路径也必须有效。需要重跑时修改参数，而非拷贝到硬编码位置。

默认扫描已知本机路径、PATH、Steam 注册表/`libraryfolders.vdf`、工具目录和 Blender 插件目录，范围有限，**不是全盘搜索**。`-NoDefaultSearch` 仅供隔离测试/完全手动配置。路径未发现时先询问或检查用户指定位置，不能立即认定未安装。

输出里的 `CachedSourceToolsArchives` 只能帮助复用下载缓存，不能让 `BlenderSourceTools.Found` 为真。插件代码找到后，仍需检查当前 Blender 中是否启用。`DiscoveryWarnings` 表示有目录无法读取；不可把这些区域当作“确认没安装”，应指定可访问路径或通过现场插件查询补证。

## 必需工具缺失：先选择安装方式

列出缺失工具及用途，向用户提供以下两个选项，并等待明确答复。未回答时不下载、安装、解压插件或修改客户端配置；可以继续不依赖缺失项的资料整理。

1. **用户自行安装**：Codex 核实官方/项目主仓库的下载链接，给出适配版本和安装、启用步骤；用户负责下载、安装与配置。
2. **Codex 安装**：Codex 在用户已选授权和运行环境允许的权限内下载、安装/解压并配置；登录、购买和许可确认仍由用户完成。

链接与版本会变，两个分支都需在执行时浏览当前官方来源，核对操作系统、架构、Blender 版本和 Source 分支兼容性。不能固定使用过时镜像，也不能把源代码 ZIP 误认为可安装插件包。已工作的版本不自动升级。

### 用户自行安装

为每个缺失项给出可点击的官方发布/下载页面；能核实兼容的实际安装资产时同时给出直接下载链接、资产名和版本。无法核实直链时保留官方入口并说明需要选择的资产，不猜链接或宣称其已核实。给出相关步骤：

- Blender：按官方页面选择兼容的 Windows 安装包或便携包，安装或解压后记录 `blender.exe` 路径。
- Python：先复用 Blender 自带或已安装的 Python 3.10+。确实缺失时从 Python 官方下载页选择对应系统架构的安装包，安装后记录真实 `python.exe` 路径；可通过 `-PythonPath` 指定，不把 WindowsApps 占位符当解释器。
- 官方 Blender Lab MCP：跟随官方页面的服务与扩展说明，并阅读 `$blender-mcp` 的安装/连接指南；用户配置服务、在 Blender 启用扩展并启动 Bridge。保留其他客户端配置，不能用同名社区 MCP 替代。
- Blender Source Tools：选择项目说明中适配当前 Blender 的可安装插件包；用户按项目步骤安装并在当前 Blender 中启用，记录包目录和版本。只有下载 ZIP 不等于安装。
- Crowbar / VTFCmd：下载已核实的项目发行包，解压到具名版本目录，找到真实可执行文件；按发行说明处理依赖，记录工具路径。不要从不明网站补 DLL。
- Steam / GMod / StudioMDL：用户通过官方 Steam 客户端安装已有授权的 GMod，记录实际 Steam 库和 GMod 根目录；从该安装或兼容的官方 SDK 获取编译工具。购买、登录与许可确认由用户自行完成。HLMV 如随安装存在只记录其位置，无需为任务另外安装或启动。

本分支不调用下载助手，不代替用户下载、执行安装程序、解压插件、启用插件或改配置。交付步骤后等待用户告知安装完成及路径，再重跑只读检测；后续任务的真实导入、导出、转换和编译负责暴露生产错误，不安排默认的全套软件冒烟或游戏检查。

### Codex 安装

1. 沿用用户对本次缺失项选择的 Codex 安装授权；浏览下面的官方/项目主仓库，选择兼容资产。授权未取得时先返回安装方式选择，不因检测发现缺失而自动安装。
2. 告知下载对象、来源、版本、落盘路径、便携或系统安装方式。按运行环境取得网络/文件写入/安装权限；不要借脚本绕过审批。
3. 调用 `scripts/download_tool_asset.ps1`，默认缓存根目录 `D:\gmod工具\_downloads`；非默认机器可指定 `-DownloadRoot`。例如下列变量必须先替换为已核实值：

   ```powershell
   & "$SkillDir\scripts\download_tool_asset.ps1" -Url $VerifiedAssetUrl -Tool 'crowbar' -Version $VerifiedVersion -FileName $AssetName -DownloadRoot $DownloadRoot
   ```

   可用 `-ExpectedSha256` 对照发布方提供的摘要。每个资产旁生成 `.provenance.json`，记录请求/最终响应 URL、版本、SHA-256、签名状态和时间。下载助手只保存和校验，不执行、解压或安装。
4. 复用资产时重新校验摘要和来源。失败文件保持 `.partial`，不得执行。无签名的项目便携 ZIP 与来源未知的安装 EXE 不等同；签名失效或散列不符必须调查，不降低安全设置。不要执行不可信安装程序。
5. ZIP 解压到新的具名版本目录，查看包内真实路径；安装插件并在当前 Blender 中启用。MCP 按官方说明配置服务和扩展，保留其他客户端配置与已启用插件；调用 `$blender-mcp` 读取其专用安装/连接指南。**不要安装同名社区 MCP 来代替官方服务。**
6. 将已核实的安装位置、版本、来源和资产摘要记录到本次工程的工具审计报告；可维护工具根目录的清单，但必须合并现有记录，不覆盖整份清单。重跑只读检测，并在实际任务操作中检查连接、导出和编译结果；不以新安装为由自动安排全套冒烟测试或视觉/游戏验收。
7. 已有工具工作正常就保留。Steam 组件通过用户的 Steam 获取/验证；遇到登录、购买或许可确认交给用户，不自动购买，也不从第三方下载单独的游戏 DLL。

## 当前来源入口

- [Blender 官方下载](https://www.blender.org/download/)
- [Python 官方 Windows 下载](https://www.python.org/downloads/windows/)：按当前系统架构与辅助脚本要求选择；已有兼容解释器可复用。
- [Steam 官方客户端下载](https://store.steampowered.com/about/)
- [Garry's Mod 官方 Steam 页面](https://store.steampowered.com/app/4000/Garrys_Mod/)：登录、授权及游戏安装由用户的 Steam 完成。
- [官方 Blender Lab MCP](https://www.blender.org/lab/mcp-server/)：先核对支持的 Blender 版本，再跟随官方页面的服务/扩展发布链接。
- [Blender Source Tools 主仓库](https://github.com/Artfunkel/BlenderSourceTools)：遵循项目链接的插件包/发行说明。
- [Crowbar 发布](https://github.com/ZeqMacaw/Crowbar/releases)
- [VTFEdit Reloaded 主仓库发布](https://github.com/Sky-rym/VTFEdit-Reloaded/releases)：保留已验证能工作的旧版，不因发现新版本而升级。
- [Facepunch 玩家模型编译指南](https://wiki.facepunch.com/gmod/Player_model_compilation)
- [GMod 动画和 QC 示例](https://github.com/robotboy655/gmod-animations)

发布版本和地址会变，执行时重新核实直接下载 URL，不在 skill 中固定“最新版本号”。

## 生产检查与停止条件

- MCP 必须能读取正确场景和当前工作副本。服务存在但连接失败时停止场景编辑；沿用安装方式选择，由对应一方完成连接处理。
- 实际使用 Source Tools 导入参考、导出候选 SMD 后检查完整输出、`nodes`、`skeleton`、`triangles` 与操作错误；不把文件发现、插件启用或操作返回值当作导出成功。
- Crowbar/StudioMDL 的实际反编译与成品编译使用独立 staging，保存命令和日志，处理缺骨、权重、材质、物理及边界错误，不污染正在使用的 addon。
- VTFCmd 的实际材质转换需检查产物存在、完整性与纹理尺寸/格式；像素与 alpha 的保留依照材质生产要求处理，不额外强制 GUI 预览。

保存实际生产操作的命令、版本、输出和错误处理结果；需要定位工具错误时才做针对性最小检查，不默认运行完整软件冒烟、姿势渲染或视觉验收。已有与当前版本和输入匹配的有效记录可复用，`Ready` 仍只表示文件发现。

成品安装/交付后由用户自行验证。提供完整重启 GMod、选择人物、动作及第一人称持枪/换弹的简短检查建议和回退路径；Codex 不启动、关闭、重启或操作 HLMV/GMod，不等待用户验收才能交付，不声称已经游戏实测。只有用户另行明确委托验收时，才在该范围内执行相应检查。

本机历史路径仅作为候选：Blender `D:\Blender 5.2\blender.exe`；工具根 `D:\gmod工具`；GMod `D:\steam\Steam\steamapps\common\GarrysMod`。官方扩展曾使用 `bl_ext.user_default.mcp`，不只找社区插件键 `mcp`。
