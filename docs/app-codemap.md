# app/ 源码结构索引（app/lib）

Flutter 桌面客户端的全部实现都在 `app/`：`lib/` 72 个文件、30082 行，`test/` 46 个文件、10817 行。
本文路径一律相对 `app/`。

- 每条设计决定的**理由** → [`app/README.md`](../app/README.md)
- 跨文件、只看单个文件看不出来的**硬约束** → [`CLAUDE.md`](../CLAUDE.md)
- 原 pyVideoTrans 的 Python 实现索引 → [`archive-codemap.md`](archive-codemap.md)

这份只回答一个问题：**要改的东西在哪个文件、它旁边是谁。**
行数与文件数以 `Joycai-main` @ `f75d10e3` 为准。

## 一、分层

| 层 | 目录 | 文件 / 行数 | 规则 |
|---|---|---|---|
| 装配 | `lib/main.dart` | 1 / 517 | 唯一 new 服务对象、唯一决定"现在显示哪一页"的地方 |
| 界面 | `lib/features/` | 33 / 18331 | shell · tasks · transcode · editor · settings |
| 流水线 | `lib/pipeline/` | 2 / 1003 | 串行队列与阶段机，可以碰 IO |
| 服务 | `lib/services/` | 15 / 4029 | 网络、外部进程、文件、shared_preferences |
| 领域 | `lib/domain/` | 12 / 3918 | 纯数据 + 纯函数，**零 IO、零 Flutter 依赖**（grep 可验证） |
| 视觉基座 | `lib/core/` | 9 / 2284 | theme（令牌 → ThemeData）+ widgets（无业务语义的控件） |

依赖单向向下：`features → pipeline → services → domain`；`core` 与 `domain` 互不认识。
两处故意的例外：

- `features/editor/editor_controller.dart` 直接用 `Registry` 造 provider ——
  编辑器里的「重新翻译这一条」「翻译缺失项」必须与流水线走同一套服务与协议，另写一份必然走偏。
- `features/` 里的表单控制器读 `AppSettings`、调 `Media` 探测文件，但**不写设置**：
  它们只把用户填的东西打包成 `TaskOptions` / `TranscodeOptions` 交给队列。

## 二、逐文件

### `lib/main.dart`

进程入口 + `SubtitleStudioApp`，只做三类事：

1. `main()`：`MediaKit.ensureInitialized()` → 载设置 → 建应用支持目录（`work/`、`tasks/`、`editor/`、
   `ffmpeg/` 投放目录）→ new `Media` / `Transcoder` / `TaskQueue(TaskRunner)` / `TaskStore` / `EditorStore`
   → `queue.restore()` → `runApp`。
2. 页面切换：一个 `AppSection` 枚举 + `_body` 的 `switch`，**没有 Navigator 路由表** ——
   六个"页"其实是同一个 `AppShell` 换 child。各页的 `GlobalKey` 用来让顶栏按钮调到页面方法
   （`_tasksKey.currentState?.newTranscribe()`）。
3. 顶栏与状态栏内容：`_chrome` / `_status` 两个 getter，具体文案由各页文件导出的
   `xxxChrome(...)` 工厂提供。

四个表单控制器（转写 / 翻译 / 转码 / 编辑器入口）挂在这一层，所以切页不丢用户填的东西。
`_live = Listenable.merge([...])` 是顶栏与状态栏的唯一驱动源；退出与挂起前 `queue.flush()` 写盘。

### `lib/core/theme/` —— 令牌 → 主题（669）

| 文件 | 行 | 内容 |
|---|---:|---|
| `app_extensions.dart` | 348 | 三个 ThemeExtension：`AppColors`（成功态、说话人调色板）、`AppGlass`（玻璃材质）、`AppElevation`（阴影 / 模糊）；`extension ThemeTokens on BuildContext` 提供 `context.colors` 之类短写法 |
| `app_theme.dart` | 255 | 浅深两套 `ColorScheme`（深色单独调校，不是反色）+ `_build()` 组装出 `lightTheme` / `darkTheme` |
| `tokens.dart` | 66 | 与业务无关的常量：`AppSpacing` / `AppRadius` / `AppDuration` / `AppFonts` / `AppStateLayer`（z 序） |

