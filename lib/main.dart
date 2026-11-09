import 'package:flutter/material.dart';

import 'ui/poker_table_screen.dart';
import 'ui/theme.dart';

void main() => runApp(const SolVerApp());

class SolVerApp extends StatelessWidget {
  const SolVerApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Sol-ver 6-Max',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const PokerTableScreen(),
      );
}
