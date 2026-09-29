import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/shortcuts/shortcut_action.dart';
import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/glass_panel.dart';

/// 锚在某个控件下方的浮层（来源浮层、说话人菜单、筛选菜单）。
///
/// 点浮层外面任意处或按 Esc 关闭（输入法组字时的 Esc 是取消候选，不关）。
/// 浮层内容由 [popover] 构建，拿到 `close` 回调。
///
/// 打开时焦点移进浮层：Esc 先由浮层处理，不会穿到外面去（比如把编辑器的
/// 多选一起退掉）。浮层在焦点树上仍挂在锚点底下，别的键照常往锚点的祖先
/// 冒泡 —— 所以只挂在字幕列表上的单键碰不到这里的菜单。关闭时焦点还给打开
/// 前的那个节点，字幕表的单键马上又能用。
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
  State<AnchoredPopover> createState() => _AnchoredPopoverState();
}

class _AnchoredPopoverState extends State<AnchoredPopover> {
  final _portal = OverlayPortalController();
  final _anchorKey = GlobalKey();
  /// 浮层自己的焦点作用域。用作用域而不是普通焦点节点：autofocus 只在所在
  /// 作用域还没有焦点时生效，浮层里后建出来的 autofocus 输入框（「新增说话人…」）
  /// 要有一个空着的作用域才拿得到光标。
  final _focus = FocusScopeNode(debugLabel: 'AnchoredPopover');

  /// 打开前焦点在哪，关闭时还回去。
  FocusNode? _returnTo;

  bool get isOpen => _portal.isShowing;

  void open() {
    _returnTo = FocusManager.instance.primaryFocus;
    setState(_portal.show);
    // autofocus 只在所在作用域还没有焦点时生效，这里外面通常已经有了，
    // 得显式要一次。浮层下一帧才建出来。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _portal.isShowing) _focus.requestFocus();
    });
  }

  void close() {
    if (!_portal.isShowing) return;
    // 焦点已经被用户挪到别处（比如点了浮层外的输入框）就不抢回来。
    final restore = _focus.hasFocus;
    setState(_portal.hide);
    final target = _returnTo;
    _returnTo = null;
    if (restore && target != null && target.context != null) {
      target.requestFocus();
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
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
            Positioned.fill(
              child: CustomSingleChildLayout(
                delegate: _PopoverLayout(
                  anchor: topLeft & anchorBox.size,
                  width: width,
                  gap: widget.gap,
                  alignRight: widget.alignRight,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Shortcuts(
                    shortcuts: const {
                      SingleActivator(LogicalKeyboardKey.escape):
                          _CloseIntent(),
                    },
                    child: Actions(
                      actions: {
                        _CloseIntent: ShortcutAction<_CloseIntent>(
                          (_) => close(),
                        ),
                      },
                      child: FocusScope(
                        node: _focus,
                        child: widget.popover(overlayContext, close),
                      ),
                    ),
                  ),
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

/// 在锚点下方摆浮层，高度封顶在窗口内（内容过长时由浮层自己滚，见
/// [MenuScrollSection]）。下方放得下就往下开；放不下时往上下两边更宽裕的
/// 那边开 —— 得先量出浮层多高才知道，所以用布局代理而不是 Positioned。
class _PopoverLayout extends SingleChildLayoutDelegate {
  _PopoverLayout({
    required this.anchor,
    required this.width,
    required this.gap,
    required this.alignRight,
  });

  /// 浮层离窗口上下边缘至少留这么多。
  static const double edgeMargin = 12;

  final Rect anchor;
  final double? width;
  final double gap;
  final bool alignRight;

  double _below(Size overlay) =>
      overlay.height - anchor.bottom - gap - edgeMargin;
  double _above() => anchor.top - gap - edgeMargin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxHeight = math.max(
      0.0,
      math.max(_below(constraints.biggest), _above()),
    );
    final w = width;
    return w == null
        ? BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: maxHeight)
        : BoxConstraints.tightFor(width: w).copyWith(maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final below = _below(size);
    final downward = childSize.height <= below || below >= _above();
    return Offset(
      alignRight ? anchor.right - childSize.width : anchor.left,
      downward ? anchor.bottom + gap : anchor.top - gap - childSize.height,
    );
  }

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      anchor != old.anchor ||
      width != old.width ||
      gap != old.gap ||
      alignRight != old.alignRight;
}

class _CloseIntent extends Intent {
  const _CloseIntent();
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

/// 菜单里条数不定的一段（说话人列表）：浮层被窗口高度封顶时只有这一段滚，
/// 上面的标题 / 范围选择和下面的操作行始终露在外面。放在 [GlassMenu] 的
/// children 里用。
class MenuScrollSection extends StatelessWidget {
  const MenuScrollSection({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Flexible(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
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

/// 今天的只写钟点，其他日子带上日期。
String shortFriendlyTime(DateTime t) => friendlyTime(t).replaceFirst('今天 ', '');

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
