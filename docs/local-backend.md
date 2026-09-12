# 本地模型后端（草案 · 第一期不实施）

## 目标

本地模型（Whisper / SenseVoice / Ollama 等）不嵌进 Flutter 客户端，而是由一个**独立的本地
Python 后端进程**提供 HTTP 服务。Flutter 客户端通过**与在线 API 完全相同的链路**调用它。

## 为什么

客户端里不存在「本地分支」和「在线分支」两套代码。本地后端只是 `AsrProvider` /
`TranslationProvider` 的又一个实现，与 OpenAI、阿里百炼平级。好处：

- 流水线、进度、断点续跑、取消、日志、错误处理全部复用一套。
- Python 侧可以自由用 torch / funasr / faster-whisper，不受 Dart 生态限制。
- 后端可以独立升级、独立崩溃，不拖垮客户端。

## 协议

后端暴露 **OpenAI 兼容**接口，这样它天然就能被现有的 `OpenAiCompatibleAsrProvider` /
`OpenAiCompatibleTranslationProvider` 直接驱动，无需新增客户端代码：

```
POST {baseUrl}/v1/audio/transcriptions    # multipart, 兼容 OpenAI Whisper
POST {baseUrl}/v1/chat/completions        # 兼容 OpenAI Chat，用于翻译
GET  {baseUrl}/v1/models                  # 列出已安装的本地模型
```

额外的、非 OpenAI 的管理接口（模型下载、显存占用、健康检查）走独立命名空间，
由客户端的「本地服务」设置页调用：

```
GET  {baseUrl}/local/health               # {status, gpu, vramUsedMb, vramTotalMb}
GET  {baseUrl}/local/models               # 已安装 / 可下载模型清单与校验和
POST {baseUrl}/local/models/{id}/download # 流式返回下载进度
```

## 客户端侧预留

已经预留好的位置（第一期为 stub，不发请求）：

- `lib/services/local/local_backend.dart` — 后端进程的发现、健康检查、生命周期
- `AsrProviderId.localBackend` / `TranslationProviderId.localBackend` — 枚举项已存在
- 设置页「本地服务」分区 — 已渲染，标注「第一期未实施」

启用时要做的事，仅此而已：把 `localBackend` 的 `baseUrl` 指向后端进程，
复用 OpenAI 兼容实现。
