# app/ 源码结构索引（app/lib）

`app/` 是 Flutter 桌面客户端（macOS / Windows / Linux）的全部实现。
当前 `lib/` 共 180 个 Dart 文件、约 3.7 万行；`test/` 共 70 个 Dart 文件、约 1.8 万行。
本文路径一律相对 `app/`。

- 设计决定与产品约束 → [`README.md`](../app/README.md)
- 跨文件开发约束 → [`CLAUDE.md`](../CLAUDE.md)
- 原 Python 实现的功能索引 → [`archive-codemap.md`](archive-codemap.md)

这份文档回答：**要改某项能力，应从哪个目录和哪个文件开始。**

## 一、分层与依赖方向

```text
main.dart
  ↓ 装配
features/ ───────────────→ pipeline/
  ↓                         ↓
core/       domain/ ←──── services/
```

| 层 | 目录 | 责任 |
|---|---|---|
| 装配 | `lib/main.dart` | 初始化服务、持有根级表单控制器、页面切换、顶栏与状态栏快照 |
| 界面 | `lib/features/` | 按功能分 `shell / tasks / transcribe / translate / transcode / merge / editor / settings`；跨功能 UI 放 `shared/` |
| 流水线 | `lib/pipeline/` | 串行队列、任务编排、阶段壳、字幕写出与转码 / 合并任务执行 |
| 服务 | `lib/services/` | 网络、ffmpeg / ffprobe、文件持久化、shared_preferences、provider 构造 |
| 领域 | `lib/domain/` | 数据模型与纯规则；不依赖 Flutter，不执行网络或外部进程 |
| 视觉基座 | `lib/core/` | 主题令牌和无业务语义的通用控件 |

当前相对 import 依赖图**没有循环**。边界约定：

- `domain/` 不 import Flutter、`services/`、`pipeline/` 或 `features/`。
- feature 之间不互相拿实现组件；跨 feature 复用放 `features/shared/`。
- `features/` 与 `core/` 不 import `dart:io`：读写文件、判断存在、路径分隔符都走 `services/file_io.dart`。
- 各页交给顶栏的内容走 `features/shared/page_chrome.dart` 这个契约，不 import `shell/` 的任何实现。
- 页面文件负责装配、生命周期和键盘 / 拖放入口；大块内容拆成同目录的 `*_panel.dart`、
  `*_section.dart`、`*_list.dart`。
- 对外需要稳定入口时可保留很薄的门面文件，例如 `core/widgets/fields.dart`。

## 二、装配与应用框架

### `lib/main.dart`

唯一装配点：

1. 初始化 Flutter 与 media_kit。
2. 载入 `AppSettings`，创建应用支持目录。
3. 构造 `Ffmpeg`、`Transcoder`、`TaskRunner`、`TaskQueue`、`TaskStore`、`EditorStore`。
4. 恢复任务后启动 `SubtitleStudioApp`。
5. 持有任务页的 `TasksController`、转写 / 翻译 / 转码 / 合并的表单控制器和编辑器的 `EditorWorkspace`，保证切页不丢状态。
6. 用 `Listenable.merge` 只驱动顶栏、状态栏和需要实时更新的页面，避免进度回调重建整棵应用树。

只做接线：各页的顶栏内容由各自的 `xxxChrome()` 给出，状态栏快照由
`StatusSnapshot.from` 拼，编辑器换会话、草稿恢复、最近打开的规则在 `EditorWorkspace`。
编辑器要问用户的事（对话框、目录选择、SnackBar）由这里造一个 `DialogEditorPrompts`
注入 `EditorWorkspace`，编辑器的 view-model 自己不碰 widget。

### `lib/features/shell/`

| 文件 | 内容 |
|---|---|
| `nav_rail.dart` | `AppSection` 七个导航项和 72px 导航栏 |
| `app_shell.dart` | Rail + 顶栏 + 内容区 + 状态栏的总体栅格 |
| `status_bar.dart` | `StatusSnapshot`（`from` 按设置、ffmpeg 与队列拼出快照；后台任务数按 `TaskFilter.running` 算）与底部状态栏；控件只画快照 |

## 三、视觉基座 `lib/core/`

### `core/theme/`

- `tokens.dart`：间距、圆角、时长、字体、状态层级。
- `app_extensions.dart`：`AppColors`、`AppGlass`、`AppElevation` 与 BuildContext 短写。
- `app_theme.dart`：独立调校的浅色 / 深色 `ThemeData`。

### `core/shortcuts/`

- `app_shortcut.dart`：`AppShortcut`，一条快捷键（主键 + 修饰键 + 是否连发）生成 `SingleActivator` 与界面文案。
- `shortcut_action.dart`：`ShortcutAction`，全应用快捷键动作的基类。条件不满足时不启用、按键外传；输入法组字时一律不启用。
  主修饰键按平台区分：macOS 是 ⌘，Windows 与 Linux 是 Ctrl。鼠标操作用 `isPrimaryModifierPressed`。
  全应用的键盘绑定与快捷键提示都从这里生成，不再手查 `HardwareKeyboard` 或写死「⌘S」。

### `core/widgets/`

- `buttons.dart`：主按钮、控制按钮、静默按钮、图标按钮、分段选择、筛选条 `FilterChipBar` 与单颗筹码 `FilterChipButton`
  （词表勾选这类要多选、要换行的地方直接用后者）。
- `glass_dialog.dart`：询问对话框外壳（标题、正文、说明条、左侧文字操作 + 右侧按钮）。
- `fields.dart`：表单控件公共入口，只 export 下面三个实现文件。
- `dropdown.dart`：`AppDropdown`、分组 / 条目模型、菜单定位与条目渲染；分组可带分隔线（`divided`），
  菜单末尾可带一段说明（`footer`）。
