---
name: blender-gmod-playermodel
description: Convert or repair a Blender character into a Garry's Mod player-model addon with optional separate first-person c_hands. Detect the toolchain, let the user choose who installs missing software, fit and bind the character, preserve textures, compile and install reversibly, then hand visual and game acceptance to the user. Use for player-model and first-person hand creation or deformation repair, not unrelated props or maps.
---

# Blender 人物 → GMod 玩家模型与第一人称手模

产出保留角色外观、可回退的玩家模型 addon，并支持从原人物制作独立第一人称 c_hands。经典 Valve/GMod 模型提供标准骨架和编译规范；不把其可见网格、贴图替换进用户角色。

## 第一步：检测软件，选择安装方式

**转换或修复前先运行** `scripts/detect_gmod_toolchain.ps1 -Json`，阅读 [工具与安装选择](references/prerequisites.md)。使用返回路径；先排查自定义路径、Steam 库和下载缓存，区分真正缺失、路径未找到和插件未启用。

- 生产工具包括 Blender、Python、官方 Blender Lab MCP、Blender Source Tools、Crowbar、StudioMDL、VTFCmd 和 GMod 参考资源。HLMV 是用户验收的可选工具；GMad、发布工具按用户任务需要处理，不能因可选软件缺失阻塞制作。
- `Ready` 只代表文件发现。连接 MCP 并读取正确场景、实际导入导出和编译成功，才证明制作操作可用；不为证明游戏可用而启动游戏。
- 确认缺少必需工具后，列出缺失项并提供两个选项：**用户自行安装** / **由 Codex 安装**。等待用户选择，不能把未回答或默认选中当作安装授权；本次已有明确安装方式授权时沿用，不重复询问。
- 用户自行安装：浏览并核实官方或项目主仓库的下载页，给出逐项可点击链接、兼容版本/架构要求、简明安装及插件启用步骤。能核实直接资产链接时一并提供。不代下载、安装或修改配置；用户告知完成后重读路径及制作所需连接状态。可继续不依赖缺失工具的准备工作。
- 由 Codex 安装：按选择实际下载、解压/安装、启用并重跑检测，保留已有配置和正常工作的版本，记录来源与摘要。具体权限仍按执行环境处理；Steam 登录、购买及许可确认交给用户。

只更新 skill 时，不继续模型制作、不安装整套软件、不打开 Blender/HLMV/GMod。

## 范围与保护

确认源文件、导出对象、ASCII addon/model slug、显示名、动画族、独立材质和第一人称手模需求。完整人物转换时一并考虑原角色的第一人称双臂、手套与袖口；用户只要求第三人称或局部修复时，不扩大修改范围。

- 实时 Blender 编辑使用 `$blender-mcp` 的官方 MCP，先读取当前场景；断线后重新确认，不用后台 Blender 替代现场编辑。
- 原始文件不覆盖，建立具名工作副本。拟合、绑定、导出、编译及安装前保留检查点；先读已有产物和日志再续做。
- 保留原贴图像素、UV、独立材质及未涉及区域。按原始位置、权重、拓扑和用途划分部件，不能把同材质所有面当成一个身体部位。
- 独立 staging 编译；Source 临时路径和文件标识优先 ASCII。旧 addon 备份到 `garrysmod/addons` **以外**，避免重复挂载，不改其他 addon。

## 制作流程

### 1. 源场景和参考骨架

通过 MCP 读取对象、骨架、变换、尺寸、修改器、顶点组、UV、材质、图像节点及缺失资源。保存可复用的源数据，不默认制作基线渲染或截图。

按 [玩家模型流程](references/workflow.md) 从本机已安装/挂载的经典角色提取并反编译参考。保持标准 ValveBiped 名称、父级、静止变换和附件/IK/布娃娃约定；SMD 数字 ID 可以一致重映射，不能只改骨名而不变换绑定空间和权重。

### 2. 拟合、权重、服装与材质

