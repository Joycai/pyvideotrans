import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/srt.dart';
import '../../pipeline/task_queue.dart';
import '../shared/provider_fields.dart';
import '../shell/page_chrome.dart';
import 'transcribe_form.dart';

/// 顶栏内容：标题、随文件变化的副标题、「上次参数」。
/// 放在这里而不是 main.dart，截图测试才能用同一份。
PageChrome newTranscribeChrome(TranscribeFormController form) {
  final n = form.enqueueable.length;
  return PageChrome(
    title: '新建转写',
    subtitle: form.files.isEmpty
        ? '从音视频生成字幕，可接着翻译'
        : '$n 个文件 · 总时长 ${_hms(form.totalDuration)} · '
              '将创建 $n 个${form.kindLabel}任务',
    actions: [
      ControlButton(
        label: '上次参数',
        icon: Symbols.history,
        onPressed: form.hasLastUsed ? form.applyLastUsed : null,
      ),
    ],
  );
}

/// 总时长固定写成 h:mm:ss —— 批量文件加起来经常过小时，位数稳定才好比较。
String _hms(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$h:$m:$s';
}

/// 导航栏里的「新建转写」页：常驻的工作台。
///
/// 与对话框共用 [TranscribeFormController]，不同的是它**不会关闭**：跳去设置
/// 填密钥再回来，文件与参数还在；提交后列表清空、参数保留，方便一批接一批建。
/// 表单控制器由应用根节点持有并传进来，切换导航不会丢状态。
///
/// 布局按设计稿 NewTranscribePage：左列文件面板（自适应），右列参数面板
/// （400px，窗口窄于 1100 时 360，窄于 960 时上下堆叠）。
class NewTranscribePage extends StatefulWidget {
  const NewTranscribePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenSettings,
    required this.onOpenTasks,
  });

  final TranscribeFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenTasks;

  @override
  State<NewTranscribePage> createState() => NewTranscribePageState();
}

class NewTranscribePageState extends State<NewTranscribePage> {
  bool _dragging = false;

  /// 提交后的横幅：入队了几个任务。6 秒后自动收起。
  int? _enqueued;
  Timer? _bannerTimer;

  TranscribeFormController get _form => widget.form;

  @override
  void initState() {
    super.initState();
    _form.addListener(_refresh);
  }

