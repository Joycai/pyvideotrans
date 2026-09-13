# Claude Design prompt · 编辑器（M-EditorOpen + M-EditorFrame 扩展）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> 配套设计稿：Artifact「编辑器设计稿」 https://claude.ai/code/artifact/2742cd67-7622-445d-8825-fca3f18ce46d

---

在项目「桌面字幕工具 · 设计系统」里补全「编辑器」：没有打开任何会话时显示的入口页、挂载本地原文 SRT 和译文 SRT、说话人名单与逐条修改。现有 `M-EditorFrame` 是「任务会话、没有说话人」的样子，保持像素不变，只通过新增 props 加内容。动手前先读 `readme.md`、`M-EditorFrame.dc.html`、`M-TranslatePage.dc.html`（空态落区、面板头、页脚的做法照它来）。

## 要产出的文件

1. `M-EditorOpen.dc.html` — 新模块，编辑器入口页。props：`theme` `variant=A|B|C`（A 空 / B 已放入两份文件 / C 时间轴对不上）`dragging=none|source|translation`。
2. `M-EditorFrame.dc.html` — 扩展，不复制。新增 props：`source=task|files`（默认 task）`speakers`（bool，默认 false）`singleFile`（bool）`dirty`（0–9）`overlay=none|sources|speakerManager|speakerMenu|speakerFilter|unsaved`。所有新 props 取默认值时，渲染结果必须与现在完全一致。
3. `C-SpeakerBadge.dc.html` — props：`name` `index` `unnamed` `size=20|28`。
4. `C-SpeakerManager.dc.html` — 说话人名单 Dialog。props：`theme` `editingIndex` `menuIndex` `exportLabels=none|name`。
5. `P4b Editor Open.dc.html` — 入口页浅色 A / B / C 三屏，顶部加互跳导航条。
6. `P4c Editor Local Light.dc.html` — 本地会话浅色：常态（speakers）、只有原文（singleFile）、overlay=sources。
7. `P4d Editor Local Dark.dc.html` — 深色：常态、overlay=speakerManager。
8. `P4e Editor Speakers.dc.html` — 交互标注：speakerMenu、speakerFilter、unsaved 三个浮层的特写，加编号标注。
9. 更新 `readme.md` 的 P 表、M 表、C 表；`P4 Editor.dc.html` 顶部导航条追加上面四个链接。

每个 P 文件的渲染体积保持在 200k 以下，文件名只用 ASCII。

## 页面框架

1440×900，与 `M-EditorFrame` 相同：grid 列 `72px | 1fr`，行 `52px | 1fr | 32px`，gap 12，padding 12。Rail `active="editor"`。

## M-EditorOpen · 入口页

顶栏 title「编辑器」，meta「打开一份字幕开始校对」，右侧无按钮。内容区 grid `1fr | 400px`。

**左栏「本地字幕」**（面板头 60px：「本地字幕」+ body-small「SRT · VTT，可以只打开原文」；B 态右侧 text 按钮「清空」）

- 两个位置，grid `1fr | 36px | 1fr`，高 232。
  - 空位置：虚线落区（1.5px dashed outline，radius 14）。原文位置：icon `subtitles` 40px、「拖入原文字幕」title-medium、「识别出来或听写的那一份，必须有」、按钮「选择文件…」。译文位置：icon `translate`、「拖入译文字幕」、「可选；不挂也能在编辑器里翻译」。
  - 中间是 36px 圆形 icon 按钮 `swap_horiz`，只有原文时禁用（38%）。
  - 放入文件后：白底卡片，第一行 label「原文 / 译文」加右侧 `close`；文件行（icon + 文件名 + 目录）；「486 条」「00:00:01 – 00:48:12」（timecode）；语言 select「中文 · 自动识别」。
  - 拖入态：对应位置 primary 6% 底，描边改为 primary 实线加 1px inset ring，文字变为「松开以放入原文」。
- 配对块（margin 0 20，radius 12）：空态时为 surface-container-low 底，icon `link` 加一句「两份都添加后，会在这里检查能不能逐条对上」。B 态改为 1px outline-variant 描边：标题「配对」，右侧小号分段控件「按时间轴 / 按序号」；三列数字（timecode 20px）：`480` 条逐条对上 / `6` 条原文没有译文，显示为「未翻译」/ `2` 条译文找不到原文，单独成行，标「未配对」；下方 body-small「两份条数不同，按序号配对会从第 214 条开始错位」。
- 说话人标签行（只在检测到行首标签时显示）：Switch 开 +「读取行首的说话人标签」+ note「原文里有 3 种标签：「Mia：」「周老师：」「说话人3：」。打开后标签会从文本中去掉，变成说话人名单，可以改名。」
- 「最近打开」：3 行，每行 52px：icon、文件名（两份时写「a.zh.srt + a.en.srt」）加目录、tag「本地 / 任务」、「488 条 · 3 位说话人」、时间。
- 页脚：A 态「先添加原文字幕」（icon `add_circle`）加禁用按钮「打开编辑器」；B 态「将打开 488 条；⌘S 保存会写回这 2 个文件」加 filled 按钮 icon `edit_note`「打开编辑器」。
- C 态：配对块换成 error-container 横幅「时间轴基本对不上，可能不是同一个视频的字幕」，三个数字为 `41 / 445 / 437`；「打开编辑器」禁用，直到切换到「按序号」。

