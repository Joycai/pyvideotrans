# app/ 源码结构索引（app/lib）

`app/` 是 Flutter 桌面客户端（macOS / Windows / Linux）的全部实现。
当前 `lib/` 共 135 个 Dart 文件、约 3.1 万行；`test/` 共 47 个 Dart 文件、约 1.1 万行。
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
| 界面 | `lib/features/` | 按功能分 `shell / tasks / transcribe / translate / transcode / editor / settings`；跨功能 UI 放 `shared/` |
| 流水线 | `lib/pipeline/` | 串行队列、任务编排、阶段壳、字幕写出与转码任务执行 |
| 服务 | `lib/services/` | 网络、ffmpeg / ffprobe、文件持久化、shared_preferences、provider 构造 |
| 领域 | `lib/domain/` | 数据模型与纯规则；不依赖 Flutter，不执行网络或外部进程 |
| 视觉基座 | `lib/core/` | 主题令牌和无业务语义的通用控件 |

当前相对 import 依赖图**没有循环**。边界约定：

- `domain/` 不 import Flutter、`services/`、`pipeline/` 或 `features/`。
- feature 之间不互相拿实现组件；跨 feature 复用放 `features/shared/`。
- 各页交给顶栏的内容走 `features/shared/page_chrome.dart` 这个契约，不 import `shell/` 的任何实现。
- 页面文件负责装配、生命周期和键盘 / 拖放入口；大块内容拆成同目录的 `*_panel.dart`、
  `*_section.dart`、`*_list.dart`。
- 对外需要稳定入口时可保留很薄的门面文件，例如 `core/widgets/fields.dart`。

## 二、装配与应用框架

### `lib/main.dart`

唯一装配点：

1. 初始化 Flutter 与 media_kit。
2. 载入 `AppSettings`，创建应用支持目录。
3. 构造 `Media`、`Transcoder`、`TaskRunner`、`TaskQueue`、`TaskStore`、`EditorStore`。
4. 恢复任务后启动 `SubtitleStudioApp`。
5. 持有转写、翻译、转码的表单控制器和编辑器的 `EditorWorkspace`，保证切页不丢状态。
6. 用 `Listenable.merge` 只驱动顶栏、状态栏和需要实时更新的页面，避免进度回调重建整棵应用树。

只做接线：各页的顶栏内容由各自的 `xxxChrome()` 给出，状态栏快照由
`StatusSnapshot.from` 拼，编辑器换会话、草稿恢复、最近打开的规则在 `EditorWorkspace`。

### `lib/features/shell/`

| 文件 | 内容 |
|---|---|
| `nav_rail.dart` | `AppSection` 六个导航项和 72px 导航栏 |
| `app_shell.dart` | Rail + 顶栏 + 内容区 + 状态栏的总体栅格 |
| `status_bar.dart` | `StatusSnapshot`（`from` 按设置、ffmpeg 与队列拼出快照）与底部状态栏；控件只画快照 |

## 三、视觉基座 `lib/core/`

### `core/theme/`

- `tokens.dart`：间距、圆角、时长、字体、状态层级。
- `app_extensions.dart`：`AppColors`、`AppGlass`、`AppElevation` 与 BuildContext 短写。
- `app_theme.dart`：独立调校的浅色 / 深色 `ThemeData`。

### `core/widgets/`

- `buttons.dart`：主按钮、控制按钮、静默按钮、图标按钮、分段选择、筛选条。
- `glass_dialog.dart`：询问对话框外壳（标题、正文、说明条、左侧文字操作 + 右侧按钮）。
- `fields.dart`：表单控件公共入口，只 export 下面两个实现文件。
- `dropdown.dart`：`AppDropdown`、分组 / 条目模型、菜单定位与条目渲染。
- `form_fields.dart`：标签、输入表面、数字 / 多行输入、开关、表单分区。
- `glass_panel.dart`：玻璃卡片与内容面板。
- `indicators.dart`：状态标签、时间码、渐变进度条、状态点。
- `dashed_border.dart`：转写、翻译、转码三页共用的虚线圆角框。
- `wallpaper.dart` + `baked_backdrop.dart`：静态背景烘焙，避免高 DPI 下重复全屏混合。

