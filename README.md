# 明日方舟工具箱 (Arknights Toolbox)

这是一个为《明日方舟》玩家设计的 **iOS 原生应用**，提供多种资料查询与养成辅助功能，旨在提升游戏体验与效率。  
应用数据源来自 **PRTS 明日方舟中文 Wiki**，并通过自动化脚本与 Firebase 云存储保持同步更新。

---

## 📱 主要功能

- **干员材料查询**  
  快速查找任意干员的精英化材料、技能升级材料与模组材料，支持图标显示与稀有度高亮。

- **公开招募模拟器**  
  根据标签组合智能筛选符合条件的干员，支持资深/高级资深等特殊标签识别。

- **经验计算器**  
  输入当前等级与目标等级后，自动计算所需经验值与龙门币，并给出素材使用建议。

- **自动补全与标签筛选**  
  支持干员名称自动补全与多标签筛选操作，提升交互流畅度与搜索效率。

---

## 🧠 技术栈与架构

| 层级 | 技术/框架 | 说明 |
|------|------------|------|
| 前端 | **Swift + SwiftUI** | 使用 MVVM 架构，界面与逻辑分离，支持深色模式与动画交互 |
| 数据 | **Firebase Storage** | 存放所有 JSON 数据与图片（头像、技能图标、模组图标、材料图标）；App 优先读云端，并在本机缓存，离线可用 |
| 兜底 | **本地 JSON / Assets** | 云端不可用时使用打包在 App 内的少量数据 |
| 数据源 | **PRTS Wiki** | 通过 MediaWiki API 与"道具一览"页面获取干员、模组、公招与材料数据 |

---

## 🔁 数据更新机制

首页右下角的刷新按钮会在 App 内完成全部同步（代码在 `ArknightsToolBox/ViewModel/Sync/`）：

| 数据 | 云端路径 |
|------|----------|
| 干员名单 | `json/all_operators.json` |
| 技能列表 | `json/skills.json` |
| 模组列表 | `json/operator_modules_cleaned.json` |
| 公开招募标签 | `json/公开招募干员带标签.json` |
| 材料稀有度 | `json/arknights_materials_rarity.json` |
| 干员头像 / 技能图标 / 模组图标 / 材料图标 | `character_logo/`、`skill_icons/`、`module_icons/`、`material_icons/` |

特点：

- **增量同步**：用 PRTS 的"最近更改"判断哪些干员页面变化过，只重新抓取变化的部分；没有变化时几秒即可完成。
- **批量请求**：一次请求取多个页面源码，并统一限速、重试与退避。
- **安全写入**：单个干员失败不影响其他；已有非空数据解析为空时保留旧数据；覆盖 JSON 前自动备份到 `json_backup/`；图片上传前校验 PNG 完整性。
- **条件请求**：材料目录页面未变化时不下载、不解析。

数据解析逻辑参考了作者的另一个项目 [ArknightsResourceTool](https://github.com/JinjiaOu/ArknightsResourceTool)（Python 版采集工具）。

---

## 🛠 构建

项目使用 CocoaPods，请打开 **`ArknightsToolBox.xcworkspace`**（不是 `.xcodeproj`）：

```bash
pod install
open ArknightsToolBox.xcworkspace
```
