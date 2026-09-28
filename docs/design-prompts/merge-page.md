# Claude Design prompt · 合并页（M-Merge）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> Flutter 实现：`app/lib/features/merge/`，参数模型：`app/lib/domain/mux/merge_options.dart`；任务页部分在 `app/lib/features/tasks/`（`task_table.dart`、`task_detail_*.dart`）。
> 产出的设计稿：`P6d Merge Page` / `P6e Merge States` / `P6f Merge Task`，模块 `M-Merge`（module = MergePage | MergeTask）。
> - 合并页常态 light / dark：https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P6d+Merge+Page.dc.html
> - 空态 / 参数不一致 / 就绪：https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P6e+Merge+States.dc.html
> - 任务页里的合并任务：https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P6f+Merge+Task.dc.html
> - 模块本身：https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=M-Merge.dc.html
>
> 实现与稿子的差异：长说明块能折行（稿里是单行 NoteBar）；列表宽不到 760 时时长、音频写在文件列第二行；编码放不进容器时状态写「不兼容」。
> 设计系统里还没补的：`C-Base` NavRail 的「合并」项、`readme.md` 的 P / M 表（P6d–P6f、M-Merge）。

---

在项目「桌面字幕工具 · 设计系统」里新增「合并」常驻页面。它把 N 段（≥2）视频按顺序不转码（`-c copy`）
拼成一个 MP4 / MOV，每段自动成为一个章节；各段可挂一个 SRT / VTT 字幕，按「前面各段时长之和」平移后
拼成一份，可内嵌为软字幕轨、也可旁挂 SRT。导航栏里排在「转码」下面，建出的任务与转写、翻译、转码
任务进同一个任务队列。

页面与 `M-TranscodePage` 同构：左列分段面板（自适应），右列参数面板 400px；顶栏、状态栏复用 C 组件。
动手前先读 `readme.md`、`M-Workbench.dc.html`（module = TranscodePage），凡与转码页相同的元素
（面板头高 60、空态落区、三步指示、页脚、按钮、分段控件、命令预览块）保持像素一致。

## 要产出的文件

1. `M-Merge.dc.html` — 模块，`module = MergePage | MergeTask`。
   - MergePage props：`theme` `variant=A|B|C|D|E` `dragging`。A 空态、B 常态（第 3 段读取中）、C 参数不一致、D 就绪、E 提交后。
   - MergeTask props：`theme` `state=running|done|failed`。
   - 导航栏在 M-Merge 内按 Flutter `AppNavRail` 的尺寸自绘（72 宽、56 高一项、56×32 选中胶囊），
     在「转码」与「编辑器」之间多一项「合并」，icon `merge`。`C-Base` 的 NavRail 部件还没有这一项，
     不改已有组件；实现落地后再给 NavRail 加 `merge`。
2. `P6d Merge Page.dc.html` — 常态 light / dark。
3. `P6e Merge States.dc.html` — 空态、参数不一致、就绪（light）。
4. `P6f Merge Task.dc.html` — 任务页：浅色进行中 / 深色完成 / 浅色准备失败。
5. 顶部互跳导航条串起 P6d–P6f。每个 P 文件渲染体积 200k 以下，文件名只用 ASCII。

## 页面框架

1440×900。顶栏 title「合并」；meta 空态「把几段视频按顺序拼成一个文件，不转码，每段一个章节」，
有段时「3 段 · 共 1:08:32 · H.264 1920×1080 · 30p · 无转码 → MP4 · 3 个章节」；
有段在读取时把「共 …」换成「第 3 段读取中」；有不一致时换成「第 2 段参数与第 1 段不一致」。顶栏无右侧按钮。

## 左列 · 分段面板

- 头部 60px：「分段 3」+ text「清空」+ outlined「添加视频…」（icon `add`）。
- 空态：虚线落区，icon `merge` 40px，标题「把要合并的视频拖到这里」，副文案「至少 2 段，按添加顺序首尾相接 ·
  MP4 · MOV · MKV · TS · M2TS」，小字「视频旁有同名的 .srt / .vtt 会一起挂上；也可以把字幕单独拖进来」，
  outlined「选择文件…」。三步：1 添加视频（2 段以上）/ 2 排好顺序、挂上字幕 / 3 加入队列，进度在任务页。
- 有段：有序列表（不是转码页的文件表），外框 1px outline-variant、圆角 12。表头 36px「# / 文件 · 章节 · 字幕 /
  时长 / 视频 / 音频 / 状态」，列 `20 | 24 | 1fr | 56 | 128 | 104 | 84 | 92`，列间距 10。
  每段两行：
  - 第一行：拖动把手 `drag_indicator` · 序号方块 · 文件名 + 目录 · 时长（mono）· 视频两行（`H.264` / `1920×1080 · 30p`）·
    音频两行（`AAC` / `48 kHz · 2ch`）· 状态 chip（就绪 / 读取中 / 不一致 / 无法读取）· 上移 / 下移 / 移除三个 28px 图标按钮
    （第 1 段上移、最后一段下移 38% 不可点）。
  - 第二行（从文件列起跨到末列）：「章节」+ 32px 高输入框（默认文件名去扩展名，可改）；「字幕」+ 已挂字幕 chip
    （icon `subtitles`、文件名、`402 条`、小标签「同名自动挂上」、摘下按钮）或 text「挂字幕…」+ 小字「这一段不出字幕，时长照算」。
  - 不一致的段：左侧 3px error 竖边，状态 chip「不一致」，出问题的那一项文字改 error 色加粗，第三行 error 色一句
    「分辨率 1280×720 ≠ 第 1 段 1920×1080」。只报第一处不一致。