### `lib/core/widgets/` —— 无业务语义的控件（1615）

| 文件 | 行 | 内容 |
|---|---:|---|
| `glass_panel.dart` | 94 | `GlassPanel`（玻璃卡片）、`ContentPanel`（内容区大面板） |
| `buttons.dart` | 489 | `PrimaryButton`（渐变主按钮）、`ControlButton`、`QuietButton`、`IconActionButton`、`SegmentedToggle<T>`、`FilterChipBar` |
| `fields.dart` | 669 | `LabeledField`、`ControlSurface`、`AppDropdown<T>`（支持 `DropdownEntry` / `DropdownGroup` 分组与徽标）、`NumberField`、`MultilineField`、`AppSwitch`、`FormSection` |
| `indicators.dart` | 173 | `StatusTag`（`TagTone` 五档）、`Timecode`、`GradientProgressBar`、`StatusDot` |
| `wallpaper.dart` | 57 | `AppWallpaper`：底层竖向渐变 + 三团低对比光晕 |
| `baked_backdrop.dart` | 133 | 把静态装饰层烘成一张 `ui.Image`，每帧只画一个纹理 quad。**逐帧动画放进去会每帧重烘，比不烘更慢** |

### `lib/domain/` —— 纯数据与纯函数（3918）

| 文件 | 行 | 内容 |
|---|---:|---|
| `cue.dart` | 365 | `Cue`（毫秒时间轴、`CueState` 校对态、说话人）与 `SubtitleDocument`（不可变文档：改字、拆分、合并、说话人重命名 / 合并，以及 reviewCount 之类派生统计）。**所有编辑操作都返回新文档** |
| `language.dart` | 230 | `Language` 值对象 + `Languages` 表（含 `cjk` 判定）。识别、翻译、折行、产物命名共用这一张表，语种与代码沿用原 Python 实现 |
| `srt.dart` | 349 | SRT / VTT 解析与序列化、`SrtField`（导出哪一路文本）、`SpeakerLabelDetection`（`[说话人1]` 前缀的检测与剥离） |
| `line_wrap.dart` | 97 | `LineWrap`：单行字数上限折行（CJK 15 / 拉丁 40），**只在导出时被调用** |
| `segmenter.dart` | 167 | `Segmenter`：识别原始结果 → 字幕（修重叠、合并过短、限最长）。各渠道结果质量参差，统一在这里兜底 |
| `subtitle_pairing.dart` | 248 | `PairingMode` / `PairingResult` / `SubtitlePairing`：本地打开时原文与译文两份字幕怎么逐条对上 |
| `speech_segments.dart` | 116 | `SpeechSegments`：把 silencedetect 的静音区间变成可逐段识别的语音片段（给不返回时间戳的 ASR 用） |
| `recognition_checkpoint.dart` | 180 | `SegmentPiece` / `SegmentRecord` / `RecognitionCheckpoint`：段级识别检查点，随任务持久化，续跑跳过已完成段 |
| `task.dart` | 379 | `TaskStage`（排队 / 准备 / 识别 / 断句 / 翻译 / 转码 / 完成）、`StageState`、`StageRecord`、`TaskStatus`、`TaskKind`（含 `stages`、`needsRecognition`）、`LogLevel` / `LogEntry`、`TaskOutput`、`SubtitleTask`（含 `resumeStage`、`toJson` / `fromJson`）、`TaskError`。**阶段名与顺序在这里改** |
| `task_options.dart` | 291 | `SubtitleFormat`、`BilingualLayout`、`OutputLocation`、`TaskOptions`（入队即定死的全部参数，含产物命名与双语标签） |
| `transcode.dart` | 1463 | 转码的全部数据与规则：`TranscodeMode` / `OutputContainer` / `VideoCodec` / `AudioCodec` / `EncoderBackend`、`EncoderParam` 家族（Choice / Int / Bool）、`VideoEncoder` + `VideoEncoders`（**每个编码器自己一套参数表**）、`TranscodeOptions`、`MediaProbe` 与流信息、`TranscodeJob`、`TranscodeCommand`（拼 ffmpeg 命令行）、`TranscodeProgress`（解析 `-progress`）。容器兼容名单也在这里 |
| `media_kinds.dart` | 33 | 按扩展名判断"媒体还是字幕"，决定建转写任务还是翻译任务 |

