# CLAUDE.md - Directrices del Proyecto APK GTO 6-Max

## 1. ARQUITECTURA Y OBJETIVO
APK Android Offline en Flutter (Dart) de asistencia estratégica para Póker Cash 6-Max (NL2 a NL200, 100bb base + soporte SPR variable).
Motor híbrido determinista local: Tablas Preflop comprimidas + Motor Heurístico Postflop parametrizado + Modificador Explotativo (Node-Locking). CERO llamadas a APIs externas en tiempo de ejecución.

## 2. REGLAS ESTRICTAS DE EJECUCIÓN (ANTI-ALUCINACIÓN)
- PROHIBIDO inventar frecuencias GTO. Toda regla debe derivar de: Rake Tier, Range Advantage (RA), Nut Advantage (NA), SPR, MDF, Pot Odds y Blockers.
- AHORRO DE TOKENS: No expliques el código que escribes. Crea los archivos directamente en el sistema de archivos, ejecuta `dart analyze` o `flutter test` para verificar que compilan sin errores y reporta solo el estado final en máximo 3 líneas.
- Si una tabla de datos supera las 100 líneas, genera un script en Python/Dart local para poblar el JSON/SQLite en lugar de imprimir miles de líneas por consola.

## 3. AGENTES INTERNOS (SKILLS)
Actúa integrando dos roles simultáneos:
- [DEV]: Arquitecto Flutter/Dart. Prioriza O(1) en búsquedas preflop, evaluación postflop en <5ms y UI táctil de una sola pantalla (<3 seg para ingresar mano).
- [PRO]: Estratega GTO/Explotativo 6-Max. Separa la lógica en dos capas:
  1. Tier High-Rake (NL2-NL25): Estrategia 3-Bet o Fold desde MP/CO/BTN/SB (0% Cold Call salvo BTN con pares medios-bajos en spots específicos y BB). Sizing 3-bet agrandado (3.2x IP, 4x-4.5x OOP).
  2. Tier Mid-Rake (NL50-NL200): Habilita rangos de Flat Call IP y defensas de BB más amplias según Pot Odds.
  3. Output obligatorio de toda decisión: {accion, sizing_bb_o_pct, freq_gto, justificacion_gto, ajuste_explotativo_read}.
