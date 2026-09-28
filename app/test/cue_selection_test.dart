import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/cue_selection.dart';

void main() {
  final all = [0, 1, 2, 3, 4, 5, 6, 7];

  group('单选', () {
    test('焦点、锚点与集合都是那一条', () {
      const s = CueSelection.single(3);
      expect(s.focus, 3);
      expect(s.anchor, 3);
      expect(s.positions, {3});
      expect(s.isMultiple, isFalse);
      expect(s.contains(3), isTrue);
      expect(s.contains(2), isFalse);
    });
  });

  group('⌘/Ctrl 切换', () {
    test('加入一条：焦点与锚点移过去，原来的保留', () {
      final s = const CueSelection.single(1).toggle(4, all);
      expect(s.positions, {1, 4});
      expect(s.focus, 4);
      expect(s.anchor, 4);
    });

    test('取消非焦点行：焦点不变，锚点落在被取消的行上', () {
      final s = const CueSelection.single(1).toggle(4, all).toggle(1, all);
      expect(s.positions, {4});
      expect(s.focus, 4);
      expect(s.anchor, 1);
    });

    test('取消焦点行：焦点移到可见顺序里往后最近的选中行', () {
      final s = const CueSelection.single(1)
          .toggle(6, all)
          .toggle(3, all)
          .toggle(3, all);
      expect(s.positions, {1, 6});
      expect(s.focus, 6);
    });

    test('后面没有选中行时往前找', () {
      final s = const CueSelection.single(1).toggle(6, all).toggle(6, all);
      expect(s.focus, 1);
    });

    test('唯一一条不能取消', () {
      const s = CueSelection.single(2);
      expect(s.toggle(2, all), s);
    });
  });

  group('Shift 扩选', () {
    test('往下扩：锚点到目标整段，焦点在目标，锚点不变', () {
      final s = const CueSelection.single(2).extendTo(5, all);
      expect(s.positions, {2, 3, 4, 5});
      expect(s.focus, 5);
      expect(s.anchor, 2);
    });

    test('往上扩，再换个方向扩时以同一锚点重算', () {
      final up = const CueSelection.single(5).extendTo(2, all);
      expect(up.positions, {2, 3, 4, 5});
      final down = up.extendTo(7, all);
      expect(down.positions, {5, 6, 7});
    });

    test('只覆盖可见行，筛掉的行不会被选进去', () {
      final visible = [0, 2, 5, 7];
      final s = const CueSelection.single(0).extendTo(5, visible);
      expect(s.positions, {0, 2, 5});
    });

    test('锚点不可见时退回单选', () {
      final s = const CueSelection.single(3).extendTo(5, [0, 2, 5]);
      expect(s, const CueSelection.single(5));
    });

    test('⌘ 点过的行成为新锚点', () {
      final s = const CueSelection.single(0).toggle(4, all).extendTo(6, all);
      expect(s.positions, {4, 5, 6});
    });
  });

  group('只保留看得见的行', () {
    test('去掉被筛掉的行，焦点与看得见的锚点不变', () {
      final s = const CueSelection.single(1).extendTo(4, all);
      final r = s.restrictTo({1, 2, 4, 6});
      expect(r.positions, {1, 2, 4});
      expect(r.focus, 4);
      expect(r.anchor, 1);
    });

    test('焦点被筛掉，或只剩一条：退回单选', () {
      final s = const CueSelection.single(1).extendTo(4, all);
      expect(s.restrictTo({1, 2}), const CueSelection.single(4));
      expect(s.restrictTo({4, 7}), const CueSelection.single(4));
    });

    test('锚点被筛掉时换成焦点：Shift 扩选仍有起点', () {
      final s = const CueSelection.single(1).extendTo(4, all);
      final r = s.restrictTo({2, 3, 4, 6});
      expect(r.anchor, 4);
      expect(r.extendTo(6, [2, 3, 4, 6]).positions, {4, 6});
    });

    test('单选时锚点被筛掉也换成焦点', () {
      final s = const CueSelection.single(1).toggle(4, all).toggle(4, all);
      expect((s.focus, s.anchor), (1, 4));
      expect(s.restrictTo({0, 1, 2}), const CueSelection.single(1));
    });

    test('全都看得见时原样返回', () {
      final s = const CueSelection.single(1).extendTo(4, all);
      expect(identical(s.restrictTo(all.toSet()), s), isTrue);
    });
  });

  test('性质：随机操作序列下不变量始终成立', () {
    final random = Random(20260928);
    for (var round = 0; round < 300; round++) {
      final n = 1 + random.nextInt(20);
      // 可见行随机收窄或放宽，模拟筛选变化：锚点和已选行可能被筛掉。
      List<int> visible() {
        final order = [
          for (var i = 0; i < n; i++)
            if (random.nextDouble() < 0.7) i,
        ];
        if (order.isEmpty) order.add(random.nextInt(n));
        return order;
      }

      var order = visible();
      var s = CueSelection.single(order[random.nextInt(order.length)]);
      for (var step = 0; step < 40; step++) {
        if (random.nextInt(5) == 0) order = visible();
        final p = order[random.nextInt(order.length)];
        final extend = random.nextBool();
        s = extend ? s.extendTo(p, order) : s.toggle(p, order);

        final r = s.restrictTo(order.toSet());
        expect(r.positions, contains(r.focus));
        expect(r.focus, s.focus);
        if (r.isMultiple) expect(order, containsAll(r.positions));
        // 焦点看得见时锚点一定看得见，Shift 扩选总有起点。
        if (order.contains(r.focus)) expect(order, contains(r.anchor));

        expect(s.positions, isNotEmpty);
        expect(s.positions, contains(s.focus));
        expect(s.length, s.positions.length);
        for (final q in s.positions) {
          expect(s.contains(q), isTrue);
          expect(q, inInclusiveRange(0, n - 1));
        }
        if (extend) {
          // 扩选的结果是可见顺序里的一段连续区间，而且只含可见行；
          // 锚点被筛掉时退回单选，也满足这一条。
          final at = s.positions.map(order.indexOf).toList()..sort();
          expect(at.first, greaterThanOrEqualTo(0));
          expect(at.last - at.first + 1, at.length);
          expect(s.focus, p);
        }
      }
    }
  });
}
