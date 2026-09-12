# 字幕工具 · Flutter 客户端

跨平台桌面应用（macOS / Windows / Linux）。两项核心能力：

1. **音视频语音生成字幕** —— 抽音 → 识别 → 断句
2. **字幕翻译** —— 大模型按批翻译，条数严格一一对应

UI 遵循 Claude Design 项目「桌面字幕工具 · 设计系统」。

## 跑起来

```bash
cd app
flutter run -d macos      # 或 -d windows / -d linux
```

需要 `ffmpeg`（用来抽音）。应用会依次在「应用目录/ffmpeg」、Homebrew 与
`/usr/local/bin`、PATH 里找它：

```bash
brew install ffmpeg
```

Windows 把 `ffmpeg.exe` 放进应用目录下的 `ffmpeg` 文件夹即可。

首次使用先去**设置**里填识别与翻译服务的地址、模型和密钥。

## 架构

```
lib/
  core/theme/      设计令牌 → ThemeData（ColorScheme / TextTheme / 三个 ThemeExtension）
  core/widgets/    玻璃面板、渐变按钮、状态标签、进度条…
  domain/          Cue / SubtitleDocument / SubtitleTask，SRT 编解码
  services/        provider 抽象 + OpenAI 兼容实现 + 登记表 + 设置
  services/local/  本地后端客户端（第一期为 stub）
  pipeline/        六阶段流水线与任务队列
  features/        shell / tasks / editor / settings
```

### 为什么「本地」不是一条单独的代码路径

本地模型（第二期）由一个独立的 Python 进程提供服务，对外暴露 **OpenAI 兼容**
接口。于是客户端这边只是多一个 `baseUrl` 指向 `127.0.0.1` 的 provider ——
流水线、进度、断点续跑、取消、日志、错误处理全部原样复用。

Ollama 和 LM Studio 说的也是这套协议，所以**现在就能在本机跑翻译**：
装好之后在设置的「翻译服务」里选中它们即可。

详见 [`../docs/local-backend.md`](../docs/local-backend.md)。

### 断点续跑

任务分六个阶段：排队 / 准备 / 识别 / 断句 / 翻译 / 完成。失败或取消时，
**已完成阶段的结果全部保留**，重试从中断处继续。翻译阶段以「这一条有没有译文」
为断点，续跑只翻剩下的，不会重复花钱。

### 翻译为什么要带行号

大模型翻译字幕最常见的故障不是翻错，而是**条数对不上** —— 把两行合成一句、
丢掉语气词、为了语顺把成分挪到下一行。一旦发生，后面所有字幕的时间轴就全错位了。

所以线路协议给每行打了行号（`§3§ ...`），返回后逐行核对：条数不符、行号越界或
重复，这批就判定为不可信，减半批量重试，绝不把错位的译文写进字幕。

## 测试

```bash
flutter test                                  # 单元与集成测试
flutter test --tags golden --run-skipped      # 界面截图核对
flutter test --tags golden --run-skipped --update-goldens   # 重新生成截图
```

截图测试依赖宿主机的系统字体，换机器像素就会不一样，所以默认跳过。

## 第一期没做的事

- **视频播放**：编辑器的预览区保留了版位并在画面里标明未实施。做它要引入
  media_kit / video_player 这类重依赖，与两项核心功能无关。字幕样式预览
  （黄字黑底那一块）用的是真实数据，是可用的。
- **本地模型**：见上。接口已留好。
- **阿里百炼 Qwen3-ASR**：它的识别接口不是 OpenAI 兼容形态，且不返回时间戳，
  需要先做静音切分才能对接。已在登记表里标为未实施，选中时给明确提示。
- **密钥存储**：目前明文存在 `shared_preferences` 里，还没接 macOS Keychain /
  Windows Credential Manager。
- **字体**：设计稿要求打包 Noto Sans SC 与 JetBrains Mono 的 ttf。
  目前用同名系统字体回退（PingFang SC / Microsoft YaHei、SF Mono / Consolas），
  把 ttf 放进 `assets/fonts/` 并在 `pubspec.yaml` 里声明即可切到设计指定的字体。
