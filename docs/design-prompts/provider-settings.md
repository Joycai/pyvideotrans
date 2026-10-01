> 历史设计需求：当前由 Codex 按 [仓库设计系统](../design-system.md) 维护。下文的 Claude Design 项目与画板是来源记录，不是开发前提。

# Claude Design prompt · 服务与模型、词表（设置页与建任务页）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> 设计文档与落地规格是开发时的工作文档，不在仓库里；实现与这份 prompt 的出入记在文末「落地时的出入」。
> 产出的设计稿：
> - `P7a Provider Models` https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P7a+Provider+Models.dc.html
> - `P7b Glossary` https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P7b+Glossary.dc.html
> - `P7c Task Glossary` https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P7c+Task+Glossary.dc.html
> - 原型里的新状态：`P8 Prototype` →「设置」屏 https://claude.ai/design/p/a18fe120-0675-45f9-bda3-1eeb471bb364?file=P8+Prototype.dc.html
> - 组件与模块：`C-ModelList` `C-GlossarySection` `C-TaskFields` `C-ProviderSection`（改）`C-Base`（SectionOutline 多一项）`M-SettingsPage` `M-TaskSections`

---

在项目「桌面字幕工具 · 设计系统」里，把设置页「识别服务 / 翻译服务」的模型配置从一串逗号文本改成有结构的模型列表，新增「词表」分区，并把这两样东西带到建任务页。动手前先读 `readme.md`、`C-ProviderSection.dc.html`、`C-SettingsSection.dc.html`、`C-SettingsRow.dc.html`、`C-Base.dc.html`（Field / Chip / Switch / Button / SectionOutline）、`M-Workbench.dc.html` 的 SettingsPage、`M-Pipeline.dc.html` 的四个建任务模块，以及 `P9 Specs` 里设置页的令牌标注。凡与现有设置页、建任务页相同的元素保持像素一致，不另起风格，不加这里没写的功能。

## 要产出的文件

1. `C-ModelList.dc.html` — 模型列表编辑器。props：`theme` `kind=asr|mt` `multiTransport` `models[]` `presets[]` `expanded` `hovered` `addName` `addError` `addHint` `addTransport=sync|async` `addDialect=qwen3|qwenaudio|funasr`。
2. `C-ProviderSection.dc.html` — 加可选 props：`models[]` / `modelList`（有就把「模型」一行换成 C-ModelList）`multiTransport` `presets[]` `expanded` `hovered` `add*` `glossaryNote` `promptCapable` `warnBody`。**不传新 props 时与原来逐像素一致。**
3. `C-GlossarySection.dc.html` — 「词表」分区。props：`theme` `state=normal|blank|error|empty` `stacked` `saved`。
4. `C-Base.dc.html` — SectionOutline 在「翻译服务」后加一项「词表」，icon `dictionary`。
5. `C-TaskFields.dc.html` — part = ModelSelect | GlossaryChips | DiarizeSwitch，建任务页用。
6. `M-SettingsPage.dc.html` — 新版设置页（整页）。在原 props 之外加 `focus=asr|mt|glossary` `asrDefault=sync|filetrans` `asrExpanded` `mtExpanded` `asrAdd=duplicate|space|suggest` `glossary=normal|blank|error|empty`。
7. `M-TaskSections.dc.html` — module = Recognize | Translate，`host=page|dialog`：建任务页「识别」「翻译」两段的新版。
8. `P7a Provider Models.dc.html` `P7b Glossary.dc.html` `P7c Task Glossary.dc.html` — 三个画板，顶部互跳导航条，页尾编号标注。
9. 更新 `P8 Prototype` 的 STATES（设置屏）与组件列表，更新 `readme.md` 的 P / M / C 表。

每个 P 文件渲染体积保持 200k 以下，文件名只用 ASCII。`dc-import` 不接受 `style`，定位时外面套一层 div。

## 设置页 · 模型列表编辑器（C-ModelList）

