/// 模型名的校验规则。
///
/// 模型名原样进请求体，服务端按字面匹配 —— 多一个空格、夹一个换行就是
/// 「找不到模型」的 404，而且从报错里看不出是名字写坏了。所以在用户写下它
/// 的那一刻就拦住，不等到任务跑起来。设置页的模型列表与建任务页的
/// 「其他模型…」用同一套规则。
abstract final class ModelName {
  static const maxLength = 128;

  /// 去掉首尾空白。粘贴来的名字常带尾随空格或换行，这不算用户写错。
  static String normalize(String raw) => raw.trim();

  static final _blankOrComma = RegExp(r'[\s,，]');

  /// 控制字符与格式字符（零宽、双向控制、软连字符……）：从聊天软件、网页复制时
  /// 混进来的，眼睛看不见。按 Unicode 类别判，不逐个列码位 —— 列举总会漏。
  static final _invisible = RegExp(
    r'[\p{Cc}\p{Cf}]',
    unicode: true,
  );

  /// 合法返回 null，否则返回一句可以直接显示的原因。
  ///
  /// [existing] 是同一个服务下已有的模型名：重名的第二个永远选不中，
  /// 留着只会让人以为有两份不同的配置。
  static String? validate(String raw, {Iterable<String> existing = const []}) {
    final name = normalize(raw);
    if (name.isEmpty) return '模型名不能为空';
    // 先查空白再查不可见字符：换行、制表符两边都算，按更好懂的那句报。
    if (_blankOrComma.hasMatch(name)) return '模型名不能含空格或逗号';
    if (_invisible.hasMatch(name)) return '模型名里有不可见字符';
    if (name.length > maxLength) return '模型名不能超过 $maxLength 个字符';
    if (existing.contains(name)) return '列表里已经有 $name';
    return null;
  }
}
