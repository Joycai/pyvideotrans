# 翻译后端与 Responses 接入

## 范围与步骤

1. 核对官方文档中的 DeepSeek V4 / V4.1、GPT 5.6 / 6 / 6.1 模型 ID 与参数。
2. 为翻译模型声明增加协议与参数画像，随设置和任务快照持久化；旧声明保留 Chat Completions。
3. 更新预置、暂停硅基流动翻译入口；实现非流式 Responses 请求与终态校验，复用字幕行号协议。
4. 设置中的自定义模型可选择协议；参数控件复用现有目录。
5. 补充请求、错误、迁移与快照测试，运行 analyze / test / golden，并作只读审查。

## 契约

- 运行时按声明分派，不从模型名推测接口。已有设置不自动替换型号，已入队任务不迁移协议。
- Responses 每批独立发送 instructions / input，不使用服务端会话；只接收完成的正文，拒绝失败、截断和拒答。
- 保留术语表、翻译要求、逐行校验及批量减半续跑。
- 自定义网关的能力由用户声明，不套用官方厂商私有字段。
- 不修改当前工作区已有的编辑器相关改动，不执行付费 API 请求。

## 证据（2026-11-03 官方文档，未实测）

- [DeepSeek 模型](https://api-docs.deepseek.com/quick_start/pricing/)：deepseek-flash 为 V4.1 Flash，deepseek-v4-pro 为 V4 Pro。
- [DeepSeek 思考模式](https://api-docs.deepseek.com/guides/thinking_mode/)：Chat 的 thinking 开关与 low / high / max 档位。
- [DeepSeek Responses](https://api-docs.deepseek.com/guides/responses_api/)：instructions / input，stateless，reasoning.effort。
- [GPT 系列指南](https://developers.openai.com/api/docs/guides/latest-model)：GPT 5.6 Sol / Terra / Luna，GPT 6 Astra / Sol / Luna，GPT 6.1 Sol / Terra；推理开启时不发 temperature。

## 验证

- `flutter analyze`：通过。
- 最终验证结果见下方审查修复记录（golden / live 依配置跳过）。
- 新增协议及预算配置浅色 880px / 深色 600px 三张 golden，包含关闭思考场景；检查无溢出与数字截断。
- 原有 golden 首轮 21 通过、39 失败。在 HEAD 临时副本复测：32 通过、28 失败，证明原有基线已有 28 项差异。
- 两轮失败集合比较新增 11 项：9 张翻译页、2 张任务页。逐像素差异边界仅在模型名称区域（deepseek-chat → deepseek-flash），仅更新这 11 张；不覆盖原有 28 项差异。
- 未执行付费真实 API 调用，接口验证使用 MockClient；官方文档事实不当作线上实测。
- 编辑器相关修改已独立合入主分支，本次仅提交翻译接入与预算相关文件。


## effort 与上下文审查修复

1. 按模型保存允许的 effort、默认 effort、上下文与输出能力；支持 none 的 GPT 独立声明。
2. 新预置每批默认输出预算 32768 token，计入推理与正文；设置可调低窗口及调整预算。
3. 采用 UTF-8 字节数加协议余量的保守估算，发送前为输出留空间；不是精确 tokenizer。
4. 明确的服务端超窗错误触发降批，普通 400 / 鉴权 / 限流不降批；固定提示超预算直接提示调整。
5. 模型声明及所有参数随设置与任务快照往返，旧配置不自动升级；补全回归测试后审查并提交。

能力数值依据：[DeepSeek 模型列表](https://api-docs.deepseek.com/api/list-models/)、
[DeepSeek 输出上限](https://api-docs.deepseek.com/api/create-chat-completion/)、
[GPT 6.1 Sol](https://developers.openai.com/api/docs/models/gpt-6.1-sol)、
[OpenAI 推理预算](https://developers.openai.com/api/docs/guides/reasoning)。

### 最终验证与只读审查

- `flutter analyze`：通过，无问题。
- `flutter test`：1133 通过、16 跳过，零失败。
- golden：35 通过、28 失败；失败用例集合与干净基线完全相同，无新增失败。
- 三张新配置截图已逐张检查，百万级预算完整显示；仅更新有意设计变化的截图。
- 审查覆盖协议分派、正文终态、行号校验、预算错误分类、降批续跑、参数持久化与旧配置兼容；未发现新增阻塞问题。
- `git diff --check` 通过；未执行付费 API 实测。
