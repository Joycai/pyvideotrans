# Joycai Subtitle Studio · Flutter 客户端

跨平台桌面应用（macOS / Windows / Linux）。核心能力：

1. **音视频语音生成字幕** —— 抽音 → 识别 → 断句
2. **字幕翻译** —— 大模型按批翻译，条数严格一一对应
3. **视频转码** —— FFmpeg 的图形外壳，任务同样进任务队列
4. **视频合并** —— 几段视频无转码首尾相接，每段一个章节，字幕按起点平移后拼成一份

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
  参数表定义在 `lib/domain/transcode/encoder_catalog.dart` 的 `VideoEncoders`。
- 可用性检测：先看 `ffmpeg -encoders` 有没有编入，再对硬件编码器试编码 1 帧。
  编入了但没有对应显卡的会标「设备不可用」并写明原因。
- 产物写到 `原文件名.hevc.mp4`（后缀可改），已存在时加序号，不覆盖；先写 `.part`，
  成功后才改名。高级里能看到并复制完整的 ffmpeg 命令。
- 复制流时按源文件编码核对容器兼容（名单经本机 ffmpeg 实测），放不进的文件在列表里
  标「不兼容」并跳过。

硬件编码的端到端测试（`test/transcode_ffmpeg_test.dart`）在本机没有 ffmpeg 时跳过，
VideoToolbox 用例只在 macOS 上跑。

## 视频合并

导航栏「转码」下面的「合并」页，一次建一个任务。

- N 段（至少 2 段）有序视频，可拖动或点箭头排序；同一个文件可以加两次。
  添加时 ffprobe 逐段读参数，**各段与第 1 段不一致就不让开始**，并指出哪段哪一项：
  流路数、视频编码 / profile / 分辨率 / 像素格式 / 画面方向 / 帧率（相对差 1% 以内算一致）、
  音频编码 / profile / 采样率 / 声道，以及编码能不能原样放进所选容器。
- 只做 `-c copy`（concat demuxer），不转码。容器 MP4、MOV。
- 每段一个章节（FFMETADATA），标题默认文件名、可改；开关默认开。
- 每段可挂一份 SRT / VTT；添加视频时旁边同名（或带语言后缀，如 `.zh`）的字幕自动挂上。
  各段字幕按「前面各段时长之和」平移后拼成一份：内嵌软字幕轨（`mov_text`）、旁挂 SRT 两个独立开关。
  合并后字幕的语言从各段字幕的文件名推断（各段一致才算数）：旁挂写成
  `<产物名>.zh.srt` / `<产物名>.Bilingual.zh.srt`，内嵌轨写 `language` 元数据（三字母码，
  MOV 只认 ffmpeg 那张 Macintosh 语言表，部分语言写不进去）。
  字幕只收 UTF-8（或带 BOM 的 UTF-16），别的编码直接报错，不猜。
- 产物默认 `<第 1 段文件名>.merged.mp4`，与旁挂 SRT 一起避让已有文件；先写 `.part`，成功后改名。
- 已知限制：某段音频比视频短时，拼接后音画会逐段累积错位，目前不检查也不提示。

端到端测试（`test/merge_ffmpeg_test.dart`）用 lavfi 现生成短片实跑，本机没有 ffmpeg 时跳过。

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
macOS 与 Windows 的播放库随应用打包；Linux 要装系统的 libmpv
（`packaging/linux/install.sh` 会自动装，手动跑 `flutter run -d linux` 时自己装一次）：

```bash
sudo apt install libmpv-dev mpv    # Debian / Ubuntu；Fedora 用 mpv-libs-devel，Arch 用 mpv
```

首次使用先去**设置**里填识别与翻译服务的地址、模型和密钥。

打包 dmg / Windows 安装包以及应用图标的生成见 [packaging/README.md](packaging/README.md)。

## 架构

```
lib/
  main.dart          装配点：服务对象、根级表单控制器、页面切换、顶栏与状态栏
  core/theme/        设计令牌 → ThemeData 与 ThemeExtension
  core/widgets/      无业务语义控件；fields.dart 是 dropdown / form_fields / form_layout 的公共入口
  domain/            纯数据与纯规则，不碰网络 / 外部进程
  domain/transcode/  编解码枚举、编码器目录、参数、探测结果、ffmpeg 命令
  domain/mux/        合并的参数与纯规则（一致性、偏移、章节、concat 列表、字幕平移）、MuxPlan
  services/          provider、ffmpeg / ffprobe、设置与持久化
  pipeline/          串行队列、任务编排、阶段壳、字幕写出、转码与合并执行
  features/shared/   跨 feature 共用的服务字段、命令块、参数分区、入队横幅与步骤说明
  features/          shell / tasks / transcribe / translate / transcode / merge / editor / settings
```

逐文件的职责、按功能反查、测试对照见 [`../docs/app-codemap.md`](../docs/app-codemap.md)。

### 为什么「本地」不是一条单独的代码路径