  @override
  void didUpdateWidget(NewTranscribePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.form != widget.form) {
      oldWidget.form.removeListener(_refresh);
      widget.form.addListener(_refresh);
    }
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _form.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 拖放要真实的平台事件才能触发，留个入口给测试。
  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    _form.handleDrop(paths);
  }

  /// 立即入队，列表清空，参数保留。不跳转任务页 —— 批量建任务的人往往
  /// 一批接一批，跳走反而打断；横幅里的「查看任务」是主动去看进度的入口。
  void start() {
    final result = _form.submit();
    if (result == null) return;
    widget.queue.enqueueAll(result.paths, options: result.options);
    _form.clear();
    showEnqueuedBanner(result.paths.length);
  }

  @visibleForTesting
  void showEnqueuedBanner(int count) {
    _bannerTimer?.cancel();
    setState(() => _enqueued = count);
    _bannerTimer = Timer(const Duration(seconds: 6), _dismissBanner);
  }

  void _dismissBanner() {
    _bannerTimer?.cancel();
    if (mounted) setState(() => _enqueued = null);
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  /// 拖放拒收在页面上是中性说明（文件区里已经有一条行内提示），
  /// 不像对话框那样用 error 色。「新建翻译」在这里叫「翻译」—— 导航栏上就是这个名字。
  String? get _rejectNote => _form.dropError?.replaceAll('「新建翻译」', '「翻译」');

  ({String text, IconData icon, bool error})? get _footerOverride {
    final note = _rejectNote;
    if (note == null) return null;
    return (text: note, icon: Symbols.block, error: false);
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): start,
        // Esc 只清除焦点，不清空页面 —— 这里没有「关闭」可言。
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            FocusManager.instance.primaryFocus?.unfocus(),
      },
      child: Focus(
        autofocus: true,
        child: DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (d) => handleDrop(d.files.map((f) => f.path).toList()),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.maxWidth;
              if (w < 960) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: _FilePanel(page: this)),
                    const SizedBox(height: AppSpacing.s3),
                    Expanded(child: _ParamPanel(page: this)),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _FilePanel(page: this)),
                  const SizedBox(width: AppSpacing.s3),
                  SizedBox(
                    width: w < 1100 ? 360 : 400,
                    child: _ParamPanel(page: this),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 文件面板
// ═══════════════════════════════════════════════════════════════════════

class _FilePanel extends StatelessWidget {
  const _FilePanel({required this.page});

  final NewTranscribePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    final files = form.files;
    final dragging = page._dragging;

    // 整个面板就是落点：拖入时描边转 primary、底色 primary 6%。
    return AnimatedContainer(
      duration: AppDuration.medium,
      curve: kEasingStandard,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: dragging
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: dragging ? cs.primary : cs.outlineVariant,
          width: dragging ? 2 : 1,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: Row(
                children: [
                  Text('文件', style: context.texts.titleMedium),
                  const SizedBox(width: AppSpacing.s2),
                  Timecode('${files.length}', color: cs.onSurfaceVariant),
                  const Spacer(),
                  if (files.isNotEmpty) ...[
                    QuietButton(label: '清空', onPressed: form.clear),
                    const SizedBox(width: AppSpacing.s2),
                    ControlButton(
                      label: '添加文件…',
                      icon: Symbols.add,
                      onPressed: form.browse,
                    ),
                  ],
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: AppDuration.medium,
            curve: kEasingStandard,
            alignment: Alignment.topCenter,
            child: page._enqueued == null
                ? const SizedBox(width: double.infinity)
                : _Banner(count: page._enqueued!, page: page),
          ),
          Expanded(
            child: files.isEmpty
                ? _EmptyArea(page: page)
                : _ListArea(page: page),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.count, required this.page});

  final int count;
  final NewTranscribePageState page;

  @override
  Widget build(BuildContext context) {
    final ext = context.ext;
    final fg = ext.onSuccessContainer;
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s3,
      ),
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: AppSpacing.s2),
      decoration: BoxDecoration(
        color: ext.successContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Symbols.check_circle, size: 20, weight: 400, color: ext.success),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('已加入队列 ', style: context.texts.bodyMedium?.copyWith(color: fg)),
          Timecode('$count', color: fg),
          Text(
            ' 个任务，按列表顺序排队',
            style: context.texts.bodyMedium?.copyWith(color: fg),
          ),
          const SizedBox(width: AppSpacing.s2 + 2),
          Text('·', style: TextStyle(color: fg.withValues(alpha: 0.5))),
          const SizedBox(width: AppSpacing.s2 + 2),
          LinkText(label: '查看任务', color: fg, onTap: page.widget.onOpenTasks),
          const Spacer(),
          IconActionButton(
            icon: Symbols.close,
            tooltip: '关闭',
            iconSize: 18,
            onPressed: page._dismissBanner,
          ),
        ],
      ),
    );
  }
}

class _EmptyArea extends StatelessWidget {
  const _EmptyArea({required this.page});

  final NewTranscribePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dragging = page._dragging;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _DashedBorder(
                color: dragging ? cs.primary : cs.outline,
                radius: AppRadius.md,
              ),
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Symbols.upload_file,
                      size: 40,
                      weight: 400,
                      color: dragging ? cs.primary : cs.onSurfaceVariant,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    Text(
                      dragging ? '松开以添加文件' : '把音视频文件拖到这里',
                      style: context.texts.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      'mp4 · mov · mkv · mp3 · m4a · wav，可一次选多个',
                      style: context.texts.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s5),
                    ControlButton(label: '选择文件…', onPressed: page._form.browse),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s4),
          _Steps(current: page._enqueued != null ? 3 : 1),
        ],
      ),
    );
  }
}

