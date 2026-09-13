import 'package:flutter/material.dart';

/// 扩展色：成功态（阶段条「完成」、状态栏连接点）。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.onSuccessContainer,
    required this.speakers,
  });

  final Color success;
  final Color successContainer;
  final Color onSuccessContainer;

  /// 说话人徽标的底色：八种低饱和、明度相近的颜色，避开 primary 蓝与字幕黄
  /// 的色相。文字一律 onSurface，两套主题下都达到 AA。只用于徽标，不用于
  /// 行底色、描边或文字。编号超过 8 时循环。
  final List<Color> speakers;

  Color speaker(int id) => speakers[id % speakers.length];

  static const light = AppColors(
    success: Color(0xFF1F7A45),
    successContainer: Color(0xFFCFEEDB),
    onSuccessContainer: Color(0xFF0A3D1F),
    speakers: [
      Color(0xFFEFD6DC), // 玫瑰
      Color(0xFFD2E8D6), // 绿
      Color(0xFFE0D8EF), // 紫
      Color(0xFFF0DACD), // 珊瑚
      Color(0xFFCDE7E3), // 青
      Color(0xFFEBD6E8), // 藕荷
      Color(0xFFDDE6CC), // 苔
      Color(0xFFD5E2EA), // 灰蓝
    ],
  );

  static const dark = AppColors(
    success: Color(0xFF7ED4A0),
    successContainer: Color(0xFF1B4A2E),
    onSuccessContainer: Color(0xFFCFEEDB),
    speakers: [
      Color(0xFF4A2F37),
      Color(0xFF2E4434),
      Color(0xFF3A3350),
      Color(0xFF4B3629),
      Color(0xFF2A4441),
      Color(0xFF473045),
      Color(0xFF3A4230),
      Color(0xFF2E3B45),
    ],
  );

  @override
  AppColors copyWith({
    Color? success,
    Color? successContainer,
    Color? onSuccessContainer,
    List<Color>? speakers,
  }) => AppColors(
    success: success ?? this.success,
    successContainer: successContainer ?? this.successContainer,
    onSuccessContainer: onSuccessContainer ?? this.onSuccessContainer,
    speakers: speakers ?? this.speakers,
  );

  @override
  AppColors lerp(AppColors? other, double t) => other == null
      ? this
      : AppColors(
          success: Color.lerp(success, other.success, t)!,
          successContainer: Color.lerp(
            successContainer,
            other.successContainer,
            t,
          )!,
          onSuccessContainer: Color.lerp(
            onSuccessContainer,
            other.onSuccessContainer,
            t,
          )!,
          speakers: t < 0.5 ? speakers : other.speakers,
        );
}

/// 玻璃材质：只用于导航（Rail / 顶栏 / 状态栏）与浮层（Dialog / 菜单 / 详情面板）。
///
/// 半透明 78–92% + 1px 亮边 + 顶部 1px 高光，**不做背景模糊**（桌面性能考量）。
/// 内容区始终是不透明的 surfaceContainerLowest，保证表格文字对比度。
@immutable
class AppGlass extends ThemeExtension<AppGlass> {
  const AppGlass({
    required this.glass,
    required this.glassStrong,
    required this.glassBorder,
    required this.glassHighlight,
  });

  final Color glass;
  final Color glassStrong;
  final Color glassBorder;

  /// 顶部 1px 内高光的颜色。
  final Color glassHighlight;

  static const light = AppGlass(
    glass: Color(0xC7FFFFFF),
    glassStrong: Color(0xE6FFFFFF),
    glassBorder: Color(0xB3FFFFFF),
    glassHighlight: Color(0xE6FFFFFF),
  );

  static const dark = AppGlass(
    glass: Color(0xD1232238),
    glassStrong: Color(0xED232238),
    glassBorder: Color(0x1AFFFFFF),
    glassHighlight: Color(0x1AFFFFFF),
  );

  @override
  AppGlass copyWith({
    Color? glass,
    Color? glassStrong,
    Color? glassBorder,
    Color? glassHighlight,
  }) => AppGlass(
    glass: glass ?? this.glass,
    glassStrong: glassStrong ?? this.glassStrong,
    glassBorder: glassBorder ?? this.glassBorder,
    glassHighlight: glassHighlight ?? this.glassHighlight,
  );

  @override
  AppGlass lerp(AppGlass? other, double t) => other == null
      ? this
      : AppGlass(
          glass: Color.lerp(glass, other.glass, t)!,
          glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
          glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
          glassHighlight: Color.lerp(
            glassHighlight,
            other.glassHighlight,
            t,
          )!,
        );
}

/// 立体感所需的渐变与阴影（M3 的 ButtonStyle 不支持 gradient，需自绘）。
@immutable
class AppElevation extends ThemeExtension<AppElevation> {
  const AppElevation({
    required this.primaryGradient,
    required this.primaryShadow,
    required this.controlGradient,
    required this.controlShadow,
    required this.progressGradient,
    required this.wallpaper,
    required this.shadow1,
    required this.shadow2,
    required this.shadow3,
  });

  /// 主按钮竖向渐变。
  final List<Color> primaryGradient;
  final List<BoxShadow> primaryShadow;