本地模型（第二期）由一个独立的 Python 进程提供服务，对外暴露 **OpenAI 兼容**
接口。于是客户端这边只是多一个 `baseUrl` 指向 `127.0.0.1` 的 provider ——
流水线、进度、断点续跑、取消、日志、错误处理全部原样复用。

Ollama 和 LM Studio 说的也是这套协议，所以**现在就能在本机跑翻译**：
装好之后在设置的「翻译服务」里选中它们即可。

详见 [`../docs/local-backend.md`](../docs/local-backend.md)。

### 任务参数在入队那一刻定死

建任务时用的全部参数（语言、服务、整份模型声明、勾选的词表展开后的条目、批大小、
折行上限、产物格式与位置）打包在 [`TaskOptions`](lib/domain/task_options.dart) 里，随任务一起入队。
任务是排队串行跑的，用户很可能在排队期间改设置去建下一个任务 —— 参数要是
运行时才去读全局设置，前面排着的任务就会被后面的改动影响，这类 bug 事后
极难复现。全局设置只作为新建任务时的默认值。

### 模型是一份声明，不是一个名字

设置里每家服务的模型以前是一串逗号分隔的名字，「这个模型走哪个接口、发哪种报文、
能不能分离说话人」靠名字的前后缀去猜 —— 用户自己填的名字一旦不合那个规律就接错。
现在每个模型是一份声明（[`ModelSpec`](lib/domain/providers/model_spec.dart)）：名字、
接入方式、报文族、可调参数的取值。能力（能不能分离说话人、接不接受上下文提示、
时间码从哪来）由接入方式与报文族查一张只读的表得出，界面上开关的显隐、就绪检查的
提示、服务实现发不发某个字段，读的都是这一张表。

- 名字在写下的那一刻校验（空白、逗号、不可见字符），不等任务跑起来才报 404。
- 参数照目录出控件（[`ModelParams`](lib/domain/providers/model_params.dart)）。没动过的
  取目录默认值，存档里不留这一项：什么都没改的用户，发出去的请求与加这个功能之前
  一个字段都不差。
- 按名字推断只剩两个用处：读旧版本的存档，以及添加模型时给界面预填一个建议。

### 词表是数据，不是提示词里的一段话

专有名词以前只能写进「识别提示」「翻译要求」两段自由文本，识别与翻译各写一遍。
现在是独立的词表（[`Glossary`](lib/domain/glossary.dart)）：可以有多份，建任务时
勾选要用的几份。识别时原文拼进上下文提示；翻译时有译文的按「原文 → 译文」交给模型，
没写译文的要求照抄原文。勾选的是「用哪几份」，条目在入队那一刻才展开进任务参数，
之后再改词表不影响排着队的任务。词表不参与「恢复默认」—— 它是用户攒出来的数据。

### 媒体任务挂在一个 sealed 的 `MediaJob` 上

转码、合并这类「产出一个媒体文件、不产字幕」的任务，状态挂在
`SubtitleTask.media`（[`MediaJob`](lib/domain/media_job.dart)）上：`TranscodeJob`、`MergeJob`
是它的子类。产物路径、命令、倍速、「在访达中显示」这些通用信息走接口；任务行的
「服务」列、详情头标签这类按种类画的地方写 `switch (task.media)`。

原来是一个类型专用的可空字段 `task.transcode`，「是不是转码任务」在十来处各自判断，
加合并就得每处再补一个分支，漏一处（比如定位产物）就出错。现在加新种类（重混流、mkv）
只加一个子类，编译器会在每个 sealed switch 处提示补分支。存档的键名沿用
`'transcode'` / `'merge'`，旧任务文件不用迁移。

合并命令由声明式的 [`MuxPlan`](lib/domain/mux/mux_plan.dart) 拼出（输入、`-map`、章节来源、
字幕封装编码）：页面命令预览与流水线执行共用它，只差临时文件的路径；以后的重混流产出同一个结构。
concat 列表的 `duration`、章节起点、字幕平移用 `offsets` 算出的**同一份偏移**，三者不可能对不上。

### 折行发生在导出时，不在文档里

单行字数上限（中日韩 15、其他 40，沿用原 Python 实现的默认值）在写出产物时
才应用。文档里始终存不带硬换行的干净文本，用户在编辑器里改完再导出会按当前
设置重新折，不会叠加上一次的换行。

### 产物命名与双语字幕

产物落在 `原文件名.语言代码.扩展名`：`demo.zh.srt` 是原文，`demo.en.srt` 是译文。
用代码而不是中文名，是因为中文带不进跨平台安全的文件名。

命名照 Jellyfin 的外挂字幕约定（Plex、Kodi 也兼容）：主干与视频相同，语言码放在
扩展名前的最后一段；播放器从后往前认，认不出的段拼成字幕轨标题。于是：
- 源语言是「自动检测」时原文不写语言段（`demo.srt`）。以前写 `src`，会被当成标题。
- 纯翻译任务先去掉源字幕名末尾的语言段：`demo.en.srt` 译成中文写 `demo.zh.srt`，
  不写 `demo.en.zh.srt`（`en` 会成为标题）。去掉后与源文件同名时保留，不盖源文件。
