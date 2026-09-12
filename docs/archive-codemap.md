# 归档代码索引（archive/python）

`archive/` 里是原 [pyVideoTrans](../archive/python/README.md) 的完整 Python 实现，
**只作功能参考**，不参与构建。写 Flutter 侧功能时想知道"原来是怎么做的、有哪些参数、
踩过哪些坑"，从这里找。

约 5.6 万行、300 多个 Python 文件，直接 grep 很容易迷路，所以有这份索引。
所有路径都相对 `archive/python/`。

## 一、三条主线

原项目做的事比我们多（它还做配音与合成视频）。与我们相关的是前三条：

| 能力 | 任务类 | 入口窗口 |
|---|---|---|
| **音视频 → 字幕**（我们的「转写」） | `videotrans/task/speech2text.py` | `videotrans/winform/fn_recogn.py` |
| **字幕 → 译文字幕**（我们的「翻译」） | `videotrans/task/translate_srt.py` | `videotrans/winform/fn_fanyisrt.py` |
| 视频翻译全流程（转写+翻译+配音+合成） | `videotrans/task/trans_create.py` | 主窗口 `videotrans/mainwin/` |
| 字幕配音 | `videotrans/task/dubbing.py` | `videotrans/winform/fn_peiyin.py` |

`trans_create.py` 本身没多少代码，真正的步骤是一串 mixin，按执行顺序：

```
_stage_prepare.py   准备（探测格式、抽音、分离人声）
_stage_recogn.py    识别（调 recognition/）
_stage_diariz.py    说话人分离
_stage_subtitle.py  字幕整理（断句、换行、标点）
_stage_translate.py 翻译（调 translator/）
_stage_dubbing.py   配音（调 tts/）
_stage_align.py     音画对齐、变速
_stage_assemble.py  合成输出
```

我们的六阶段流水线（`app/lib/pipeline/task_runner.dart`）对应其中前五个。

## 二、目录总览

| 目录 | 行数 | 是什么 |
|---|---:|---|
| `videotrans/ui/` | 10193 | Qt 界面的**布局**定义（PySide6，纯控件摆放，无逻辑） |
| `videotrans/winform/` | 5531 | 与 `ui/` 一一对应的**行为**：取值、校验、起任务 |
| `videotrans/mainwin/` | 1851 | 主窗口，逻辑拆成 `_actions_*.py` 一堆 mixin |
| `videotrans/component/` | 6046 | 自定义控件（拖放按钮、进度条、表格、各种设置小窗） |
| `videotrans/task/` | 4215 | 任务类与执行阶段（见上） |
| `videotrans/process/` | 3114 | 真正干活的函数：各家 ASR 的调用、VAD、降噪、人声分离、TTS |
| `videotrans/recognition/` | 3654 | 识别渠道登记表 + 28 个渠道适配器 |
| `videotrans/translator/` | 2037 | 翻译渠道登记表 + 30 余个渠道适配器 |
| `videotrans/tts/` | 3609 | 配音渠道（我们不做） |
| `videotrans/util/` | 4725 | ffmpeg/ffprobe 封装、SRT 解析与换行、GPU 检测、下载 |
| `videotrans/configure/` | 3151 | 全局配置、设置项定义、语言表、日志、异常 |
| `videotrans/codes/` | 710 | 模型下载地址与校验 |
| `videotrans/language/` | — | `zh_CN.json` / `en_US.json` 全部界面文案 |
| `videotrans/prompts/` | — | 提示词模板：`recogn/` `resegment/` `srt/` `text/` `language_prompts/` |
| `docs/` | — | 原项目文档，`architecture.md` 与 `Synchronize.md`（音画同步原理）值得读 |
| `tests/` | — | pytest，覆盖不全但能看出模块边界 |

入口：`sp.py`（GUI）、`cli.py`（命令行）、`webui.py`（Gradio）。

## 三、按功能找代码

### 识别 / 转写

