import 'package:flutter/material.dart';

import '../../domain/paths.dart';
import '../shared/page_chrome.dart';
import 'editor_controller.dart';
import 'editor_open_page.dart';
import 'editor_page_actions.dart';
import 'editor_session.dart';
import 'editor_title.dart';
import 'editor_workspace.dart';

/// 编辑器分区交给顶栏的内容。入口页盖在上面、或还没有会话时是入口页的顶栏。
///
/// 保存、导出、补翻这几个动作落在编辑页的 State 上，由装配层经 GlobalKey 转交。
PageChrome editorChrome(
  EditorWorkspace workspace, {
  required VoidCallback onSave,
  required VoidCallback onExport,
  required VoidCallback onTranslateMissing,
}) {
  final editor = workspace.current;
  if (editor == null || workspace.showOpen) {
    return editorOpenChrome(
      onBack: editor == null ? null : workspace.backToEditor,
    );
  }
  return PageChrome(
    title: '编辑器',
    subtitle: editorSubtitle(editor),
    titleTrailing: EditorTitleTrailing(
      controller: editor,
      onReplace: workspace.stageReplacement,
      onRepair: workspace.repair,
      onOpenOther: workspace.openOther,
      onSave: onSave,
    ),
    actions: [
      EditorPageActions(
        controller: editor,
        onTranslateMissing: onTranslateMissing,
        onExport: onExport,
        onSave: onSave,
      ),
    ],
  );
}

/// 顶栏副标题。
String editorSubtitle(EditorController controller) {
  final session = controller.session;
  final count = controller.document.cues.length;
  return switch (session) {
    FileSession(:final sourcePath) when !controller.hasTranslations =>
      '${baseName(sourcePath)} · $count 条 · ${session.sourceLanguage.name}',
    _ =>
      '${session.title} · $count 条 · '
          '${session.sourceLanguage.name} → ${session.targetLanguage.name}',
  };
}

/// 状态栏右侧：字幕文件落后多少、正在写、刚写了哪些（画板 1 的表）。
String? editorStatusNote(EditorController controller) => controller.locked
    ? '任务跑完后会写出字幕文件'
    : switch (controller.sync) {
        SyncState.synced => null,
        SyncState.dirty => '字幕文件落后 ${controller.unsavedEdits} 处修改 · ⌘S 写入',
        SyncState.writing => '正在写入…',
        SyncState.written =>
          '已写入 ${controller.justWritten.map(baseName).join('、')}',
        SyncState.failed => '修改仍在编辑进度里，没有丢',
        SyncState.conflict => '保存前会先问怎么处理',
        SyncState.noOutput => '任务没有跑完，字幕文件还没生成 · ⌘S 生成',
      };
