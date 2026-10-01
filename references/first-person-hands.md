# 第一人称角色手模（c_hands）制作

本参考适用于用户要求把角色的手、手套、袖口或前臂用于 GMod 第一人称视角。第一人称手模是独立模型产物，应与第三人称玩家模型分别保存、导出、编译和注册。

默认完成范围是制作、制作错误检查、编译、可回退安装及交付。最终效果由用户完全重启 GMod 后自行验收。不要默认开启渲染、姿势压力测试、HLMV 检查或游戏实测；只有用户明确委托动作诊断、预览或游戏验证时，才在对应范围内进行。

## 软件缺失时先选择安装方式

先使用主流程的工具检测与已有路径检查，区分手模制作必需的软件和用户验收可选的软件。HLMV 是可选查看工具，缺少它不应阻止普通手模制作。

确认缺失必需软件或插件时，先让用户选择“用户自行安装”或“由 Codex 安装”。用户选择自行安装时，提供该软件当前官方或项目主仓库的下载链接、所需组件及安装启用步骤，等待用户安装后继续依赖操作。用户选择由 Codex 安装时，在授权范围内安装并确认实际可用。不要在选择前自动下载安装，也不要把已有下载缓存当作安装成功。

官方来源与具体检测步骤沿用 [工具检测与安装选择](prerequisites.md)。软件已经正常工作时，无需为手模制作升级它。

## 1. 建立独立源网格

从原角色创建具名手模工作副本，保留可恢复的原始文件。实时场景操作遵循主流程的 Blender MCP 约定。

通过几何位置、连通片、骨骼权重及用户要求确定左右手、手套、袖口和所需前臂的范围。共用材质不代表同一身体部位；不要按一个材质名选出整个身体或整件衣服。

提取时保留原顶点顺序或明确的源顶点映射、拓扑、UV、材质槽、材质分配和原始权重。第一次提取应保存未经拟合的源对象，后续修复从它重新计算，避免不断叠加变换。仅保留手模所需的几何；切口位置和可见袖口按角色设计处理。

原第三人称玩家模型、其自定义骨架、已有动画重定向及动作兼容处理保持独立。不能因为第三人称允许自定义比例，就让第一人称手模直接使用同一套静止骨架。

## 2. 选择本机实际原生参考

优先从用户本机 GMod 实际安装或挂载的原生 `models/weapons/c_arms_*.mdl` 提取并反编译，放入独立参考目录。核对配套 MDL、VVD、VTX 和必要的动画数据是否完整；直接使用对应模型的实际 reference bind pose。

参考 QC 可能包含多个 body、bodygroup 或参考 SMD。应读取 QC 并检查每个参考网格的几何、权重和材质用途，区分真正的手掌/手指网格与袖子或前臂网格。文件名含 `c_arms` 并不保证那个 SMD 含有手掌；用袖子网格当手指几何参考会失去厚度和指尖信息。

参考模型的静止姿态与它的 idle 动画可能包含不同根偏移。不要把动画第 0 帧、网络示例源码中的旧根位置或另一件武器的动画姿态当作最终 bind pose。也不要为了方便拼接来自不同参考的骨架与逆绑定矩阵。

按所选参考保留标准骨名、父子关系、静止变换和 helper/procedural 约定。骨骼数量由实际参考决定，不使用固定数字。SMD 骨 ID 是文件内部编号，可以一致重映射；每个权重索引都必须映射到正确的名字和绑定空间。

参考网格用于拟合与检查，最终包只包含用户角色的可见几何和获准使用的资源。

## 3. 第一人称骨架与拟合

GMod 的 hands 通常通过 `EF_BONEMERGE` 跟随当前武器 viewmodel。匹配的骨名会得到武器对应骨的变换；骨合并不会自动把自定义骨长或不同 bind pose 转换成标准比例。因此，手模应使用所选原生 hands 的标准绑定契约，角色网格在这个契约下适配。

静态制作检查至少确认：