- 这样命名很容易与用户已有的字幕同名（`Film.srt`、`Film.zh.srt`）。首次写出时那里已有
  文件就带序号避让（`demo.2.zh.srt`），序号单独成段，拼进主干（`demo-2`）就配不上视频了；
  写出过之后保存沿用记下的路径，改规则之前的老任务也接着写回老名字。编辑器「导出…」
  落在产物目录时同样不盖已有文件，否则保存时避让开的那份又会被导出盖掉。

双语指**同一条字幕里两行文字**，不是两个文件 —— 播放器只能挂一轨字幕，想同时
看原文和译文只有这一条路。上下顺序由 [`BilingualLayout`](lib/domain/task_options.dart)
决定，产物名加一个标题段、语言段写译文语言（`demo.Bilingual.en.srt`），跟单语那份
区分得开。不写 `zh-en` 这种合成码：它不是合法语言码，播放器认不出语言。两行各按
自己语言的单行上限折行：中日韩一行 15 字、拉丁语一行 40 字，用同一个上限必然
有一边难看。

纯翻译任务（输入本来就是字幕文件）只写译文，不再复制一份原文。

### 断点续跑

字幕任务分六个阶段：排队 / 准备 / 识别 / 断句 / 翻译 / 完成（转码、合并只走排队 / 准备 /
转码或合并 / 完成）。失败或取消时，
**已完成阶段的结果全部保留**，重试从中断处继续（合并任务例外：合并没做完时每次都重跑准备，
重新探测各段 —— 期间文件可能被换过，探测也很便宜）。翻译阶段以「这一条有没有译文」
为断点，续跑只翻剩下的，不会重复花钱。

### 翻译为什么要带行号

大模型翻译字幕最常见的故障不是翻错，而是**条数对不上** —— 把两行合成一句、
丢掉语气词、为了语顺把成分挪到下一行。一旦发生，后面所有字幕的时间轴就全错位了。

所以线路协议给每行打了行号（`§3§ ...`），返回后逐行核对：条数不符、行号越界或
重复，这批就判定为不可信，减半批量重试，绝不把错位的译文写进字幕。

### 快捷键按焦点分范围，不猜焦点

校对时单手连按 J/K、数字键指派说话人是核心效率，所以编辑器保留单键。
可单键最容易误触：
- 在输入框里打「3」被当成指派说话人。
- 焦点停在按钮上时按空格，本想播放却点了按钮。
- 弹窗里按 Esc，填的内容全没了。

早先的做法是一个全局按键处理函数，再用「焦点是不是在输入框里」去猜要不要让路。
每多一种可聚焦控件就得再补一个判断，补不全。

现在用焦点树表达作用范围：
- 单键只挂在字幕列表自己的焦点上，焦点在输入框、按钮、浮层里时，按键根本到不了那里。
- 带 ⌘ 的组合挂在整个编辑器分区（连顶栏一起），打字时也能保存、指派、标记已校对。
- Esc 由最里层先处理：浮层 → 对话框 → 输入框 → 字幕表。
- 条件不满足的动作不吞掉按键，按键继续交给真正该处理它的控件。输入法组字时所有快捷键都不启用，这条写在共同的基类 `ShortcutAction` 里：原先建任务入口、编辑器、浮层各判断一次，浮层那处漏了，拼音打到一半按 Esc 整个菜单连字一起没了。

修饰键按平台区分：macOS 用 ⌘，Windows 和 Linux 用 Ctrl，不两个都认。
- macOS 上 Ctrl+点击按惯例是右键，⌘⇧3/4/5 是系统截屏键，都不拿来用。
- 界面上的快捷键文案和绑定出自同一份登记表，平台不同写法也跟着变。

## 测试

```bash
flutter test                                  # 单元与集成测试
flutter test --tags golden --run-skipped      # 界面截图核对
flutter test --tags golden --run-skipped --update-goldens   # 重新生成截图
```

截图测试依赖宿主机的系统字体，换机器像素就会不一样，所以默认跳过。

## 第一期没做的事

- **字幕样式**：编辑器预览画面上叠的字幕固定是黄字黑底，只示意当前条的
  内容与位置，不代表最终效果。SRT / VTT 本身不带样式，长什么样由播放器决定；
  能带样式的 ASS 导出还没做（格式选项里标为未实施），在那之前做可调的样式
  预览没有对象可对照。
- **本地模型**：见上。接口已留好。
- **密钥存储**：目前明文存在 `shared_preferences` 里，还没接 macOS Keychain /
  Windows Credential Manager。
- **字体**：设计稿要求打包 Noto Sans SC 与 JetBrains Mono 的 ttf。
  目前用同名系统字体回退（PingFang SC / Microsoft YaHei、SF Mono / Consolas），
  把 ttf 放进 `assets/fonts/` 并在 `pubspec.yaml` 里声明即可切到设计指定的字体。