- `form_fields.dart`：标签、输入表面、单行 / 数字 / 多行输入、开关、表单分区。
  `SingleLineField` 是「值由外面拿着」的单行输入（设置页的地址、密钥、转码后缀 / 额外参数）的实现，
  外部值变化且无焦点时同步进框。要自己拿着焦点与控制器的几处（模型列表的添加行与数字框、词表的改名框与
  条目格、建任务页手填模型名）直接用 `ControlSurface` + `TextField`，外观是同一身皮。
- `form_layout.dart`：整行可点、链接文字、一段说明 `InlineNote`、单选行、两列与平铺段。
- `text_focus.dart`：`appInBackground`，应用是不是退到了后台 —— 「失焦就提交 / 放弃」的输入框先问它，切去别的应用
  丢掉的焦点不算离开。`isEditingText`，焦点在不在输入框里。只剩两处用：`SubmitShortcuts`（打字时 Esc 先失焦、多行框里让回车），以及编辑器的 ⌘Z 在打字时让给输入框。同文件的 `isComposingText` 判断输入法是否在组字，只由 `ShortcutAction` 调用。编辑器的单键靠焦点范围隔开，不用它们。
- `glass_panel.dart`：玻璃卡片与内容面板。
- `indicators.dart`：状态标签、状态胶囊（`StateChip`，文件表状态列与编码器卡片）、时间码、渐变进度条、状态点。
- `note_bar.dart`：36px 中性提示条（拖放拒收、忽略了音视频），右侧可带动作或关闭。
- `dashed_border.dart`：转写、翻译、转码三页共用的虚线圆角框。
- `wallpaper.dart` + `baked_backdrop.dart`：静态背景烘焙，避免高 DPI 下重复全屏混合。

## 四、领域层 `lib/domain/`

### 字幕与任务

| 文件 | 内容 |
|---|---|
| `cue.dart` | `Cue`、校对状态和不可变 `SubtitleDocument`；拆分、合并、说话人操作都返回新文档；界面显示状态 `displayStateOf`、按时间定位 `cueIndexAt` |
| `language.dart` | 统一语言表、CJK 判定、文件名语言推断、写进视频轨道的 ISO 639-2 码（`iso6392Of`） |
| `paths.dart` | 跨平台纯字符串路径规则：basename、dirname、stem、extension；比较用的 `sameSeparators`；文件名自然序 `naturalCompare`（`part2` 在 `part10` 前） |
| `output_naming.dart` | 产物命名唯一来源 `OutputNaming`：任务写哪几路、语言段、文件名；流水线、编辑器导出、任务详情、建任务页示例共用；语言标签（自动检测不写）；按 Jellyfin 约定：双语加 `Bilingual` 标题段、纯翻译任务去掉源字幕的语言段（`stemFor`）、认视频旁的字幕（`sidecarTags`，合并页配字幕与推断合并字幕语言共用） |
| `numbers.dart` | 千位分隔 `grouped`；取值范围 `IntRange` |
| `srt.dart` | SRT / VTT 解析与序列化、时长格式（`formatDuration`，可固定写出小时位）、说话人标签检测、导出字段 |
| `line_wrap.dart` | 导出时折行；CJK 与拉丁文字使用不同上限 |
| `segmenter.dart` | 识别结果的重叠修正、短句合并、长句拆分 |
| `cue_selection.dart` | 字幕表选区 `CueSelection`：焦点、选中集合与 Shift 锚点；主修饰键切换、Shift 只在可见行里扩选 |
| `subtitle_pairing.dart` | 本地原文与译文字幕的配对模式、统计与合并 |
| `speech_segments.dart` | 静音区间 → 可逐段识别的语音区间 |
| `recognition_checkpoint.dart` | 段级识别检查点，支持失败、取消和重启后的续跑 |
| `task_kind.dart` | `TaskStage` 与 `TaskKind`（`isMedia`、各种任务走的阶段）；独立放置以避免 `TaskOptions ↔ SubtitleTask` 循环 |
| `task_filter.dart` | `TaskFilter` 状态分组（排队算进行中、取消算失败）；任务页筛选 chip、顶栏副标题与状态栏计数共用 |
| `task_options.dart` | 入队时冻结的全部参数（含整份模型声明与词表条目）、产物目录规则、JSON；各项取值范围 `*Range`；换服务的规则 `withAsrProvider` / `withTranslationProvider`；读旧存档时把模型名补成声明（`isLegacyJson`、`DefaultModels`） |
| `glossary.dart` | 词表 `Glossary` / `GlossaryEntry`；`GlossaryText`：粘贴的多行文本 → 条目、条目 → 识别提示词、条目 → 翻译系统提示的「术语表」段 |
| `task.dart` | `SubtitleTask`、阶段记录、日志、错误、产物和 JSON；媒体任务状态 `media`；续跑点 `resumeStage` 与「续跑会不会盖掉编辑」`resumeOverwritesEdits`；export `task_kind.dart` |
| `media_job.dart` | sealed `MediaJob` 及其子类 `TranscodeJob`、`MergeJob`（sealed 要求同库，所以都在这个文件）：产物、命令、倍速等通用接口，存档键 `'transcode'` / `'merge'` |
| `media_kinds.dart` | 按扩展名判断媒体 / 音频 / 字幕 |
| `app_branding.dart` | 应用名的中英两份；另有五份在各平台的清单与 runner 里，见 `packaging/README.md` |
| `file_stamp.dart` | 文件大小 + 修改时间，判断字幕文件是否在外部被改过；`FileChange` |
| `task_control.dart` | 跨层共用的 `CancellationToken`、`TaskCancelled`、`ActionableException`（带建议的失败）、`ProgressSink`；provider、ffmpeg、转码、字幕写出、编辑器都用 |
| `enum_by_name.dart` | `values.tryByName(x)`：认不出的枚举名返回 null，读存档与偏好时用 `??` 写明回落值 |

