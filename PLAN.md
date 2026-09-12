# 字幕工具 · Flutter 重构计划

用 Flutter 重做本项目的桌面客户端（Windows / macOS / Linux）。UI 遵循 Claude Design
项目 `a18fe120-0675-45f9-bda3-1eeb471bb364`（桌面字幕工具 · 设计系统）。

## 分支

- **`Joycai-main`** —— 主分支，所有开发合并到这里。
- `main` —— fork 时的上游快照，仅作参考，不开发、不合并。
- 功能分支从 `Joycai-main` 切出，再开 PR 合回 `Joycai-main`。

## 范围

保留原项目两项核心能力：

1. **音视频语音生成字幕**（ASR）
2. **字幕翻译**（MT）

第一期**只实现在线 API 对接**。本地模型不实施，但把接口留好。

## 本地模型方案（草案，暂不实施）

独立的本地 Python 后端以 HTTP 暴露模型服务，Flutter 客户端**走与在线 API 完全相同的链路**
调用它 —— 即本地后端只是 `AsrProvider` / `TranslationProvider` 的又一个实现，
客户端不区分「本地」和「在线」两条代码路径。

详见 [`docs/local-backend.md`](docs/local-backend.md)。

## 阶段

| 阶段 | 内容 | 状态 |
|------|------|------|
| P0 | 建分支、归档 Python 实现、计划文档 | ✅ |
| P1 | Flutter 脚手架 + 设计系统（令牌 / 主题 / 基础组件） | ✅ |
| P2 | 应用框架（玻璃 Rail、顶栏、状态栏、路由、壁纸底层） | ✅ |
| P3 | 领域模型 + SRT 解析/序列化 + 服务抽象层 | ✅ |
| P4 | 在线 API 实现（ASR / MT）+ 凭据存储 | ✅ |
| P5 | 任务流水线（ffmpeg 抽音、阶段机、进度、断点续跑、取消、日志） | ✅ |
| P6 | 任务页（表格、阶段条、详情面板、拖放新建） | ✅ |
| P7 | 编辑器页（字幕表、检视面板、校对、拆分合并、导出） | ✅ |
| P8 | 设置页 + 本地后端端口预留 | ✅ |

每个阶段一个（或数个）独立 commit。

## 目录

```
app/                Flutter 客户端
  lib/
    core/           主题、令牌、通用组件
    domain/         模型（Task / Cue / Stage）、SRT 编解码
    services/       ASR / MT provider 抽象与在线实现
    features/       tasks / editor / settings 页面
archive/python/     原 Python 实现（仅作功能参考，后续可能删除）
docs/               新文档
```

## 原实现的功能参考点

- `archive/python/videotrans/recognition/` — 各家 ASR 对接（OpenAI 兼容、阿里百炼 Qwen3-ASR 等）
- `archive/python/videotrans/translator/` — 各家翻译对接与分批策略（按 N 条一批、md5 缓存）
- `archive/python/videotrans/prompts/srt/` — 字幕翻译提示词（1:1 块保持、口语化、时长压缩）