### `lib/services/` —— IO 与外部世界（4029，含 `local/`）

| 文件 | 行 | 内容 |
|---|---:|---|
| `provider_api.dart` | 119 | 契约层：`CancellationToken`（协作式取消）、`TaskCancelled`、`ProviderException`（带 hint；`batchTooLarge` 触发减半重试）、`ProgressSink`、`ProviderInfo`（登记表元信息）、`AsrProvider`、`TranslationProvider` |
| `registry.dart` | 249 | `Registry`：ASR 与翻译两张 `ProviderInfo` 表 + `buildAsr` / `buildTranslation` 工厂。**加一家 OpenAI 兼容服务通常只是加一条记录** |
| `openai_compatible.dart` | 388 | `Endpoint`（baseUrl + model + key）与两个实现：`OpenAiCompatibleAsrProvider`（`POST /audio/transcriptions`）、`OpenAiCompatibleTranslationProvider`（chat completions + 行号协议）。Ollama / LM Studio / 将来的本地 Python 后端都走这里 |
| `translation_protocol.dart` | 106 | `TranslationProtocol`：`systemPrompt` / `encode`（打 `§N§` 行号）/ `decode`（逐行核对，条数不符返回 null） |
| `dashscope_asr.dart` | 664 | 阿里百炼 Qwen3-ASR 多模态识别（不返回时间戳）：切音频 → 逐段 base64 上传 → 用片段时间当字幕时间；含轮询与退避的 `_Outcome` 状态机 |
| `dashscope_filetrans.dart` | 586 | 百炼录音文件异步转写：getPolicy 上传 → 提交任务 → 轮询 → 取句级时间戳与说话人 |
| `audio_splitter.dart` | 111 | `AudioSplitter` 接口 + `FfmpegAudioSplitter`。抽成接口是为了测试塞假实现，不真起 ffmpeg |
| `media.dart` | 478 | `Media`（ChangeNotifier）：ffmpeg / ffprobe 定位（投放目录 → 应用目录 → Homebrew 等系统位置 → PATH）、`probeDuration` / `probeFile`、`detectSilences`、`cutAudio`、`extractAudio`、`killTree` / `killOnCancel`（取消时杀进程树） |
| `transcoder.dart` | 380 | `Transcoder`（ChangeNotifier）：编码器可用性两步检测（`-encoders` 列表 + 试编 1 帧）、`parseEncoderList`、`explainEncoderFailure`、`probe`、`run`（跑转码回进度）、`describeFailure` |
| `readiness.dart` | 168 | `Readiness` / `ReadinessLevel` + `ProviderReadiness.asr()` / `.translation()`：把"没配密钥""语言不支持""服务未实施"统一成可行动提示，由界面决定是拦住还是提醒 |
| `settings.dart` | 363 | `ProviderConfig`（单服务的 baseUrl / model / apiKey）+ `AppSettings`（ChangeNotifier，shared_preferences **明文**）：服务与语言、批大小、提示词、主题、输出目录、折行与断句上下限、`defaultTaskOptions()`、上次用过的参数。`SettingsGroup` 供"恢复默认"分组 |
| `task_store.dart` | 60 | `TaskStore`：一个任务一份 JSON 存 `tasks/`（某一份坏了只丢一个任务） |
| `editor_store.dart` | 211 | `EditorStore`：本地会话的附加状态（SRT 装不下的已校对标记、置信度、说话人名单，带文件大小与 mtime 校验）、字幕 ↔ 媒体关联、`RecentSession` 最近打开 |
| `reveal.dart` | 50 | `Reveal`：在 Finder / Explorer 里定位文件或打开目录，按平台给不同文案与命令 |
| `local/local_backend.dart` | 96 | `LocalBackend`：本地 Python 后端客户端，**第一期是空壳**（`implemented = false`）。方案见 [`local-backend.md`](local-backend.md) |