## 四、领域层 `lib/domain/`

### 字幕与任务

| 文件 | 内容 |
|---|---|
| `cue.dart` | `Cue`、校对状态和不可变 `SubtitleDocument`；拆分、合并、说话人操作都返回新文档 |
| `language.dart` | 统一语言表、CJK 判定、文件名语言推断 |
| `paths.dart` | 跨平台纯字符串路径规则：basename、dirname、stem、extension |
| `output_naming.dart` | 产物语言标签（自动检测写 `src`） |
| `srt.dart` | SRT / VTT 解析与序列化、说话人标签检测、导出字段 |
| `line_wrap.dart` | 导出时折行；CJK 与拉丁文字使用不同上限 |
| `segmenter.dart` | 识别结果的重叠修正、短句合并、长句拆分 |
| `subtitle_pairing.dart` | 本地原文与译文字幕的配对模式、统计与合并 |
| `speech_segments.dart` | 静音区间 → 可逐段识别的语音区间 |
| `recognition_checkpoint.dart` | 段级识别检查点，支持失败、取消和重启后的续跑 |
| `task_kind.dart` | `TaskStage` 与 `TaskKind`；独立放置以避免 `TaskOptions ↔ SubtitleTask` 循环 |
| `task_options.dart` | 入队时冻结的全部参数、产物目录规则、JSON |
| `task.dart` | `SubtitleTask`、阶段记录、日志、错误、产物和 JSON；export `task_kind.dart` |
| `media_kinds.dart` | 按扩展名判断媒体 / 音频 / 字幕 |
| `app_branding.dart` | 应用名的中英两份；另有五份在各平台的清单与 runner 里，见 `packaging/README.md` |
| `file_stamp.dart` | 文件大小 + 修改时间，判断字幕文件是否在外部被改过 |

### `domain/transcode/`

原先的单个 1463 行文件已按责任拆开：

| 文件 | 内容 |
|---|---|
| `codecs.dart` | 模式、容器、视频 / 音频编码枚举与兼容规则 |
| `encoder_params.dart` | 编码器参数模型：Choice / Int / Bool 与 `VideoEncoder` |
| `encoder_catalog.dart` | x264 / x265 / AV1 / VideoToolbox / NVENC / QSV / AMF 参数目录 |
| `options.dart` | `TranscodeOptions`、分辨率限制、参数 JSON |
| `probe.dart` | `MediaProbe` 与音视频流信息 |
| `command.dart` | `TranscodeJob`、ffmpeg 命令拼装、产物命名、进度解析 |

## 五、服务层 `lib/services/`

### Provider

- `provider_api.dart`：取消令牌、`ProviderException`、`ProviderInfo`、ASR / 翻译接口。
- `registry.dart`：可选服务登记表和 provider 工厂。
- `openai_compatible.dart`：OpenAI 兼容 ASR 与翻译实现；在线服务、Ollama、LM Studio、
  将来的本地 Python 后端共用。
- `translation_protocol.dart`：给每行加 `§N§`，返回后校验条数和行号。
- `dashscope_asr.dart`：百炼 Qwen3-ASR，静音切分后逐段识别。
- `dashscope_filetrans.dart`：百炼异步整文件转写，上传、提交、轮询、读取句级时间戳。
- `audio_splitter.dart`：切音频接口与 ffmpeg 实现，测试可注入假实现。
- `readiness.dart`：未配置、语言不支持、未实施等状态统一成可行动提示。

### 本地 IO 与持久化

- `media.dart`：定位 ffmpeg / ffprobe、探测文件、抽音、静音检测、切音频、取消时杀进程树。
- `transcoder.dart`：编码器检测、试编码、ffprobe、执行转码和错误解释。
- `settings.dart`：shared_preferences 设置和 provider 连接配置；不依赖 Registry，由调用方传 provider id。
- `task_store.dart`：一个任务一份 JSON，进度更新时只重写变化的任务。
- `editor_store.dart`：本地会话的附加状态与编辑进度草稿、媒体关联和最近打开。
- `file_io.dart`：读文件时间戳；原子写（先写临时文件再改名），多份文件成组写，要么全成要么都不留。
- `reveal.dart`：Finder / Explorer 中定位文件或打开目录。
- `local/local_backend.dart`：本地 Python 后端客户端占位，第一期未实施。

