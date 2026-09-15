import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/fields.dart';
import '../../core/widgets/indicators.dart';
import '../../domain/task_options.dart';
import '../../domain/transcode.dart';
import '../../pipeline/task_queue.dart';
import '../../services/transcoder.dart';
import '../shell/app_shell.dart';
import '../tasks/provider_fields.dart' show LinkText;
import '../tasks/task_detail_panel.dart' show CommandBlock;
import 'transcode_form.dart';

/// 顶栏：标题、随文件变化的副标题、「上次参数」。
PageChrome transcodeChrome(TranscodeFormController form) => PageChrome(
  title: '转码',
  subtitle: form.summary,
  actions: [
    ControlButton(
      label: '上次参数',
      icon: Symbols.history,
      onPressed: form.hasLastUsed ? form.applyLastUsed : null,
    ),
  ],
);

/// 导航栏里的「转码」页：FFmpeg 的图形外壳。
///
/// 布局按设计稿 M-TranscodePage，与翻译页同构：左列视频文件面板，右列参数面板
/// （400px，窄于 1100 时 360，窄于 960 时上下堆叠）。建出的任务进同一个任务队列。
class TranscodePage extends StatefulWidget {
  const TranscodePage({
    super.key,
    required this.form,
    required this.queue,
    required this.onOpenTasks,
  });

  final TranscodeFormController form;
  final TaskQueue queue;
  final VoidCallback onOpenTasks;

  @override
  State<TranscodePage> createState() => TranscodePageState();
}

class TranscodePageState extends State<TranscodePage> {
  bool _dragging = false;
  int? _enqueued;
  Timer? _bannerTimer;

  TranscodeFormController get _form => widget.form;

  @override
  void initState() {
    super.initState();
    _form.addListener(_refresh);
    // 打开页面就开始检测编码器：卡片上的状态在加文件之前就该是真的。
    _form.transcoder.ensureProbed();
  }

  @override
  void didUpdateWidget(TranscodePage oldWidget) {
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

  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    _form.handleDrop(paths);
  }

  /// 入队，列表清空，参数保留，不跳转 —— 与翻译页一致。
  void start() {
    final result = _form.submit();
    if (result == null) return;
    widget.queue.enqueueTranscode(result.paths, options: result.options);
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

  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): start,
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

  final TranscodePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    final files = form.files;
    final dragging = page._dragging;
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
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                0,
                AppSpacing.s4,
                AppSpacing.s4,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (form.dropError != null) ...[
                    _DropNote(form: form),
                    const SizedBox(height: AppSpacing.s3),
                  ],
                  Expanded(
                    child: files.isEmpty
                        ? _EmptyArea(page: page)
                        : _ListArea(page: page),
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

class _Banner extends StatelessWidget {
  const _Banner({required this.count, required this.page});

  final int count;
  final TranscodePageState page;

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

class _DropNote extends StatelessWidget {
  const _DropNote({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(left: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Symbols.block, size: 18, weight: 400, color: cs.onSurfaceVariant),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              form.dropError!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
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
    );
  }
}

class _EmptyArea extends StatelessWidget {
  const _EmptyArea({required this.page});

  final TranscodePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final dragging = page._dragging;
    return Column(
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
                    Symbols.movie,
                    size: 40,
                    weight: 400,
                    color: dragging ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Text(
                    dragging ? '松开以添加文件' : '把视频拖到这里',
                    style: context.texts.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    'MP4 · MOV · MKV · AVI · WebM · FLV · WMV · TS，可一次选多个',
                    textAlign: TextAlign.center,
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
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.current});

  final int current;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    const labels = ['添加视频', '选择编码与编码器', '加入队列，进度在任务页'];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: AppSpacing.s6,
      runSpacing: AppSpacing.s2,
      children: [
        for (final (i, label) in labels.indexed)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          ),
      ],
    );
  }
}

class _ListArea extends StatelessWidget {
  const _ListArea({required this.page});

  final TranscodePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
                      for (final file in form.files)
                        _FileRow(
                          file: file,
                          form: form,
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
          form.applyNote,
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
                  Symbols.movie,
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
    );
  }
}

