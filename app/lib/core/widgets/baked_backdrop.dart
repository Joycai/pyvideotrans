import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// 把一层**静态的装饰性**背景烘焙成一张 [ui.Image]，每帧只画一个纹理 quad。
///
/// 动机：多个全窗口渐变叠加时，第二层起每层都要让 GPU 回读整块渲染目标，
/// 在高 DPI 最大化窗口下单层就是十几毫秒；烘焙后与画一张图片同价。
///
/// 只适合不随帧变化的层：任何逐帧动画放进来都会逐帧重烘，比不烘更糟。
/// 让它在真实应用里可用的两个关键是尺寸量化与去抖，见下方注释。
class BakedBackdrop extends StatefulWidget {
  const BakedBackdrop({
    super.key,
    required this.paint,
    required this.recipeKey,
    required this.fallback,
    required this.child,
  });

  /// 往 [size] 大小的画布上画背景。必须是纯函数：相同输入相同输出。
  final void Function(Canvas canvas, Size size) paint;

  /// 除尺寸外背景依赖的一切（主题明暗、强调色…）。变化即重烘，
  /// 所以它必须在多次 build 之间比较相等 —— 不能是每次新分配的对象。
  final Object recipeKey;

  /// 首次烘焙落地前显示的底色。用背景自己的基色，切换时无人察觉。
  final Color fallback;

  final Widget child;

  @override
  State<BakedBackdrop> createState() => _BakedBackdropState();
}

class _BakedBackdropState extends State<BakedBackdrop> {
  ui.Image? _image;
  ({Size size, Object key})? _baked;
  ({Size size, Object key})? _pending;
  Timer? _debounce;

  /// 柔和渐变经得起 4 倍降采样，4K 下纹理从 33 MB 降到 2 MB。
  static const _downscale = 4;

  /// 烘焙尺寸向上取整到这个倍数，拖动窗口边缘几像素时复用上一张图
  /// 而不是重烘。把一层柔光拉伸几十像素看不出来；拖窗口时逐帧重烘看得出来。
  static const _quantum = 16;

  /// 带实时预览的控件（拖动中的取色器）否则会每帧请求一次烘焙。
  /// 第一张图不去抖：启动那一帧就该看到真正的壁纸，而不是先闪一下底色。
  static const _debounceDelay = Duration(milliseconds: 120);

  Size _bakeSize(Size size) {
    int q(double v) {
      final raw = (v / _downscale).ceil();
      return ((raw + _quantum - 1) ~/ _quantum * _quantum).clamp(1, 4096);
    }

    return Size(q(size.width).toDouble(), q(size.height).toDouble());
  }

  void _request(({Size size, Object key}) req) {
    if (_pending == req) return; // 已排队：不要重置计时器
    _pending = req;
    _debounce?.cancel();
    if (_image == null) {
      _bake(req);
      return;
    }
    _debounce = Timer(_debounceDelay, () => _bake(req));
  }

  void _bake(({Size size, Object key}) req) {
    if (!mounted) return;
    final recorder = ui.PictureRecorder();
    widget.paint(Canvas(recorder), req.size);
    final picture = recorder.endRecording();
    // toImageSync 直接在 GPU 上出图，不用等一轮事件循环，首帧不会先闪底色；
    // 测试环境（软件渲染）里同样可用。
    final image = picture.toImageSync(
      req.size.width.round(),
      req.size.height.round(),
    );
    picture.dispose();
    setState(() {
      _image?.dispose();
      _image = image;
      _baked = req;
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (size.isFinite && !size.isEmpty) {
          final req = (size: _bakeSize(size), key: widget.recipeKey);
          if (_baked != req) {
            // build 里不做 setState，也不做异步工作。
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _request(req));
          }
        }
        final image = _image;
        return Stack(
          fit: StackFit.expand,
          children: [
            if (image == null)
              ColoredBox(color: widget.fallback)
            else
              // 低于 low 就是最近邻采样，会把 1/4 分辨率的烘焙图放成色块。
              RawImage(
                image: image,
                fit: BoxFit.fill,
                filterQuality: FilterQuality.low,
              ),
            widget.child,
          ],
        );
      },
    );
  }
}