### `domain/providers/`

服务与模型的只读描述。实例怎么建在 `services/registry.dart`。

| 文件 | 内容 |
|---|---|
| `provider_info.dart` | sealed `ProviderInfo` → `AsrProviderInfo`（支持哪些接入方式）/ `ChatProviderInfo`；预置模型 `presets`；按名字补声明 `guess`（只在手里只有一个名字时用：读旧存档、添加模型时预填并认出同名预置、建任务页手填）；用户添加模型时的声明 `declare` |
| `provider_catalog.dart` | 登记表 `ProviderCatalog`：全部识别 / 翻译服务及其预置模型；按 id 查；旧存档的模型名 → 声明（`legacyAsrSpec` / `legacyChatSpec`）；什么都没配时的默认模型 |
| `model_spec.dart` | sealed `ModelSpec` → `AsrModelSpec`（接入方式、报文族、语种限制、参数取值）/ `ChatModelSpec`；JSON；`guessFromName` |
| `asr_transport.dart` | 接入方式 `AsrTransport`、百炼报文族 `DashScopeDialect`、能力表 `AsrCapabilities.of(transport, dialect)` |
| `model_params.dart` | 模型参数目录 `ModelParams`（识别温度、逆文本规范化、翻译温度）与取值 `ModelOptions`（没动过 = 默认，存 null = 不发送） |
| `model_name.dart` | 模型名校验与规整 `ModelName` |

### `domain/transcode/`

原先的单个 1463 行文件已按责任拆开：

| 文件 | 内容 |
|---|---|
| `codecs.dart` | 模式、容器、视频 / 音频编码枚举与兼容规则 |
| `encoder_params.dart` | 编码器参数模型：Choice / Int / Bool 与 `VideoEncoder` |
| `encoder_catalog.dart` | x264 / x265 / AV1 / VideoToolbox / NVENC / QSV / AMF 参数目录 |
| `options.dart` | `TranscodeOptions`、分辨率限制、参数 JSON |
| `probe.dart` | `MediaProbe` 与音视频流信息（含 profile、采样率、旋转，合并比对用） |
| `command.dart` | ffmpeg 命令拼装、产物命名、进度解析（`TranscodeJob` 在 `domain/media_job.dart`） |

### `domain/mux/`

「只搬流、不转码」的子域：合并是第一个用法，以后的重混流是第二个。

| 文件 | 内容 |
|---|---|
| `merge_options.dart` | `MergeSegment`（视频、可选字幕、章节标题）、`MergeOptions`（有序段、容器、章节 / 内嵌 / 旁挂三个开关、输出位置与文件名、JSON 回落） |
| `merge_rules.dart` | 纯规则：`mergeIssues`（逐段与第 1 段比参数、容器能不能装）、`offsets`（前缀和，concat / 章节 / 字幕平移共用）、`ffmetadata`、`concatList`、`concatCues` 与 `keptCueCount`、`mergePlan`（参数 → `MuxPlan`，页面命令预览与流水线共用，临时文件占位名在 `MergeTempFiles`）、`mergedSubtitleLabel` / `mergedSubtitleTags`（从各段字幕名推断合并字幕的语言，旁挂名与内嵌轨语言共用）、`mergeOutputPath` 与 `sidecarPathFor`、`looksTruncated` |
| `mux_plan.dart` | 声明式封装计划 `MuxPlan` / `MuxInput`：输入、`-map`、章节来源、字幕封装编码与语言 → ffmpeg 参数；`MuxPlan.merge` |

## 五、服务层 `lib/services/`

### Provider

- `provider_api.dart`：`Endpoint`、ASR / 翻译接口；re-export `domain/task_control.dart` 与
  `domain/providers/provider_info.dart`。
- `registry.dart`：provider 工厂。按模型声明的接入方式选实现类，模型参数与词表在这里接进实例；
  登记表本身在 `domain/providers/provider_catalog.dart`。
- `openai_compatible.dart`：OpenAI 兼容 ASR 与翻译实现；在线服务、Ollama、LM Studio、
  将来的本地 Python 后端共用。
- `translation_protocol.dart`：给每行加 `§N§`，返回后校验条数和行号。
- `dashscope_asr.dart`：百炼同步接口，静音切分后逐段识别；报文形状由声明里的报文族决定。
- `dashscope_filetrans.dart`：百炼异步整文件转写，上传、提交、轮询、读取句级时间戳；同样按报文族拼参数。
- `audio_splitter.dart`：切音频接口与 ffmpeg 实现，测试可注入假实现。
- `readiness.dart`：未配置、语言不支持、未实施等状态统一成可行动提示。

### 本地 IO 与持久化

- `ffmpeg.dart`：`Ffmpeg` 定位 ffmpeg / ffprobe、探测文件、抽音、静音检测、切音频、取消时杀进程树。
  不叫 `Media`：会和 media_kit 的 `Media` 撞名。
