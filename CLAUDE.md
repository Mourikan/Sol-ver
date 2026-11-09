# CLAUDE.md - Directrices del Proyecto APK GTO 6-Max

## 1. ARQUITECTURA DE MAXIMIZACIÓN DE EV ACOTADA (BOUNDED-GTO + SAFE EXPLOIT)
APK Android Offline en Flutter (Dart) para Póker Cash 6-Max (NL2 a NL200, 100bb base + SPR variable). Motor determinista local (tablas preflop + heurística postflop + node-locking). CERO llamadas externas en runtime.
1. **Prioridad Absoluta (+EV):** El motor opera sobre una línea base GTO inquebrantable (MDF, Pot Odds con Rake Final Esperado, Conteo Real de Combos) y solo desvía las frecuencias cuando el EV de la explotación supera al EV del equilibrio sin exponer fugas masivas.
2. **Prohibición de Multiplicadores Ciegos:** Prohibido apilar penalizaciones multiplicativas sin piso (`floor`). Todo ajuste por MDA, Timing o Read opera sobre el conteo real de combos del `RangeFunnel`.
3. **Filtro de Cordura (`EV_Sanity_Guard`):** Ninguna heurística puede emitir una jugada -EV evidente: prohibido pagar 5-bet shoves de 100bb con `A5s` (es 4-bet bluff, no call-off), prohibido farolear River vs `CallingStation/Fish`, prohibido c-betear aire vs `Trapper_Limp_Reraiser`, prohibido foldear `Sets/Nut-Draws` en Turn o vs `Agro/Maniac`.
4. **Arquitectura de defensa:** Flop/Turn = `DefenseBudget` (top `MDF x Exploit_Defense_Factor` del rango que llega al nodo: 1.0 Reg/GTO, 1.15 Agro, 0.82 Passive/Scared <=NL50). River = `Bluff_Combo_Audit` por combos reales. Implementación en `lib/core/postflop/defense_budget.dart` y `lib/core/discipline/`.

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

## 4. SKILL ELITE: [DISCIPLINE_AND_MDA_ENGINE]
- **Leyes de Mass Data Analysis (MDA) por Nivel:**
  - En NL2-NL50, las líneas de `River Raise`, `Turn Check-Raise` y `Triple Barrel Overbet` del pool general están sub-faroleadas entre un 12% y un 18% respecto al GTO. Por defecto, todos los `Pure Bluff-Catchers` (1 par o dobles bajas en boards dinámicos) tienen EV negativo (-EV) en esos nodos salvo que exista un `Read = Agro_Spewy` o un sobre-conteo explícito de faroles rotos.
- **Regla de Oro de Disciplina (Anti-Inmolación):** Prohibido recomendar un Call en Turn/River basándose únicamente en la fuerza absoluta de la mano de Hero (ej. Overpair AA/KK o Top Pair) o en MDF teórico ciego. Todo Call de River pasa por `Bluff_Combo_Audit` (combos reales); en Turn el filtro es `DefenseBudget`. Con `Agro_Spewy/Maniac` el piso aditivo `max(ratio x 1.4, pot odds + 5%)` desactiva hero folds forzados con TwoPair+/TopPair fuerte.
- Implementación: `lib/core/discipline/` (`bluff_catch_auditor.dart`, `blocker_bluff_converter.dart`, `timing_tells_matrix.dart`). Los porcentajes MDA/timing son priors poblacionales declarados por el usuario (constantes explícitas), no frecuencias de solver.
