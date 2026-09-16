# 字幕工具 · Flutter 客户端

跨平台桌面应用（macOS / Windows / Linux）。核心能力：

1. **音视频语音生成字幕** —— 抽音 → 识别 → 断句
2. **字幕翻译** —— 大模型按批翻译，条数严格一一对应
3. **视频转码** —— FFmpeg 的图形外壳，任务同样进任务队列

## 视频转码

导航栏「翻译」下面的「转码」页。

- 视频编码：H.264、HEVC、AV1，或原样复制；也可以「仅重混流」，不重新编码只换容器。
  不提供 VC-1（FFmpeg 只有 VC-1 解码器）；VC-1 源文件可以复制或重混流。
- 音频编码：AAC、MP3、Opus，或复制。不提供 Vorbis（OGG 音频），MP4 / MOV 都装不下它；
  Opus 只能放进 MP4。
- 容器：MP4、MOV。
- 编码器：CPU（x264 / x265 / SVT-AV1 / libaom）、VideoToolbox（Apple）、NVENC（NVIDIA）、
  QSV（Intel）、AMF（AMD）。**每个编码器用自己的一套参数**（x264 的 CRF 与 preset、
  NVENC 的 CQ 与 p1–p7、QSV 的 ICQ、AMF 的 CQP……），不做通用的「质量 / 速度」映射。
  参数表定义在 `lib/domain/transcode.dart` 的 `VideoEncoders`。
- 可用性检测：先看 `ffmpeg -encoders` 有没有编入，再对硬件编码器试编码 1 帧。
  编入了但没有对应显卡的会标「设备不可用」并写明原因。
- 产物写到 `原文件名.hevc.mp4`（后缀可改），已存在时加序号，不覆盖；先写 `.part`，
  成功后才改名。高级里能看到并复制完整的 ffmpeg 命令。
- 复制流时按源文件编码核对容器兼容（名单经本机 ffmpeg 实测），放不进的文件在列表里
  标「不兼容」并跳过。

硬件编码的端到端测试（`test/transcode_ffmpeg_test.dart`）在本机没有 ffmpeg 时跳过，
VideoToolbox 用例只在 macOS 上跑。

UI 遵循 Claude Design 项目「桌面字幕工具 · 设计系统」。

## 跑起来

```bash
cd app
flutter run -d macos      # 或 -d windows / -d linux
```

需要 `ffmpeg`（用来抽音与转码）。macOS / Linux 用包管理器装上就行：

```bash
brew install ffmpeg                # macOS
sudo apt install ffmpeg            # Debian / Ubuntu
```

Windows 装 ffmpeg 通常卡在「该放哪、怎么配环境变量」上，所以应用里留了条不用配的路：
**设置 → 环境 → 打开目录**，把 `ffmpeg.exe` 和 `ffprobe.exe` 拖进去，再点「重新检测」。
那个目录在应用支持目录下（不是安装目录 —— 安装目录在 Program Files 里，往里拖文件要过 UAC）。

完整查找顺序：投放目录 → 应用目录/ffmpeg（随包分发时放这儿）→
Homebrew 与 `/usr/local/bin` 等系统位置（Windows 上是 `C:\ffmpeg\bin`、winget、
scoop、choco 的落点）→ PATH。macOS 上 GUI 应用拿不到用户 shell 的 PATH，
所以必须显式找 Homebrew。

编辑器里的预览用 [media_kit](https://pub.dev/packages/media_kit) 播放音视频。
macOS 与 Windows 的播放库随应用打包；Linux 要装系统的 libmpv：

```bash
sudo apt install libmpv-dev mpv    # Debian / Ubuntu
```

首次使用先去**设置**里填识别与翻译服务的地址、模型和密钥。

打包 dmg / Windows 安装包以及应用图标的生成见 [packaging/README.md](packaging/README.md)。

## 架构

```
lib/
  core/theme/      设计令牌 → ThemeData（ColorScheme / TextTheme / 三个 ThemeExtension）
  core/widgets/    玻璃面板、渐变按钮、状态标签、进度条…
  domain/          Cue / SubtitleDocument / SubtitleTask / TaskOptions，
                   语言表、折行、SRT 与 VTT 编解码
  services/        provider 抽象 + OpenAI 兼容实现 + 登记表 + 可用性检查 + 设置
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

### 任务参数在入队那一刻定死

建任务时用的全部参数（语言、服务、模型、批大小、折行上限、产物格式与位置）
打包在 [`TaskOptions`](lib/domain/task_options.dart) 里，随任务一起入队。
任务是排队串行跑的，用户很可能在排队期间改设置去建下一个任务 —— 参数要是
运行时才去读全局设置，前面排着的任务就会被后面的改动影响，这类 bug 事后
极难复现。全局设置只作为新建任务时的默认值。

### 折行发生在导出时，不在文档里

单行字数上限（中日韩 15、其他 40，沿用原 Python 实现的默认值）在写出产物时
才应用。文档里始终存不带硬换行的干净文本，用户在编辑器里改完再导出会按当前
设置重新折，不会叠加上一次的换行。

### 产物命名与双语字幕

产物落在 `原文件名.语言代码.扩展名`：`demo.zh.srt` 是原文，`demo.en.srt` 是译文。
用代码而不是中文名，是因为中文带不进跨平台安全的文件名。

双语指**同一条字幕里两行文字**，不是两个文件 —— 播放器只能挂一轨字幕，想同时
看原文和译文只有这一条路。上下顺序由 [`BilingualLayout`](lib/domain/task_options.dart)
决定，产物名带上两种语言（`demo.zh-en.srt`），跟单语那份区分得开。两行各按
自己语言的单行上限折行：中日韩一行 15 字、拉丁语一行 40 字，用同一个上限必然
有一边难看。

纯翻译任务（输入本来就是字幕文件）只写译文，不再复制一份原文。

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
