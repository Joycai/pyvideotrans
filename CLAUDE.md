# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 仓库形态

- **实际代码只有 `app/`** —— Flutter 桌面客户端（macOS / Windows / Linux），pub 包名 `subtitle_studio`。
  几乎所有改动都在这里，命令也都在 `app/` 下跑。
- `archive/python/` 是原 pyVideoTrans 的 Python 实现，**只作功能参考，不参与构建**。
  想知道"原来怎么做的、有哪些参数、踩过哪些坑"，先看 `docs/archive-codemap.md` 的索引再进去找，
  别直接 grep 那 5.6 万行。
- **主分支是 `Joycai-main`**，功能分支从它切出、PR 合回它。仓库里的 `main` 是 fork 时的上游快照，
  不开发、不合并、不比对。

## 常用命令

```bash
cd app
flutter run -d macos                                        # 或 -d windows / -d linux
flutter analyze
flutter test                                                # 单元与集成测试
flutter test test/pipeline_test.dart                        # 跑单个文件
flutter test test/pipeline_test.dart --plain-name '续跑'      # 按名字筛用例（子串匹配）
flutter test --tags golden --run-skipped                    # 界面截图核对
flutter test --tags golden --run-skipped --update-goldens   # 重新生成截图
DASHSCOPE_API_KEY=sk-… flutter test --tags live --run-skipped  # 真实调百炼的联调用例
```

两类测试默认跳过（见 `app/dart_test.yaml`）：`golden` 依赖宿主机系统字体，换机器像素就不一样；
`live` 要真实密钥。`test/transcode_ffmpeg_test.dart` 在没装 ffmpeg 的机器上自动跳过，
VideoToolbox 用例只在 macOS 跑。

打包（dmg / Inno Setup / Linux 安装脚本）与应用图标生成见 `app/packaging/README.md`。
**改版本号用 `bump-versions` skill**，它会一次改齐 pubspec 之外所有硬编码的副本。

## 架构

```
app/lib/
  main.dart          唯一装配点
  core/theme/        设计令牌 → ThemeData / ThemeExtension
  core/widgets/      无业务语义控件（fields.dart 是公共入口）
  domain/            纯数据与纯规则；转码子域在 domain/transcode/
  services/          网络、外部进程、设置与持久化
  pipeline/          队列、任务编排、阶段壳、字幕写出、转码执行
  features/shared/   跨 feature 共用组件
  features/          shell / tasks / transcode / editor / settings
```

`app/README.md` 有每条设计决定的完整理由，改到相关代码前先读那一节。
依赖边界：`domain` 不依赖 Flutter 或上层；feature 之间不互相 import 实现，公共件进
`features/shared/`；页面文件只做生命周期与装配，大块界面拆到同目录 panel / section / list。
相对 import 依赖图必须保持无环。
文件级的源码结构索引（每个文件干什么、按功能反查、测试对照）在 `docs/app-codemap.md`。
下面是跨多个文件、
**只看单个文件看不出来**的约束：

### 服务抽象：本地不是一条单独的代码路径

`Registry`（`services/registry.dart`）登记所有可选服务。Ollama、LM Studio 和第二期的本地
Python 后端都说 OpenAI 兼容协议，于是共用 `OpenAiCompatibleAsrProvider` /
`OpenAiCompatibleTranslationProvider`，**区别只在 baseUrl、要不要密钥、界面上一个图标**。
加在线服务通常只是往登记表加一条 `ProviderInfo`。
例外是阿里百炼 Qwen3-ASR：接口不是 OpenAI 形态，单独实现在 `dashscope_asr.dart`
（切片后逐段识别）与 `dashscope_filetrans.dart`（异步整文件转写）。

### 任务参数在入队那一刻定死

建任务用到的全部参数打包进 `TaskOptions`，随任务入队。任务串行排队跑，用户很可能在排队期间
改设置去建下一个任务 —— **运行时再去读全局设置，前面排着的任务就会被后面的改动影响**，
这类 bug 事后极难复现。`AppSettings` 只作为新建任务时的默认值来源。

