/// 一种语言。识别、翻译、断句换行与产物文件名都用这张表，避免各处
/// 各自为政地判断「这是不是中日韩」。
///
/// 语种与中文名取自原 Python 实现的 `EDGE_LANGUANGES_CODE` 与
/// `EDGET_LANGUAGES_NAME2CODE`（见 docs/archive-codemap.md）。
class Language {
  const Language(this.code, this.name, {this.cjk = false});

  /// BCP-47 风格代码，发给识别服务、也用作产物文件名的语言标签。
  final String code;

  /// 界面上显示的中文名。
  final String name;

  /// 中日韩等不用空格分词的语言。决定合并字幕时加不加空格、
  /// 以及单行字数按哪一档限制。
  final bool cjk;

  bool get isAuto => code == Languages.autoCode;

  @override
  String toString() => '$name($code)';
}

abstract final class Languages {
  static const autoCode = 'auto';

  /// 让识别服务自己判断。翻译的目标语言不能选它。
  static const auto = Language(autoCode, '自动检测');

  /// 可作为识别源语言的全部选项（含「自动检测」）。
  static const source = <Language>[auto, ...all];

  /// 可作为翻译目标语言的选项。
  static const target = all;

  static const all = <Language>[
    Language('zh', '简体中文', cjk: true),
    Language('en', '英语'),
    Language('ja', '日语', cjk: true),
    Language('ko', '韩语', cjk: true),
    Language('zh-tw', '繁体中文', cjk: true),
    Language('yue', '粤语', cjk: true),
    Language('fr', '法语'),
    Language('de', '德语'),
    Language('es', '西班牙语'),
    Language('es-419', '西班牙语(拉美)'),
    Language('pt', '葡萄牙语'),
    Language('pt-br', '葡萄牙语(巴西)'),
    Language('it', '意大利语'),
    Language('ru', '俄语'),
    Language('hu', '匈牙利语'),
    Language('pl', '波兰语'),
    Language('nl', '荷兰语'),
    Language('sv', '瑞典语'),
    Language('uk', '乌克兰语'),
    Language('cs', '捷克语'),
    Language('el', '希腊语'),
    Language('nb', '挪威语(书面挪威语)'),
    Language('ro', '罗马尼亚语'),
    Language('bg', '保加利亚语'),
    Language('fi', '芬兰语'),
    Language('vi', '越南语'),
    Language('th', '泰国语', cjk: true),
    Language('id', '印度尼西亚'),
    Language('ms', '马来语'),
    Language('fil', '菲律宾语'),
    Language('km', '高棉语', cjk: true),
    Language('lo', '老挝语', cjk: true),
    Language('my', '缅甸语'),
    Language('hi', '印度语'),
    Language('ur', '乌尔都语'),
    Language('bn', '孟加拉语'),
    Language('ar', '阿拉伯语'),
    Language('tr', '土耳其语'),
    Language('fa', '波斯语'),
    Language('kk', '哈萨克语'),
    Language('uz', '乌兹别克语'),
    Language('he', '希伯来语'),
    Language('af', '南非荷兰语'),
    Language('sq', '阿尔巴尼亚语'),
    Language('am', '阿姆哈拉语'),
    Language('az', '阿塞拜疆语'),
    Language('bs', '波斯尼亚语'),
    Language('ca', '加泰罗尼亚语'),
    Language('hr', '克罗地亚语'),
    Language('da', '丹麦语'),
    Language('et', '爱沙尼亚语'),
    Language('gl', '加利西亚语'),
    Language('ka', '格鲁吉亚语'),
    Language('gu', '古吉拉特语'),
    Language('is', '冰岛语'),
    Language('iu', '因纽特语'),
    Language('ga', '爱尔兰语'),
    Language('jv', '爪哇语'),
    Language('kn', '卡纳达语'),
    Language('lv', '拉脱维亚语'),
    Language('lt', '立陶宛语'),
    Language('mk', '马其顿语'),
    Language('ml', '马拉雅拉姆语'),
    Language('mt', '马耳他语'),
    Language('mr', '马拉地语'),
    Language('mn', '蒙古语'),
    Language('ne', '尼泊尔语'),
    Language('ps', '普什图语'),
    Language('sr', '塞尔维亚语'),
    Language('si', '僧伽罗语'),
    Language('sk', '斯洛伐克语'),
    Language('sl', '斯洛文尼亚语'),
    Language('so', '索马里语'),
    Language('su', '巽他语'),
    Language('sw', '斯瓦希里语'),
    Language('ta', '泰米尔语'),
    Language('te', '泰卢固语'),
    Language('cy', '威尔士语'),
    Language('zu', '祖鲁语'),
  ];

  static Language? byCode(String code) {
    final lower = code.trim().toLowerCase();
    if (lower == autoCode) return auto;
    for (final l in all) {
      if (l.code == lower) return l;
    }
    return null;
  }

  static Language? byName(String name) {
    final trimmed = name.trim();
    for (final l in all) {
      if (l.name == trimmed) return l;
    }
    return null;
  }

  /// 把「可能是代码、可能是显示名」的值解析成语言。
  ///
  /// 历史设置里存的是显示名（'中文'、'英文'），新代码存的是代码，
  /// 所以两种都要认。都认不出来时退回 [auto]，绝不抛异常 ——
  /// 一个不认识的语言值不该让任务建不起来。
  static Language resolve(String? value) {
    if (value == null || value.trim().isEmpty) return auto;
    return byCode(value) ?? byName(value) ?? _legacy(value.trim()) ?? auto;
  }

  /// 旧版本设置里用过、但不在表里的写法。
  static Language? _legacy(String value) => switch (value) {
    '中文' || '中文（简体）' => byCode('zh'),
    '英文' => byCode('en'),
    '日文' => byCode('ja'),
    '韩文' => byCode('ko'),
    _ => null,
  };
}
