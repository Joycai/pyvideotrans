# Qwen 3.1 ASR 接入

- 暂停 OpenAI / Groq / 硅基流动 ASR，保留配置；就绪检查及运行工厂同时拦截。
- Filetrans 复用异步上传、轮询与任务检查点。
- Message 新增显式 WebSocket transport；等待 task-started 后发送 16 kHz 单声道 WAV，finish-task 后等待 task-finished，只收最终句子。
- 验证声明存档、协议、取消、超时和异常断连；执行 analyze、全量测试及 golden。
- 本轮不发送付费探测请求；真实接口可用性另行验证。

协议来源（2026-10-30）：
- https://www.qianwenai.com/models/qwen-audio-3.1-asr-flash-filetrans
- https://help.aliyun.com/en/model-studio/qwen-asr-message-client-events
- https://help.aliyun.com/en/model-studio/qwen-asr-message-server-events

## 已实现范围

- 新安装默认选择百炼；保存过的服务选择和 API Key 不迁移、不清除。
- 两个新模型可从设置的常用列表添加；已有自定义模型列表不会被覆盖。
- Message 支持语言提示、上下文（自由提示前 400 字符）和即时热词（任务词表原词，权重 4）、最终句级时间戳。
- Filetrans 复用原有句/词时间戳及说话人分离；Qwen-Audio 方言通过 input.context 传上下文，parameters.vocabulary 传即时热词；不外推到 Qwen3/Fun-ASR。
- Message 当前用于转写已抽取的音频文件，不提供麦克风录音。连接失败后重试会从文件开头重发，不能复用远端会话；不把中间/不完整结果标记为完成。
- 服务地址仍由百炼配置决定。千问平台文档示例为 `https://cn-beijing.maas.qianwenaiapi.com/api/v1`；Message 使用同域名的 `/api-ws/v1/inference`。密钥与服务区域必须对应。

## 准确率增强补齐

- 复用入队词表快照；归一化、去重后最多 2000 条，非 ASCII 词条最多 15 字符，ASCII 最多 7 词，超限明确报错。
- 自由提示与词表分离，提示按 Unicode 字符截取 400 字符。
- 补齐报文、能力开关、边界与工厂传递测试；运行静态检查和全量测试。
- Filetrans 专用文档的上下文字段是 input.context，不照搬同步接口的 input.messages。

协议核对补充：
- https://platform.qianwenai.com/docs/developer-guides/speech/improve-recognition-accuracy
- https://docs.modelstudio.console.alibabacloud.com/en/model-studio/fun-asr-recorded-speech-recognition-http-api （检索索引中的 Qwen-Audio Filetrans 示例；当前页面已拆分为 Fun-ASR）