/// 表格列宽：图标 36 | 文件 自适应 | 时长 72 | 视频 136 | 音频 96 | 大小 80 | 状态 96 | 移除 36。
const _kCols = (
  icon: 36.0,
  len: 72.0,
  video: 136.0,
  audio: 96.0,
  size: 80.0,
  chip: 96.0,
  remove: 36.0,
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final style = context.texts.titleSmall?.copyWith(
      color: cs.onSurfaceVariant,
    );
    Widget cell(double w, String t, {bool right = false}) => SizedBox(
      width: w,
      child: Text(t, textAlign: right ? TextAlign.right : null, style: style),
    );
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: _Cols(
        icon: const SizedBox(),
        name: Text('文件', style: style),
        len: cell(_kCols.len, '时长', right: true),
        video: cell(_kCols.video, '视频'),
        audio: cell(_kCols.audio, '音频'),
        size: cell(_kCols.size, '大小', right: true),
        chip: cell(_kCols.chip, '状态'),
        remove: const SizedBox(),
      ),
    );
  }
}

/// 表头与数据行共用的列排布；窄窗口时先收掉视频、音频两列。
class _Cols extends StatelessWidget {
  const _Cols({
    required this.icon,
    required this.name,
    required this.len,
    required this.video,
    required this.audio,
    required this.size,
    required this.chip,
    required this.remove,
  });

  final Widget icon, name, len, video, audio, size, chip, remove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final roomy = c.maxWidth >= 760;
        Widget fixed(double w, Widget child) =>
            SizedBox(width: w, child: child);
        const gap = SizedBox(width: AppSpacing.s3);
        return Row(
          children: [
            fixed(_kCols.icon, icon),
            gap,
            Expanded(child: name),
            gap,
            fixed(_kCols.len, len),
            if (roomy) ...[
              gap,
              fixed(_kCols.video, video),
              gap,
              fixed(_kCols.audio, audio),
            ],
            gap,
            fixed(_kCols.size, size),
            gap,
            fixed(_kCols.chip, chip),
            gap,
            fixed(_kCols.remove, remove),
          ],
        );
      },
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({
    required this.file,
    required this.form,
    required this.onRemove,
  });

  final StagedVideo file;
  final TranscodeFormController form;
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
    final state = widget.form.stateOf(file);
    final problem = widget.form.problemOf(file);
    final ready = state == StagedVideoState.ready;
    final numberColor = ready ? cs.onSurface : cs.onSurfaceVariant;
    final video = file.video;
    final audio = file.audio;

    Widget twoLines(String? top, String? bottom) => Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          top ?? '—',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: kTimecodeStyle.copyWith(
            fontSize: 12,
            height: 16 / 12,
            fontWeight: FontWeight.w500,
            color: numberColor,
          ),
        ),
        if (bottom != null && bottom.isNotEmpty)
          Text(
            bottom,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: kTimecodeStyle.copyWith(
              fontSize: 12,
              height: 16 / 12,
              fontWeight: FontWeight.w400,
              color: cs.onSurfaceVariant,
            ),
          ),
      ],
    );

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
        child: _Cols(
          icon: Container(
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            child: Icon(
              Symbols.movie,
              size: 20,
              weight: 400,
              color: cs.onSurfaceVariant,
            ),
          ),
          name: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                file.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: problem != null ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                problem ?? file.directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: problem != null ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          len: Text(
            file.durationLabel,
            textAlign: TextAlign.right,
            style: kTimecodeStyle.copyWith(color: numberColor),
          ),
          video: twoLines(
            video == null ? null : MediaProbe.codecLabel(video.codec),
            video?.shape,
          ),
          audio: twoLines(
            audio == null ? null : MediaProbe.codecLabel(audio.codec),
            audio?.channels == null ? null : '${audio!.channels}ch',
          ),
          size: Text(
            file.sizeBytes > 0 ? file.sizeLabel : '',
            textAlign: TextAlign.right,
            style: kTimecodeStyle.copyWith(color: cs.onSurfaceVariant),
          ),
          chip: _StateChip(state: state),
          remove: Focus(
            onFocusChange: (v) => setState(() => _focused = v),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered || _focused ? 1 : 0,
              child: IconActionButton(
                icon: Symbols.close,
                tooltip: '移除',
                iconSize: 18,
                onPressed: widget.onRemove,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});

  final StagedVideoState state;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    final (label, icon, bg, fg) = switch (state) {
      StagedVideoState.ready => (
        '就绪',
        Symbols.check,
        ext.successContainer,
        ext.onSuccessContainer,
      ),
      StagedVideoState.probing => (
        '读取中',
        Symbols.progress_activity,
        cs.surfaceContainer,
        cs.onSurfaceVariant,
      ),
      StagedVideoState.incompatible => (
        '不兼容',
        Symbols.block,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
      StagedVideoState.broken => (
        '无法读取',
        Symbols.error,
        cs.errorContainer,
        cs.onErrorContainer,
      ),
    };
    return _Chip(label: label, icon: icon, bg: bg, fg: fg);
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });

  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Align(
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

  final TranscodePageState page;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final form = page._form;
    final o = form.options;
    final footer = form.footer;
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
                  _OutputSection(form: form),
                  if (o.remux)
                    _Section(
                      title: '音视频',
                      children: [
                        _Hint(
                          '不重新编码，原样复制音视频流到新容器，速度快、画质无损；字幕轨不带入',
                        ),
                      ],
                    )
                  else ...[
                    _VideoSection(form: form),
                    _AudioSection(form: form),
                  ],
                  _AdvancedSection(form: form),
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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        footer.icon,
                        size: 16,
                        weight: 400,
                        color: footer.error ? cs.error : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          footer.text,
                          style: context.texts.bodySmall?.copyWith(
                            color: footer.error
                                ? cs.error
                                : cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.s3),
                PrimaryButton(
                  label: '开始转码 · ${form.enqueueable.length}',
                  icon: Symbols.video_settings,
                  onPressed: form.canStart ? page.start : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 参数面板里的一段：16px 内边距，段与段之间 1px 分隔线。
class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.children,
    this.trailing,
    this.first = false,
    this.onTapTitle,
    this.leading,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final bool first;
  final VoidCallback? onTapTitle;
  final IconData? leading;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s4,
        first ? AppSpacing.s1 : AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
      ),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: cs.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onTapTitle,
            behavior: HitTestBehavior.opaque,
            child: MouseRegion(
              cursor: onTapTitle == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: SizedBox(
                height: 24,
                child: Row(
                  children: [
                    if (leading != null) ...[
                      Icon(
                        leading,
                        size: 18,
                        weight: 400,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: AppSpacing.s1),
                    ],
                    Text(
                      title,
                      style: context.texts.titleSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    if (trailing != null) Expanded(child: trailing!),
                  ],
                ),
              ),
            ),
          ),
          for (final child in children) ...[
            const SizedBox(height: AppSpacing.s3),
            child,
          ],
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.error = false});

  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: context.texts.bodySmall?.copyWith(
      color: error ? context.colors.error : context.colors.onSurfaceVariant,
    ),
  );
}