- `transcoder.dart`：编码器检测、试编码、ffprobe、执行 ffmpeg（转码与合并共用）和错误解释。
- `settings.dart`：shared_preferences 设置和 provider 连接配置；各服务的模型声明列表
  （`asrModelsFor` / `chatModelsFor` / `setModels`，旧版本的逗号串在读取时补成声明）；
  词表的存取与展开（`glossaries`、`glossaryEntries`）。
- `task_store.dart`：一个任务一份 JSON，进度更新时只重写变化的任务。
- `editor_store.dart`：本地会话的附加状态与编辑进度草稿、媒体关联和最近打开。
- `file_io.dart`：界面层用到的文件系统小操作（存在、读文本、读字幕文本 `readSubtitleText`（UTF-8 / 带 BOM 的 UTF-16）、列目录 `listFiles`、大小、建目录、`findSiblingMedia` 找同名音视频）；读文件时间戳；原子写（先写临时文件再改名），多份文件成组写，要么全成要么都不留。
- `reveal.dart`：Finder / Explorer 中定位文件或打开目录。
- `local/local_backend.dart`：本地 Python 后端客户端占位，第一期未实施。

## 六、流水线 `lib/pipeline/`

| 文件 | 内容 |
|---|---|
| `task_queue.dart` | 串行队列；入队、取消、继续、优先、删除、恢复；脏任务攒 300ms 批量写盘 |
| `task_runner.dart` | 按 `task.media` 分派字幕 / 转码 / 合并、统一捕获取消 / provider / 未知错误；字幕的准备、识别、断句、翻译编排 |
| `task_stage_runner.dart` | 所有阶段共用的断点跳过、active / done 状态、耗时与通知 |
| `subtitle_output_writer.dart` | SRT / VTT / TXT 原子写出、按语言折行、双语命名、说话人标签、记产物时间戳；完成阶段与编辑器「保存」共用 |
| `transcode_task_pipeline.dart` | 转码准备、执行 `.part` 临时文件、完成校验 |
| `merge_task_pipeline.dart` | 合并：准备（探测、一致性二次把关、读字幕、定产物；合并没做完时每次开跑都重跑）、合并（临时目录写 concat 列表 / 章节 / 字幕，跑 ffmpeg 写 `.part`，以 0 退出时 stderr 里的话记进日志）、完成（产物非空且不缺段） |
| `ffmpeg_progress.dart` | ffmpeg 进度区块 → 任务进度、ETA、倍速与阶段备注；转码与合并共用 |
| `task_progress.dart` | 字幕按条目、转码按毫秒共用的 ETA 外推公式 |

关键承诺仍由 `TaskRunner` 统一维护：失败或取消时保留已完成阶段；重试从
`SubtitleTask.resumeStage` 继续。

## 七、跨 feature 公共件 `lib/features/shared/`

- `provider_fields.dart`：服务分组、模型字段 `ModelField`、readiness 行、服务 / 模型摘要。模型字段的候选是设置里
  这家服务的模型声明，每项带接入方式标签（仅多接入方式的服务）与能力摘要；只有一种接入方式的服务末尾有
  「其他模型…」（手填一个只用于这次任务的名字，校验不过时交出「未选择」），多接入方式的服务末尾指路去设置。
- `glossary_chips.dart`：`GlossaryChips`，建任务页勾选词表的一行筹码，转写与翻译共用。
- `command_block.dart`：转码页、合并页与任务详情共用的可复制命令块。
- `param_section.dart`：参数面板里的分段 `ParamSection` 与小字 `ParamHint`，转码页与合并页共用。
- `enqueued_banner.dart`：各建任务页面共用的入队成功横幅。
- `step_dots.dart`：各建任务页面共用的三步说明。
- `page_chrome.dart`：页面交给顶栏的稳定契约：标题、副标题、尾随标签、操作区。Shell 与各页都依赖它，
  放在这里而不是 `shell/`，各页就不必 import 另一个 feature。
- `new_task_page.dart`：`NewTaskPageState`，四个建任务页（含合并）的页面状态基类 —— 拖放、入队横幅、
  快捷键、960 / 1100 两栏布局；各页只说明表单、怎么入队、两栏各放什么。
- `submit_shortcuts.dart`：`SubmitShortcuts`，建任务入口（工作台页与两个对话框）共用的键盘约定：
  Enter 提交但让给多行框与按钮，⌘Enter 一律提交，Esc 先失焦再关闭。
- `new_task_panels.dart`：建任务页的面板外框 —— 文件面板（标题行、横幅、提示条槽位）、
  空态落区、参数面板（标题行、滚动段、页脚）、页面与对话框共用的页脚校验文案 `TaskFooterLine`，
  以及顶栏的「上次参数」按钮 `LastUsedButton`。
- `new_task_file_table.dart`：建任务页有文件时的文件表 `NewTaskFileTable` —— 表头、56px 行壳
  （悬停底色、图标块、文件名 + 目录 / 问题说明、淡入的移除按钮）、参数说明、底部追加落区
  `FileAppendStrip`；各页只给中间几列（`FileTableColumn`，可按行宽收起）和每行的单元格。

- `new_task_form.dart`：三个建任务表单的公共基类 `NewTaskFormBase<TOptions, TFile>` —— 参数与
  `update` / `reset` / 「上次参数」、文件列表的增删与占位行替换、拖放说明、高级区开合、输出位置与
  选目录（`pickDirectory` 可注入）、`seed` / `browse`；`TaskOptionsFormBase` 在其上接好 `TaskOptions`
  （转写与翻译）：跟着设置刷新模型与默认勾选的词表、`toggleGlossary`、提交时展开词表 `frozenOptions`。
  参数从哪条路写进来都先过 `normalize`（转写表单在这里保证「说话人分离开着，选中的模型就得支持」）。
  暂存行的基类 `StagedPath`（路径、文件名、目录）。各表单只写收什么文件、怎么探测、怎么校验。