放在 C-ProviderSection 原「模型」一行的控件列，占满列宽。容器 surface-container-lowest、1px outline-variant、圆角 10。

- **模型行**：最小高 44。行首 24px 箭头（`chevron_right` / `expand_more`）；模型名用 JetBrains Mono（timecode）；名字后面是标签：
  - 声明标签（描边，高 20，label-small）：接入方式「同步逐段 / 异步整文件」+ 模型族「Qwen3-ASR / Qwen-Audio 3.0 / Fun-ASR」。**只有声明了多种接入方式的服务（阿里百炼）显示**，其余服务一个都不出现。
  - 能力 chip（实底 surface-container，高 20，带 14px 图标）：说话人分离 `group`、提示词 `edit_note`、语种受限 `language`。由（接入方式，模型族）查能力表得出，不可编辑。翻译模型没有。
  - 名字与标签放不下时，标签折到名字下一行。
- 第一行行尾常显「默认」标记（secondary-container）。
- 行尾操作（28px 图标按钮，悬停或展开时出现，位置常驻占位）：`vertical_align_top` 设为默认（第一行没有）、`tune` 参数、`close` 删除。
- **展开参数面板**（surface-container-low 底，同一时间只展开一行）按参数目录渲染：Bool → Switch；Number → 88 宽数字框 +「不发送」勾选（勾上后数字框置灰显示 —）；Choice → 分段。第一版只有三项：OpenAI 转写 `temperature`（默认不发送）、Qwen3-ASR 同步的「逆文本规范化」开关（默认开）、翻译 `temperature`（默认 0.3）。目录为空写一句「该模型没有可调参数」。面板末尾一行小字「参数随任务入队时定下，改动只影响之后新建的任务。」
- **添加行**：等宽输入框（占位「模型名，例 qwen3-asr-flash」）+ 百炼时两组分段（接入方式、模型族，按名字预填建议并写一句「已按名字预填「异步整文件 · Fun-ASR」，不对可以改」）+ outlined「添加」。校验错误：输入框 2px error 描边，下方一行 error 色说明（「列表里已经有 qwen3-asr-flash」「模型名不能含空格或逗号」），「添加」禁用。
- **常用行**：「常用」+ 预置模型名做成带 `add` 的小号 outlined 按钮，点一下加入列表；已在列表里的不显示。
- **空列表**：有常用列表的服务写「未添加模型，新建任务时使用常用列表」（中性）；自定义服务写「至少添加一个模型」（error），分区标签保持「未配置」并出横幅。

C-ProviderSection 另外两处：提示字段标签改「识别提示（风格与说明）」「翻译要求（风格与说明）」，说明末尾写「专有名词、人名请用「词表」」；识别分区在默认模型不接受上下文提示时，提示框下一行 info 小字「当前默认模型不接受上下文提示，词表与识别提示不会发送」。

## 设置页 · 「词表」分区（C-GlossarySection）

排在「翻译服务」之后。分区说明：「专有名词、人名、术语。识别与翻译共用，新建任务时勾选要用的几份；已入队的任务用的是入队那一刻的内容。」没有状态标签。

- 左列 220：词表列表。表头「3 份词表」+ `add`；每行名字 + 条数（mono）+ 6px primary 点（默认启用）；选中行 secondary-container。列表下一行图例「● 新建任务时默认启用」。
- 右列：头行 = 词表名（title-small）+ `edit` 重命名 + `delete` 删除 + 右侧「新建任务时默认启用」开关。下面是条目表：两列「原文 / 译文（可空）」+ 36px 操作列，表头 32 高 surface-container-low，数据行 36 高，单元格就是输入框（聚焦 2px primary 内描边），行悬停出现 `close`；表尾常驻新增行（占位「原文」「译文，留空则保留原文写法」+ primary 色 `add`）。表下一行小字：「多行粘贴会按「原文=译文」「原文→译文」「原文<Tab>译文」逐行解析，只有原文也可以。共 7 条。」
- 四种状态：**正常**；**当前词表为空**（表里一行说明「还没有条目。在下面一行输入，或把多行文本直接粘贴进来。」+ 新增行）；**错误**（原文为空 / 重复：该格 2px error 描边 + 行下一行 error 说明）；**没有任何词表**（虚线框 + `dictionary` 图标 +「还没有词表」+ 两段说明识别与翻译各怎么用它 +「新建词表」按钮）。
- 示例数据：「术语 · 产品」7 条（Kubernetes / 缓存穿透→cache penetration / 布隆过滤器→Bloom filter / SenseVoice（无译文）/ 字幕组→fansub group / 向量数据库→vector database / whisper-large-v3（无译文））、「人名」5 条、「第 3 季新词」0 条且未默认启用。

