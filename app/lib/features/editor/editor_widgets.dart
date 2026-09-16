import 'package:flutter/material.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';

/// 锚在某个控件下方的浮层（来源浮层、说话人菜单、筛选菜单）。
///
/// 点浮层外面任意处关闭。浮层内容由 [popover] 构建，拿到 `close` 回调。
class AnchoredPopover extends StatefulWidget {
  const AnchoredPopover({
    super.key,
    required this.anchor,
    required this.popover,
    this.width,
    this.gap = 6,
    this.alignRight = false,
    this.matchAnchorWidth = false,
  });

  final Widget Function(BuildContext context, VoidCallback toggle, bool open)
  anchor;
  final Widget Function(BuildContext context, VoidCallback close) popover;
  final double? width;
  final double gap;

  /// 右边缘对齐锚点（工具栏最右侧的筛选 chip）。
  final bool alignRight;

  /// 与锚点同宽（检视面板里的说话人字段）。
  final bool matchAnchorWidth;

  @override
  State<AnchoredPopover> createState() => AnchoredPopoverState();
}

class AnchoredPopoverState extends State<AnchoredPopover> {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();

  bool get isOpen => _portal.isShowing;

  void open() => setState(_portal.show);

  void close() {
    if (_portal.isShowing) setState(_portal.hide);
  }

  void toggle() => isOpen ? close() : open();

  /// 按锚点在浮层坐标系里的位置摆放。不用 CompositedTransformFollower：
  /// 它放在 Positioned(0, 0) 里时，命中测试按变换前的位置算，菜单项点不到。
  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (overlayContext) {
        final anchorBox =
            _anchorKey.currentContext?.findRenderObject() as RenderBox?;
        final overlayBox =
            Overlay.of(overlayContext).context.findRenderObject() as RenderBox?;
        if (anchorBox == null || overlayBox == null || !anchorBox.attached) {
          return const SizedBox.shrink();
        }
        final topLeft = anchorBox.localToGlobal(
          Offset.zero,
          ancestor: overlayBox,
        );
        final width = widget.matchAnchorWidth
            ? anchorBox.size.width
            : widget.width;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: close,
              ),
            ),
            Positioned(
              left: widget.alignRight ? null : topLeft.dx,
              right: widget.alignRight
                  ? overlayBox.size.width - topLeft.dx - anchorBox.size.width
                  : null,
              top: topLeft.dy + anchorBox.size.height + widget.gap,
              child: SizedBox(
                width: width,
                child: Material(
                  type: MaterialType.transparency,
                  child: widget.popover(overlayContext, close),
                ),
              ),
            ),
          ],
        );
      },
      child: KeyedSubtree(
        key: _anchorKey,
        child: widget.anchor(context, toggle, isOpen),
      ),
    );
  }
}

/// 玻璃浮层菜单的外壳：glass-strong、12px 圆角、shadow3、内边距 6。
class GlassMenu extends StatelessWidget {
  const GlassMenu({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.all(6),
  });

  final List<Widget> children;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GlassPanel(
    strong: true,
    radius: 12,
    expand: false,
    shadow: context.elevation.shadow3,
    padding: padding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

/// 菜单里 36px 高的一行。
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    this.leading,
    required this.label,
    this.trailing,
    this.onTap,
    this.labelColor,
  });

  final Widget? leading;
  final String label;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Color? labelColor;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm + 2),
        hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
        child: SizedBox(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 10)],
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      color: labelColor ?? cs.onSurface,
                    ),
                  ),
                ),
                ?trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class MenuDivider extends StatelessWidget {
  const MenuDivider({super.key});

  @override
  Widget build(BuildContext context) => Container(
    height: 1,
    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
    color: context.colors.outlineVariant,
  );
}

/// 小号分段控件（32 或 28 高、labelMedium），配对方式、应用范围、导出标签用。
class MiniSegmented<T> extends StatelessWidget {
  const MiniSegmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.height = 32,
  });

  final List<({T value, String label})> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final e = context.elevation;
    final radius = height >= 32 ? AppRadius.md : AppRadius.sm + 2;
    return Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: cs.outlineVariant),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: e.controlGradient,
        ),
        boxShadow: e.controlShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, seg) in segments.indexed) ...[
            if (i > 0) VerticalDivider(width: 1, color: cs.outlineVariant),
            Material(
              color: seg.value == value
                  ? cs.secondaryContainer
                  : Colors.transparent,
              child: InkWell(
                onTap: () => onChanged(seg.value),
                hoverColor: cs.onSurface.withValues(alpha: AppStateLayer.hover),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: height >= 32 ? 12 : 10,
                  ),
                  child: Center(
                    child: Text(
                      seg.label,
                      maxLines: 1,
                      style: context.texts.labelMedium?.copyWith(
                        color: seg.value == value
                            ? cs.onSecondaryContainer
                            : cs.onSurface,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 36×36 的图标方块（文件行、任务行前面）。
class FileIconBox extends StatelessWidget {
  const FileIconBox(this.icon, {super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    width: 36,
    height: 36,
    decoration: BoxDecoration(
      color: context.colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.sm + 2),
    ),
    child: Icon(
      icon,
      size: 20,
      weight: 400,
      color: context.colors.onSurfaceVariant,
    ),
  );
}

/// 窗口窄于 1100 时编辑页收紧：检视面板 380px、说话人列只留徽标、
/// 原文 / 译文 / 双语收进「视图」下拉。按窗口算，顶栏与正文用同一个判断。
bool isCompactEditor(BuildContext context) =>
    MediaQuery.sizeOf(context).width < 1100;

/// 相对时间的「现在」。截图测试把它钉死，否则「今天 / 昨天」每天都变。
@visibleForTesting
DateTime Function() editorClock = DateTime.now;

/// 「今天 14:20」「昨天 21:04」「9月10日」。
String friendlyTime(DateTime time, {DateTime? now}) {
  final today = now ?? editorClock();
  String two(int v) => v.toString().padLeft(2, '0');
  final hm = '${two(time.hour)}:${two(time.minute)}';
  final day = DateTime(time.year, time.month, time.day);
  final diff = DateTime(today.year, today.month, today.day).difference(day);
  if (diff.inDays == 0) return '今天 $hm';
  if (diff.inDays == 1) return '昨天 $hm';
  if (time.year != today.year) return '${time.year}年${time.month}月${time.day}日';
  return '${time.month}月${time.day}日';
}

String parentDir(String path) {
  final i = path.lastIndexOf(RegExp(r'[/\\]'));
  return i <= 0 ? path : path.substring(0, i);
}

String baseName(String path) => path.split(RegExp(r'[/\\]')).last;

class EditorTextAction extends StatelessWidget {
  const EditorTextAction({
    super.key,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(AppSpacing.s2),
    hoverColor: color.withValues(alpha: AppStateLayer.hover),
    child: Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      alignment: Alignment.center,
      child: Text(
        label,
        style: context.texts.labelMedium?.copyWith(color: color),
      ),
    ),
  );
}