- `enqueue_request.dart`：`EnqueueRequest`，建任务表单交出来的「一批文件 + 一份参数」。
- `footer_message.dart`：`FooterMessage` / `FooterTone`，表单报页脚文案的性质，图标由 `TaskFooterLine` 决定 —— 表单不 import material；
  以及三个表单共用的页脚句子：`queuedFooter`（「将创建 N 个…任务」）、`blockedFooter` / `advisoryFooter`（就绪检查）。

共享组件放这里后，各 feature 不再互相 import 实现文件。

## 八、任务与建任务

新建转写、新建翻译与转码一样是导航栏上的同级入口，所以各自是一个 feature，
不放在 `tasks/` 下面。任务页的「新建转写 / 新建翻译」对话框由 `main.dart` 注入，
`tasks/` 不 import 另外两个 feature。

### 任务列表 `lib/features/tasks/`

- `tasks_page.dart`：把队列与 `TasksController` 接到 board 上；建任务对话框由装配层注入。
- `tasks_controller.dart`：`TasksController`，筛选与选中（挂在根节点上，离开任务页再回来还在）、建完任务选中这一批的第一个文件、拖入文件按多数分流（`routeDrop`）。
- `task_resume_dialog.dart`：续跑会重建文档、而编辑器里改过时的提醒（判断规则是 `SubtitleTask.resumeOverwritesEdits`）。
- `tasks_board.dart`：列表、详情和拖放区的组合。
- `task_table.dart`：任务表格、行内操作与空态。
- `stage_bar.dart`：阶段进度条。
- `drop_zone.dart`：按文件类型分流到转写或翻译。

任务详情按区块拆成：

- `task_detail_panel.dart`：选择与组合区块。
- `task_detail_header.dart`、`task_detail_error.dart`、`task_detail_stages.dart`。
- `task_detail_outputs.dart`（字幕产物 / 媒体产物）、`task_detail_log.dart`、`task_detail_section.dart`。
- `task_detail_chapters.dart`：合并任务的「章节」分区（每段起点、标题、字幕条数）。

### 新建转写 `lib/features/transcribe/`

- `transcribe_form.dart`：`TranscribeFormController`（继承 `shared/new_task_form.dart`）、暂存文件与提交结果。
- `transcribe_recognize_section.dart`、`transcribe_translate_section.dart`、
  `transcribe_advanced_section.dart`：表单分区；`transcribe_footer.dart`：开始按钮。
- `new_transcribe_page.dart`：顶栏内容、表单与入队（页面行为在 `shared/new_task_page.dart`）。
- `new_transcribe_file_panel.dart`、`new_transcribe_file_list.dart`（列定义与单元格，表格在
  `shared/new_task_file_table.dart`）、`new_transcribe_param_panel.dart`：往共享面板外框里填的内容。
- `new_transcribe_dialog.dart`：任务页使用的紧凑对话框入口。

### 新建翻译 `lib/features/translate/`

- `translate_form.dart`：`TranslateFormController`（继承 `shared/new_task_form.dart`）、暂存字幕、忽略的音视频与提交结果。
- `translate_language_section.dart`、`translate_advanced_section.dart`；`translate_footer.dart`：开始按钮。
- `translate_file_notes.dart`：忽略媒体 / 拒收格式提示（页面与对话框共用）。
- `new_translate_page.dart`：顶栏内容、表单、入队与「改用新建转写」（页面行为在 `shared/new_task_page.dart`）。
- `new_translate_file_panel.dart`、`new_translate_file_list.dart`（列定义与单元格，表格在
  `shared/new_task_file_table.dart`）、`new_translate_param_panel.dart`：往共享面板外框里填的内容。
- `new_translate_dialog.dart`：任务页使用的紧凑对话框入口。

## 九、转码功能 `lib/features/transcode/`

- `transcode_form.dart`：`TranscodeFormController`（继承 `shared/new_task_form.dart`）、源文件探测、按编码器记住参数和入队。
- `transcode_page.dart`：顶栏内容、表单、入队、进页即探测编码器（页面行为在 `shared/new_task_page.dart`）。
- `transcode_file_panel.dart`、`transcode_file_list.dart`：文件区；表格在 `shared/new_task_file_table.dart`，
  这里只给列定义（窄窗口收起视频、音频列）与单元格。
- `transcode_param_panel.dart`：输出、音频、高级区及开始按钮，装进共享参数面板外框。
- `transcode_video_section.dart`：编码器卡片和每家自己的参数控件。

## 十、合并功能 `lib/features/merge/`

- `merge_form.dart`：`MergeFormController`（**不**继承 `NewTaskFormBase`：合并是 N 行成一个任务）——
  有序段列表 `StagedSegment`、异步探测与字幕解析按段 id 回写、同名字幕配对、页脚优先级、命令预览、提交。
- `merge_page.dart`：顶栏内容、入队（页面行为在 `shared/new_task_page.dart`）。
- `merge_segment_list.dart`：分段面板、可拖动排序的段列表与行、章节起点条。
- `merge_param_panel.dart`：输出、章节与字幕开关、方式说明、命令预览与开始按钮。

## 十一、编辑器 `lib/features/editor/`

### 会话与状态

