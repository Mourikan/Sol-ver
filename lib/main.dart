import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/packed_lookup_repository.dart';
import 'ui/screens/solver_cockpit_screen.dart';
import 'ui/theme.dart';

void main() {
  // Tablas O(1) empaquetadas en memoria antes del primer frame.
  PackedLookupRepository.instance;
  WidgetsFlutterBinding.ensureInitialized();
  // Idea A: modo inmersivo (oculta barras del sistema Android, +espacio vertical).
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const SolVerApp());
}

class SolVerApp extends StatelessWidget {
  const SolVerApp({super.key});

  @override
  Widget build(BuildContext context) =>
      MaterialApp(title: 'Sol-ver 6-Max', debugShowCheckedModeBanner: false, theme: buildTheme(), home: const SolverCockpitScreen());
}
