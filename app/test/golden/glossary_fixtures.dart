import 'package:subtitle_studio/domain/glossary.dart';

/// 设计稿「词表」画板里的三份：一份术语、一份人名、一份还空着且没启用。
/// 设置页与建任务页的截图共用。
const sampleGlossaries = [
  Glossary(
    id: 'terms',
    name: '术语 · 产品',
    entries: [
      GlossaryEntry(term: 'Kubernetes', translation: 'Kubernetes'),
      GlossaryEntry(term: '缓存穿透', translation: 'cache penetration'),
      GlossaryEntry(term: '布隆过滤器', translation: 'Bloom filter'),
      GlossaryEntry(term: 'SenseVoice'),
      GlossaryEntry(term: '字幕组', translation: 'fansub group'),
      GlossaryEntry(term: '向量数据库', translation: 'vector database'),
      GlossaryEntry(term: 'whisper-large-v3'),
    ],
  ),
  Glossary(
    id: 'people',
    name: '人名',
    entries: [
      GlossaryEntry(term: '陈嘉行', translation: 'Chen Jiaxing'),
      GlossaryEntry(term: 'Aaron Patterson'),
      GlossaryEntry(term: '李雪琴', translation: 'Li Xueqin'),
      GlossaryEntry(term: 'Mia'),
      GlossaryEntry(term: '周鸣', translation: 'Zhou Ming'),
    ],
  ),
  Glossary(id: 'season3', name: '第 3 季新词', enabledByDefault: false),
];