- `editor_session.dart`：sealed `EditorSession`；两种会话同一套保存规则 —— 编辑进度自动存，字幕文件（任务产物 / 挂载的本地文件）只在保存时写；写前比对时间戳；任务排队 / 运行中时 `busy`，编辑器只读。
- `editor_controller.dart`：筛选、搜索、选中、撤销、改字 / 时间、拆分 / 合并、说话人、翻译与导出；保存状态 `SyncState`、连续编辑合并、本地草稿；`follow` 任务队列，流水线换了文档就刷新、清撤销栈，`locked` 时一切修改不生效。写入流程也在这里：`confirmLeave`（离开前先写编辑进度、只读时不问、「先写入字幕文件？」）与 `writeFiles`（`save` → `WriteConflict` → 覆盖 / 挑目录 `saveAs`、`TargetRejected` 提示），要问用户的经 `EditorPrompts`。持有 `media`，随 controller 释放。
- `editor_prompts.dart`：`EditorPrompts` 接口（`askLeave` / `askConflict` / `pickDir` / `say`）与 `LeaveIntent`、`LeaveChoice`、`ConflictChoice`；只 import domain，测试换成按剧本回答的假实现（`test/editor_fixtures.dart` 的 `ScriptedPrompts`）。
- `editor_media.dart`：`EditorMedia`，检视面板预览的音视频：找文件（只找一次，手动关联优先）、「关联视频…」换上并记进 `EditorStore`、持有 `PreviewPlayback`；编辑页收起时只暂停，回来播放位置还在。
- `editor_open_form.dart`：本地原文 / 译文槽位、解析与配对预检。
- `preview_playback.dart`：media_kit 播放器封装，与选中条双向同步，多选时两个方向都脱钩（纯函数 `followTarget` / `seeksOnSelect`）；只依赖 `PlaybackCues` 接口（controller 实现它），免得 controller → media → playback → controller 成环。
- `editor_workspace.dart`：`EditorWorkspace`，当前会话、入口页是否盖在上面、最近打开；换会话 / 退出前的询问（`confirmLeave`）、保存（`save`）、草稿恢复、替换 / 重新配对都走它，打开会话时让 `media` 去找音视频。只依赖 `EditorPrompts`，不 import widget；挂在根节点上，由 `main.dart` 接线。

### 编辑页

- `editor_page.dart`：页面组合、焦点作用域与字幕表焦点（焦点落到作用域本身时转给列表）、生命周期。不读写文件、不持有播放器：预览从 `controller.media` 拿，保存交给上层的 `onSave`。键位与动作在 `editor_shortcuts.dart`。
- `editor_drop_zone.dart`：拖文件到编辑页的左右两块落区。
- `editor_banners.dart`：只读横幅与恢复横幅。
- `editor_chrome.dart`：编辑器分区的顶栏内容、副标题与状态栏文案。
- `editor_page_actions.dart`：视图菜单、保存 / 导出 / 翻译操作。
- `editor_title.dart`：顶栏标题右侧的组合与待校对徽标。
- `editor_source_chip.dart`：本地会话的来源 chip 与来源浮层。
- `editor_sync_chip.dart`：任务会话的保存状态 chip 与弹层。
- `editor_leave_dialog.dart`：`DialogEditorPrompts`，`EditorPrompts` 的界面实现 —— 「先写入字幕文件？」与外部修改冲突两个 `GlassDialog`、目录选择、SnackBar。只管问，不做决定。

字幕表格拆成：

- `cue_table.dart`：列表滚动、选中与页脚。列表区有自己的焦点，有焦点时整张表描主色边，页脚提示跟着焦点变。
- `cue_table_toolbar.dart`：视图、筛选、搜索、说话人筛选。
- `cue_table_rows.dart`：表头、字幕行、说话人单元格、状态标签、列宽。

检视面板拆成：

- `inspector.dart`：预览和当前条编辑器的组合。
- `inspector_preview.dart`：视频 / 音频画面、播放控制与 SeekBar。
- `inspector_cue_editor.dart`：当前字幕文本、文件名、时间码与动作。
- `inspector_speaker_field.dart`：说话人字段与菜单；多选时作用于全部选中条。
- `inspector_selection_editor.dart`：多选时替换当前条编辑器：已选条数、行号区间、批量说话人字段。

入口页拆成：

- `editor_open_page.dart`：生命周期和两栏布局。
- `editor_open_panels.dart`：本地 / 任务 / 最近打开面板。
- `editor_open_slots.dart`：原文 / 译文文件槽位与交换按钮。
- `editor_open_pairing.dart`：配对方式与统计。

快捷键拆成：

- `editor_keys.dart`：`EditorKeys` 登记表，只有键位，不依赖控制器，控制器与各处文案也引用它。
- `editor_shortcuts.dart`：两个作用范围。
  - `CueTableShortcuts`：单键，只包住列表区域，焦点在列表时才生效。
  - `EditorShortcuts`：⌘ 组合与「Esc 回到字幕表」，由 `main.dart` 挂在应用外壳外面，连顶栏一起包住；不在编辑器分区时动作不启用。
  - 另有页脚提示与完整快捷键表的生成。

其余：`editor_widgets.dart`（编辑器专用小件；`AnchoredPopover` 打开时焦点进浮层自己的作用域，Esc 关闭，关闭后焦点还回去）、`speaker_badge.dart`、`speaker_manager.dart`。

## 十二、设置 `lib/features/settings/`

- `settings_page.dart`：滚动监听、目录高亮、恢复默认和布局组合。
- `section_outline.dart`：分区枚举 `SettingsSectionKey`（先后就是页面顺序）；宽窗口 Rail / 窄窗口 Tabs。
- `settings_section.dart`：设置区、设置行、已保存提示和通用输入控件。
- `provider_section.dart`：识别 / 翻译服务的地址、模型列表、密钥、批大小、提示。两边的差别收在增强枚举
  `ProviderKind` 里（分区、文案、读写哪几项设置），界面代码里不逐处分叉。
