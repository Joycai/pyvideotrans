import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue.dart';
import 'package:subtitle_studio/domain/language.dart';
import 'package:subtitle_studio/domain/srt.dart';

Cue _c(String text, {int? speaker}) =>
    Cue(index: 1, startMs: 0, endMs: 1000, source: text, speaker: speaker);

void main() {
  group('识别行首说话人标签', () {
    test('名字标签按出现顺序编号并记名，默认标签换回编号', () {
      final r = Srt.detectSpeakerLabels([
        _c('Mia：大家好'),
        _c('说话人3：嗯'),
        _c('周老师: 谢谢邀请\n很高兴来聊'),
        _c('没有标签的一句'),
        _c('Mia：好，我们继续'),
      ])!;
      expect(r.labels, ['Mia', '说话人3', '周老师']);
      // 说话人3 占住编号 2；Mia、周老师按出现顺序拿空着的 0、1。
      expect(r.cues.map((c) => c.speaker), [0, 2, 1, null, 0]);
      expect(r.speakers, {0: 'Mia', 1: '周老师'});
      expect(r.cues[0].source, '大家好');
      // 多行字幕只去掉第一行的标签。
      expect(r.cues[2].source, '谢谢邀请\n很高兴来聊');
      expect(r.cues[3].source, '没有标签的一句');
    });

    test('Speaker N 不区分大小写，编号从 0 起', () {
      final r = Srt.detectSpeakerLabels([
        _c('Speaker 1: Hello'),
        _c('speaker 2: Hi'),
      ])!;
      expect(r.cues.map((c) => c.speaker), [0, 1]);
      expect(r.speakers, isEmpty);
    });

    test('名字标签先出现也不会占掉后面默认标签的编号', () {
      final r = Srt.detectSpeakerLabels([
        _c('Mia：大家好'),
        _c('说话人1：嗯'),
        _c('周老师：谢谢'),
      ])!;
      expect(r.cues.map((c) => c.speaker), [1, 0, 2]);
      expect(r.speakers, {1: 'Mia', 2: '周老师'});
    });

    test('带标签的条目不到 30% 时不算', () {
      expect(
        Srt.detectSpeakerLabels([
          _c('注意：这里要先装 ffmpeg'),
          _c('然后打开设置'),
          _c('填入地址'),
          _c('保存即可'),
        ]),
        isNull,
      );
    });

    test('时间、网址、带句读或太长的前缀不当作人名', () {
      expect(
        Srt.detectSpeakerLabels([
          _c('10:30 开会'),
          _c('https://example.com'),
          _c('好的，那么：我们开始'),
          _c('this is a very long sentence: really'),
        ]),
        isNull,
      );
    });

    test('标签种类太多时不算', () {
      expect(
        Srt.detectSpeakerLabels([for (var i = 0; i < 25; i++) _c('人$i：话')]),
        isNull,
      );
    });

    test('空文档返回 null', () {
      expect(Srt.detectSpeakerLabels(const []), isNull);
    });
  });

  group('文档上的说话人', () {
    const doc = SubtitleDocument(
      cues: [
        Cue(index: 1, startMs: 0, endMs: 1000, source: '你好', speaker: 0),
        Cue(index: 2, startMs: 1000, endMs: 2000, source: '嗯', speaker: 1),
      ],
      speakers: {0: 'Mia'},
    );

    test('标签用名字，没名字的用默认名，按语言选冒号', () {
      final zh = doc.speakerLabeler(Languages.byCode('zh')!)!;
      expect(zh(0), 'Mia：');
      expect(zh(1), '说话人2：');
      final en = doc.speakerLabeler(Languages.byCode('en')!)!;
      expect(en(0), 'Mia: ');
      expect(en(1), 'Speaker 2: ');
    });

    test('关掉标签后写出方拿到 null', () {
      expect(
        doc.copyWith(speakerLabels: false).speakerLabeler(Languages.auto),
        isNull,
      );
    });

    test('写出的 SRT 带名字标签，读回来能识别成同样的名单', () {
      final text = Srt.serialize(
        doc.cues,
        speakerLabel: doc.speakerLabeler(Languages.byCode('zh')!),
      );
      expect(text, contains('Mia：你好'));
      final back = Srt.detectSpeakerLabels(Srt.parse(text))!;
      expect(back.cues.map((c) => c.source), ['你好', '嗯']);
      expect(back.labels, ['Mia', '说话人2']);
    });

    test('名单与标签开关随 JSON 往返', () {
      final json = doc.copyWith(speakerLabels: false).toJson();
      final back = SubtitleDocument.fromJson(json);
      expect(back.speakers, {0: 'Mia'});
      expect(back.speakerLabels, isFalse);
      expect(SubtitleDocument.fromJson(doc.toJson()).speakerLabels, isTrue);
    });

    test('旧存档没有名单字段也能读', () {
      final back = SubtitleDocument.fromJson({'cues': const []});
      expect(back.speakers, isEmpty);
      expect(back.speakerLabels, isTrue);
    });

    test('卸载译文：清空译文、删掉未配对行、行号连续', () {
      const withTranslation = SubtitleDocument(
        cues: [
          Cue(
            index: 1,
            startMs: 0,
            endMs: 1000,
            source: '一',
            translation: 'one',
          ),
          Cue(
            index: 2,
            startMs: 1000,
            endMs: 1500,
            source: '',
            translation: 'x',
          ),
          Cue(
            index: 3,
            startMs: 1500,
            endMs: 2000,
            source: '二',
            translation: 'two',
          ),
        ],
      );
      final stripped = withTranslation.withoutTranslations();
      expect(stripped.cues.map((c) => c.index), [1, 2]);
      expect(stripped.cues.every((c) => !c.hasTranslation), isTrue);
    });
  });

  group('猜语言', () {
    test('文件名里的语言段', () {
      expect(Languages.fromFileName('/a/interview_ep12.zh.srt')?.code, 'zh');
      expect(Languages.fromFileName('demo.en-US.vtt')?.code, 'en');
      expect(Languages.fromFileName('ep1.chs.srt')?.code, 'zh');
      expect(Languages.fromFileName(r'C:\subs\ep1.cht.srt')?.code, 'zh-tw');
      expect(Languages.fromFileName('movie.pt-BR.srt')?.code, 'pt-br');
      expect(Languages.fromFileName('movie.srt'), isNull);
      expect(Languages.fromFileName('movie.final.srt'), isNull);
    });

    test('按文字判断', () {
      expect(Languages.guessFromText('今天我们聊一聊本地模型的部署')?.code, 'zh');
      expect(Languages.guessFromText('首先确认 Ollama 已经在后台运行')?.code, 'zh');
      expect(Languages.guessFromText('今日はローカルモデルについて話します')?.code, 'ja');
      expect(Languages.guessFromText('오늘은 로컬 모델에 대해 이야기합니다')?.code, 'ko');
      expect(
        Languages.guessFromText(
          'Today we are going to talk about the models and the setup',
        )?.code,
        'en',
      );
      expect(
        Languages.guessFromText('Bonjour à tous, bienvenue dans cet épisode'),
        isNull,
      );
    });
  });
}