## 窄窗口

`M-SettingsPage winWidth=960`：目录折叠成顶部 Tab（多出「词表」），表单行 stacked。模型列表占满内容列（约 800），一行放得下名字 + 标签 + chip；词表列表变成一行可换行的 filter chip（选中 = 当前词表）+ text 按钮「新建」，条目表占满内容列。

## 建任务页（C-TaskFields + M-TaskSections）

只画变化的两段，页面形态（右侧 400 宽面板，平铺）与对话框形态（720 宽，卡片）各一套；面板其余部分、文件列表、页脚不重画。

- **模型下拉**：每项第一行模型名，名字后的小标签是接入方式短名（仅百炼），第二行小字是能力摘要（「上下文提示 · 切片时间码」「说话人分离 · 句级时间戳」「上下文提示 · 分段时间戳」）。翻译模型没有标签与摘要。只有一种接入方式的服务，菜单末尾隔线多一项「其他模型…」（第二行「手动填写模型名，只用于这次任务」），选中后下拉变成等宽输入框 + 尾部 `close`，错误时 2px error 描边 + 一行说明；百炼不提供，菜单末尾改为一句「要用列表外的模型，在设置里添加」（后半句是链接）。
- **说话人分离开关**：只在当前模型具备能力时出现。关：「区分多位说话人，给每条字幕标上说话人编号」；开：「按说话人切开字幕并标上「说话人1：」；多人会议、访谈适用。时间码取自句级时间戳。」不写模型名。
- **词表 chip 行**（C-Chip kind=filter，多选，chip 上的数字是条数）：转写页 / 对话框放在识别段末尾、状态行之前；翻译页 / 对话框放在「每批条数」与「翻译要求」之间。没有任何词表时换成一句「还没有词表 · 去设置里建一个」。当前模型不接受提示时 chip 行下一行 info 小字「当前模型不接受上下文提示，识别时不会发送词表与识别提示；接着翻译时仍会用词表。」
- 文案：高级段「识别提示词（可选）」占位改「风格与说明；专有名词请用词表」；翻译段「术语表与风格（可选）」改名「翻译要求（可选）」，说明「风格与说明；专有名词请用词表。仅用于本次任务。」

## 画板

- **P7a**：880 宽内容列里的分区，7 块——百炼常态（第二行悬停）/ 展开参数 + 重名错误 / 按名字预填 + 默认模型不接受提示 + 无参数模型 / OpenAI 单接入方式（temperature 不发送、含空格错误）/ 自定义服务空列表（未配置）/ 深色 · 翻译服务 DeepSeek（推理模型勾了不发送）/ 960 stacked。另附能力表与参数目录两张小表。标注 10 条：校验规则、默认标记、接入方式与模型族标签的显隐、能力 chip 与能力表的对应、参数面板、添加行与预填、常用、空列表、提示字段、响应式。
- **P7b**：6 块——正常 / 错误 / 深色 / 空词表 / 空态 / 960 stacked，加一整页 `M-SettingsPage win-width=960 focus=glossary`，再附粘贴解析规则表。标注 10 条：词表列表、条目表、粘贴解析、校验、默认启用、重命名与删除、与任务的关系（入队冻结）、恢复默认（词表不受影响）、空态、960 窄窗。
- **P7c**：9 块——转写页百炼下拉展开 / 能分离的模型开关开态 + 不接受提示说明 + 高级 / 深色开关关态 / OpenAI 下拉含「其他模型…」/ 输入框校验错误 / 翻译页 / 翻译页无词表 / 转写对话框 / 翻译对话框下拉展开。标注 10 条：下拉项规则、列表外的模型、输入校验、说话人分离、chip 行、冻结时机、模型不接受提示、没有词表、文案收窄、响应式与任务列表。

