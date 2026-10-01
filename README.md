# blender-gmod-playermodel
使用 Blender 和官方 MCP 制作、修复 GMod 玩家模型与第一人称手模的 Codex Skill。

## 功能

- 将 Blender 人物转换为可操控的 Garry's Mod 玩家模型，保留角色外观、贴图和独立材质。
- 从原角色制作独立第一人称 `c_hands`，处理手掌、手指、手套及袖口的拟合与权重。
- 支持导出、Source 编译、Lua 注册、可回退安装和局部变形修复。
- 先检测工具；缺少必需软件时，让用户选择自行安装或由 Codex 安装。自行安装时提供官方链接和步骤。
- 制作完成交给用户自行验证游戏效果；默认不启动或重启 GMod，不进行动作压力测试或 HLMV 验收。

## 使用

1. 下载或克隆本仓库，将目录放入 Codex 的技能目录，保持以下位置：

   ```text
   ~/.codex/skills/blender-gmod-playermodel/SKILL.md
   ```

2. 配置 [官方 Blender Lab MCP](https://www.blender.org/lab/mcp-server/)，并准备配套的 `blender-mcp` skill。它提供实时 Blender 连接和场景操作指导，本仓库引用该技能。
3. 在 Codex 中调用，例如：

   ```text
   使用 $blender-gmod-playermodel 把这个 Blender 人物制作成 GMod 玩家模型，并制作她的第一人称手模。
   ```

工具检测及下载来源见 [安装方式说明](references/prerequisites.md)，第一人称流程见 [c_hands 制作](references/first-person-hands.md)。

## 环境与路径

当前辅助脚本主要面向 Windows，推荐 PowerShell 7 与 Python 3.10+。制作需要 Blender、Blender Source Tools、Crowbar、StudioMDL、VTFCmd、GMod 参考资源及可连接的官方 MCP。HLMV 是用户可选的查看工具。

脚本里的工具路径是候选或默认值。可用 `-ToolRoot`、`-GModRoot`、`-SteamRoots`、`-BlenderPath`、`-PythonPath` 等参数指定实际安装位置；下载助手可用 `-DownloadRoot` 指定缓存目录。

## 文件

```text
SKILL.md                 技能入口
agents/openai.yaml       Codex 界面元数据
references/              安装、模型、手模及修复流程
scripts/                 工具检测、下载与可选静态检查
```

游戏中的外观、动作、持枪、换弹和布娃娃效果由使用者自行验证；第一人称手模适用于支持 GMod hands 系统的武器。