- 列表下方说明「按列表顺序首尾相接，第 1 段是参数基准；拖动左侧把手或点箭头调整顺序」。
- 「章节起点 · 字幕按同样的起点平移」：一条 36px 的比例条，每段一块（宽度按时长，最小 112），块内 `#2 00:32:10`，
  有字幕的块右侧 `subtitles` 小图标；读取中的段虚线框「读取中」；不一致的段 error 描边。
- 底部 44px 虚线条「继续拖入视频追加为新段；拖入字幕会配给同名、还没挂字幕的段」。

## 右列 · 参数面板

头部 60px「参数」+ text「重置为默认」。内容区滚动，页脚常驻。

- 输出：容器分段控件「MP4 / MOV」；输出位置单选「与第 1 段同目录 / 指定目录」；文件名 text（mono，默认
  `<第 1 段文件名>.merged`），hint「写成 interview_ep12_part1.merged.mp4；同名文件已存在时自动加序号」（开旁挂时补「与 ….srt」）。
- 章节与字幕：三个开关——添加章节（开，note「每段一个章节，起点是前面各段时长之和，标题用左侧的「章节」」）、
  内嵌字幕轨（开，note「各段字幕平移后拼成一条软字幕轨（mov_text）写进视频，播放器里可开关」）、
  旁挂 SRT（关，note「在视频旁另写一份合并后的 <文件名>.srt」）。下面一条说明块：「2 / 3 段挂了字幕；没挂的段不出字幕，
  但时长照算，后面各段的字幕照样平移」；一段都没挂时「还没有段挂字幕，内嵌与旁挂都不会产生字幕」。
- 方式：说明块 icon `content_copy`「不重新编码，原样复制音视频流……各段的视频编码、分辨率、帧率、像素格式与音频编码、
  采样率、声道要与第 1 段一致」。
- 高级（可折叠，折叠摘要「命令预览」）：命令预览块 + 复制按钮，下面小字「list.txt、chapters.txt、merged.srt 在开始时
  写进临时目录，合并完删掉」。示例：
  `ffmpeg -hide_banner -f concat -safe 0 -i list.txt -i chapters.txt -i merged.srt -map 0:V -map 0:a? -map 2:s -map_metadata 1 -map_chapters 1 -c copy -c:s mov_text -f mp4 interview_ep12_part1.merged.mp4`

页脚：左侧状态句 + icon，右侧 filled「开始合并」（icon `merge`）。

| 情形 | 文案 | 色 |
| --- | --- | --- |
| 无段 | 先添加至少 2 段视频 | on-surface-variant，icon `add_circle` |
| 只有 1 段 | 至少要 2 段才能合并 | 同上 |
| 有段在读取 | 第 3 段还在读取参数，读完才能开始 | on-surface-variant |
| 参数不一致 | 第 2 段分辨率与第 1 段不同，不能无转码拼接。换掉它，或先用「转码」转成 1920×1080 | error，icon `error` |
| 就绪 | 将合并成 interview_ep12_part1.merged.mp4 · 3 个章节 · 字幕内嵌 713 条 | on-surface-variant，icon `info` |

除「就绪」外开始按钮都禁用，悬停提示与页脚同句。

## 任务页里的合并任务（MergeTask）

- 任务行：类型列「合并」；文件列 icon `merge`，第一行产物名 `interview_ep12_part1.merged.mp4`，第二行「1:08:32 · 3 段 → MP4」；
  服务 / 模型列 icon `content_copy`，第一行「3 段 · 无转码」，第二行 mono「-c copy · 3 个章节」；阶段条四段「排队 / 准备 / 合并 / 完成」，
  阶段文字「合并 · 38x」；进度 62%；剩余「约 20 秒」；操作 text「取消」。
- done：阶段条全绿「完成」，操作 outlined dense「在访达中显示」（文案随平台，见 `services/reveal.dart`），不给「打开编辑器」。
- failed：左边 error 竖边，阶段条第 2 段 error 40%，「准备失败」，操作「从准备继续」。
- 详情面板（玻璃）：标题产物名，副标题「合并 · 1:08:32 · 3 段 → MP4」，三个标签「无转码 · stream copy」「3 个章节」「字幕内嵌」；
  运行中给进度块（62% · 剩余约 20 秒 · 38x + 取消）；完成给 success 块「已完成 · 用时 47 秒 · 2.1 GB」；失败给 error 块
  「第 2 段的文件找不到了」+ 路径 + 建议 + filled「从准备阶段继续」。
  分区：阶段（四行，准备 note「ffprobe · 3 段参数一致 · 字幕 2 份 713 条」，合并 note「38x · 62%」）/ 章节（起点 + 标题 + 字幕条数）/
  产物（视频一行，完成后右侧 `folder_open`「在访达中显示」；下面一句字幕去向）/ FFmpeg 命令（可复制）。

## 规则

- 只用 `tokens/` 里的令牌；深色主题单独校验 AA。玻璃只在 Rail / 顶栏 / 状态栏 / 详情面板。
- 文案陈述句，不用感叹号、不用 emoji，数字半角；编码、分辨率、时长、时间码、命令用 mono tnum。
- 与 M-TranscodePage 相同的元素保持像素一致；差异只出现在：有序分段列表、章节 / 字幕行、章节起点条、三个开关。
- 不另起风格，不画插画；图标 Material Symbols Rounded 400。