- `model_list_editor.dart`：`ModelListEditor`，一家服务的模型列表 —— 每行一个模型声明（接入方式与模型族标签、
  能力、「默认」标记、设为默认 / 参数 / 删除），添加行在写下名字时校验，展开是照参数目录出控件的参数面板。
  只管界面状态，列表由外面给；改动只在确认时回调，写设置走 `AppSettings.addModel` 等四个入口。
- `glossary_section.dart`：`GlossarySection`，「词表」分区 —— 词表列表（窄窗是一行筹码）、新建 / 改名 / 删除、
  默认启用开关。
- `glossary_entry_table.dart`：`GlossaryEntryTable`，一份词表的条目表 —— 逐格编辑、表尾常驻新增行、多行粘贴
  按行解析；原文空着或重复的行只留在界面上标红，不存盘。表体按需建行、最多显示 12 行。
- `appearance_section.dart`、`language_section.dart`、`defaults_section.dart`、`output_section.dart`。
- `environment_section.dart`、`local_backend_section.dart`。
- `settings_footer.dart`、`settings_reset_dialog.dart`。

每个分区组件统一接收 `settings / stacked / saved / onChanged`；页面不再内联数百行表单。

## 十三、运行主线

1. **启动**：`main()` → 设置与目录 → 服务装配 → `TaskQueue.restore()` → `runApp()`。
2. **建任务**：表单控制器把参数冻结为 `TaskOptions` / `TranscodeOptions` / `MergeOptions` → `TaskQueue` 入队。
3. **执行**：`TaskRunner` 按 `task.media` 选择字幕、转码或合并分支；`TaskStageRunner` 统一阶段状态和续跑。
4. **识别**：`Registry.buildAsr()` → provider；逐段渠道把检查点写回任务。
5. **翻译**：已有译文跳过；条数不符只对可信的 `batchTooLarge` 错误减半重试。
6. **写字幕**：`SubtitleOutputWriter` 在落盘时折行；文档内始终保持无硬换行文本。
7. **转码 / 合并**：先写 `.part`，成功后改名；失败和取消清理临时文件。合并另在临时目录写 concat 列表、章节与拼好的字幕，完事删掉。
8. **编辑器**：编辑进度自动存（任务 JSON / 本地草稿）；字幕文件只在保存时写，任务会话写产物，文件会话写回原文件。

## 十四、按功能反查

| 要改什么 | 从这里开始 |
|---|---|
| 加 OpenAI 兼容服务 | `domain/providers/provider_catalog.dart` 增一条 `AsrProviderInfo` / `ChatProviderInfo` |
| 加非兼容 provider | `AsrTransport` 加一种接入方式 + 新适配器（参照 `dashscope_*.dart`），在 `services/registry.dart` 的 `switch` 里接上 |
| 加一个模型参数 | `domain/providers/model_params.dart` 的目录 + 对应实现类里读 `options` |
| 词表怎么进提示词 | `domain/glossary.dart`（`GlossaryText`）；识别在 `services/registry.dart` 拼进提示，翻译在 `services/translation_protocol.dart` |
| 设置页怎么编辑模型列表 | `features/settings/model_list_editor.dart`（界面）+ `services/settings.dart` 的 `addModel` / `removeModel` / `setDefaultModel` / `setModelOption` |
| 设置页怎么编辑词表 | `features/settings/glossary_section.dart` + `glossary_entry_table.dart`；存取在 `services/settings.dart` |
| 建任务页的模型下拉、「其他模型…」 | `features/shared/provider_fields.dart`（`ModelField`） |
| 建任务页勾选词表、什么时候展开成条目 | `features/shared/glossary_chips.dart` + `features/shared/new_task_form.dart`（`toggleGlossary` / `frozenOptions`） |
| 开关按模型能力显隐（说话人分离） | `domain/providers/asr_transport.dart`（`AsrCapabilities`）+ `features/transcribe/transcribe_recognize_section.dart`；开关与模型的约束在 `transcribe_form.dart` 的 `normalize` |
| 服务未配置 / 语言不支持提示 | `services/readiness.dart` + `features/shared/provider_fields.dart` |
| 任务类型与阶段顺序 | `domain/task_kind.dart` |
| 任务筛选分组、后台任务计数 | `domain/task_filter.dart` |
| 任务页选中、拖入分流 | `features/tasks/tasks_controller.dart` |
| 阶段断点、状态与耗时 | `pipeline/task_stage_runner.dart` |
| 字幕任务执行 | `pipeline/task_runner.dart` |
| 转码任务执行 | `pipeline/transcode_task_pipeline.dart` |
| 合并任务执行 | `pipeline/merge_task_pipeline.dart` |
| 合并的一致性检查、章节、字幕平移 | `domain/mux/merge_rules.dart` |
| 合并 / 重混流的 ffmpeg 参数 | `domain/mux/mux_plan.dart` |
| 加一种媒体任务（重混流、mkv） | `domain/media_job.dart` 加子类，按编译器提示补各处 `switch (task.media)` |
| 翻译条数协议 | `services/translation_protocol.dart` + `task_runner.dart` 的翻译阶段 |
| 断句 | `domain/segmenter.dart` |
| 折行 | `domain/line_wrap.dart`；调用在 `pipeline/subtitle_output_writer.dart` |
| SRT / VTT 与说话人标签 | `domain/srt.dart` |
| 产物目录 / 文件名 | `domain/paths.dart`、`output_naming.dart`、`task_options.dart` |
| ffmpeg 查找顺序 | `services/ffmpeg.dart` |
| 编码器参数目录 | `domain/transcode/encoder_catalog.dart` |
| ffmpeg 命令 | `domain/transcode/command.dart` |
| 编码器可用性检测 | `services/transcoder.dart` |
| 任务 JSON | `domain/task.dart` + `services/task_store.dart` |
| 设置键与默认值 | `services/settings.dart` |
| 导航项 | `features/shell/nav_rail.dart` + `main.dart` 的页面 switch |
| 顶栏内容 | 各页的 `xxxChrome()` + `features/shared/page_chrome.dart` |
| 建任务页的拖放、横幅、快捷键、两栏断点 | `features/shared/new_task_page.dart` + `submit_shortcuts.dart` |
| 快捷键（键位、作用范围、提示文案） | `core/shortcuts/app_shortcut.dart` / `shortcut_action.dart` + `features/editor/editor_keys.dart` / `editor_shortcuts.dart` |
| 建任务页的面板外框、空态、页脚文案、「上次参数」 | `features/shared/new_task_panels.dart` |
| 建任务页的文件表、追加落区 | `features/shared/new_task_file_table.dart` |
| 三个建任务表单共有的状态（参数、文件列表、输出位置、「上次参数」） | `features/shared/new_task_form.dart` |
| 字幕表格 | `features/editor/cue_table*.dart` |
| 编辑动作与撤销 | `features/editor/editor_controller.dart` + `domain/cue.dart` |
| 多选与批量改说话人 | `domain/cue_selection.dart` + `editor_controller.dart`（`visiblePositions` 是唯一的可见行来源，选区读取时与它取交集；`selectWith` / `assignSpeaker` / `assignNewSpeaker`）+ `inspector_selection_editor.dart` |
| 预览播放 | `features/editor/editor_media.dart` + `preview_playback.dart` + `inspector_preview.dart` |
| 保存 / 离开前询问 / 冲突 | `features/editor/editor_controller.dart`（`confirmLeave` / `writeFiles`）+ `editor_prompts.dart` + `editor_leave_dialog.dart` |

