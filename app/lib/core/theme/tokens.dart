import 'package:flutter/material.dart';

/// 间距阶梯（对应 tokens/spacing.css）。
abstract final class AppSpacing {
  static const s1 = 4.0;
  static const s2 = 8.0;
  static const s3 = 12.0;
  static const s4 = 16.0;
  static const s5 = 20.0;
  static const s6 = 24.0;
  static const s8 = 32.0;
  static const s12 = 48.0;
}

/// 圆角：控件 10、容器/面板 16、Dialog 20。圆形只用于 Switch 与状态点。
abstract final class AppRadius {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 10.0;
  static const lg = 16.0;
  static const xl = 20.0;
}

abstract final class AppDuration {
  static const short = Duration(milliseconds: 100);
  static const medium = Duration(milliseconds: 200);
  static const long = Duration(milliseconds: 300);
}

abstract final class AppEasing {
  static const standard = Cubic(0.2, 0, 0, 1);
  static const emphasized = Cubic(0.05, 0.7, 0.1, 1);
}

/// 字体。设计稿要求 Noto Sans SC + JetBrains Mono；未打包 ttf 时按平台系统字体回退。
abstract final class AppFonts {
  static const sansFallback = <String>[
    'Noto Sans SC',
    'PingFang SC',
    'Microsoft YaHei',
    'Source Han Sans SC',
  ];
  static const monoFallback = <String>[
    'JetBrains Mono',
    'SF Mono',
    'Menlo',
    'Consolas',
    'Noto Sans Mono CJK SC',
  ];
}

abstract final class AppTextStyles {
  /// 时间码样式：等宽 + 表格数字（tnum），保证列对齐不跳动。
  static const timecode = TextStyle(
    fontFamilyFallback: AppFonts.monoFallback,
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );
}

/// 状态层不透明度，对应 WidgetStateProperty.overlayColor。
abstract final class AppStateLayer {
  static const hover = 0.08;
  static const focus = 0.12;
  static const pressed = 0.12;
  static const disabledContainer = 0.12;
  static const disabledContent = 0.38;
}