class _OutputSection extends StatelessWidget {
  const _OutputSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    return _Section(
      title: '输出',
      first: true,
      children: [
        LabeledField(
          label: '方式',
          child: SegmentedToggle<TranscodeMode>(
            fill: true,
            value: o.mode,
            segments: [
              for (final m in TranscodeMode.values)
                (value: m, label: m.label, enabled: true),
            ],
            onChanged: (m) => form.update((o) => o.copyWith(mode: m)),
          ),
        ),
        LabeledField(
          label: '容器',
          child: SegmentedToggle<OutputContainer>(
            fill: true,
            value: o.container,
            segments: [
              for (final c in OutputContainer.values)
                (value: c, label: c.label, enabled: true),
            ],
            onChanged: form.setContainer,
          ),
        ),
      ],
    );
  }
}

class _VideoSection extends StatelessWidget {
  const _VideoSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final codec = o.videoCodec;
    final encoder = o.encoder;
    final transcoding = codec != VideoCodec.copy;
    final codecHint = switch (codec) {
      VideoCodec.av1 when o.container == OutputContainer.mov =>
        'MOV 装不下 AV1 视频，换成 MP4',
      VideoCodec.copy => '视频流原样复制，分辨率与帧率不能改',
      _ => null,
    };
    return _Section(
      title: '视频',
      children: [
        LabeledField(
          label: '编码',
          child: SegmentedToggle<VideoCodec>(
            fill: true,
            value: codec,
            segments: [
              for (final c in VideoCodec.values)
                (
                  value: c,
                  label: c.label,
                  enabled: c == VideoCodec.copy || o.container.acceptsVideo(c),
                ),
            ],
            onChanged: form.setVideoCodec,
          ),
        ),
        if (codecHint != null)
          _Hint(codecHint, error: codec != VideoCodec.copy),
        if (transcoding) ...[
          _EncoderList(form: form),
          if (encoder != null) _EncoderParams(form: form, encoder: encoder),
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: '分辨率',
                  child: AppDropdown<ResolutionLimit>(
                    value: o.resolution,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          for (final r in ResolutionLimit.values)
                            DropdownEntry(value: r, label: r.label),
                        ],
                      ),
                    ],
                    onChanged: (r) =>
                        form.update((o) => o.copyWith(resolution: r)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledField(
                  label: '帧率',
                  child: AppDropdown<int?>(
                    value: o.fps,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          const DropdownEntry(value: null, label: '保持原样'),
                          for (final f in TranscodeOptions.frameRates)
                            DropdownEntry(value: f, label: '$f'),
                        ],
                      ),
                    ],
                    onChanged: (f) => form.update((o) => o.copyWith(fps: f)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 编码器卡片列表。不可用的整张 38% 且不可点，右侧说明原因。
class _EncoderList extends StatelessWidget {
  const _EncoderList({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final transcoder = form.transcoder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '编码器',
          style: context.texts.labelMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.s1 + 2),
        for (final (encoder, status) in form.encoderChoices) ...[
          _EncoderCard(
            encoder: encoder,
            status: status,
            selected: encoder.id == form.options.encoderId,
            onTap: () => form.selectEncoder(encoder.id),
          ),
          const SizedBox(height: 6),
        ],
        Row(
          children: [
            QuietButton(
              label: transcoder.isProbing ? '检测中…' : '重新检测',
              icon: Symbols.refresh,
              height: 28,
              onPressed: transcoder.isProbing ? null : transcoder.refresh,
            ),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                '检测方式：对每个硬件编码器试编码 1 帧',
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EncoderCard extends StatelessWidget {
  const _EncoderCard({
    required this.encoder,
    required this.status,
    required this.selected,
    required this.onTap,
  });

  final VideoEncoder encoder;
  final EncoderStatus status;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final ext = context.ext;
    // 设计稿：检测中的卡片不变淡，但要等结果出来才能选。
    final enabled = status.state == EncoderState.available;
    final dimmed = status.state == EncoderState.notCompiled ||
        status.state == EncoderState.failed;
    final (chipBg, chipFg, chipIcon) = switch (status.state) {
      EncoderState.available => (
        ext.successContainer,
        ext.onSuccessContainer,
        Symbols.check,
      ),
      EncoderState.probing => (
        cs.surfaceContainer,
        cs.onSurfaceVariant,
        Symbols.progress_activity,
      ),
      EncoderState.notCompiled => (
        cs.surfaceContainer,
        cs.onSurfaceVariant,
        Symbols.block,
      ),
      EncoderState.failed => (
        cs.errorContainer,
        cs.onErrorContainer,
        Symbols.error,
      ),
    };
    final sub = [
      encoder.id,
      if (encoder.note != null) encoder.note!,
    ].join(' · ');

    final card = Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(12, 4, 10, 4),
      decoration: BoxDecoration(
        color: selected
            ? Color.alphaBlend(
                cs.primary.withValues(alpha: 0.06),
                cs.surfaceContainerLowest,
              )
            : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: selected ? cs.primary : cs.outlineVariant,
        ),
      ),
      child: Row(
        children: [
          _Radio(selected: selected),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(encoder.title, style: context.texts.bodyMedium),
                Text(
                  sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: kTimecodeStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (status.state == EncoderState.failed &&
                    status.reason != null)
                  Text(
                    status.reason!,
                    style: context.texts.bodySmall?.copyWith(color: cs.error),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s2),
          Tooltip(
            message: status.reason ?? '',
            child: _Chip(
              label: status.state.label,
              icon: chipIcon,
              bg: chipBg,
              fg: chipFg,
            ),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: dimmed ? AppStateLayer.disabledContent : 1,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          behavior: HitTestBehavior.opaque,
          child: card,
        ),
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  const _Radio({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? cs.primary : cs.outline,
          width: 2,
        ),
      ),
      child: selected
          ? Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: cs.primary,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );
  }
}

/// 当前编码器自己的参数表。换编码器时整块换掉（key 带上编码器名），
/// 数字框里残留的输入不会串到另一家的同名参数上。
class _EncoderParams extends StatelessWidget {
  const _EncoderParams({required this.form, required this.encoder});

  final TranscodeFormController form;
  final VideoEncoder encoder;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final values = form.options.resolvedParams;
    final visible = encoder.params.where((p) => p.isVisible(values));
    // 设计稿：参数区是一块 surface-container-low 底的圆角块，与上面的编码器
    // 卡片区分开 —— 这一块的内容整个随编码器换。
    return Container(
      key: ValueKey('params-${encoder.id}'),
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppRadius.md + 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('编码器参数', style: context.texts.titleSmall),
              const Spacer(),
              Text(
                encoder.id,
                style: kTimecodeStyle.copyWith(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          for (final param in visible) ...[
            const SizedBox(height: AppSpacing.s3),
            EncoderParamField(
              key: ValueKey('${encoder.id}.${param.key}'),
              param: param,
              value: values[param.key]!,
              onChanged: (v, {bool notify = true}) =>
                  form.setParam(param.key, v, notify: notify),
            ),
          ],
        ],
      ),
    );
  }
}

/// 一项编码器参数的控件：选项少用分段、多用下拉，数值用数字框，开关用 Switch。
class EncoderParamField extends StatelessWidget {
  const EncoderParamField({
    super.key,
    required this.param,
    required this.value,
    required this.onChanged,
  });

  final EncoderParam param;
  final Object value;
  final void Function(Object value, {bool notify}) onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final hint = param.hint;
    final Widget control = switch (param) {
      final ChoiceParam p when p.segmented => SegmentedToggle<String>(
        fill: true,
        value: value as String,
        segments: [
          for (final (v, label) in p.options)
            (value: v, label: label, enabled: true),
        ],
        onChanged: onChanged,
      ),
      final ChoiceParam p => AppDropdown<String>(
        value: value as String,
        menuWidth: 240,
        groups: [
          DropdownGroup(
            entries: [
              for (final (v, label) in p.options)
                DropdownEntry(value: v, label: label),
            ],
          ),
        ],
        onChanged: onChanged,
      ),
      final IntParam p => Row(
        children: [
          NumberField(
            value: value as int,
            min: p.min,
            max: p.max,
            width: 120,
            onChanged: (v) => onChanged(v),
          ),
          const SizedBox(width: AppSpacing.s2),
          Text(
            [
              ?p.unit,
              '${p.min}–${p.max}',
            ].join(' · '),
            style: context.texts.bodySmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
      BoolParam() => const SizedBox.shrink(),
    };

    if (param is BoolParam) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(param.label, style: context.texts.bodyMedium),
                if (hint != null)
                  Text(
                    hint,
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          AppSwitch(value: value as bool, onChanged: onChanged),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LabeledField(label: param.label, child: control),
        if (hint != null) ...[
          const SizedBox(height: AppSpacing.s1),
          _Hint(hint),
        ],
      ],
    );
  }
}

class _AudioSection extends StatelessWidget {
  const _AudioSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final o = form.options;
    final hint = switch (o.audioCodec) {
      AudioCodec.opus when o.container == OutputContainer.mov =>
        'MOV 装不下 Opus，换成 MP4 或 AAC',
      _ when o.container == OutputContainer.mov => 'Opus 放不进 MOV，已禁用',
      _ => null,
    };
    return _Section(
      title: '音频',
      children: [
        LabeledField(
          label: '编码',
          child: SegmentedToggle<AudioCodec>(
            fill: true,
            value: o.audioCodec,
            segments: [
              for (final c in AudioCodec.values)
                (
                  value: c,
                  label: c.label,
                  enabled: c == AudioCodec.copy || o.container.acceptsAudio(c),
                ),
            ],
            onChanged: (c) => form.update((o) => o.copyWith(audioCodec: c)),
          ),
        ),
        if (hint != null)
          _Hint(hint, error: !o.container.acceptsAudio(o.audioCodec)),
        if (o.audioCodec != AudioCodec.copy)
          Row(
            children: [
              Expanded(
                child: LabeledField(
                  label: '码率',
                  child: AppDropdown<int>(
                    value: o.audioBitrate,
                    menuWidth: 200,
                    groups: [
                      DropdownGroup(
                        entries: [
                          for (final b in TranscodeOptions.bitrates)
                            DropdownEntry(value: b, label: '$b kbps'),
                        ],
                      ),
                    ],
                    onChanged: (b) =>
                        form.update((o) => o.copyWith(audioBitrate: b)),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: LabeledField(
                  label: '声道',
                  child: AppDropdown<int?>(
                    value: o.audioChannels,
                    menuWidth: 200,
                    groups: const [
                      DropdownGroup(
                        entries: [
                          DropdownEntry(value: null, label: '保持'),
                          DropdownEntry(value: 2, label: '立体声'),
                          DropdownEntry(value: 1, label: '单声道'),
                        ],
                      ),
                    ],
                    onChanged: (c) =>
                        form.update((o) => o.copyWith(audioChannels: c)),
                  ),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  const _AdvancedSection({required this.form});

  final TranscodeFormController form;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final o = form.options;
    final open = form.advancedOpen;
    final example = form.outputNameFor(
      form.files.firstOrNull?.fileName ?? 'interview_ep12.mkv',
    );
    return _Section(
      title: '高级',
      leading: open ? Symbols.expand_more : Symbols.chevron_right,
      onTapTitle: () => form.advancedOpen = !open,
      trailing: open
          ? null
          : Text(
              form.advancedSummary,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
      children: !open
          ? const []
          : [
              LabeledField(
                label: '输出位置',
                child: Row(
                  children: [
                    Expanded(
                      child: SegmentedToggle<OutputLocation>(
                        fill: true,
                        value: o.outputLocation,
                        segments: [
                          for (final l in OutputLocation.values)
                            (value: l, label: l.label, enabled: true),
                        ],
                        onChanged: (l) {
                          if (l == OutputLocation.custom &&
                              (o.outputDir?.isEmpty ?? true)) {
                            form.pickOutputDir();
                          } else {
                            form.update((o) => o.copyWith(outputLocation: l));
                          }
                        },
                      ),
                    ),
                    if (o.outputLocation == OutputLocation.custom) ...[
                      const SizedBox(width: AppSpacing.s2),
                      QuietButton(label: '选择…', onPressed: form.pickOutputDir),
                    ],
                  ],
                ),
              ),
              if (o.outputLocation == OutputLocation.custom &&
                  o.outputDir != null)
                Text(
                  o.outputDir!,
                  style: kTimecodeStyle.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              LabeledField(
                label: '文件名后缀',
                child: _TextInput(
                  key: const ValueKey('suffix'),
                  value: o.suffix ?? '',
                  hint: o.remux ? 'remux' : o.effectiveVideo.suffix,
                  onChanged: (v) => form.update(
                    (o) => o.copyWith(suffix: v.trim().isEmpty ? null : v),
                  ),
                ),
              ),
              _Hint('写成 $example；同名文件已存在时自动加序号'),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('快速启动（moov 前置）', style: context.texts.bodyMedium),
                        const _Hint('便于网页边下边播'),
                      ],
                    ),
                  ),
                  AppSwitch(
                    value: o.faststart,
                    onChanged: (v) =>
                        form.update((o) => o.copyWith(faststart: v)),
                  ),
                ],
              ),
              LabeledField(
                label: '额外参数',
                child: _TextInput(
                  key: const ValueKey('extra'),
                  value: o.extraArgs,
                  hint: '-x265-params aq-mode=3',
                  mono: true,
                  onChanged: (v) => form.update((o) => o.copyWith(extraArgs: v)),
                ),
              ),
              const _Hint('原样追加在输出文件前，参数错误会在任务日志里看到 FFmpeg 的报错'),
              LabeledField(
                label: '命令预览',
                child: CommandBlock(
                  command: form.commandPreview,
                  maxHeight: 200,
                  onCopy: () {
                    Clipboard.setData(ClipboardData(text: form.commandPreview));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      const SnackBar(content: Text('命令已复制')),
                    );
                  },
                ),
              ),
            ],
    );
  }
}

/// 单行输入。外观同 [ControlSurface]。
class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.value,
    required this.hint,
    required this.onChanged,
    this.mono = false,
  });

  final String value;
  final String hint;
  final ValueChanged<String> onChanged;
  final bool mono;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final _controller = TextEditingController(text: widget.value);
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void didUpdateWidget(_TextInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 「重置为默认」「上次参数」从外面改了值，没在输入时同步进来。
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ControlSurface(
    padding: const EdgeInsets.symmetric(horizontal: 12),
    focused: _focus.hasFocus,
    child: TextField(
      controller: _controller,
      focusNode: _focus,
      style: widget.mono
          ? kTimecodeStyle.copyWith(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: context.colors.onSurface,
            )
          : context.texts.bodyMedium,
      decoration: bareInputDecoration(context, hint: widget.hint),
      onChanged: widget.onChanged,
    ),
  );
}