/// 三步说明。是真实顺序，所以用了编号；当前步骤的点是 primary。
class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    const labels = ['添加文件', '确认右侧参数', '加入队列，进度在任务页'];
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s6),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i + 1 == current ? cs.primary : cs.outlineVariant,
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Timecode(
            '${i + 1}',
            fontSize: 12,
            color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            label,
            style: context.texts.bodySmall?.copyWith(
              color: i + 1 == current ? cs.onSurface : cs.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _ListArea extends StatelessWidget {
  const _ListArea({required this.page});

  final NewTranscribePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    final files = form.files;
    final n = form.enqueueable.length;
    final note = page._rejectNote;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        0,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) ...[
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  Icon(
                    Symbols.block,
                    size: 18,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      note,
                      style: context.texts.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconActionButton(
                    icon: Symbols.close,
                    tooltip: '关闭',
                    size: 28,
                    iconSize: 16,
                    onPressed: form.clearDropError,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
          ],
          Flexible(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                border: Border.all(color: cs.outlineVariant),
                borderRadius: BorderRadius.circular(AppRadius.md + 2),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _HeaderRow(),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      children: [
                        for (final file in files)
                          _FileRow(
                            file: file,
                            onRemove: () => form.remove(file),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            '参数统一应用到每个文件；入队后按列表顺序生成 $n 个独立任务，单个失败不影响其余',
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            height: 44,
            child: CustomPaint(
              painter: _DashedBorder(
                color: page._dragging ? cs.primary : cs.outline,
                radius: AppRadius.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.upload_file,
                    size: 20,
                    weight: 400,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Text(
                    page._dragging ? '松开以添加文件' : '继续拖入可追加文件',
                    style: context.texts.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 表格列宽：图标 36 | 文件名 自适应 | 时长 88 | 大小 80 | 状态 96 | 移除 36，间距 12。
const _kCols = (icon: 36.0, len: 88.0, size: 80.0, chip: 96.0, remove: 36.0);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          SizedBox(width: _kCols.icon),
          const SizedBox(width: AppSpacing.s3),
          Expanded(child: Text('文件', style: style)),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.len,
            child: Text('时长', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.size,
            child: Text('大小', textAlign: TextAlign.right, style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(
            width: _kCols.chip,
            child: Text('状态', style: style),
          ),
          const SizedBox(width: AppSpacing.s3),
          SizedBox(width: _kCols.remove),
        ],
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({required this.file, required this.onRemove});

  final StagedFile file;
  final VoidCallback onRemove;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final file = widget.file;
    final info = file.info;
    final state = file.state;
    final bad = state == StagedFileState.unreadable;
    final showRemove = _hovered || _focused;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
        decoration: BoxDecoration(
          color: _hovered
              ? cs.onSurface.withValues(alpha: 0.06)
              : Colors.transparent,
          border: Border(bottom: BorderSide(color: cs.outlineVariant)),
        ),
        child: Row(
          children: [
            Container(
              width: _kCols.icon,
              height: 36,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.sm + 2),
              ),
              child: Icon(
                file.isVideo ? Symbols.movie : Symbols.audio_file,
                size: 20,
                weight: 400,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: bad ? cs.onSurfaceVariant : cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    bad ? '文件损坏或编码不受支持，将跳过' : file.directory,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(
                      color: bad ? cs.error : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.len,
              child: Text(
                info?.duration == null
                    ? '—'
                    : Srt.formatDuration(info!.duration!),
                textAlign: TextAlign.right,
                style: kTimecodeStyle.copyWith(
                  color: state == StagedFileState.ready
                      ? cs.onSurface
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.size,
              child: Text(
                info?.sizeLabel ?? '',
                textAlign: TextAlign.right,
                style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.chip,
              child: _StateChip(state: state),
            ),
            const SizedBox(width: AppSpacing.s3),
            SizedBox(
              width: _kCols.remove,
              child: Focus(
                onFocusChange: (v) => setState(() => _focused = v),
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: showRemove ? 1 : 0,
                  child: IconActionButton(
                    icon: Symbols.close,
                    tooltip: '移除',
                    iconSize: 18,
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final StagedFileState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch (state) {
      StagedFileState.ready => (
        '就绪',
        Symbols.check,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      StagedFileState.probing => (
        '探测中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      StagedFileState.unreadable => (
        '无法读取',
        Symbols.error,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: 24,
        padding: const EdgeInsets.only(left: 6, right: AppSpacing.s2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.xs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, weight: 400, color: fg),
            const SizedBox(width: AppSpacing.s1),
            Text(label, style: context.texts.labelMedium?.copyWith(color: fg)),
          ],
        ),
      ),
    );
  }
}

/// 1px 虚线圆角框。Flutter 的 Border 没有 dashed，自己画。
class _DashedBorder extends CustomPainter {
  const _DashedBorder({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0.5, 0.5, size.width - 1, size.height - 1),
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    const dash = 4.0, space = 4.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + space;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorder old) =>
      old.color != color || old.radius != radius;
}

// ═══════════════════════════════════════════════════════════════════════
// 参数面板
// ═══════════════════════════════════════════════════════════════════════

class _ParamPanel extends StatelessWidget {
  const _ParamPanel({required this.page});

  final NewTranscribePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 60,
            child: Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.s4,
                right: AppSpacing.s2,
              ),
              child: Row(
                children: [
                  Text('参数', style: context.texts.titleMedium),
                  const Spacer(),
                  QuietButton(label: '重置为默认', onPressed: form.reset),
                ],
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TranscribeRecognizeSection(
                    form: form,
                    flat: true,
                    onOpenSettings: page.widget.onOpenSettings,
                  ),
                  TranscribeTranslateSection(form: form, flat: true),
                  TranscribeAdvancedSection(form: form, flat: true),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLowest,
              border: Border(top: BorderSide(color: cs.outlineVariant)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TranscribeFooterLine(
                    form: form,
                    line: page._footerOverride,
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                TranscribeStartButton(
                  form: form,
                  onStart: page.start,
                  withCount: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
