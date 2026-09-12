import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/core/theme/app_extensions.dart';
import 'package:subtitle_studio/core/theme/app_theme.dart';

void main() {
  group('主题', () {
    test('浅色与深色都注册了三个扩展', () {
      for (final theme in [lightTheme, darkTheme]) {
        expect(theme.extension<AppColors>(), isNotNull);
        expect(theme.extension<AppGlass>(), isNotNull);
        expect(theme.extension<AppElevation>(), isNotNull);
      }
    });

    test('深色不是浅色的反色，是单独调校的', () {
      expect(lightTheme.colorScheme.primary, const Color(0xFF2A63F5));
      expect(darkTheme.colorScheme.primary, const Color(0xFF6E8CFF));
    });

    test('玻璃层半透明，内容层不透明', () {
      expect(AppGlass.light.glass.a, lessThan(1.0));
      expect(AppGlass.dark.glass.a, lessThan(1.0));
      expect(lightTheme.colorScheme.surfaceContainerLowest.a, 1.0);
    });
  });

  testWidgets('扩展在 BuildContext 上可取到', (tester) async {
    late AppElevation elevation;
    await tester.pumpWidget(
      MaterialApp(
        theme: lightTheme,
        home: Builder(
          builder: (context) {
            elevation = context.elevation;
            return const SizedBox();
          },
        ),
      ),
    );
    // 进度条是全应用唯一允许出现紫色的地方。
    expect(elevation.progressGradient.last, const Color(0xFF7B61FF));
  });
}
