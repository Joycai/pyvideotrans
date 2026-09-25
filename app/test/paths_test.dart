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
    test('自动检测写 src，普通语言写代码', () {
      expect(languageTag(Languages.auto), 'src');
      expect(languageTag(const Language('zh-tw', '繁体中文')), 'zh-tw');
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
        ['ep1.zh.srt', 'ep1.zh-en.srt'],
      );
    });
  });

  test('比较路径时两种分隔符算同一处', () {
    expect(
      sameSeparators(r'C:\out/ep1.zh.srt'),
      sameSeparators(r'C:\out\ep1.zh.srt'),
    );
  });
}
