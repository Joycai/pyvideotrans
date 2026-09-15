# Claude Design prompt · 转码页（M-TranscodePage）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> Flutter 实现：`app/lib/features/transcode/`，参数模型：`app/lib/domain/transcode.dart`。
> 产出的设计稿：`P6a Transcode Page Light` / `P6b Transcode Page Dark` / `P6c Transcode Encoders` / `P6d Transcode Task`，
> 模块 `M-TranscodePage` / `M-TranscodeTask`（https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P6a+Transcode+Page+Light.dc.html）。

---

在项目「桌面字幕工具 · 设计系统」里新增「转码」常驻页面。它是 FFmpeg 的图形外壳：把视频批量转成
H.264 / HEVC / AV1，或者不转码只把音视频流重混流进 MP4 / MOV。导航栏里排在「翻译」下面，建出的
任务与转写、翻译任务进同一个任务队列。

页面与 `M-TranslatePage` 同构：左列文件面板（自适应），右列参数面板 400px；Rail、顶栏、状态栏全部复用
C 组件。动手前先读 `readme.md`、`M-TranslatePage.dc.html`、`M-TasksBoard.dc.html`，凡与翻译页相同的
元素（面板头高 60、横幅、空态落区、三步指示、页脚、按钮）保持像素一致。

## 要产出的文件

1. `C-NavRail.dc.html` — 在「翻译」与「编辑器」之间加一项「转码」，icon `video_settings`，`active="transcode"`。
2. `M-TranscodePage.dc.html` — 模块。props：`theme` `variant=A|B|C|D` `dragging` `encoder=x264|videotoolbox|nvenc|qsv|amf|svtav1`（只影响 B 态参数区，默认 videotoolbox）。
3. `M-TranscodeTask.dc.html` — 任务页里一条转码任务选中后的样子：任务表格（含一条转码任务行、一条转写任务行作对照）+ 右侧详情面板。props：`theme` `state=running|done|failed`。
4. `P6a Transcode Page Light.dc.html` — 浅色四态并排；顶部互跳导航条串起 P6a–P6d。
5. `P6b Transcode Page Dark.dc.html` — 深色四态。
6. `P6c Transcode Encoders.dc.html` — 六个编码器参数区并排（每块 400 宽，只画参数面板本身）+ 编号标注。
7. `P6d Transcode Task.dc.html` — 任务页浅色 running / 深色 done / 浅色 failed。
8. 更新 `readme.md` 的 P / M 表。

每个 P 文件渲染体积保持 200k 以下，文件名只用 ASCII。

## 页面框架

1440×900，与翻译页相同。Rail `active="transcode"`。顶栏 title「转码」；meta 空态「用 FFmpeg 把视频转成其他编码，或不转码直接换容器」，有文件时「3 个视频 · 共 1:12:40 · HEVC · VideoToolbox → MP4 · 将创建 3 个转码任务」。顶栏右侧 outlined 按钮「上次参数」（icon `history`）。

## 左列 · 文件面板

- 头部、空态、横幅、三步、拖入态全部同翻译页。空态 icon `movie`，标题「把视频拖到这里」，副文案「MP4 · MOV · MKV · AVI · WebM · FLV · WMV · TS，可一次选多个」。三步：1 添加视频 / 2 选择编码与编码器 / 3 加入队列，进度在任务页。
- 有文件：表格 grid `36px | 1fr | 72px | 136px | 96px | 80px | 96px | 36px`，列头「文件 / 时长 / 视频 / 音频 / 大小 / 状态」。视频列两行小字：`HEVC` + `3840×2160 · 60p`；音频列 `AAC` + `2ch`（mono tnum）。状态 chip：就绪（success-container）/ 读取中（surface-container，`progress_activity`）/ 不兼容（error-container，副标题 error 色，例如「WMV3 视频不能直接放进 MP4，将跳过；改为转码即可」）/ 无法读取（error-container，「ffprobe 读不出音视频流，将跳过」）。
- 表格下方一句说明：「参数统一应用到每个文件；输出写到源文件旁，文件名加 `.hevc` 后缀，不覆盖原文件」。
- 底部 44px 虚线条「继续拖入可追加文件」。

## 右列 · 参数面板

头部 60px「参数」+ text 按钮「重置为默认」。内容区滚动，页脚常驻。

### 分区一「输出」

- 方式：分段控件「转码 / 仅重混流」。重混流时下面「视频」「音频」两个分区折叠成一行说明：「不重新编码，原样复制音视频流到新容器，速度快、画质无损；字幕轨不带入」。
- 容器：分段控件「MP4 / MOV」。

### 分区二「视频」

