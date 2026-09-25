import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/app_extensions.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/dashed_border.dart';

/// 文件表里文件名与移除按钮之间的一列定宽列。
class FileTableColumn {
  const FileTableColumn(
    this.label,
    this.width, {
    this.alignEnd = false,
    this.minRowWidth = 0,
  });

  final String label;
  final double width;

  /// 表头文字靠右，跟数字列的单元格对齐。单元格自己的对齐由各页给。
  final bool alignEnd;

  /// 行宽（扣掉左右内边距）低于这个值时整列收起：窄窗口先让出次要列。
  final double minRowWidth;
}

/// 文件表的一行：图标、文件名 + 目录（有问题时换成问题说明）、各列单元格、移除。
class FileTableEntry {
  const FileTableEntry({
    required this.icon,
    required this.fileName,
    required this.directory,
    required this.cells,
    required this.onRemove,
    this.problem,
  });

  final IconData icon;
  final String fileName;
  final String directory;

  /// 为什么这个文件会被跳过；非 null 时文件名变灰、目录那行换成它并用 error 色。
  final String? problem;

  /// 与 [NewTaskFileTable.columns] 一一对应。
  final List<Widget> cells;
  final VoidCallback onRemove;
}

/// 建任务页左列有文件时的正文：带表头的文件表、参数说明、底部的追加落区。
///
/// 表格随行数长高，放不下时在表内滚动；说明与落区之间留弹性空白，落区始终贴底。
/// 列宽固定为 图标 36 | 文件名 自适应 | [columns] | 移除 36，间距 12。
class NewTaskFileTable extends StatelessWidget {
  const NewTaskFileTable({
    super.key,
    required this.columns,
    required this.entries,
    required this.applyNote,
    required this.appendIcon,
    required this.dragging,
  });

  final List<FileTableColumn> columns;
  final List<FileTableEntry> entries;

  /// 表格下方那行说明：参数怎么应用、会建几个任务。
  final String applyNote;

  /// 追加落区里的图标，与本页接收的文件类型一致。
  final IconData appendIcon;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
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
                _HeaderRow(columns: columns),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      for (final entry in entries)
                        _FileRow(columns: columns, entry: entry),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s3),
        Text(
          applyNote,
          style: context.texts.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
        const Spacer(),
        const SizedBox(height: AppSpacing.s3),
        FileAppendStrip(icon: appendIcon, dragging: dragging),
      ],
    );
  }
}

/// 文件表底部 44px 的虚线落区：提示还能继续拖入，拖放中描边转 primary。
class FileAppendStrip extends StatelessWidget {
  const FileAppendStrip({
    super.key,
    required this.icon,
    required this.dragging,
  });

  final IconData icon;
  final bool dragging;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SizedBox(
      height: 44,
      child: CustomPaint(
        painter: DashedBorder(
          color: dragging ? cs.primary : cs.outline,
          radius: AppRadius.md,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, weight: 400, color: cs.onSurfaceVariant),
            const SizedBox(width: AppSpacing.s2),
            Text(
              dragging ? '松开以添加文件' : '继续拖入可追加文件',
              style: context.texts.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const _kIconWidth = 36.0;
const _kRemoveWidth = 36.0;

/// 表头与数据行共用的列排布，按行宽收起 [FileTableColumn.minRowWidth] 不够的列。
class _Cols extends StatelessWidget {
  const _Cols({
    required this.columns,
    required this.icon,
    required this.name,
    required this.cells,
    required this.remove,
  });

  final List<FileTableColumn> columns;
  final Widget icon, name, remove;
  final List<Widget> cells;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = SizedBox(width: AppSpacing.s3);
        return Row(
          children: [
            SizedBox(width: _kIconWidth, child: icon),
            gap,
            Expanded(child: name),
            for (var i = 0; i < columns.length; i++)
              if (c.maxWidth >= columns[i].minRowWidth) ...[
                gap,
                SizedBox(width: columns[i].width, child: cells[i]),
              ],
            gap,
            SizedBox(width: _kRemoveWidth, child: remove),
          ],
        );
      },
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.columns});

  final List<FileTableColumn> columns;

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
      child: _Cols(
        columns: columns,
        icon: const SizedBox(),
        name: Text('文件', style: style),
        cells: [
          for (final col in columns)
            Text(
              col.label,
              textAlign: col.alignEnd ? TextAlign.right : null,
              style: style,
            ),
        ],
        remove: const SizedBox(),
      ),
    );
  }
}

class _FileRow extends StatefulWidget {
  const _FileRow({required this.columns, required this.entry});

  final List<FileTableColumn> columns;
  final FileTableEntry entry;

  @override
  State<_FileRow> createState() => _FileRowState();
}

class _FileRowState extends State<_FileRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final entry = widget.entry;
    final problem = entry.problem;
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
          columns: widget.columns,
          icon: Container(
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.sm + 2),
            ),
            child: Icon(
              entry.icon,
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
                entry.fileName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                  color: problem != null ? cs.onSurfaceVariant : cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                problem ?? entry.directory,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.texts.bodySmall?.copyWith(
                  color: problem != null ? cs.error : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
          cells: entry.cells,
          // 平时隐藏，悬停或键盘焦点落到按钮上时淡入。
          remove: Focus(
            onFocusChange: (v) => setState(() => _focused = v),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              opacity: _hovered || _focused ? 1 : 0,
              child: IconActionButton(
                icon: Symbols.close,
                tooltip: '移除',
                iconSize: 18,
                onPressed: entry.onRemove,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