**右栏「从任务打开」**（面板头：「从任务打开」加 timecode 计数 6）

6 行，每行 64px：icon `mic` 或 `translate`、文件名、副标题「486 条 · 中文 → 英语 · 3 位说话人」、右侧时间。悬停行加 on-surface 6% 底，时间换成小号 outlined 按钮「打开」。页脚：「只列出已完成、带字幕的任务」加 text 按钮「去任务页 →」。

## M-EditorFrame · 新增内容

**顶栏**

- meta 之后加一个 28px 的来源 chip：`source=files` 时为 icon `description`「本地 · 2 个文件」加 `expand_more`（singleFile 时为「1 个文件」）；`source=task` 时为 icon `check`「已自动保存」，body-small，on-surface-variant，不做成 chip。
- `source=files` 时，在「翻译未译」和「导出」之间加 outlined 按钮「保存」。`dirty>0` 时文字左侧有 6px primary 圆点，`dirty=0` 时按钮禁用。状态栏右侧文字「未保存 3 处修改」。

**表格（speakers=true）**

- 列 grid 改为 `52px 124px 104px 1fr 1fr 72px`：# / 开始 / 说话人 / 原文 / 译文 / 状态。去掉「结束」列，因为同时放说话人列会把两列文本挤到 150px 以下；结束时间在检视面板里能看到。表头「说话人」右侧有 16px `edit` 图标，点击打开名单。
- 说话人格：C-SpeakerBadge 20px 加名字（超出省略）。同一个人连续的几条只在第一条显示，后续行在徽标中线位置画一条 1px outline-variant 竖线，上下贯通。
- 工具栏：搜索框收窄到 188px；筛选 chip 在「未翻译」之后加「未配对 2」（数量为 0 时不显示）；右侧（原来放快捷键提示的位置）改为下拉 chip：icon `record_voice_over`「说话人 · 全部」加 `expand_more`。快捷键提示移到表格页脚左侧：「显示 001–014 / 488 · J/K 上下条 · Enter 校对 · ⌘S 保存」。
- 示例数据使用 14 行，说话人依次为 Mia、Mia、周老师、周老师、说话人3（待校对，徽标为虚线框，名字灰色）、周老师、Mia（选中）、周老师（待校对）、周老师（未翻译）、周老师、Mia、周老师、未配对行、Mia。未配对行：原文位置写灰色「— 没有对应的原文」，译文「Right, in batches.」，状态 tag 为 1px dashed outline 的「未配对」。页脚右侧「已校对 468 · 待校对 12 · 未翻译 6 · 未配对 2」。

**检视面板**

- 本地会话预览高度降到 150，左上角文字改为「未关联视频 · 只预览字幕样式」；去掉播放按钮和波形，只留上一条 / 下一条按钮与时间码。
- 在「开始 / 结束」与「原文」之间加「说话人」字段：label 右侧 primary 色 body-small 链接，icon `group`「管理说话人」；select 内容为徽标、名字、body-small「142 条」、`expand_more`。
- 原文、译文 label 右侧显示来源文件名（body-small，on-surface-variant）；译文仍保留「重新翻译此条」。
- singleFile：表格保留「结束」列（此时没有说话人），译文表头加 primary 链接「+ 挂载译文…」；检视面板的译文框为虚线空态「这份字幕还没有译文」，下面两个按钮：outlined 小号「翻译此条…」、text「挂载译文文件」。
- 选中未配对行时，原文框换成两个 text 按钮：「并入上一条」「并入下一条」。

**浮层**（玻璃 glass-strong + shadow-3；菜单 radius 12，Dialog radius 20）