- 编码：分段控件 5 段「H.264 / HEVC / AV1 / VC-1 / 复制」。VC-1 禁用 38%，tooltip 与下方 hint「FFmpeg 没有 VC-1 编码器，VC-1 源文件可以用「复制」或「仅重混流」」。
- 编码器：单选卡片列表，每张 48px：左侧 radio，中间两行（第一行「VideoToolbox · Apple」body-medium；第二行 mono body-small `hevc_videotoolbox`），右侧状态 chip：
  - 可用（success-container，`check`）
  - 检测中（surface-container，`progress_activity`）
  - 未编入（surface-container，文字 on-surface-variant，`block`）—「此 FFmpeg 没有编入 hevc_nvenc」
  - 设备不可用（error-container，`error`）—编入了但试编码失败，副标题 error 色一句原因「没有找到 NVIDIA 显卡或驱动」
  不可用的卡片整张 38% 且不可点。列表顺序：CPU（x264 / x265 / SVT-AV1）、VideoToolbox、NVENC、QSV、AMF。卡片下方一行 text 按钮「重新检测」+ 说明「检测方式：对每个编码器试编码 1 帧」。
- 编码器参数：标题「编码器参数」右侧 mono 小字当前编码器名。**参数项随编码器变**，不是一套通用表单（详见下节）。
- 分辨率 select「保持原样 / 2160p / 1440p / 1080p / 720p / 480p」、帧率 select「保持原样 / 60 / 30 / 25 / 24」两列。

### 各编码器的参数（P6c 逐块画出，B 态按 `encoder` prop 切换）

| 编码器 | 参数项 |
| --- | --- |
| x264 / x265（CPU） | 码率控制 分段「CRF 恒定质量 / 平均码率」；CRF number（x264 默认 23、x265 默认 28，范围 0–51，hint「数值越小画质越高、文件越大；18 左右肉眼无损」）或 码率 number kbps；预设 select ultrafast…veryslow（默认 medium，hint「越慢压缩率越高，画质相同时文件更小」）；调优 select 不指定 / film / animation / grain / stillimage / fastdecode / zerolatency（x265 少 film、stillimage）；Profile select 自动 / baseline / main / high（x265：自动 / main / main10） |
| VideoToolbox（Apple） | 码率控制 分段「恒定质量 / 平均码率 / 固定码率」；质量 number 1–100（默认 65，hint「仅 Apple 芯片支持恒定质量」）或 码率 kbps；Profile；开关「优先速度」（`-prio_speed`）；开关「允许回退到软件编码」（`-allow_sw`）；开关「硬件解码」（`-hwaccel videotoolbox`） |
| NVENC（NVIDIA） | 预设 分段 p1…p7（默认 p4，两端标「最快」「最好」）；调优 select hq / ll 低延迟 / ull 超低延迟 / lossless；码率控制 分段「CQ 恒定质量 / VBR / CBR」；CQ number 0–51（默认 23）或 码率 kbps + 最大码率 kbps；多遍编码 select 关闭 / 四分之一分辨率 / 全分辨率；前瞻帧数 number 0–32；开关「空间自适应量化 AQ」；开关「CUDA 硬件解码」（`-hwaccel cuda`）。AV1 卡片 hint「需要 RTX 40 系列及以上」 |
| QSV（Intel） | 预设 select veryfast…veryslow；码率控制 分段「ICQ 恒定质量 / VBR / CBR」；ICQ number 1–51（默认 23）或 码率；开关「前瞻 Look-ahead」（仅 H.264）；开关「QSV 硬件解码」 |
| AMF（AMD） | 质量档 分段「速度 / 均衡 / 质量」；码率控制 分段「CQP 固定量化 / VBR 峰值 / CBR」；QP number 0–51（默认 23，I/P 帧同值）或 码率；开关「预分析」；开关「D3D11 硬件解码」 |
| SVT-AV1（CPU） | 码率控制 分段「CRF / 平均码率」；CRF number 0–63（默认 35）；预设 number 0–13（默认 8，hint「0 最慢最好，13 最快」）；胶片颗粒 number 0–50（默认 0） |

P6c 的标注指向：同一个「H.264」在 x264 与 NVENC 下参数完全不同；码率控制切换时下方数值框随之替换（CRF ↔ 码率）；硬件解码开关只在硬件编码器出现；参数改动实时反映到命令预览。

### 分区三「音频」

- 编码：分段「AAC / MP3 / Opus / Vorbis / 复制」。容器不支持时该段禁用 38% 并在下方说明：Vorbis 两种容器都不行（hint「MP4 与 MOV 都装不下 Vorbis（OGG 音频），要 OGG 系音频请选 Opus，仅 MP4 支持」）；MOV 下 Opus 禁用。
- 码率 select 96 / 128 / 160 / 192 / 256 / 320 kbps（默认 160），声道 select 保持 / 立体声 / 单声道 两列。