## 六、流水线 `lib/pipeline/`

| 文件 | 内容 |
|---|---|
| `task_queue.dart` | 串行队列；入队、取消、继续、优先、删除、恢复；脏任务攒 300ms 批量写盘 |
| `task_runner.dart` | 选择字幕 / 转码分支、统一捕获取消 / provider / 未知错误；字幕的准备、识别、断句、翻译编排 |
| `task_stage_runner.dart` | 所有阶段共用的断点跳过、active / done 状态、耗时与通知 |
| `subtitle_output_writer.dart` | SRT / VTT / TXT 原子写出、按语言折行、双语命名、说话人标签、记产物时间戳；完成阶段与编辑器「保存」共用 |
| `transcode_task_pipeline.dart` | 转码准备、执行 `.part` 临时文件、完成校验 |
| `task_progress.dart` | 字幕按条目、转码按毫秒共用的 ETA 外推公式 |

关键承诺仍由 `TaskRunner` 统一维护：失败或取消时保留已完成阶段；重试从
`SubtitleTask.resumeStage` 继续。

## 七、跨 feature 公共件 `lib/features/shared/`

- `provider_fields.dart`：服务分组、模型字段、readiness 行、链接文字、单选行、服务 / 模型摘要。
- `command_block.dart`：转码页与任务详情共用的可复制命令块。
- `enqueued_banner.dart`：三个建任务页面共用的入队成功横幅。
- `step_dots.dart`：三个建任务页面共用的三步说明。
- `page_chrome.dart`：页面交给顶栏的稳定契约：标题、副标题、尾随标签、操作区。Shell 与各页都依赖它，
  放在这里而不是 `shell/`，各页就不必 import 另一个 feature。

- `enqueue_request.dart`：`EnqueueRequest`，建任务表单交出来的「一批文件 + 一份参数」。

共享组件放这里后，各 feature 不再互相 import 实现文件。

## 八、任务与建任务

新建转写、新建翻译与转码一样是导航栏上的同级入口，所以各自是一个 feature，
不放在 `tasks/` 下面。任务页的「新建转写 / 新建翻译」对话框由 `main.dart` 注入，
`tasks/` 不 import 另外两个 feature。

### 任务列表 `lib/features/tasks/`

- `tasks_page.dart`：筛选、选中；建任务对话框由装配层注入。
- `task_resume_dialog.dart`：续跑会重建文档、而编辑器里改过时的提醒。
- `tasks_board.dart`：列表、详情和拖放区的组合。
- `task_table.dart`：任务表格、行内操作与空态。
- `stage_bar.dart`：阶段进度条。
- `drop_zone.dart`：按文件类型分流到转写或翻译。

任务详情按区块拆成：

- `task_detail_panel.dart`：选择与组合区块。
- `task_detail_header.dart`、`task_detail_error.dart`、`task_detail_stages.dart`。
- `task_detail_outputs.dart`、`task_detail_log.dart`、`task_detail_section.dart`。

### 新建转写 `lib/features/transcribe/`

- `transcribe_form.dart`：`TranscribeFormController`、暂存文件与提交结果。
- `transcribe_recognize_section.dart`、`transcribe_translate_section.dart`、
  `transcribe_advanced_section.dart`、`transcribe_footer.dart`：表单分区。
- `new_transcribe_page.dart`：生命周期、拖放、快捷键、入队和响应式两栏布局。
- `new_transcribe_file_panel.dart`、`new_transcribe_file_list.dart`、
  `new_transcribe_param_panel.dart`：页面内容。
- `new_transcribe_dialog.dart`：任务页使用的紧凑对话框入口。

### 新建翻译 `lib/features/translate/`