| 要找 | 看这里 |
|---|---|
| 转写窗口有哪些参数、怎么校验 | `winform/fn_recogn.py`，布局在 `ui/recogn.py` |
| 识别渠道有哪些、渠道 ID 常量 | `recognition/__init__.py` 开头的 `FASTER_WHISPER=0 …` |
| 渠道→可选模型、渠道→支持语言 | `recognition/__init__.py` 的 `get_model_by_type` / `is_allow_lang` |
| 渠道适配器（每家一个文件） | `recognition/_whisper.py` `_openairecognapi.py` `_qwen3asr.py` … |
| 适配器基类：VAD 切分、结果后处理 | `recognition/_base.py`（`_vad_split` / `cut_audio` / `_post_fix`） |
| 实际推理调用 | `process/stt_*.py` |
| 静音切分（长音频必须先切） | `process/vad.py` |
| 降噪、标点恢复/删除 | `process/_audio_noise.py` |
| 说话人分离与标注 | `process/_audio_speakers.py`、`task/_stage_diariz.py` |

### 翻译

| 要找 | 看这里 |
|---|---|
| 翻译窗口 | `winform/fn_fanyisrt.py` + `ui/fanyi.py` |
| 渠道登记表 | `translator/_registry.py`、`translator/__init__.py` |
| OpenAI 兼容实现（我们抄的就是这套） | `translator/_openaicompat.py`、`_chatgpt.py`、`_localllm.py` |
| 分批、重试、条数对齐 | `translator/_runner.py`、`translator/_base.py` |
| 提示词模板 | `prompts/srt/`、`prompts/text/`、`prompts/language_prompts/` |
| 语言代码与显示名互转 | `translator/_lang_codes.py`、`_lang_utils.py`、`configure/_languages_dict.py` |

### 字幕处理

| 要找 | 看这里 |
|---|---|
| SRT 解析与序列化 | `util/_srt_parse.py`（聚合出口 `util/help_srt.py`） |
| 单行字数换行（CJK 15 / 其他 40） | `util/_srt_wrap.py` 的 `simple_wrap` |
| ASS 样式 | `util/_srt_ass.py` |
| 断句重排（LLM） | `prompts/resegment/`、`task/_stage_subtitle.py` |

### 音视频

| 要找 | 看这里 |
|---|---|
| ffmpeg 调用与错误提取 | `util/_ffmpeg_runner.py` |
| 探测时长/编码/有无音轨 | `util/_ffprobe.py` |
| 抽音、转 16k、拼接、变速、去静音 | `util/_ffmpeg_audio.py` |
| 硬件编码器探测 | `util/_ffmpeg_hwcodec.py` |
| 人声/伴奏分离 | `process/_audio_separate.py` |

### 配置与设置

| 要找 | 看这里 |
|---|---|
| 全部设置项、默认值、中英说明 | `ui/setini.py`（702 行，参数字典就在里面） |
| 运行时配置对象 | `configure/_app_cfg.py` `_app_params.py` `_app_settings.py` |
| 常量（模型名单等） | `configure/contants.py` |
| 异常类型与提示 | `configure/excepts.py` |

## 四、命名约定

- `_xxx.py` 是私有实现，同目录下有个**聚合模块**把它们 re-export 出来：
  `util/help_srt.py`、`util/help_ffmpeg.py`、`util/tools.py`、`process/prepare_audio.py`。
  grep 找不到定义时，多半是被聚合模块转了一手。
- `ui/` 与 `winform/` 同名成对：`ui/recogn.py` 摆控件，`winform/fn_recogn.py` 接逻辑。
- `winform/fn_*.py` 是**功能窗口**（转写、翻译、配音、合并…）；
  其余如 `winform/deepseek.py` `winform/siliconflow.py` 是**渠道配置窗**，
  每个渠道一个，由 `recognition/__init__.py` 的 `_ID_NAME_DICT` 里的 `win=` 字段指过来。
- `ChannelProvider` 与 `get_class()` 在 `videotrans/__init__.py`：渠道 ID → 适配器类的
  统一入口，识别与翻译都走它。

## 五、几个坑

- **全局可变状态很多**：`config.params` / `app_cfg` / `settings` 是进程级字典，
  窗口读写它们来传参。读某段逻辑时要留意参数其实来自哪里。
- **渠道 ID 是整数常量且与顺序绑定**（`RECOGN_NAME_LIST` 按 ID 排序生成下拉项），
  所以下拉框的 `currentIndex()` 就是渠道 ID。我们改用字符串 id，不要照搬。
- **界面文案全在 `language/zh_CN.json`**，代码里到处是 `tr('xxx')`，
  想知道某个按钮实际显示什么，去 json 里查 key。
- 作者在 `sp.py` 顶部自陈"全局变量乱如麻，线程队列八九个，传参全靠大字典"——
  参考它的**功能与参数**，不要参考它的结构。