### `lib/pipeline/` —— 队列与阶段机（1003）

| 文件 | 行 | 内容 |
|---|---:|---|
| `task_queue.dart` | 299 | `TaskQueue`（ChangeNotifier）：串行执行（限流与 GPU 独占的考虑）、`enqueueAll` / `enqueueTranscode` / `cancel` / `resume` / `resumeAuto` / `prioritize` / `remove`、`_pump` 调度、脏任务攒 300ms 批量 `persist`、`flush`、`restore`（重启后上次在跑的标为已暂停）、`overallProgress` |
| `task_runner.dart` | 704 | `TaskRunner`：阶段机，`AsrFactory` / `TranslationFactory` 可注入（测试换假实现）。`run()` 按 `TaskKind` 走两条路，`_stage()` 统一做"已完成则跳过 + 计时 + 记日志"。转写线 `_prepare` → `_recognize` → `_segment` → `_translate`（行号核对，`batchTooLarge` 减半重试最多 3 次）→ `_finish`（`writeOutputs`）；转码线 `_prepareTranscode` → `_transcode`（先写 `.part`）→ `_finishTranscode`。**取消与失败都保留已完成阶段** |

### `lib/features/shell/` —— 应用框架（431）

| 文件 | 行 | 内容 |
|---|---:|---|
| `nav_rail.dart` | 157 | `AppSection` 六项枚举（图标 + 中文名）+ 72px 玻璃导航栏 |
| `app_shell.dart` | 165 | `PageChrome`（每页交给顶栏的标题 / 副标题 / 尾随标签 / 操作区）+ `AppShell`（Rail + 52px 顶栏 + 内容 + 32px 状态栏，用 `live` 局部重建顶栏与状态栏） |
| `status_bar.dart` | 109 | `StatusSnapshot`（本地引擎 / 云端 / 本地后端 / 进行中任务数 / 总进度 / ETA / 一句话附注）+ `AppStatusBar`。快照由 `main.dart` 填，状态栏自己不去查服务 |

### `lib/features/tasks/` —— 任务页与建任务（7233）

| 文件 | 行 | 内容 |
|---|---:|---|
| `tasks_page.dart` | 166 | 任务页容器：筛选、选中、拖放入口，把队列接到 `TasksBoard`；`newTranscribe()` / `newTranslate()` 走**对话框版**建任务 |
| `tasks_board.dart` | 130 | 展示逻辑：`TaskTable` + `TaskDetailPanel` + `TaskDropZone` 的组合与空态 |
| `task_table.dart` | 566 | 任务列表（文件 / 服务 / 阶段 / 进度 / 操作列，`TaskAction`，行内继续、取消、优先、删除） |
| `task_detail_panel.dart` | 796 | 右侧详情：阶段耗时、错误块（title / detail / hint 三段式）、产物列表与"打开 / 在文件夹中显示"、`CommandBlock`（可复制的 ffmpeg 命令）、日志视图 |
| `stage_bar.dart` | 141 | 阶段条（含虚线未完成段的 CustomPainter） |
| `drop_zone.dart` | 157 | `TaskDropZone`：拖放区，按扩展名分流到转写 / 翻译 |
| `new_transcribe_page.dart` | 911 | 「新建转写」整页版（导航栏入口），文件里还有 `newTranscribeChrome()` |
| `new_transcribe_dialog.dart` | 402 | 「新建转写」对话框版（任务页工具栏与拖放走这条），入口 `showNewTranscribeDialog()` |
| `new_translate_page.dart` | 953 | 「翻译」整页版 + `newTranslateChrome()` |
| `new_translate_dialog.dart` | 453 | 「翻译」对话框版 + `showNewTranslateDialog()` |
| `transcribe_form.dart` | 1013 | `TranscribeFormController`（ChangeNotifier）：暂存文件、校验、造 `TaskOptions` 入队；其余是它的展示分块（识别 / 翻译 / 高级 / 底部 / 开始按钮） |
| `translate_form.dart` | 1181 | `TranslateFormController` + `StagedSubtitle` + 各分块（语言、交换语言、高级、`LayoutPreview` 排版预览、输出位置、底部、开始） |
| `provider_fields.dart` | 364 | 选服务 / 填模型的公共件：`providerGroups`（按厂商分组的下拉）、`modelField`、`resolvedModel`、`ModelTextField`、`ReadinessLine`、`Tappable` / `LinkText` / `RadioRow` |

