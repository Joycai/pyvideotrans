# Claude Design prompt · 翻译页（M-TranslatePage）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> 配套设计稿：Artifact「翻译页设计稿」 https://claude.ai/code/artifact/cede480c-06e1-4956-9a97-7ecd93716b11

---

在项目「桌面字幕工具 · 设计系统」里新增「翻译」常驻页面。它是导航栏第三项「翻译」点开后的工作台，与现有 `M-TranscribePage` 同构：左列字幕文件面板（自适应），右列参数面板 400px；Rail、顶栏、状态栏全部复用 C 组件。动手前先读 `readme.md`、`M-TranscribePage.dc.html`、`M-TranslateDialog.dc.html`，页面上凡与转写页相同的元素保持像素一致。

## 要产出的文件

1. `M-TranslatePage.dc.html` — 模块。props：`theme` `variant=A|B|C|D` `dragging` `rejectedMedia`（0–9，被忽略的音视频文件数）。
2. `P3e Translate Page Light.dc.html` — 浅色四态并排（A 空态 / B 常态 / C 阻断态 / D 提交后），顶部互跳导航条把 P3a–P3g 串起来。
3. `P3f Translate Page Dark.dc.html` — 深色四态。
4. `P3g Translate Page Drag.dc.html` — 拖放态 + 交互标注。编号标注指向：语言对换按钮、条数列与调用次数估算、忽略音视频提示条、排版预览、页脚文案规则、960 / 1100 两档响应式。
5. 更新 `readme.md` 的 P 表与 M 表；已有 P2 / P3 页面顶部的导航条追加这三个链接。

每个 P 文件渲染体积保持 200k 以下，文件名只用 ASCII。

## 页面框架

1440×900，grid 列 `72px | 1fr`，行 `52px | 1fr | 32px`，gap 12，padding 12，底层 `--wallpaper`。Rail `active="translate"`。

顶栏 title「翻译」；meta 空态「把字幕文件翻译成目标语言」，有文件时「3 个文件 · 共 1,596 条 · 自动检测 → 英语 · 将创建 3 个翻译任务」。顶栏右侧一个 outlined 按钮「上次参数」（icon `history`）。

## 左列 · 文件面板

- 头部 60px：「文件」+ timecode 计数；有文件时右侧「清空」（text）与「添加文件…」（outlined，icon `add`）。
- 空态：虚线落区 —— icon `subtitles` 40px、「把字幕文件拖到这里」（title-medium）、「SRT · VTT · ASS · SSA，可一次选多个；音视频请用「新建转写」」（body-medium，on-surface-variant）、「选择文件…」按钮。下方三步：1 添加字幕文件 / 2 确认语言与服务 / 3 加入队列，进度在任务页；当前步的点是 primary。
- 有文件：表格 grid `36px | 1fr | 80px | 88px | 80px | 96px | 36px`，列头「文件 / 条数 / 时长 / 大小 / 状态」。行复用 C-FileRow 的结构（icon `subtitles`，第一行文件名，第二行目录），比转写页多一列「条数」（timecode，右对齐，千分位）。状态 chip：就绪（success-container）/ 解析中（surface-container，icon `progress_activity`）/ 无法解析（error-container，副标题 error 色「解析不出字幕内容，将跳过」）。悬停行 on-surface 6% 底，右侧 `close` 出现。
- 表格上方（有忽略时）36px 中性提示条：icon `block`「已忽略 1 个音视频文件，音视频请用「新建转写」」+ 右侧链接「改用新建转写」（点击把这些文件带到转写页）。用 surface-container 中性色，不用 error。
- 表格下方一句说明：「参数统一应用到每个文件；共 1,596 条，每批 20 条，约 80 次调用；单个失败不影响其余」。条数与调用次数随文件和每批条数联动。
- 底部 44px 虚线条「继续拖入可追加文件」。
- 拖入态：面板底 primary 6%，描边 primary + 1px inset ring，落区文字变「松开以添加文件」，200ms standard easing。

## 右列 · 参数面板

头部 60px「参数」+ 右侧 text 按钮「重置为默认」。内容区可滚动，页脚常驻。

分区一「翻译」（title-small，on-surface-variant）：