## 十五、验证

```bash
cd app
flutter analyze
flutter test
flutter test --tags golden --run-skipped
```

- 常规测试覆盖 domain、provider、队列、续跑、表单、编辑器、转码与合并。
- 合并：`test/mux_test.dart`（纯规则与 `MuxPlan`）、`merge_pipeline_test.dart`（假 Transcoder 的流水线）、
  `merge_ffmpeg_test.dart`（实跑 ffmpeg，没装时跳过）、`merge_form_test.dart`、`merge_page_test.dart`、`merge_tasks_test.dart`。
- `test/paths_test.dart` 钉死 POSIX / Windows 路径、盘符根目录与产物语言标签。
- `test/editor_workspace_test.dart` 覆盖换会话、入口页开合、「最近打开」的串行写盘、换会话 / 退出前的询问与保存（用 `ScriptedPrompts`，不需要 widget 树）；
  `test/editor_save_test.dart` 的「写入流程」组覆盖离开前写草稿、覆盖 / 另存为 / 取消与目标被拒的提示；
  `test/preview_playback_test.dart` 的 `EditorMedia` 组覆盖只找一次、手动关联优先与记住关联；
  `test/text_focus_test.dart` 钉死「焦点在输入框里」的判断（单行 / 多行）；
  `test/app_shortcut_test.dart` 钉死三个平台的修饰键与文案，`shortcut_action_test.dart` 钉死组字时不启用，`editor_shortcuts_test.dart` 覆盖单键只在列表有焦点时生效、⌘ 组合在输入框里生效、Esc 分层、长按不连发，`submit_shortcuts_test.dart` 与 `anchored_popover_test.dart` 覆盖建任务入口与浮层的键盘行为；
  `test/cue_selection_test.dart` 用随机操作序列检查选区不变量，`editor_test.dart` 与 `editor_ui_test.dart` 的「多选」组覆盖点选、筛选下扩选、批量指派与撤销，并用随机操作序列检查「批量只改看得见的选中行」；
  `preview_playback_test.dart` 的「播放与选区的联动」组覆盖多选时的脱钩。
- 服务与模型：`test/model_spec_test.dart`、`model_params_test.dart`、`provider_catalog_test.dart` 钉死声明、参数与登记表
  （预置的接法必须与按名字推断的一致）；`glossary_test.dart` 覆盖词表解析与两种提示词；
  `openai_asr_provider_test.dart`、`dashscope_asr_test.dart`、`dashscope_filetrans_test.dart`、`provider_test.dart`
  钉死请求形状 —— 不改设置时发出去的请求一个字段都不变；`readiness_test.dart` 覆盖就绪检查。
  界面：`model_list_editor_test.dart`（设置页模型列表）、`glossary_section_test.dart`（词表分区与条目表）、
  `provider_fields_test.dart`（建任务页的模型字段与说话人分离开关）、`glossary_chips_test.dart`（词表勾选）。
- `test/status_snapshot_test.dart` 钉死状态栏快照的服务文案（未选择 / 未配置 / 已配置）与任务计数。
- `test/task_filter_test.dart` 钉死状态分组；`test/tasks_controller_test.dart` 覆盖筛选、选中、拖入分流，
  以及拆掉任务页再装回来后选中与筛选仍在。
- golden 测试共 58 张场景图；拆 UI 文件后必须保持逐像素一致。
- `live` 测试需要真实密钥，默认跳过；ffmpeg / 平台硬件编码用例会按本机能力跳过。
