import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';

void main() => runApp(const SubtitleStudioApp());

class SubtitleStudioApp extends StatelessWidget {
  const SubtitleStudioApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '字幕工具',
    debugShowCheckedModeBanner: false,
    theme: lightTheme,
    darkTheme: darkTheme,
    home: const Scaffold(body: Center(child: Text('字幕工具'))),
  );
}