### `lib/features/transcode/` —— 转码页（2329）

| 文件 | 行 | 内容 |
|---|---:|---|
| `transcode_form.dart` | 462 | `TranscodeFormController` + `StagedVideo`：暂存视频、探测源流、按编码器切参数表、造 `TranscodeOptions` 入队 |
| `transcode_page.dart` | 1867 | 转码页全部界面：文件面板、步骤条、文件行、参数面板（视频 / 编码器卡片 / 编码器参数 / 音频 / 高级里的完整命令）、输出区。**仓库里最大的一个文件** |

### `lib/features/editor/` —— 编辑器（6263）

| 文件 | 行 | 内容 |
|---|---:|---|
| `editor_session.dart` | 372 | sealed `EditorSession`：`TaskSession`（改动随任务写盘）与 `FileSession`（保存时写回原文件，含 `LocalSubtitleFile` 与挂载译文），共用 document / options / title / exportDir / exportStem / `locateMedia`；`findSiblingMedia` 找同名媒体 |
| `editor_controller.dart` | 542 | `EditorController`（ChangeNotifier）：视图（原文 / 译文 / 双语）、筛选（全部 / 待校对 / 未翻译 / 未配对）、搜索、说话人筛选、选中与步进、撤销栈、改字改时间、拆分 / 合并、说话人改名与合并、`save` / `export` / `retranslate` / `translateMissing`。`displayStateOf` 决定一行显示什么状态标签 |
| `editor_page.dart` | 1071 | 编辑器整页：快捷键、拖放、导出对话框、离开确认（`confirmLeaveEditor`）、`editorSubtitle` / `editorStatusNote`（顶栏与状态栏文案）、`EditorPageActions`、`EditorTitleTrailing`、`EditorReviewBadge` |
| `cue_table.dart` | 925 | 字幕表格：列表、表头、行（原文 / 译文 / 说话人 / 时间码 / 状态）、工具栏、页脚统计、`_Grid` 列宽 |
| `inspector.dart` | 1093 | 右侧检视面板：预览画面（media_kit_video）、播放控制与进度条、当前条编辑器（文本 / 说话人 / 时间码） |
| `preview_playback.dart` | 165 | `PreviewPlayback`（ChangeNotifier）：media_kit 播放器封装，按字幕时间码定位；`cueIndexAt` 找某毫秒对应哪一条 |
| `speaker_manager.dart` | 353 | `showSpeakerManager` 弹窗：说话人改名 / 合并 / 统计（`speakerStat`） |
| `speaker_badge.dart` | 116 | `SpeakerBadge`（说话人色块，调色板在 `AppColors.speakers`）+ `DashedRRectPainter` |
| `editor_widgets.dart` | 315 | 编辑器专用小件：`AnchoredPopover`、`GlassMenu` / `MenuRow` / `MenuDivider`、`MiniSegmented`、`FileIconBox`、`friendlyTime`、`parentDir`、可注入的 `editorClock`（golden 测试钉时间用） |
| `editor_open_form.dart` | 289 | `EditorOpenForm`（ChangeNotifier）：入口页两个槽位（`OpenSlot.source` / `.translation`）的挑文件、解析、配对预检，`build()` 出 `FileSession` |
| `editor_open_page.dart` | 1022 | 入口页：本地文件配对面板、从任务打开、最近打开、说话人标签开关 + `editorOpenChrome()` |

### `lib/features/settings/` —— 设置页（2075）

