# 历史设计需求索引

此目录保留 Claude Design 时期的原始 prompt 与来源链接，供追溯页面意图。它们不是当前设计工具的操作指令，不要求访问旧项目、readme.md、tokens/*.css 或 `.dc.html`。

当前标准由 Codex 在仓库维护，入口是 [设计系统](../design-system.md) 与 [UI 设计 skill](../../.agents/skills/subtitle-ui-design/SKILL.md)。令牌和组件以 Flutter 代码为准；行为以当前控制器、测试及 app/README.md 为准。

| 历史需求 | 当前代码入口 | 关注点 |
| --- | --- | --- |
| [翻译](translate-page.md) | [features/translate](../../app/lib/features/translate/) | 文件列表、参数、就绪与入队 |
| [转码](transcode-page.md) | [features/transcode](../../app/lib/features/transcode/) | 编码器能力、命令、输出与阻塞原因 |
| [合并](merge-page.md) | [features/merge](../../app/lib/features/merge/) | 有序分段、参数一致性、章节与字幕 |
| [编辑器](editor-page.md) | [features/editor](../../app/lib/features/editor/) | 本地/任务会话、说话人、检视与选择 |
| [编辑器保存](editor-save.md) | [editor_controller.dart](../../app/lib/features/editor/editor_controller.dart) | 自动存进度、手动写文件、冲突与另存 |
| [服务与词表](provider-settings.md) | [features/settings](../../app/lib/features/settings/)、[features/shared](../../app/lib/features/shared/) | 模型声明、服务配置、词表与建任务字段 |

外部项目是否仍有效未核实，本文不声称已经恢复原项目的全部画板。重建范围是当前应用可查证的设计与交互契约。