把角色网格按关节中心拟合到标准骨架，保持标准骨架静止变换，不用 QC `$scale` 掩盖单位问题。清除陈旧/零/极小权重，最多三个有效骨影响，归一化且保留唯一有效权重。

明显改变角色比例的方案先说明实际差异并取得用户选择：更匹配的经典参考、接受有限拟合，或自定义骨架及整套动画重定向。已有授权沿用。自定义骨架不能未经重定向直接复用标准动画，也不意味着第一人称手骨跟着改动。

手部、附件和裙摆问题读取 [局部变形修复](references/deformation-repair.md)。保留角色设计和不在修改范围内的几何。保留每个独立 Source 材质，按真实节点及 UV 转换 VTF、建立 VMT；核对 SMD 材质名、`$cdmaterials` 和 `$basetexture` 路径。不要用 `save_render` 代替原始纹理导出。

### 3. 独立第一人称手模

制作或修复第一人称时读取 [c_hands 制作](references/first-person-hands.md)。从原角色提取手臂、手套和袖口，另用本机原生 c_arms 骨架适配；保持关节、手指链、标准静止矩阵和程序骨骼约定。

按骨骼实际局部轴拟合，保持手指长度、宽度和厚度的比例以及掌根连续过渡。第三人称骨架可保留角色比例，但 c_hands 必须独立满足武器骨骼合并约定。原生参考的可见手、武器及诊断材质仅用于制作参考，不能打包替代角色外观。

### 4. 导出、编译、打包和安装

制作过程中处理真实错误：确认导出文件存在完整、骨/权重有效、编译退出码及日志、模型文件族和材质齐全、注册路径正确；安装时核对文件复制与备份。不要把这些成功状态写成用户已游戏验收。

玩家模型按实际动画族使用 `m_anm.mdl` / `f_anm.mdl` 或已授权的重定向库，打包 MDL/VVD/VTX/PHY、可选 ANI、VMT/VTF 与 Lua。用同一精确路径注册 `list.Set("PlayerOptionsModel", ...)` 和 `player_manager.AddValidModel(...)`。

第一人称手模单独编译和打包，注册 `player_manager.AddValidHands(...)`，其注册名称键与玩家模型相同；常规 c_hands 不要求玩家模型 PHY/碰撞和选择器注册。

辅助脚本可供明确请求的静态检查或定位真实导出/打包错误：`validate_smd.py`；`validate_gmod_addon.ps1 -ModelKind PlayerModel|Hands`。不默认追加独立验证阶段或反复运行测试，参数与适用范围见对应参考。

## 完成后由用户自行验证

**默认制作、编译、打包与可回退安装完成后直接交付，由用户验证。** 不自动启动、关闭、重启或操控 GMod/HLMV；不默认进行动作压力测试、离线动作渲染、截图或游戏验收。不因为缺少这些验收证据继续制作、阻塞交付或要求用户先批准测试。

交付模型/addon 路径、工作 .blend、必要日志、回退位置，以及简短自检建议：完全重启 GMod，重新选择人物，检查外观、走跑蹲跳、持枪、换弹、手指和布娃娃；手模说明适用武器条件。明确写“游戏效果由用户验证”，不声称实测通过。

只有用户另行明确要求预览、诊断某个动作或委托验收时，才做对应范围的检查；不得扩大为整套游戏测试。临时姿势和渲染均用 `try/finally` 恢复；用户授权自己重启时不代重启。用户反馈后按真实症状修复，保留最后可用版本。

## 故障与技能维护

失败先读 [故障排查](references/troubleshooting.md)，不以相同失败输入反复编译或安装。报清已完成的制作操作、实际错误、剩余限制和用户需完成的安装/验收步骤。

更新本 skill 后运行 skill-creator 的 `quick_validate.py`；修改辅助脚本时运行对应隔离回归，不安装软件、修改 Blender 场景或触碰游戏 addon 来测试技能。技能检查不等于模型游戏验收。
