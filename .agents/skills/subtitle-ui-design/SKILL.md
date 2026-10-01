---
name: subtitle-ui-design
description: Design and improve this repository's Flutter desktop UX/UI while preserving its established theme, components, and interaction contracts. Use for page layouts, UI polish, controls, visual states, and design reviews in Subtitle Studio.
---

# 字幕工具 UI 设计与实现

从仓库根目录开展工作。先读 [设计系统](../../../docs/design-system.md)，以及 AGENTS.md / app/README.md 中涉及本次行为的约束。设计不依赖 Claude Design 项目；旧链接不可用时继续使用本地代码与截图。

## 明确改动

根据用户问题检查相关页面、共享组件、控制器和测试。区分现有行为与建议改善，避免把历史 prompt 中未实现的内容当成已经存在的能力。

复杂任务用 [brief 模板](../../../docs/design-brief-template.md) 记录目标、状态、布局与行为契约。简单调整直接说明意图。只有会影响结果的缺失信息才需要澄清。

## 保持风格与交互

- 数值从 core/theme 取，优先复用 core/widgets 与 features/shared；设计系统含代码入口、布局阈值和截图索引。
- 保留蓝色动作、玻璃导航/浮层、不透明内容面板、独立深色主题与紧凑桌面密度。黄色用于字幕播放/待校对，渐变依照现有语义。
- 改布局时区分窗口宽与内容宽。检查长中文、长路径、窄窗口及本次涉及的空态、就绪、阻塞、运行、完成、失败。
- 保护入队快照、切页保留表单、断点续跑、设置自动保存、编辑进度与文件写入的区别；UI 不另造一套业务规则。
- 改控件时检查可见焦点、键盘操作、输入法、tooltip/semantics、禁用原因与文字对比。沿用 AppShortcut / ShortcutAction。

## 验证与交付

应用代码变更按 AGENTS.md 运行 analyze / test；界面变更另跑 golden。查看相关截图；已有方框图标与宿主字体差异是验证限制，不是设计标准。不能把只读过旧截图说成实际运行通过。

有意改变外观后，核对新结果与 brief，再更新必要的 golden 并说明原因。code-reviewer 审查不更新截图。纯设计文档或工作流变更检查链接和 skill 结构即可。

报告用户问题如何改善、改动位置、验证结果和剩余限制。新增共享设计决定同步 docs/design-system.md；无需发布到外部设计平台。