| 文件 | 行 | 内容 |
|---|---:|---|
| `settings_page.dart` | 951 | 设置页：分区、环境（ffmpeg 路径 / 投放目录 / 重新检测）、本地后端区块、页脚与恢复默认对话框 + `settingsChrome()` |
| `settings_section.dart` | 383 | `SettingsSection` / `SettingsRow` / `SavedIndicator` / `InlineNote` / `PillSegments` / `SettingsTextField` |
| `provider_section.dart` | 545 | `ProviderSection`：一个服务（`ProviderKind.asr` / `.mt`）的选择、baseUrl、模型、密钥字段、`BatchSlider`（自定义 track 与 thumb） |
| `section_outline.dart` | 196 | `SectionOutline`：左侧分区导航，窄窗口退化成 tabs（`OutlineMode`） |

## 三、运行主线

1. **启动**：`main()` → `AppSettings.load()` → 建目录 → new 服务 → `TaskQueue.restore()` → `runApp`。
   上次退出时还在跑或排队的任务标为已暂停，不自动开跑。
2. **建任务**：页面表单控制器把文件与参数打包成 `TaskOptions` / `TranscodeOptions`
   → `queue.enqueueAll()` / `enqueueTranscode()` → `TaskStore` 落盘 → `_pump()` 串行取一个跑。
   参数在这一刻定死，之后改设置不影响已排队的任务。
3. **跑任务**：`TaskRunner.run()` 按 `TaskKind` 走阶段，每个 `_stage()` 先看 `StageRecord` 是否已 done
   （续跑跳过）。识别用 `Registry.buildAsr` 造的 provider，进度经 `ProgressSink` 写回 task
   → 队列 `notifyListeners` → `main.dart` 的 `_live` 驱动顶栏、状态栏与任务页局部重建；
   `TaskQueue` 攒 300ms 批量 `persist`。
4. **出产物**：`writeOutputs()` 在写文件那一刻才折行；命名 `原文件名.语言代码.扩展名`，
   双语带两种语言；已存在加序号不覆盖。转码先写 `.part`，成功才改名。
5. **编辑器**：任务页或入口页 → `EditorController(session)` → `cue_table` + `inspector`。
   `TaskSession` 的改动经 `queue.persist(task)` 写回任务 JSON，`FileSession` 只在用户保存时写文件，
   SRT 装不下的附加状态另存 `EditorStore`。
6. **设置**：`AppSettings` 只是"新建任务时的默认值来源"，运行中的任务不读它。

## 四、按功能找代码

| 要改什么 | 看这里 |
|---|---|
| 加一家识别 / 翻译服务（OpenAI 兼容） | `services/registry.dart` 加一条 `ProviderInfo`；确实不兼容才动 `openai_compatible.dart` 或另写实现（参照 `dashscope_*.dart`） |
| "服务没配好"的提示文案 | `services/readiness.dart`，画在 `features/tasks/provider_fields.dart` 的 `ReadinessLine` |
| 阶段名 / 顺序 / 哪种任务走哪些阶段 | `domain/task.dart` 的 `TaskStage` 与 `TaskKind.stages`；执行在 `pipeline/task_runner.dart` |
| 翻译条数对不上、批量减半重试 | `services/translation_protocol.dart` + `task_runner._translate` |
| 断句规则（太短 / 太长 / 重叠） | `domain/segmenter.dart`，阈值来自 `AppSettings.minCueMs` / `maxCueMs` |
| 折行与单行字数 | `domain/line_wrap.dart`；调用点只有 `task_runner.writeOutputs` 与编辑器导出 |
| SRT / VTT 解析、说话人标签 | `domain/srt.dart` |
| 产物文件名、双语排版、输出目录 | `domain/task_options.dart` + `task_runner.writeOutputs` |
| ffmpeg 查找顺序 | `services/media.dart` 的 `_searchDirs` / `_locate` |
| 转码编码器与参数表、容器兼容 | `domain/transcode.dart`（`VideoEncoders` / `TranscodeCommand`） |
| 编码器可用性检测 | `services/transcoder.dart` |
| 任务持久化格式与兼容 | `domain/task.dart` 的 `toJson` / `fromJson` + `services/task_store.dart`，测试 `test/task_json_test.dart` |
| 设置项与默认值 | `services/settings.dart`（键名常量在文件顶部） |
| 主题色 / 圆角 / 间距 / 字体 | `core/theme/tokens.dart`、`app_extensions.dart`、`app_theme.dart` |
| 顶栏标题与副标题 | 各页的 `xxxChrome()`；编辑器的在 `editor_page.dart` 的 `editorSubtitle` |
| 状态栏内容 | `features/shell/status_bar.dart` 的 `StatusSnapshot`，填在 `main.dart` 的 `_status` |
| 导航项 | `features/shell/nav_rail.dart` 的 `AppSection` + `main.dart` 的 `_body` switch |
| 字幕表格列与行内交互 | `features/editor/cue_table.dart`（列宽在 `_Grid`） |
| 撤销与编辑操作的语义 | `features/editor/editor_controller.dart` + `domain/cue.dart` 的 `SubtitleDocument` |
| 预览播放与定位 | `features/editor/preview_playback.dart` + `inspector.dart` 的 `_Transport` / `_SeekBar` |

