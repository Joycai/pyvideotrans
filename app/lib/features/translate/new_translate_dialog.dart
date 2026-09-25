import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../core/widgets/text_focus.dart';
import '../../domain/numbers.dart';
import '../../domain/srt.dart';
import '../../services/media.dart';
import '../../services/settings.dart';
import '../shared/enqueue_request.dart';
import 'translate_advanced_section.dart';
import 'translate_footer.dart';
import 'translate_form.dart';
import 'translate_language_section.dart';

export '../shared/enqueue_request.dart';

/// 「新建翻译」对话框。
///
/// 与「新建转写」同构，少了「识别」那一段 —— 输入本来就是字幕，不需要识别；
/// 也没有「转写完成后继续翻译」开关，翻译是它的全部。确认后任务进同一个队列、
/// 同一条六阶段流水线，识别与断句两阶段标记为「已跳过」。
///
/// 表单状态、校验与文案都在 [TranslateFormController] 里，与导航栏的
/// 「翻译」页共用；这里只负责对话框的外形与关闭时机。
Future<EnqueueRequest?> showNewTranslateDialog(
  BuildContext context, {
  required AppSettings settings,
  List<String> initialPaths = const [],
  Media? media,
  VoidCallback? onOpenSettings,
  ValueChanged<List<String>>? onSwitchToTranscribe,
}) => showDialog<EnqueueRequest>(
  context: context,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
  builder: (_) => NewTranslateDialog(
    settings: settings,
    initialPaths: initialPaths,
    media: media,
    onOpenSettings: onOpenSettings,
    onSwitchToTranscribe: onSwitchToTranscribe,
  ),
);

class NewTranslateDialog extends StatefulWidget {
  const NewTranslateDialog({
    super.key,
    required this.settings,
    this.initialPaths = const [],
    this.media,
    this.onOpenSettings,
    this.onSwitchToTranscribe,
  });

  final AppSettings settings;
  final List<String> initialPaths;
  final Media? media;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字。
  final VoidCallback? onOpenSettings;

  /// 用户把音视频拖错了门：关掉这个对话框，把这些文件交给「新建转写」。
  final ValueChanged<List<String>>? onSwitchToTranscribe;

  @override
  State<NewTranslateDialog> createState() => NewTranslateDialogState();
}

class NewTranslateDialogState extends State<NewTranslateDialog> {
  late final _form = TranslateFormController(
    settings: widget.settings,
    media: widget.media,
  );

  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _form.addListener(_refresh);
    _form.seed(widget.initialPaths);
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  /// 落下一批路径。拖放本身要真实的平台事件才能触发，所以这里留个入口
  /// 给测试直接调用。
  @visibleForTesting
  void handleDrop(List<String> paths) {
    setState(() => _dragging = false);
    _form.handleDrop(paths);
  }

  void _switchToTranscribe() {
    final media = _form.takeIgnoredMedia();
    Navigator.of(context).pop();
    widget.onSwitchToTranscribe?.call(media);
  }