- 语言对一行：grid `1fr | 36px | 1fr`。原文语言 select「自动检测」/ 中间 36px 圆形 icon 按钮 `swap_horiz`（原文为自动检测时禁用 38%，tooltip「原文为自动检测时不能对换」）/ 目标语言 select「英语」。
- 翻译服务 select「DeepSeek」/ 模型 select「deepseek-chat」两列。
- 每批条数 number「20」，hint「一次送给模型的字幕条数。调大省 token，但更容易漏条或合并。范围 1–100。」
- 术语表与风格（可选）textarea 68px，示例值两行「Ballistic Missile Defense=反导系统」「保持口语，不要书面化」，hint「术语一行一条，写成「原文=译文」；其余行当作风格要求。仅用于本次任务。」
- 状态行：`check_circle`「已配置密钥，可直接开始」；本机服务「无需密钥，可直接开始」；阻断时 error 色 `error`「DeepSeek 未配置密钥，去设置里填入后可开始」+ 链接「去设置」，同时翻译服务框 2px error 描边。

分区二「高级」（可折叠；折叠时标题右侧显示摘要「仅译文 · 15 / 40 字 · SRT · 与源文件同目录」）：

- 输出格式 分段控件 SRT / VTT / TXT / ASS（ASS 禁用 38%，hint「ASS 需要一整套字幕样式配置，第二期提供。」）。
- 字幕排版 分段控件 仅译文 / 双语 · 译文在上 / 双语 · 译文在下。下方预览块（surface-container，mono）：序号「12」、时间码「00:01:23,450 --> 00:01:26,100」、两行文字按所选顺序（"We'll start from chapter two" / "我们从第二章开始"）。hint「双语指同一条字幕里两行文字，不是两个文件。」选 TXT 时分段禁用并提示「纯文本不保留双语排版，已回落到「仅译文」」。
- 每行最大字符数 · 中日韩「15」/ 其他语言「40」两列 number。
- 输出位置 单选：与源文件同目录 / 指定目录（选中时右侧 mono 路径 `/Users/mia/Movies/字幕/`）。说明「译文写成 `interview_ep12.en.zh.srt`，不覆盖原文件」；双语时语言段写成 `en-zh`，原文为自动检测时写成 `src`。

页脚 padding 12/16，上描边：左侧 body-small 状态句 + icon；右侧 filled 按钮 icon `translate`「开始翻译 · 3」，数字 timecode。页脚文案规则：

| 情形 | 文案 | 色 |
| --- | --- | --- |
| 无文件 | 先添加字幕文件 | on-surface-variant，icon `add_circle` |
| 全部无法解析 | 选中的文件都解析不出字幕内容，换几个文件再试 | on-surface-variant，icon `info` |
| 阻断 | DeepSeek 未配置密钥，去设置里填入后可开始 | error，icon `error` |
| 正常 | 将创建 3 个翻译任务，按列表顺序排队；1 个文件仍在解析，可先开始 | on-surface-variant，icon `info` |
| 有跳过 | …；1 个文件无法解析，将跳过 | 同上 |

## 四个状态

- **A 空态**：无文件，参数可编辑，开始按钮禁用（透明底、on-surface 12% 描边、38% 文字）。
- **B 常态**：3 个字幕文件 —— `interview_ep12.en.srt` 1,284 条 48:12 24.0 KB 就绪 / `product_demo_en.vtt` 312 条 06:40 7.0 KB 就绪（悬停行）/ `lecture_week3.ass` 解析中；忽略 1 个音视频；高级折叠。
- **C 阻断态**：DeepSeek 未配置密钥；原文语言「英语」目标「中文」；2 个文件，其中 `notes_raw.txt` 无法解析；高级展开且排版选「双语 · 译文在上」（面板内滚动，页脚常驻）。
- **D 提交后**：列表清空回空态，文件面板顶部 success 横幅「已加入队列 3 个任务，按列表顺序排队 · 查看任务」，6 秒自动收起，参数原样保留，三步指示到第 3 步。

## 响应式与键盘

- 窗口窄于 1100：参数列 360；窄于 960：上下堆叠，文件面板在上。
- Enter 开始（多行框内是换行）、⌘/Ctrl+Enter 强制开始、Esc 只清焦点不清空页面。

## 规则

- 只用 `tokens/` 里的令牌；深色主题单独校验 AA 对比度。玻璃只在 Rail / 顶栏 / 状态栏。
- 文案陈述句，不用感叹号、不用 emoji，数字半角，时间码 mono tnum。
- 与 M-TranscribePage 相同的元素（面板头高、页脚、按钮、步骤条、横幅）保持像素一致；差异只出现在：语言对换、条数列、忽略音视频提示条、排版预览、调用次数估算。
- 组件复用：C-NavRail、C-TopBar、C-StatusBar、C-Field、C-FileRow。「条数」列给 C-FileRow 加可选 prop `cues`（为空时该列不渲染），不要复制一份组件。