### 分区四「高级」（可折叠；折叠摘要「与源文件同目录 · 后缀 .hevc · 快速启动」）

- 输出位置 单选（同翻译页）+ 文件名后缀 text（默认随编码，mono）。说明「写成 `interview_ep12.hevc.mp4`；同名文件已存在时自动加序号」。
- 开关「快速启动（moov 前置）」note「便于网页边下边播」。
- 额外参数 text（mono，placeholder `-x265-params aq-mode=3`），hint「原样追加在输出文件前，参数错误会在任务日志里看到 FFmpeg 的报错」。
- 命令预览：surface-container 块，mono 12px，自动换行，右上角 icon 按钮 `content_copy`「复制命令」。示例：
  `ffmpeg -hide_banner -hwaccel videotoolbox -i interview_ep12.mkv -map 0:V -map 0:a? -c:v hevc_videotoolbox -q:v 65 -tag:v hvc1 -c:a aac -b:a 160k -movflags +faststart interview_ep12.hevc.mp4`

页脚：左侧状态句 + icon，右侧 filled 按钮 icon `video_settings`「开始转码 · 3」。

| 情形 | 文案 | 色 |
| --- | --- | --- |
| 无文件 | 先添加视频 | on-surface-variant，icon `add_circle` |
| 找不到 FFmpeg | 找不到 FFmpeg，macOS 执行 brew install ffmpeg 后重新检测 | error，icon `error` |
| 编码器不可用 | hevc_nvenc 在这台电脑上不可用，换一个编码器 | error，icon `error` |
| 正常 | 将创建 3 个转码任务，按列表顺序排队 | on-surface-variant，icon `info` |
| 有跳过 | …；1 个文件不兼容，将跳过 | 同上 |

## 四个状态

- **A 空态**：无文件；参数 HEVC + VideoToolbox；开始禁用。
- **B 常态**：3 个视频 —— `interview_ep12.mkv` 48:12 HEVC 3840×2160·60p / AAC 2ch 6.2 GB 就绪；`product_demo.mov` 06:40 H.264 1920×1080·30p / AAC 2ch 812 MB 就绪（悬停行）；`lecture_week3.mp4` 读取中。编码 HEVC，编码器列表：x265 可用 / VideoToolbox 可用（选中）/ NVENC 未编入 / QSV 未编入 / AMF 未编入；编码器参数按 `encoder` prop；高级折叠。
- **C 重混流**：方式「仅重混流」，容器 MP4；2 个文件，其中 `old_capture.wmv`（WMV3 / WMA）不兼容；视频与音频分区收成说明行；高级展开，命令预览是 `-c copy`。
- **D 提交后**：列表清空，success 横幅「已加入队列 3 个任务，按列表顺序排队 · 查看任务」，参数原样保留，三步到第 3 步。

## 任务页里的转码任务（M-TranscodeTask）

- 任务行：类型列「转码」；文件列第二行「48:12 · HEVC → MP4」；服务/模型列 icon `memory`（硬件）或 `computer`（CPU），第一行「VideoToolbox」第二行 mono `hevc_videotoolbox`；阶段条只有四段「排队 / 准备 / 转码 / 完成」；剩余列「约 6 分钟」，阶段文字「转码 · 2.4x」。
- 详情面板（沿用 C 结构）：头部标题文件名，副标题「转码 · 48:12 · HEVC → MP4」，标签「硬件编码 · VideoToolbox」；各阶段耗时四行（准备 note「ffprobe · 2 路流」，转码 note「帧 41,230 · 2.4x」）；产物一行 `interview_ep12.hevc.mp4` meta「1.8 GB」，完成后右侧 icon 按钮 `folder_open`「在访达中显示」；新增分区「FFmpeg 命令」mono 块 + 「复制」；日志。
- done：任务行操作列「在访达中显示」outlined dense 按钮（替代「打开编辑器」）。failed：错误块标题「hevc_nvenc 初始化失败」，detail 为 FFmpeg stderr 末尾，建议「换成 x265 或 VideoToolbox 后从转码阶段继续」，按钮「从转码阶段继续」。

## 规则

- 只用 `tokens/` 里的令牌；深色主题单独校验 AA。玻璃只在 Rail / 顶栏 / 状态栏 / 详情面板。
- 文案陈述句，不用感叹号、不用 emoji，数字半角；编码器名、参数、命令、分辨率、时长用 mono tnum。
- 与 M-TranslatePage 相同的元素保持像素一致；差异只出现在：视频/音频列、编码器卡片、随编码器变化的参数区、命令预览、不兼容 chip。
- 组件复用 C-NavRail、C-TopBar、C-StatusBar、C-Field、C-Switch、C-FileRow（视频/音频两列若 C-FileRow 放不下，给它加可选 prop `video` `audio`，为空时不渲染，不要复制组件）。
