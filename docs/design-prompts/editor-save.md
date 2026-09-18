# Claude Design prompt · 编辑器保存模型（M-EditorFrame 扩展）

> 在 Claude Design 项目「桌面字幕工具 · 设计系统」（`a18fe120-0675-45f9-bda3-1eeb471bb364`）里使用。
> 配套设计稿：Artifact「编辑器保存模型」 https://claude.ai/artifact/1Uh73p4E1vFDXj3HDUZ2JY
> 前置阅读：`editor-page.md`（`M-EditorFrame` 现有 props 与 `overlay=unsaved`）。

---

## 要解决的问题

1. **任务会话**：顶栏写「已自动保存」，实际只写进应用数据里的任务 JSON（`TaskQueue.persist`）；
   完成阶段写出的 `.zh.srt / .en.srt` 不会更新。没有保存按钮，⌘S 静默无效
   （`EditorPageState.save` 对 `TaskSession` 直接 return），只有「导出」碰巧写到同一路径。
2. **本地会话**：修改只在内存。`AppLifecycleListener.onExitRequested` 只 flush 任务队列，
   退出应用不询问，崩溃直接丢。检视面板 `onChanged` 每敲一个字就 commit 一次，
   「未保存 N 处修改」按字数涨，撤销也按字退。
3. **共有**：写文件前不检查外部修改；失败 / 暂停的任务在编辑器里改过后，从识别或断句阶段「继续」
   会重建 `task.document`，把修改盖掉且不提示。

## 设计原则

**进度自动存，文件手动写。** 两种会话同一套规则：

- 编辑进度：每次改动 300ms 内写进应用数据（任务 JSON / 本地会话新增草稿），永不丢。
- 字幕文件：只有 ⌘S / 「保存」写。任务会话写产物（与完成阶段同名同路径），本地会话写挂载的文件。
- 「导出…」是另存到别处，不改变同步状态。

## M-EditorFrame · 新增 / 修改

新增 prop `sync=synced|dirty|writing|written|failed|conflict|noOutput`（默认 `synced`），
`overlay` 追加 `syncPopover|leave|conflict|resumeWarn`，`banner=none|recovered`。

- **顶栏来源 chip**：任务会话不再是一句「已自动保存」，改为与本地会话同形的 30px chip，
  文案随 `sync`（见画板 1 的表）。本地会话 chip 保留「本地 · N 个文件」，dirty 时后接 6px primary 点
  +「N 处未写入」。
- **保存按钮**：两种会话都显示，位置在「翻译未译」与「导出…」之间；dirty 时带 6px primary 点，
  synced 时禁用不隐藏。`noOutput` 时文案「生成文件」。「导出」改名「导出…」。
- **状态栏右侧**：「字幕文件落后 N 处修改 · ⌘S 写入」；写入成功 2 秒内显示写了哪些文件，替代 SnackBar。
- **表格**：本次会话改过的行在 # 前加 6px primary 点；筛选 chip 追加「本次修改 N」。
- **syncPopover**（锚在 chip 下，宽 420，radius 12）：两段——「编辑进度 · 自动保存 · 刚刚」
  （success 容器图标）与「字幕文件 · N 处修改未写入」（primary 容器图标，列出每个文件与上次写入时间、目录）。
  底部：text「在访达中显示」、outlined「撤销到上次写入」、filled「写入文件 ⌘S」。
- **banner=recovered**（本地会话，顶栏下方，primary-container 横幅）：「上次关闭时有 N 处修改没写回 X，已接着显示」
  + 草稿时间；按钮「丢弃，按文件重新打开」「写入文件」+ 关闭。
- **leave**（替换现有 `unsaved`）：标题「先写入字幕文件？」，说明条「不写入也不会丢……」；
  左侧中性色 text「稍后再写」（不再是 error 色「不保存」），右侧「取消」+ filled「写入并打开 / 写入并退出」。
  退出应用时也弹。
- **conflict**：「X 在别处被改过」；左侧 error text「覆盖」，右侧「取消」+ filled「另存为…」（默认焦点）。
- **resumeWarn**（任务页，续跑阶段为识别 / 断句且编辑器改过时）：「继续会覆盖编辑器里的修改」；
  error text「仍然继续」、「取消」、filled「去编辑器」。

## 实现备注（给 Flutter 侧）

已合入（#36），与上面的设计有几处取舍：

- 同步基线没用 `syncedRevision`，改成计数：任务 JSON 记 `unsyncedEdits`（未写入数）、`editorEdits`
  （累计编辑数，续跑提醒用）、`outputs`（每个产物写完后的大小 + 修改时间）、`outputsWrittenAt`。
  代价：重开一个有未写入修改的任务时不知道上次写的是哪一版，「撤销到上次写入」不可用，
  「本次修改」只算这次打开之后的。
- 本地会话在 `EditorStore` 同一份附加状态里存「上次写入的版本」+ 草稿 + 未写入数。
  文件在外部被改过时附加状态作废，但有草稿的保留，打开后横幅说明、保存时走冲突询问。
- 连续编辑按「同一条 + 同一字段 + 距上一次 < 1 秒」合并。
- 「另存为」不许写回原目录、不许覆盖同名文件；本地会话写成后挂到新文件并更新「最近打开」，
  任务会话只另存副本。「导出…」挑目录，落到字幕文件本身时拒绝并提示用「保存」。
- 退出应用走 `AppLifecycleListener.onExitRequested` → `confirmLeaveEditor(intent: exit)`。
- 原文、译文成组写：全部写成临时文件后才改名，任何一份失败都不留下半套（保存、另存为、导出同理）。
- 任务排队或运行中时编辑器只读：顶部中性色横幅「任务正在翻译，编辑器暂时只读」，检视面板变灰不可点，
  保存、翻译未译、说话人管理禁用；内容跟着流水线实时刷新，跑完自动解锁（画板里没有这一态，按恢复横幅同形实现）。