  void _start() {
    final result = _form.submit();
    if (result == null) return;
    Navigator.of(context).pop(result);
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText => isEditingText(multiline: true);

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (!_editingText) _start();
        },
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): _start,
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _start,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: DropTarget(
            onDragEntered: (_) => setState(() => _dragging = true),
            onDragExited: (_) => setState(() => _dragging = false),
            onDragDone: (d) => handleDrop(d.files.map((f) => f.path).toList()),
            child: GlassPanel(
              strong: true,
              expand: false,
              radius: AppRadius.xl,
              shadow: context.elevation.shadow3,
              child: SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(cs),
                    // 内容区最高 640，再长就在对话框内部滚动 —— 标题与底部
                    // 那行校验必须始终看得见，否则用户不知道为什么不能开始。
                    Flexible(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 640),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s6,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _fileArea(),
                              const SizedBox(height: AppSpacing.s4),
                              TranslateLanguageSection(
                                form: _form,
                                onOpenSettings: widget.onOpenSettings == null
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        widget.onOpenSettings!();
                                      },
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              TranslateAdvancedSection(form: _form),
                            ],
                          ),
                        ),
                      ),
                    ),
                    _footerBar(cs),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(ColorScheme cs) => Padding(
    padding: const EdgeInsets.fromLTRB(
      AppSpacing.s6,
      22,
      AppSpacing.s6,
      AppSpacing.s4,
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('新建翻译', style: context.texts.titleLarge),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '把字幕文件翻译成目标语言',
                style: context.texts.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconActionButton(
          icon: Symbols.close,
          tooltip: '关闭（Esc）',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );

  // —— 文件区 ————————————————————————————————————————————

  Widget _fileArea() => _form.files.isEmpty ? _emptyDropZone() : _fileList();

  Widget? get _ignoredNote {
    final note = _form.ignoredNote;
    if (note == null) return null;
    return IgnoredMediaNote(
      text: note,
      onSwitchToTranscribe: widget.onSwitchToTranscribe == null
          ? null
          : _switchToTranscribe,
    );
  }

  Widget _emptyDropZone() {
    final cs = context.colors;
    final note = _ignoredNote;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 只拖了音视频进来时列表是空的，但得知道文件去了哪儿。
          if (note != null) ...[note, const SizedBox(height: AppSpacing.s3)],
          AnimatedContainer(
            duration: AppDuration.medium,
            curve: AppEasing.standard,
            height: 136,
            decoration: BoxDecoration(
              color: _dragging ? cs.primary.withValues(alpha: 0.08) : null,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _dragging ? cs.primary : cs.outline,
                width: _dragging ? 2 : 1,
                strokeAlign: BorderSide.strokeAlignInside,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Symbols.subtitles,
                  size: 32,
                  weight: 400,
                  color: _dragging ? cs.primary : cs.onSurfaceVariant,
                ),
                const SizedBox(height: AppSpacing.s1 + 2),
                Text(
                  // 桌面拖放在进入窗口时只有位置、拿不到文件列表，所以不写数量。
                  _dragging ? '松开以添加文件' : '把字幕文件拖到这里',
                  style: context.texts.titleSmall?.copyWith(
                    color: _dragging ? cs.primary : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.s1 + 2),
                Text(
                  _dragging
                      ? '非字幕文件会被忽略，音视频请用「新建转写」'
                      : '支持 SRT、VTT、ASS、SSA，可一次选多个',
                  style: context.texts.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                if (!_dragging) ...[
                  const SizedBox(height: AppSpacing.s1 + 2),
                  QuietButton(
                    label: '选择文件…',
                    height: 32,
                    onPressed: _form.browse,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fileList() {
    final cs = context.colors;
    final files = _form.files;
    final broken = _form.brokenCount;
    final note = _ignoredNote;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.s1),
              child: note,
            ),
          SizedBox(
            height: 32,
            child: Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      broken == 0
                          ? '已选 ${files.length} 个文件'
                          : '已选 ${files.length} 个文件，其中 $broken 个无法解析',
                      style: context.texts.labelMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  QuietButton(
                    label: '添加文件…',
                    icon: Symbols.add,
                    height: 28,
                    onPressed: _form.browse,
                  ),
                ],
              ),
            ),
          ),
          for (final file in files)
            _FileRow(file: file, onRemove: () => _form.remove(file)),
        ],
      ),
    );
  }

  // —— 底栏 ——————————————————————————————————————————————

  Widget _footerBar(ColorScheme cs) => Container(
    margin: const EdgeInsets.only(top: AppSpacing.s4),
    padding: const EdgeInsets.fromLTRB(AppSpacing.s6, 14, AppSpacing.s6, 18),
    decoration: BoxDecoration(
      border: Border(top: BorderSide(color: cs.outlineVariant)),
    ),
    child: Row(
      children: [
        Expanded(
          child: TranslateFooterLine(form: _form, line: _form.compactFooter),
        ),
        const SizedBox(width: AppSpacing.s4),
        ControlButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s2),
        TranslateStartButton(form: _form, onStart: _start),
      ],
    ),
  );
}

/// 文件列表的一行：文件名 + 「条数 · 时间跨度 · 大小」。
///
/// 解析不出内容的文件留在列表里，用 error 色写明会被跳过 —— 直接不收下
/// 会让用户以为自己没拖进来，反复再拖一次。
class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final StagedSubtitle file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final info = file.info;
    final broken = file.state == StagedSubtitleState.broken;
    final metaColor = broken ? cs.error : cs.onSurfaceVariant;
    final meta = switch (file.state) {
      StagedSubtitleState.parsing => '解析中…',
      StagedSubtitleState.broken => '无法解析，将跳过',
      StagedSubtitleState.ready => [
        '${grouped(info?.cueCount ?? 0)} 条',
        if (info?.duration != null) Srt.formatDuration(info!.duration!),
        info?.sizeLabel ?? '',
      ].join(' · '),
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.s3, 6, AppSpacing.s2, 6),
        child: Row(
          children: [
            Icon(
              broken ? Symbols.subtitles_off : Symbols.subtitles,
              size: 20,
              weight: 400,
              color: broken ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    file.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.texts.bodySmall?.copyWith(color: metaColor),
                  ),
                ],
              ),
            ),
            IconActionButton(
              icon: Symbols.close,
              tooltip: '移除',
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