- 骨名、父级、静止矩阵及逆绑定矩阵与参考一致，单位和坐标系有明确来源。
- 实际腕关节、各指根、各指节和指尖在正确位置，不能仅检查模型总边界或改骨名。
- 前臂、手腕、掌根、指蹼和指节过渡连续，没有离群顶点、塌陷横截面或薄片化手指。
- 手指具有合理的长度、宽度、厚度与横截面中心，拟合不会把指尖推到关节之外或压成刀片轮廓。

拟合纵向轴应由真实 joint head 到 child joint head、源网格指段中心线和实际 bone matrix 推导。Blender 可视 bone tail 或 `bone.length` 可能是导入后人为设置的显示长度；不要直接把可视局部 Y 当作实际链方向。也不要假定所有末节骨都沿局部 X，末节没有 child 时应检查对应网格的主方向与指尖范围。

指段拟合同时处理纵向长度、横向宽度、法线厚度、局部横截面中心和必要的解剖方向。只沿 X 拉长、照搬上一指节的伸长比或保持错误的末节 roll，可能让原本正常的细手指在持枪视角下呈现薄片。不要靠盲目缩短整根手指掩盖横截面问题。

掌部用手腕和多个指根作为共同控制点，检查掌面法线与厚度方向。简单的刚性掌部缩放或平均单轴比例不能保证各指根同时对齐。近共面的控制点拟合需要法线或厚度约束，避免仿射拟合把掌厚压塌。Hand 与 Finger 在相同关节附近应给出连续的映射；混合不相容变换会在权重过渡处拉伸掌根。

保持标准骨架不动，修改独立手模网格及其必要权重。需要改变角色可见手型、袖口或比例时，应依用户已授权的范围处理，并在交付中说明。没有证据时不改整条前臂或第三人称骨架。

## 4. helper 与权重

若实际原生参考包含 Ulna、Wrist 或其它程序骨，保留其父级、控制骨、trigger、静止位置和输出空间，并按对应 QC/VRD 设置。名称只作示例，不能向所有手模强行追加同一套 helper。

武器 viewmodel 中没有同名 helper 时，这些骨通常由手模自身的 procedural 逻辑在已合并的父骨下计算。不能把它们固定在 T pose，也不能用近似扭转冒充实际算法。排查程序骨问题时，比较控制空间、trigger 参数和运行时合并规则，不能只凭某个 flag 不同断定错误。

从源权重出发按实际几何整理：掌心主要跟随 Hand，指节跟随所属手指链，指蹼可有合理的相邻指根过渡，袖口/前臂按关节位置处理。helper 权重的添加和分配需符合参考契约及几何位置，不按材质整片覆盖。

移除不存在或陈旧的组，清除零/极小影响，最多保留 3 个有效影响并归一化。检查没有无权重顶点、跨手错误权重或被截断后改变所属部位的顶点。顶点法线、UV 和材料不能因权重清理被无意重建。

## 5. 独立导出与编译

为 hands 创建独立 SMD、QC、编译 staging 和模型路径。沿用原生参考的正确 bind pose、骨定义和程序骨设置，并使用用户角色的独立手模网格。是否包含共享 arms animation model、哪些骨需要 bonemerge、有哪些 bodygroup，应以实际原生 QC 和骨架为准。