- `sources`：锚在来源 chip 下方，宽 400。两段（原文 · 中文 / 译文 · 英语），每段有文件行、「目录 · 486 条」、text 按钮「替换…」；译文段多一个 error 色「卸载」。分隔线下为：`link`「按时间轴配对 · 480 条，2 条未配对」加右侧链接「重新配对…」；`folder_open`「打开其他字幕…」；最后一行 body-small「⌘S 会覆盖上面 2 个文件。想保留原文件，请用「导出」。」
- `speakerManager`（C-SpeakerManager）：宽 560。标题「说话人」，副标题「共 3 位。名字只影响显示和导出时的标签，不会改动字幕文本。」。每行 grid `28px 1fr 128px 72px`：28px 徽标 / 名字输入框（右侧 body-small「原为 说话人1」，未命名时为「未命名」）/ timecode「142 条 · 18:32」/ icon 按钮 `filter_alt` 和 `more_vert`。第二行处于编辑态（2px primary 描边，带光标）。第三行「说话人3 · 12 条 · 00:09」下方有灰色说明「只有 12 条，平均每条 0.8 秒，多半是识别服务把应答声单独分成了一个人。可以把这一位合并到其他人。」，它的 `more_vert` 打开菜单「把「说话人3」的 12 条合并到」→ Mia / 周老师 / 分隔线 / 在列表里只看这位。页脚：左侧 text 按钮 `person_add`「新增说话人」；右侧 label「导出标签」、小号分段控件「不写 / 写名字」、filled 按钮「完成」。
- `speakerMenu`：锚在检视面板的说话人字段下方，与字段同宽。顶部一行「应用范围」加小号分段控件「这一条 / 连续 3 条 · 008–010」；分隔线；每位说话人一项（徽标、名字、右侧 timecode 条数，当前项带 primary `check`）；分隔线；`person_add`「新增说话人…」、`person_off`「清除这一条的说话人」。
- `speakerFilter`：锚在工具栏的说话人 chip 下方，宽 268，多选：全部（已勾选）/ Mia 142 / 周老师 334 / 说话人3 12；分隔线；`group`「管理说话人…」。
- `unsaved`：Dialog 宽 420。标题「保存修改？」，正文「interview_ep12 有 3 处修改还没保存。保存会写回 interview_ep12.zh.srt 和 interview_ep12.en.srt。」，下方 surface-container 说明条「「已校对」标记和说话人名单不会写进 SRT，而是另存在应用数据里；下次打开这两个文件时会恢复。」。按钮：左侧 error 色 text「不保存」，右侧「取消」和 filled「保存并打开」。

## C-SpeakerBadge

中性方形徽标，不加任何色相。20px 时 radius 6，28px 时 radius 8；底色 surface-container-high，文字 on-surface，label 字重 600，内容为名字首字（「Mia」取 M，「周老师」取 周）。`unnamed` 时底色透明，1px dashed outline，文字为编号，颜色 on-surface-variant。深色主题下检查徽标与 secondary-container（选中行）、tertiary-container 45%（待校对行）叠在一起时是否可读。

## 标注（P4e）

编号标注指向：来源 chip、保存按钮的脏标记圆点、说话人筛选、连续说话人竖线、未配对行、说话人字段与应用范围、名单里的合并菜单、1–9 快捷键。另附一张配对规则小表：条数相同且时间差 ≤200ms → 按序号；否则按时间轴，重叠 ≥ 较短一条的 50% 才算配上；一条原文对多条译文 → 译文合并；配上的不到 30% → 禁止自动配对。

## 响应式与键盘

- 窗口窄于 1100：检视面板 380px；说话人列只显示徽标（44px）；原文 / 译文 / 双语的分段控件收进「视图」下拉。
- ⌘S 保存；J/K 上下条；Enter 标记已校对；1–9 把当前条改给第 N 位说话人，⇧+数字按连续范围改（输入框有焦点时不响应）；⌘Z 撤销，改名与合并都能撤销。
- 拖文件到正在编辑的页面：内容区覆盖 primary 6% 底色，上面左右两块落区「替换原文」「挂载为译文」。

## 规则

- 只用 `tokens/` 里的令牌。字幕黄只用于「当前播放字幕」和「待校对」；说话人不引入任何新色相。
- 文案用陈述句，不用感叹号、不用 emoji，数字半角，时间码用 mono tnum。
- 组件复用：C-NavRail、C-TopBar、C-StatusBar、C-Field、C-Chip、C-Button、C-Switch、C-FileRow（入口页的文件行与最近打开行都用它，不要复制一份）。
- `M-EditorFrame` 所有新 props 取默认值时，与现在的 P4 画板逐像素一致。

## 补充决定（2026-09-13，覆盖上文冲突之处）

1. **说话人用低饱和颜色区分。** 上文「C-SpeakerBadge 中性、不加色相」与「说话人不引入任何新色相」两条作废。在 `tokens/colors.css` 新增一组说话人分类色 `--speaker-1` … `--speaker-8`（浅色、深色各一套）：低饱和、明度接近，避开 primary 蓝和字幕黄的色相，徽标上的文字对比度达到 AA。颜色只用在徽标底色，以及说话人列、说话人字段、名单里的徽标上，不用于行底色、描边或文字。编号超过 8 时循环使用。未命名的说话人仍然是虚线框，不填颜色。深色主题下单独校验这组颜色叠在选中行（secondary-container）和待校对行（tertiary-container 45%）上时是否可读。在 P0a Tokens 里补一行色板。
2. **本地会话翻译直接用设置里的翻译服务。** 不弹选择服务的浮层。目标语言默认取译文文件猜出的语言，没有译文时取设置里的目标语言。