- `translate_form.dart`：`TranslateFormController`、暂存字幕与提交结果。
- `translate_language_section.dart`、`translate_advanced_section.dart`、`translate_footer.dart`。
- `translate_file_notes.dart`：忽略媒体 / 拒收格式提示；独立放置避免面板与列表循环 import。
- `new_translate_page.dart`：生命周期、拖放、快捷键、入队和响应式布局。
- `new_translate_file_panel.dart`、`new_translate_file_list.dart`、
  `new_translate_param_panel.dart`：页面内容。
- `new_translate_dialog.dart`：任务页使用的紧凑对话框入口。

## 九、转码功能 `lib/features/transcode/`

- `transcode_form.dart`：`TranscodeFormController`、源文件探测、参数选择和入队。
- `transcode_page.dart`：页面生命周期、拖放、快捷键、响应式布局。
- `transcode_file_panel.dart`、`transcode_file_list.dart`：文件区。
- `transcode_param_panel.dart`：输出、音频、高级区及开始按钮。
- `transcode_video_section.dart`：编码器卡片和每家自己的参数控件。
- `transcode_widgets.dart`：转码页内共用的 Section / Hint / Chip。

## 十、编辑器 `lib/features/editor/`

### 会话与状态

- `editor_session.dart`：sealed `EditorSession`；两种会话同一套保存规则 —— 编辑进度自动存，字幕文件（任务产物 / 挂载的本地文件）只在保存时写；写前比对时间戳；任务排队 / 运行中时 `busy`，编辑器只读。
- `editor_controller.dart`：筛选、搜索、选中、撤销、改字 / 时间、拆分 / 合并、说话人、翻译与导出；保存状态 `SyncState`、连续编辑合并、本地草稿；`follow` 任务队列，流水线换了文档就刷新、清撤销栈，`locked` 时一切修改不生效。
- `editor_open_form.dart`：本地原文 / 译文槽位、解析与配对预检。
- `preview_playback.dart`：media_kit 播放器封装和按时间定位字幕。
- `editor_workspace.dart`：`EditorWorkspace`，当前会话、入口页是否盖在上面、最近打开；换会话前询问写入、草稿恢复、替换 / 重新配对都走它。挂在根节点上，由 `main.dart` 接线。

### 编辑页

- `editor_page.dart`：快捷键、生命周期、页面组合。
- `editor_drop_zone.dart`：拖文件到编辑页的左右两块落区。
- `editor_banners.dart`：只读横幅与恢复横幅。
- `editor_chrome.dart`：编辑器分区的顶栏内容、副标题与状态栏文案。
- `editor_page_actions.dart`：视图菜单、保存 / 导出 / 翻译操作。
- `editor_title.dart`：来源浮层、保存状态 chip 与弹层、待校对徽标。
- `editor_leave_dialog.dart`：离开 / 退出前「先写入字幕文件？」、写入流程与外部修改冲突询问。

字幕表格拆成：

- `cue_table.dart`：列表滚动、选中与页脚。
- `cue_table_toolbar.dart`：视图、筛选、搜索、说话人筛选。
- `cue_table_rows.dart`：表头、字幕行、说话人单元格、状态标签、列宽。

检视面板拆成：

- `inspector.dart`：预览和当前条编辑器的组合。
- `inspector_preview.dart`：视频 / 音频画面、播放控制与 SeekBar。
- `inspector_cue_editor.dart`：当前字幕文本、文件名、时间码与动作。
- `inspector_speaker_field.dart`：说话人字段与菜单。

入口页拆成：

- `editor_open_page.dart`：生命周期和两栏布局。
- `editor_open_panels.dart`：本地 / 任务 / 最近打开面板。
- `editor_open_slots.dart`：原文 / 译文文件槽位与交换按钮。
- `editor_open_pairing.dart`：配对方式与统计。

其余：`editor_widgets.dart`（编辑器专用小件）、`speaker_badge.dart`、`speaker_manager.dart`。

## 十一、设置 `lib/features/settings/`