  /// 普通控件的白色微渐变。
  final List<Color> controlGradient;
  final List<BoxShadow> controlShadow;

  /// 进度条填充：蓝 → 紫。这是全应用唯一允许出现紫色的地方。
  final List<Color> progressGradient;

  /// 窗口底层壁纸（真实场景是用户壁纸/视频画面透出，此处用低对比冷色渐变代替）。
  final List<Color> wallpaper;

  final List<BoxShadow> shadow1;
  final List<BoxShadow> shadow2;
  final List<BoxShadow> shadow3;

  static const light = AppElevation(
    primaryGradient: [Color(0xFF4A80EC), Color(0xFF2A63F5)],
    primaryShadow: [
      BoxShadow(
        color: Color(0x4D10308C),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
    controlGradient: [Color(0xFFFFFFFF), Color(0xFFF8F8FC)],
    controlShadow: [
      BoxShadow(
        color: Color(0x12000000),
        blurRadius: 1,
        offset: Offset(0, 1),
      ),
    ],
    progressGradient: [Color(0xFF3B78FF), Color(0xFF7B61FF)],
    wallpaper: [Color(0xFFF1F0F7), Color(0xFFEBEBF3)],
    shadow1: [
      BoxShadow(
        color: Color(0x1A141820),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ],
    shadow2: [
      BoxShadow(
        color: Color(0x1F141820),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
    shadow3: [
      BoxShadow(
        color: Color(0x29141820),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );

  static const dark = AppElevation(
    primaryGradient: [Color(0xFF95B6FF), Color(0xFF6E8CFF)],
    primaryShadow: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 2,
        offset: Offset(0, 1),
      ),
    ],
    controlGradient: [Color(0xFF34334F), Color(0xFF2B2A43)],
    controlShadow: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 1,
        offset: Offset(0, 1),
      ),
    ],
    progressGradient: [Color(0xFF4F7CFF), Color(0xFF8A6CFF)],
    wallpaper: [Color(0xFF121128), Color(0xFF0C0B1C)],
    shadow1: [
      BoxShadow(
        color: Color(0x66000000),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
    ],
    shadow2: [
      BoxShadow(
        color: Color(0x73000000),
        blurRadius: 6,
        offset: Offset(0, 2),
      ),
    ],
    shadow3: [
      BoxShadow(
        color: Color(0x8C000000),
        blurRadius: 24,
        offset: Offset(0, 8),
      ),
    ],
  );

  /// 壁纸上的三团低对比冷色光晕，对应 CSS 的三个 radial-gradient。
  List<
    ({Alignment center, double radiusX, double radiusY, Color color})
  >
  get glows => wallpaper.first == const Color(0xFFF1F0F7)
      ? const [
          (
            center: Alignment(-0.8, -1),
            radiusX: 0.6,
            radiusY: 0.7,
            color: Color(0xFFE9E4F6),
          ),
          (
            center: Alignment(0.8, -0.7),
            radiusX: 0.45,
            radiusY: 0.55,
            color: Color(0xFFE4E9FB),
          ),
          (
            center: Alignment(0.2, 1),
            radiusX: 0.6,
            radiusY: 0.5,
            color: Color(0xFFE3F0EC),
          ),
        ]
      : const [
          (
            center: Alignment(-0.8, -1),
            radiusX: 0.6,
            radiusY: 0.7,
            color: Color(0xFF1F1E44),
          ),
          (
            center: Alignment(0.8, -0.7),
            radiusX: 0.45,
            radiusY: 0.55,
            color: Color(0xFF1A2450),
          ),
          (
            center: Alignment(0.2, 1),
            radiusX: 0.6,
            radiusY: 0.5,
            color: Color(0xFF14243A),
          ),
        ];

  @override
  AppElevation copyWith({
    List<Color>? primaryGradient,
    List<BoxShadow>? primaryShadow,
    List<Color>? controlGradient,
    List<BoxShadow>? controlShadow,
    List<Color>? progressGradient,
    List<Color>? wallpaper,
    List<BoxShadow>? shadow1,
    List<BoxShadow>? shadow2,
    List<BoxShadow>? shadow3,
  }) => AppElevation(
    primaryGradient: primaryGradient ?? this.primaryGradient,
    primaryShadow: primaryShadow ?? this.primaryShadow,
    controlGradient: controlGradient ?? this.controlGradient,
    controlShadow: controlShadow ?? this.controlShadow,
    progressGradient: progressGradient ?? this.progressGradient,
    wallpaper: wallpaper ?? this.wallpaper,
    shadow1: shadow1 ?? this.shadow1,
    shadow2: shadow2 ?? this.shadow2,
    shadow3: shadow3 ?? this.shadow3,
  );

  /// 渐变与阴影在主题切换时不做插值（切换是瞬时的，插值只会让中间帧发灰）。
  @override
  AppElevation lerp(AppElevation? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

extension ThemeTokens on BuildContext {
  ColorScheme get colors => Theme.of(this).colorScheme;
  TextTheme get texts => Theme.of(this).textTheme;
  AppColors get ext => Theme.of(this).extension<AppColors>()!;
  AppGlass get glass => Theme.of(this).extension<AppGlass>()!;
  AppElevation get elevation => Theme.of(this).extension<AppElevation>()!;
}
