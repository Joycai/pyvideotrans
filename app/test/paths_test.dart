import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/output_naming.dart';
import 'package:subtitle_studio/domain/paths.dart';
import 'package:subtitle_studio/domain/srt.dart';
import 'package:subtitle_studio/domain/task_kind.dart';
import 'package:subtitle_studio/domain/task_options.dart';

void main() {
  group('跨平台路径', () {
    test('文件名同时接受 POSIX 与 Windows 分隔符', () {
      expect(baseName('/work/demo.zh.srt'), 'demo.zh.srt');
      expect(baseName(r'C:\work\demo.zh.srt'), 'demo.zh.srt');
      expect(baseName('demo.zh.srt'), 'demo.zh.srt');
    });

    test('父目录保留 POSIX 根目录与 Windows 盘符根目录', () {
      expect(dirName('/work/demo.srt'), '/work');
      expect(dirName('/demo.srt'), '/');
      expect(dirName('demo.srt'), '.');
      expect(dirName(r'C:\work\demo.srt'), r'C:\work');
      expect(dirName(r'C:\demo.srt'), 'C:\\');
      expect(dirName('C:/demo.srt'), 'C:/');
    });

    test('主干与扩展名只看最后一个点', () {
      expect(stemOf('episode.12.zh.srt'), 'episode.12.zh');
      expect(extensionOf('/work/episode.12.ZH.SRT'), 'srt');
      expect(extensionOf('/work/README'), isEmpty);
    });
  });

  group('产物语言标签', () {
    test('普通语言写代码；自动检测的原文不写语言段', () {
      expect(languageTag(const Language('zh-tw', '繁体中文')), 'zh-tw');
      expect(
        OutputNaming.tags(SrtField.source, Languages.auto, Languages.all[1]),
        isEmpty,
      );
    });

    test('文件名不安全字符替换成下划线', () {
      expect(languageTag(const Language('x custom/1', '测试')), 'x_custom_1');
    });
  });

  group('产物命名', () {
    test('纯翻译任务不另写原文；转写且翻译写两份，双语带两种语言', () {
      const options = TaskOptions(
        sourceLanguage: Language('zh', '中文'),
        asrProviderId: 'openai',
        targetLanguage: Language('en', '英语'),
        translationProviderId: 'deepseek',
        translate: true,
        bilingual: BilingualLayout.targetBelow,
      );
      expect(OutputNaming.fields(TaskKind.translate, options), [
        SrtField.bilingualTargetBelow,
      ]);
      expect(OutputNaming.fields(TaskKind.transcribe, options), [
        SrtField.source,
      ]);
      expect(
        [
          for (final f in OutputNaming.fields(
            TaskKind.transcribeAndTranslate,
            options,
          ))
            OutputNaming.fileName('ep1', f, options),
        ],
        ['ep1.zh.srt', 'ep1.Bilingual.en.srt'],
      );
    });

    const translate = TaskOptions(
      sourceLanguage: Language('en', '英语'),
      asrProviderId: 'openai',
      targetLanguage: Language('zh', '中文'),
      translationProviderId: 'deepseek',
      translate: true,
    );

    // 源字幕的语言段不去掉的话写成 `Film.en.zh.srt`，Jellyfin 把 `en` 当标题。
    test('纯翻译任务去掉源字幕名末尾的语言段，与视频同主干', () {
      expect(
        OutputNaming.stemFor(TaskKind.translate, 'Film.en.srt', translate),
        'Film',
      );
      expect(
        OutputNaming.stemFor(TaskKind.translate, 'Film.chs.srt', translate),
        'Film',
      );
      // 只认语言表里的码：按形状判断会把 `Cat` 削掉。
      expect(
        OutputNaming.stemFor(TaskKind.translate, 'The.Big.Cat.srt', translate),
        'The.Big.Cat',
      );
      // 视频的主干原样用，Jellyfin 按它配字幕。
      expect(
        OutputNaming.stemFor(TaskKind.transcribe, 'Film.en.mp4', translate),
        'Film.en',
      );
    });

    test('去掉语言段后与源文件同名时保留，不盖掉源文件', () {
      expect(
        OutputNaming.stemFor(TaskKind.translate, 'Film.zh.srt', translate),
        'Film.zh',
      );
    });

    test('认得出视频旁的字幕：同名、带语言段、双语带标题段', () {
      expect(OutputNaming.sidecarTags('/v/ep1.mp4', '/v/ep1.srt'), isEmpty);
      expect(OutputNaming.sidecarTags('/v/ep1.mp4', '/v/ep1.en-US.srt'), [
        'en-US',
      ]);
      expect(
        OutputNaming.sidecarTags('/v/ep1.mp4', '/v/ep1.Bilingual.zh.srt'),
        ['Bilingual', 'zh'],
      );
      // 上次合并旁挂的产物不是这一段的字幕。
      expect(OutputNaming.sidecarTags('/v/ep1.mp4', '/v/ep1.merged.srt'), isNull);
      expect(OutputNaming.sidecarTags('/v/ep1.mp4', '/v/ep10.srt'), isNull);
    });
  });

  test('比较路径时两种分隔符算同一处', () {
    expect(
      sameSeparators(r'C:\out/ep1.zh.srt'),
      sameSeparators(r'C:\out\ep1.zh.srt'),
    );
  });

  test('naturalCompare：数字段按数值，其余不分大小写', () {
    final names = [
      'part10.mp4',
      'Part1.mp4',
      'part2.mp4',
      'part02.mp4',
      'b.mp4',
    ];
    names.sort(naturalCompare);
    expect(names, [
      'b.mp4',
      'Part1.mp4',
      'part2.mp4',
      'part02.mp4',
      'part10.mp4',
    ]);
  });
}