### 六阶段与断点续跑

`TaskStage`：排队 / 准备 / 识别 / 断句 / 翻译 / 完成（转码任务只走排队 / 准备 / 转码 / 完成，
见 `TaskKind.stages`）。**失败与取消都保留已完成阶段的结果**，重试从 `SubtitleTask.resumeStage`
继续；翻译阶段以"这一条有没有译文"为断点，续跑只翻剩下的，不重复花钱。
界面上向用户明确承诺了这件事，改 `TaskRunner` 时别破坏它。
逐段识别的服务用 `RecognitionCheckpoint` 记录每段结果，同样支持段级续跑。

### 翻译的行号协议

`services/translation_protocol.dart`。大模型翻译字幕最常见的故障不是翻错，而是**条数对不上**
（合并两行、丢语气词、把成分挪到下一行），一旦发生后面所有字幕的时间轴全错位。
协议给每行打 `§N§` 行号，返回后逐行核对：条数不符、行号越界或重复就判这批不可信，
**减半批量重试**（`ProviderException.batchTooLarge`），绝不把错位的译文写进字幕。

### 折行只发生在导出时

单行字数上限（中日韩 15、其他 40）在写出产物时才应用，`SubtitleDocument` 里始终存不带硬换行的
干净文本。否则用户编辑后再导出会叠加上一次的换行。

### 界面状态：没有状态管理库

全用 `ChangeNotifier`。`main.dart` 是唯一的装配点：
- 各页表单控制器（`TranscribeFormController` 等）**挂在根节点上**，切走再回来文件与参数还在。
- 顶栏 / 状态栏靠 `Listenable.merge` 出来的 `_live` + `ListenableBuilder` 局部驱动 ——
  直接 `setState` 会让每次进度回调重建 MaterialApp 以下整棵树。
- 编辑器会话是 sealed 的 `EditorSession`：`TaskSession` 与 `FileSession` 共用同一张表格、
  检视面板和同一套保存规则 —— **编辑进度自动存，字幕文件手动写**。编辑进度（任务 JSON /
  本地会话草稿）每次改动都存；字幕文件（任务产物 / 挂载的本地文件）只在 ⌘S 时写，写前
  比对时间戳防止盖掉外部修改。「导出…」是另存到别处，不改变同步状态。

### 持久化与外部依赖

- 任务存成 JSON 在应用支持目录（`TaskStore`），进度回调很密所以攒 300ms 批量写盘；
  重启时上次还在跑的任务标为已暂停，不自动开跑。
- 设置与密钥在 `shared_preferences`，**目前明文**（已知限制，还没接系统钥匙串）。
- ffmpeg 查找顺序：应用目录/ffmpeg → `/opt/homebrew/bin`、`/usr/local/bin`、`/usr/bin`、
  `/snap/bin` → PATH。macOS 上 GUI 应用拿不到用户 shell 的 PATH，所以必须显式找 Homebrew。
- 编码器可用性：先看 `ffmpeg -encoders` 有没有编入，再对硬件编码器试编码 1 帧；
  每个编码器用自己一套参数（`VideoEncoders` in `domain/transcode.dart`），不做通用的质量映射。

## 约定

- **注释与提交信息用中文。** 注释写"为什么"，不写"是什么"；代码里已有大量这样的注释，照着写。
- 提交信息用 conventional commits 带作用域：`feat(app):` `fix(editor):` `test(app):` `chore(ci):`。
- **别对已有文件整体跑 `dart format`**，会产生大量与改动无关的噪音；只保持自己新写的部分与周围一致。
- 界面按 Claude Design 项目「桌面字幕工具 · 设计系统」实现；`docs/design-prompts/` 存的是生成各页设计稿
  用的 prompt，里面有项目 id 与设计稿链接，改界面前从那里找到对应画板。
  改界面后跑 golden 核对；确实是设计变更才 `--update-goldens`，并在提交里说明。
- 平台插件注册文件在 `.gitattributes` 里固定为 LF，别改动它们的换行。