## 规则

- 只用 `tokens/` 里的令牌；深色主题单独核对对比度。玻璃只在 Rail / 顶栏 / 状态栏 / 对话框。
- 文案陈述句，不用感叹号、不用 emoji，数字半角；模型名、地址、数值用 mono。
- 错误一律「2px error 描边 + 一行可行动的说明」，不弹窗。
- 接入方式、模型族是用户的声明（描边标签）；能力是由声明查表得出的（实底 chip）。两者视觉上分开，能力不可编辑。
- 组件复用 C-SettingsSection、C-SettingsRow、C-Base 的 Button / Chip / Field / Switch；新组件不复制它们的样式。

## 这一轮没做的

- `M-Pipeline` 的四个建任务模块没有改写（文件 148k，设计工具只能整份写入）。「识别」「翻译」两段的新版以 `M-TaskSections` 与 P7c 为准；P8 原型的「转写」「翻译」两屏仍是旧的两段。
- `M-Workbench` 里的旧 SettingsPage 部件留着没删，新版是独立的 `M-SettingsPage`。
- 重置对话框（文案加一句「词表不受影响。」）与任务列表「服务 / 模型」列（第二行显示任务冻结的模型名）只写了规格，没有画。

## 落地时的出入

实现与设计稿不一致的地方，改设计稿时以这里为准：

- **模型列表编辑的是用户自己配的那份。** 没配过时列表是空的（「未添加模型，新建任务时使用常用列表」），常用模型都在「常用」一行。
  列表空着时加第一个模型，常用模型会一起落进列表，默认模型不变 —— 只存新加的那个会把默认模型换掉。
- **百炼的添加行固定排成两行**：名字 + 接入方式一行，模型族 + 「添加」一行。两组分段加按钮比控件列宽。
- 「模型」行的说明里厂商名取登记表的 vendor，百炼显示为「阿里百炼的模型要标明接入方式与模型族」。
- 识别分区的说明改成「地址与密钥改动后，下一个开始的任务就用新的；模型与参数在新建任务时定下」，与参数面板的脚注一致。
- **条目表的表体最多显示 12 行**，再多在表里滚；表头与新增行不跟着滚。几百条的词表不该每敲一个字重建几百个输入框。
- 多行粘贴时已经在表里的原文跳过，不追加成标红的重复行。
- 表下多一句「识别用的词不宜过多：有的模型只读提示词末尾的一小段，排在前面的会被忽略。」
- 删除词表的确认框按现有对话框的惯例，「删除」是左下角的红字，右边只有「取消」。
- 行尾操作用的是现成的圆形图标按钮，不是圆角 8 的方形热区。
- 建任务页手填「其他模型…」是输入框自己的界面状态：页面切走再回来后，手填的那个模型排在下拉最前，不再是输入框。
  名字空着或写坏了时，页脚显示的是就绪检查那句「未选择模型」，不是校验那句；校验的原因写在输入框下面。
- 模型下拉的菜单宽度沿用现有下拉（344），没有另做「输入框更宽时跟输入框等宽」。
- 建任务页里的「去设置」「在设置里添加」落到设置页对应的分区（识别服务 / 翻译服务 / 词表），不是页面顶部。
- 「当前模型不接受上下文提示…」这句在没有词表时也显示：它同时在说识别提示不会发送。
