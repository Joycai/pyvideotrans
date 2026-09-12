# 字幕工具（Flutter 重构）

> 本分支 `feat/flutter-rewrite` 用 Flutter 重做 [pyVideoTrans](archive/python/README.md)
> 的桌面客户端。**不合并回 main**，后续可能独立成项目。

保留原项目的两项核心能力：

1. **音视频语音生成字幕**（ASR）
2. **字幕翻译**（大模型）

UI 遵循 Claude Design 项目「桌面字幕工具 · 设计系统」。第一期只对接在线 API，
本地模型的接口已留好（见下）。

## 目录

| 路径 | 内容 |
|------|------|
| [`app/`](app/) | Flutter 客户端 —— **主要代码在这里**，跑起来与架构见 [app/README.md](app/README.md) |
| [`docs/local-backend.md`](docs/local-backend.md) | 本地模型后端方案（第二期） |
| [`PLAN.md`](PLAN.md) | 分阶段重构计划 |
| [`archive/python/`](archive/python/) | 原 Python 实现，仅作功能参考，后续可能删除 |

## 快速开始

```bash
brew install ffmpeg          # 抽音要用；Windows 见 app/README.md
cd app && flutter run -d macos
```

首次使用先去**设置**里填识别与翻译服务的地址、模型和密钥。

## 设计要点

**本地与在线不是两条代码路径。** 本地模型（第二期）由独立的 Python 后端提供
OpenAI 兼容接口，客户端只是多一个 `baseUrl` 指向 `127.0.0.1` 的 provider ——
流水线、进度、断点续跑、取消、日志全部复用。Ollama 与 LM Studio 说的也是这套协议，
所以**现在就能在本机跑翻译**。

**失败不等于从头再来。** 任务分六个阶段，失败或取消时已完成阶段的结果全部保留，
重试从中断处继续；翻译阶段以「这一条有没有译文」为断点，续跑只翻剩下的。

**译文条数必须与原文一一对应。** 大模型翻译字幕最常见的故障是合并或丢行，
一旦发生后面所有字幕的时间轴就全错位。线路协议给每行打了行号，返回后逐行核对，
对不上就减半批量重试，绝不把错位的译文写进字幕。

## 许可

沿用原项目的 [GPL v3](LICENSE)。
