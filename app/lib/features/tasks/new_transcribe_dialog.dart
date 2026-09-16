import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/glass_panel.dart';
import '../../domain/srt.dart';
import '../../services/media.dart';
import '../../services/settings.dart';
import 'transcribe_advanced_section.dart';
import 'transcribe_footer.dart';
import 'transcribe_form.dart';
import 'transcribe_recognize_section.dart';
import 'transcribe_translate_section.dart';

export 'transcribe_form.dart' show NewTranscribeResult;

/// 「新建转写」对话框。
///
/// 只负责收集参数，**不跑任务也不显示进度** —— 点「开始转写」立即入队并关闭，
/// 进度归任务页。原 Python 实现把识别过程跑在同一个窗口里，于是那个窗口既是
/// 表单又是控制台，两件事互相挡着。
///
/// 表单状态与三段字段在 [TranscribeFormController] 及配套的 Section 里，
/// 与导航栏的「新建转写」页共用；这里只负责对话框的壳、文件区与底栏。
Future<NewTranscribeResult?> showNewTranscribeDialog(
  BuildContext context, {
  required AppSettings settings,
  List<String> initialPaths = const [],
  Media? media,
  VoidCallback? onOpenSettings,
}) => showDialog<NewTranscribeResult>(
  context: context,
  barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32),
  builder: (_) => NewTranscribeDialog(
    settings: settings,
    initialPaths: initialPaths,
    media: media,
    onOpenSettings: onOpenSettings,
  ),
);

class NewTranscribeDialog extends StatefulWidget {
  const NewTranscribeDialog({
    super.key,
    required this.settings,
    this.initialPaths = const [],
    this.media,
    this.onOpenSettings,
  });

  final AppSettings settings;
  final List<String> initialPaths;
  final Media? media;

  /// 缺密钥时那个「去设置」。为 null 就只显示文字 —— 宁可不给链接，
  /// 也不要给一个点了没反应的链接。
  final VoidCallback? onOpenSettings;

  @override
  State<NewTranscribeDialog> createState() => NewTranscribeDialogState();
}

class NewTranscribeDialogState extends State<NewTranscribeDialog> {
  late final _form = TranscribeFormController(
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

  void _start() {
    final result = _form.submit();
    if (result != null) Navigator.of(context).pop(result);
  }

  /// 多行输入框里的回车是换行，不该把任务提交出去。
  bool get _editingText =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

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
            onDragDone: (d) =>
                handleDrop(d.files.map((f) => f.path).toList()),
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
                              TranscribeRecognizeSection(
                                form: _form,
                                onOpenSettings: widget.onOpenSettings == null
                                    ? null
                                    : () {
                                        Navigator.of(context).pop();
                                        widget.onOpenSettings!();
                                      },
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              TranscribeTranslateSection(form: _form),
                              const SizedBox(height: AppSpacing.s4),
                              TranscribeAdvancedSection(form: _form),
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
              Text('新建转写', style: context.texts.titleLarge),
              const SizedBox(height: AppSpacing.s1),
              Text(
                '从音视频生成字幕，可接着翻译',
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

  Widget _emptyDropZone() {
    final cs = context.colors;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: AnimatedContainer(
        duration: AppDuration.medium,
        curve: kEasingStandard,
        height: 136,
        decoration: BoxDecoration(
          color: _dragging ? cs.primary.withValues(alpha: 0.06) : null,
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
              Symbols.upload_file,
              size: 32,
              weight: 400,
              color: _dragging ? cs.primary : cs.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              _dragging ? '松开以添加文件' : '把音视频文件拖到这里',
              style: context.texts.titleSmall,
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            Text(
              'mp4 · mov · mkv · mp3 · m4a · wav，可一次选多个',
              style: context.texts.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s1 + 2),
            QuietButton(label: '选择文件…', height: 32, onPressed: _form.browse),
          ],
        ),
      ),
    );
  }

  Widget _fileList() {
    final cs = context.colors;
    final files = _form.files;
    return ContentPanel(
      padding: const EdgeInsets.all(AppSpacing.s2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final file in files)
            _FileRow(file: file, onRemove: () => _form.remove(file)),
          const SizedBox(height: AppSpacing.s1),
          Container(height: 1, color: cs.outlineVariant),
          SizedBox(
            height: 40,
            child: Row(
              children: [
                QuietButton(
                  label: '添加文件…',
                  icon: Symbols.add,
                  height: 28,
                  onPressed: _form.browse,
                ),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Text(
                    files.length > 1
                        ? '共 ${files.length} 个文件，以下参数统一应用到每个文件'
                        : '再拖入文件可继续添加',
                    style: context.texts.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
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
        Expanded(child: TranscribeFooterLine(form: _form)),
        const SizedBox(width: AppSpacing.s4),
        ControlButton(
          label: '取消',
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: AppSpacing.s2),
        TranscribeStartButton(form: _form, onStart: _start),
      ],
    ),
  );
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, required this.onRemove});

  final StagedFile file;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final info = file.info;
    final unreadable = file.state == StagedFileState.unreadable;
    return SizedBox(
      height: 48,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.s3, right: AppSpacing.s2),
        child: Row(
          children: [
            Icon(
              unreadable
                  ? Symbols.error
                  : file.isVideo
                  ? Symbols.movie
                  : Symbols.audio_file,
              size: 20,
              weight: 400,
              color: unreadable ? cs.error : cs.onSurfaceVariant,
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Expanded(
              child: Text(
                file.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: unreadable ? cs.onSurfaceVariant : null,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            Text(
              unreadable
                  ? '无法读取，将跳过'
                  : info?.duration == null
                  ? '—'
                  : Srt.formatDuration(info!.duration!),
              style: kTimecodeStyle.copyWith(
                color: unreadable ? cs.error : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: AppSpacing.s2 + 2),
            SizedBox(
              width: 64,
              child: Text(
                info?.sizeLabel ?? '',
                textAlign: TextAlign.right,
                style: context.texts.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
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
