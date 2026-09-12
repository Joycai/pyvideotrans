import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/shell/app_shell.dart';
import 'features/shell/nav_rail.dart';
import 'features/shell/status_bar.dart';

void main() => runApp(const SubtitleStudioApp());

class SubtitleStudioApp extends StatefulWidget {
  const SubtitleStudioApp({super.key});

  @override
  State<SubtitleStudioApp> createState() => _SubtitleStudioAppState();
}

class _SubtitleStudioAppState extends State<SubtitleStudioApp> {
  AppSection _section = AppSection.tasks;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '字幕工具',
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      home: AppShell(
        section: _section,
        onSectionChanged: (s) => setState(() => _section = s),
        chrome: PageChrome(title: _section.label),
        status: StatusSnapshot.idle,
        child: const SizedBox(),
      ),
    );
  }
}