## 五、测试对照

`test/` 与 `lib/` 大致一一对应，命名是"被测文件名 + `_test`"。

| 测试 | 覆盖 |
|---|---|
| `pipeline_test` `task_options_test` `task_store_test` `task_json_test` | 队列与阶段机、参数打包、持久化与 JSON 向后兼容 |
| `provider_test` `readiness_test` | OpenAI 兼容实现、行号协议、可用性提示 |
| `dashscope_asr_test` `dashscope_filetrans_test` `dashscope_live_test` | 百炼两条路；`live` 要 `DASHSCOPE_API_KEY`，默认跳过 |
| `srt_test` `line_wrap_test` `segmenter_test` `language_test` `subtitle_pairing_test` `speech_segments_test` `speakers_test` | domain 纯函数 |
| `transcode_test` `transcode_ffmpeg_test` | 命令拼装；ffmpeg 端到端（本机没有 ffmpeg 自动跳过，VideoToolbox 只在 macOS 跑） |
| `media_test` `media_cancel_test` `audio_splitter_test` | ffmpeg 定位与探测、取消时杀进程树、音频切分 |
| `editor_test` `editor_session_test` `editor_ui_test` `preview_playback_test` | 文档操作、两种会话、界面、播放定位 |
| `transcribe_form_test` `translate_form_test` `provider_fields_test` `new_transcribe*_test` `new_translate*_test` | 表单控制器与两套建任务入口 |
| `settings_page_test` `theme_test` `layout_test` `render_perf_test` | 设置页、主题令牌、栅格布局、重建次数 |
| `test/golden/*_golden_test.dart` + `*.png` | 截图核对，`--tags golden --run-skipped` 才跑；依赖宿主机字体，换机器像素会变 |
| `test/helpers.dart` `test/editor_fixtures.dart` | 公共夹具（语言、`TaskOptions`、字幕样本） |

## 六、几处容易踩的地方

- **两套建任务入口并存**：整页（`new_transcribe_page.dart`，导航栏进去）与对话框
  （`new_transcribe_dialog.dart`，任务页工具栏和拖放走这条）。改表单字段两边都要改，两边各有 golden。
- **表单控制器住在 `features/`，不在 `services/`**：它们是 ChangeNotifier，由 `main.dart` 持有。
  新加页面照这个模式挂上去，别在页面 State 里 new —— 否则切页就丢用户填的东西。
- **`services/local/local_backend.dart` 是空壳**：登记表里 `implemented: false`，选中时界面给明确提示。
- **密钥明文**存在 shared_preferences（`services/settings.dart`），还没接系统钥匙串。
- **字体是系统回退**：设计稿指定的 Noto Sans SC / JetBrains Mono 还没打包，见 README「第一期没做的事」。
- 别对已有文件整体跑 `dart format`，会产生大量与改动无关的噪音。
