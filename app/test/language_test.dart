import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/language.dart';

void main() {
  group('语言表', () {
    test('代码唯一，且都是小写', () {
      final codes = Languages.all.map((l) => l.code).toList();
      expect(codes.toSet(), hasLength(codes.length));
      expect(codes.every((c) => c == c.toLowerCase()), isTrue);
    });

    test('显示名唯一 —— 下拉里不能出现两个一样的选项', () {
      final names = Languages.all.map((l) => l.name).toList();
      expect(names.toSet(), hasLength(names.length));
    });

    test('中日韩标了 cjk，西文没标', () {
      expect(Languages.byCode('zh')!.cjk, isTrue);
      expect(Languages.byCode('ja')!.cjk, isTrue);
      expect(Languages.byCode('yue')!.cjk, isTrue);
      expect(Languages.byCode('en')!.cjk, isFalse);
      expect(Languages.byCode('fr')!.cjk, isFalse);
    });

    test('自动检测只出现在源语言里', () {
      expect(Languages.source.first.isAuto, isTrue);
      expect(Languages.target.any((l) => l.isAuto), isFalse);
    });
  });

  group('解析', () {
    test('认代码', () {
      expect(Languages.resolve('zh').code, 'zh');
      expect(Languages.resolve('EN').code, 'en');
      expect(Languages.resolve(' ja ').code, 'ja');
    });

    test('认显示名', () {
      expect(Languages.resolve('简体中文').code, 'zh');
      expect(Languages.resolve('日语').code, 'ja');
    });

    // 设置里存的是旧版本写的显示名，升级后不能因此把任务建不起来。
    test('认旧版本存的写法', () {
      expect(Languages.resolve('中文').code, 'zh');
      expect(Languages.resolve('英文').code, 'en');
    });

    test('认不出来时退回自动检测，而不是抛异常', () {
      expect(Languages.resolve('克林贡语').isAuto, isTrue);
      expect(Languages.resolve('').isAuto, isTrue);
      expect(Languages.resolve(null).isAuto, isTrue);
    });
  });
}
