/// 接入方式属于模型声明，任务开始后不能因设置变化而切换。
enum ChatTransport {
  completions('Chat Completions', '/chat/completions'),
  responses('Responses', '/responses');

  const ChatTransport(this.label, this.path);
  final String label;
  final String path;
}

/// 参数画像只在配置时选定，不能在发请求时从名字猜厂商。
enum ChatDialect {
  generic('通用兼容'),
  openaiReasoning('OpenAI 推理模型'),
  deepseek('DeepSeek V4 / V4.1');

  const ChatDialect(this.label);
  final String label;
}