GMod 官方教程建议保留 `c_arms_definebones.qci`，避免 StudioMDL 优化时删掉手模/武器合并需要的骨。该教程提供参考源码；选择与本机原生参考匹配的骨定义文件，核对其中的定义和 bonemerge 设置后再包含。[GMod 第一人称 hands 教程](https://wiki.facepunch.com/gmod/Using_Viewmodel_Hands)

下面 QC 只示意文件组织，不是可直接套用的完整模板；骨定义、helper/VRD、动画与 bodygroup 内容必须从所选参考核对：

```qc
$modelname "weapons/c_arms_character.mdl"
$body "hands" "character_hands_reference.smd"
$cdmaterials "models/player/character/"
$include "c_arms_definebones.qci"

// include 文件须与实际原生参考一致，不能与其它来源的骨定义重复。
// bonemerge 与程序骨/VRD 配置按同一参考核对。
// 静止序列及共享动画引用按该参考选择。
$sequence "idle" "character_hands_idle.smd" fps 30
```

检查导出的磁盘 SMD 中材质名、骨名、父级、绑定矩阵、权重和边界，保存完整 StudioMDL 编译日志。模型文件族通常包含 `.mdl`、`.vvd`、`.dx90.vtx`、`.dx80.vtx`；按编译目标及实际输出完整打包。第一人称 hands 不强制要求 `.phy`，不能因为缺少玩家模型用的布娃娃文件判为失败。

辅助静态工具仅在用户明确要求静态检查或定位真实导出/打包错误时使用：`validate_gmod_addon.ps1 -ModelKind Hands`。使用 `validate_smd.py` 时，其默认人体高度阈值不适合 hands；根据所选实际原生参考和合理袖口范围推导 `--min-height` / `--max-height`，同时比较关节点和绑定矩阵。不要为了通过检查任意放宽阈值，也不要把脚本通过表述为用户已验收。

如果本次任务只是编辑 skill，仅写说明和相应工具改动，不运行真实模型转换、渲染、编译或游戏验收。

## 6. 精确注册与武器兼容

第一人称模型路径必须在 addon 内实际存在，注册模型路径与文件大小写/拼写一致。`AddValidHands` 的第一个参数使用与 `AddValidModel` 完全相同的注册显示键；不能改用 addon slug 或猜测的模型名。[AddValidHands 参数说明](https://wiki.facepunch.com/gmod/player_manager.AddValidHands)

```lua
local modelName = "角色显示名"
local playerPath = "models/player/character/character.mdl"
local handsPath = "models/weapons/c_arms_character.mdl"

player_manager.AddValidModel(modelName, playerPath)
player_manager.AddValidHands(modelName, handsPath, 0, "0000000")
list.Set("PlayerOptionsModel", modelName, playerPath)
```

最后两个 hands 参数分别为 skin 与 bodygroup 字符串，应按实际编译模型配置填写；示例值不代表所有模型都需要相同 bodygroup 数量。GMod 通常先将玩家模型路径翻译为注册键，再查对应 hands，所以这个键必须精确一致。

原生 C 模型武器与支持 hands 的 SWEP 可使用注册手模。自定义 SWEP 需要适合的 C viewmodel 及 `SWEP.UseHands = true`。[GMod 官方 hands 教程](https://wiki.facepunch.com/gmod/Using_Viewmodel_Hands)

如果武器自带固定手臂、采用不兼容骨架或自定义渲染方式，单独注册 c_hands 不保证它显示角色手模。交付时说明适用范围，不批量修改用户其它武器 addon。

## 7. 安装、交付与用户验收

安装前在 `garrysmod/addons` 外备份旧版本，避免新旧 hands 同时挂载。将玩家模型和独立 hands 的注册及文件一起安装，静态比较 staging 与安装文件的相对路径、大小和哈希，保留回退路径。

交付工作副本、独立 hands 源文件、编译产物、材料、日志、制作错误检查结果及安装/回退位置。明确“已编译、已安装”与“用户尚未游戏验收”对应的实际状态。

模型或注册文件更新后，由用户完全退出并重新启动 GMod，再选择对应玩家模型自行查看第一人称手、手套/袖口、持枪和换弹效果。不要默认关闭用户游戏、启动测试会话或要求必须经过 agent 的验收才算交付完成。

若用户后续明确委托动作诊断，限定具体武器、动作和相机视角再检查。第一人称问题需要对应真实 viewmodel、真实动画及正确视点，普通离线 T pose 或第三人称相机不能说明第一人称轮廓。所有临时姿态、可见性、相机、渲染和场景设置用 `try/finally` 恢复；留证据后回到工作状态，不遗留测试 pose 到导出对象。

官方约定可查：[GMod 第一人称 hands](https://wiki.facepunch.com/gmod/Using_Viewmodel_Hands)、[AddValidHands](https://wiki.facepunch.com/gmod/player_manager.AddValidHands)、[Valve 骨合并源码](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/game/client/bone_merge_cache.cpp)、[Valve 程序骨源码](https://github.com/ValveSoftware/source-sdk-2013/blob/master/src/public/bone_setup.cpp)。
