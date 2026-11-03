# 火山与百炼翻译接入

## 目标与步骤

1. 从最新 Joycai-main 创建 codex/volcengine-bailian-translation。
2. 在 ProviderCatalog 增加五个独立配置：火山 API / Coding Plan / Agent Plan；百炼 API / Plan（Token Plan，北京）。地址、密钥、模型各自持久化，复用现有翻译工厂。
3. 预置 Qwen 3.7 / 3.8 与 Doubao Seed 2.0 / 2.1；声明式配置思考与预算，不在运行时猜模型名。
4. 验证请求报文、配置隔离与快照；运行 analyze、test、golden，再做只读审查。

## 依据（2026-11-03，官方文档，未付费实测）

- [火山 Coding Plan](https://docs.volcengine.com/docs/ark/coding-plan-personal-ai-codex?lang=en)：`https://ark.cn-beijing.volces.com/api/coding/v3`。
- [火山 Agent Plan / API](https://docs.volcengine.com/docs/ark/integrate-third-party-tools?lang=en)：分别 `/api/plan/v3`、`/api/v3`。按量模型用日期 ID，套餐用别名；套餐当前清单已把 Pro/Lite 更新到 2.1，因此 2.0 套餐预置仅放仍列出的 Mini，不复制旧套餐目录。
- [火山模型目录](https://docs.volcengine.com/docs/ark/model-list?lang=en)：2.0 Lite/Mini 260428 为 LTS；Pro 260215 即将下线，不设为默认。256k 窗口、128k 输出；应用保守采用 256000 / 128000。
- [火山思考](https://docs.volcengine.com/docs/ark/deep-thinking?lang=zh)、[Chat API](https://docs.volcengine.com/docs/ark/chat-api?lang=en)：显式 thinking 开关，low/medium/high；max_completion_tokens 包含思维链。
- [百炼 Chat](https://help.aliyun.com/zh/model-studio/qwen-api-via-openai-chat-completions)：沿用仍有效的北京公共域名 `https://dashscope.aliyuncs.com/compatible-mode/v1`，用户可改业务空间专属地址。Qwen 3.7+ 使用 max_completion_tokens；Qwen 3.8 原生档位 low/medium/xhigh，与 thinking_budget 互斥。
- [百炼 Token Plan](https://help.aliyun.com/zh/model-studio/qwen-code)：`https://token-plan.cn-beijing.maas.aliyuncs.com/compatible-mode/v1`；当前确认 3.8 Max/Flash、3.7 Max/Plus。Plan 不混用旧 Coding Plan 地址。
- [百炼思考](https://help.aliyun.com/zh/model-studio/deep-thinking)：3.7 商业模型支持非流式和 enable_thinking 开关，未确认深度档不展示。
- [Qwen 3.8 Flash](https://help.aliyun.cn/zh/model-studio/qwen3-8-flash)、[3.7 Max](https://help.aliyun.cn/zh/model-studio/qwen3-7-max)：上下文 1000000、最大输出 131072。

百炼预置本次只使用 Chat Completions；Responses 的不同路径与参数不类推。火山支持现有两种协议。字幕系统提示、行号协议与断点续跑保持共用。

## 验证与审查

- `flutter analyze`：通过，无问题。
- `flutter test`：1148 通过，16 跳过，无失败。
- `flutter test --tags golden --run-skipped`：37 通过、28 失败。失败集合与主分支合入 PR #73 前的最终验证日志逐项一致，无新增失败；本次两张新增截图通过并已目视核对。
- 请求测试覆盖五条专属路径、不同思考字段、完整输出预算、正文提取、模型任务快照和五份配置隔离；新增窄窗口操作测试。
- 只读审查未发现本次引入的阻塞问题。沿用 Registry 与翻译行号协议，运行参数来自模型快照，没有新增运行时名字推断。
- 未调用真实付费接口；套餐权限与可用模型仍取决于用户账户。


## 补充 Doubao 2.1（2026-11-03）

API 添加 `doubao-seed-2-1-pro-260915`、`doubao-seed-2-1-lite-260915`、
`doubao-seed-2-1-turbo-260628`；Coding Plan / Agent Plan 添加 `doubao-seed-2.1-pro`、
`doubao-seed-2.1-lite`。沿用现有默认模型，已有配置不自动换型号。

[官方模型表](https://docs.volcengine.com/docs/ark/model-list?lang=en)区分
Pro/Lite 0915 的 1024k 窗口和 Turbo 0628 的 256k 窗口；应用分别设为 1024000 / 256000，
输出上限均保守设为 256000，默认预算仍为 32768。
[套餐配置](https://docs.volcengine.com/docs/ark/coding-plan-personal-ai-zcode?lang=en)
与 [Agent Plan 上线记录](https://docs.volcengine.com/docs/ark/agent-plan-personal-model-release?lang=zh)
确认 Pro / Lite 别名。[思考规则](https://console.volcengine.com/ark/region:cn-beijing/docs/deep-thinking)
说明 xhigh / max 均映射到 high，因此只展示关闭、low、medium、high。
新增测试覆盖七个线路与模型组合的预算、档位、双协议字段及序列化；原有逐预置任务快照测试自动覆盖新型号。

补充后验证：`flutter analyze` 无问题；`flutter test` 1149 通过、16 跳过，无失败。
本次仅扩展目录与能力数据，未改界面布局或更新截图。只读审查确认日期版与套餐别名分开声明，
Turbo 未误用百万窗口，快照与报文测试通过；未进行真实付费调用。