- `settings_page.dart`：滚动监听、目录高亮、恢复默认和布局组合。
- `section_outline.dart`：宽窗口 Rail / 窄窗口 Tabs。
- `settings_section.dart`：设置区、设置行、已保存提示和通用输入控件。
- `provider_section.dart`：识别 / 翻译服务的地址、模型、密钥、批大小。
- `appearance_section.dart`、`language_section.dart`、`defaults_section.dart`、`output_section.dart`。
- `environment_section.dart`、`local_backend_section.dart`。
- `settings_footer.dart`、`settings_reset_dialog.dart`。

每个分区组件统一接收 `settings / stacked / saved / onChanged`；页面不再内联数百行表单。

## 十二、运行主线

1. **启动**：`main()` → 设置与目录 → 服务装配 → `TaskQueue.restore()` → `runApp()`。
2. **建任务**：表单控制器把参数冻结为 `TaskOptions` / `TranscodeOptions` → `TaskQueue` 入队。
3. **执行**：`TaskRunner` 选择字幕或转码分支；`TaskStageRunner` 统一阶段状态和续跑。
4. **识别**：`Registry.buildAsr()` → provider；逐段渠道把检查点写回任务。
5. **翻译**：已有译文跳过；条数不符只对可信的 `batchTooLarge` 错误减半重试。
6. **写字幕**：`SubtitleOutputWriter` 在落盘时折行；文档内始终保持无硬换行文本。
7. **转码**：先写 `.part`，成功后改名；失败和取消清理临时文件。
8. **编辑器**：编辑进度自动存（任务 JSON / 本地草稿）；字幕文件只在保存时写，任务会话写产物，文件会话写回原文件。

## 十三、按功能反查

| 要改什么 | 从这里开始 |
|---|---|
| 加 OpenAI 兼容服务 | `services/registry.dart` 增一条 `ProviderInfo` |
| 加非兼容 provider | `services/provider_api.dart` + 新适配器，参照 `dashscope_*.dart` |
| 服务未配置 / 语言不支持提示 | `services/readiness.dart` + `features/shared/provider_fields.dart` |
| 任务类型与阶段顺序 | `domain/task_kind.dart` |
| 阶段断点、状态与耗时 | `pipeline/task_stage_runner.dart` |
| 字幕任务执行 | `pipeline/task_runner.dart` |
| 转码任务执行 | `pipeline/transcode_task_pipeline.dart` |
| 翻译条数协议 | `services/translation_protocol.dart` + `task_runner.dart` 的翻译阶段 |
| 断句 | `domain/segmenter.dart` |
| 折行 | `domain/line_wrap.dart`；调用在 `pipeline/subtitle_output_writer.dart` |
| SRT / VTT 与说话人标签 | `domain/srt.dart` |
| 产物目录 / 文件名 | `domain/paths.dart`、`output_naming.dart`、`task_options.dart` |
| ffmpeg 查找顺序 | `services/media.dart` |
| 编码器参数目录 | `domain/transcode/encoder_catalog.dart` |
| ffmpeg 命令 | `domain/transcode/command.dart` |
| 编码器可用性检测 | `services/transcoder.dart` |
| 任务 JSON | `domain/task.dart` + `services/task_store.dart` |
| 设置键与默认值 | `services/settings.dart` |
| 导航项 | `features/shell/nav_rail.dart` + `main.dart` 的页面 switch |
| 顶栏内容 | 各页的 `xxxChrome()` + `features/shared/page_chrome.dart` |
| 字幕表格 | `features/editor/cue_table*.dart` |
| 编辑动作与撤销 | `features/editor/editor_controller.dart` + `domain/cue.dart` |
| 预览播放 | `features/editor/preview_playback.dart` + `inspector_preview.dart` |

## 十四、验证

```bash
cd app
flutter analyze
flutter test
flutter test --tags golden --run-skipped
```

- 常规测试覆盖 domain、provider、队列、续跑、表单、编辑器与转码。
- `test/paths_test.dart` 钉死 POSIX / Windows 路径、盘符根目录与产物语言标签。
- golden 测试共 44 张场景图；拆 UI 文件后必须保持逐像素一致。
- `live` 测试需要真实密钥，默认跳过；ffmpeg / 平台硬件编码用例会按本机能力跳过。
