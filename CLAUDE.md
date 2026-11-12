# CLAUDE.md - Directrices del Proyecto APK GTO 6-Max

## 0. SKILL OBLIGATORIA: [ZERO_BLOAT_TOKEN_MISER] (aplica a todos los turnos)
- `Rule_1_No_Full_Reads`: prohibido leer archivos > 80 líneas completos; usar `grep -n` y rangos exactos solo ante fallos de compilación/test.
- `Rule_2_Zero_Chat_Prose`: prohibido imprimir explicaciones, tablas o código en el chat; todo reporte va a un `.md` generado por script.
- `Rule_3_Console_Cap`: la salida en terminal no supera 6 líneas + `[GASTO TURNO]`.

## 1. ARQUITECTURA DE MAXIMIZACIÓN DE EV ACOTADA (BOUNDED-GTO + SAFE EXPLOIT)
APK Android Offline en Flutter (Dart) para Póker Cash 6-Max (NL2 a NL200, 100bb base + SPR variable). Motor determinista local (tablas preflop + heurística postflop + node-locking). CERO llamadas externas en runtime.
1. **Prioridad Absoluta (+EV):** El motor opera sobre una línea base GTO inquebrantable (MDF, Pot Odds con Rake Final Esperado, Conteo Real de Combos) y solo desvía las frecuencias cuando el EV de la explotación supera al EV del equilibrio sin exponer fugas masivas.
2. **Prohibición de Multiplicadores Ciegos:** Prohibido apilar penalizaciones multiplicativas sin piso (`floor`). Todo ajuste por MDA, Timing o Read opera sobre el conteo real de combos del `RangeFunnel`.
3. **Filtro de Cordura (`EV_Sanity_Guard`):** Ninguna heurística puede emitir una jugada -EV evidente: prohibido pagar 5-bet shoves de 100bb con `A5s` (es 4-bet bluff, no call-off), prohibido farolear River vs `CallingStation/Fish`, prohibido c-betear aire vs `Trapper_Limp_Reraiser`, prohibido foldear `Sets/Nut-Draws` en Turn o vs `Agro/Maniac`.
4. **Arquitectura de defensa:** Flop/Turn = `DefenseBudget` (top `MDF x Exploit_Defense_Factor` del rango que llega al nodo: 1.0 Reg/GTO, 1.18 Agro/Maniac, 0.82 Passive/Scared <=NL50). River = `Bluff_Combo_Audit` por combos reales. Implementación en `lib/core/postflop/defense_budget.dart` y `lib/core/discipline/`.

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

## 5. LÍMITES PERMANENTES DEL PROYECTO
**LO QUE NO HACEMOS (PROHIBIDO):**
1. Prohibido implementar `Hand History Tracker` / registro de sesiones o logs persistentes de manos.
2. Prohibido tocar o generar código de UI mientras se audita o calibra `lib/core/`.
3. Prohibido usar multiplicadores en cascada sin piso (`floor`) o estrategias 100% puras sin `freq_gto`.
4. Prohibido imprimir bloques de código o explicaciones largas en el chat.

**LO QUE SÍ HACEMOS (OBLIGATORIO):**
1. Maximización de EV Acotada (`Bounded-GTO + Safe Exploit`) con validación por `EV_Sanity_Guard` y puerta de EV (`[EV_GATE]`, solo des-escala apuestas propias -EV; los calls quedan bajo MDF).
2. Persistencia en memoria `O(1)` (`< 0.5ms` por consulta).
3. Cobertura exacta de los 7 Stakes: `NL2, NL5, NL10, NL25` (High-Rake, caps en bb por stake en `RakeConfig.byStake`) y `NL50, NL100, NL200` (Mid/Low-Rake). Los caps son plantilla editable, no datos de una sala concreta.

## 6. SKILL INTERNA: [TOKEN_SAVER_AND_TELEMETRY]
- Comprime toda salida de consola a máximo 6 líneas.
- Al final de CADA respuesta en el chat añade una línea de telemetría estimada (`Chars / 3.8`, aproximada; no es facturación):
  `[TELEMETRÍA TOKENS | In_Est: ~X tok | Out_Est: ~Y tok | Tip: usa /cost para facturación exacta API]`.

## 7. SKILL INTERNA: [COST_AND_REGRESSION_GUARD]
- **Gasto por mensaje:** al final de CADA respuesta, una única línea con tokens estimados (`Chars / 3.8`) y costo estimado en USD
  (`Sonnet: In*$0.000003 + Out*$0.000015` | `Opus: In*$0.000015 + Out*$0.000075`; tarifas declaradas por el usuario, estimación):
  `[GASTO TURNO | ~In: X tok / ~Out: Y tok | Costo Est: $0.XXXX USD (Sonnet) / $0.YYYY USD (Opus) | Exacto: /cost]`
- **Protocolo Zero-Break:** prohibido alterar firmas públicas o romper los checks de `docs/deep_engine_ev_audit.md`
  (Preflop_Tree 11/11, Flop_Buckets 7/7, Turn_River_Solver 7/7, Range_Funnel 5/5, Discipline_Auditor 1/1, EV_Calculator 3/3, Coverage 10/10).
  Antes de cerrar cualquier cambio: `flutter test` + todos los scripts de `docs/audit_scripts/`.

## 8. SKILL INTERNA: [NASH_DELTA_AND_POOL_EDGE_HUNTER]
**Targets teóricos (`F_GTO`) usados por `docs/audit_scripts/cold_numbers_benchmark.dart`:**
1. `Preflop BB Defense`: prohibido comparar contra MDF bruto (37.5%). Target = `GTO_Solver_Benchmark` declarado por el usuario
   (vs BTN 2.5x: 53.0% Mid / 48.0% High; vs CO 2.5x: 44.0%). No verificado contra exports de solver en este repo.
2. `Preflop 3-Bet Polar Bluff Share`: α del 3-bet (B/(P+2B)); BTN vs CO ≈ 34.5-36.5%.
3. `Turn Barrel Bluff Share`: presupuesto geométrico de 2 calles `1 - (1 - α_turn)(1 - α_river)` (≈51% con 75%/75%).
   Nota: la variante `α_t + (1-α_t)·α_r·0.65` da ≈43.7%, no 48%; se usa la forma geométrica.
4. `River Bluff Share por sizing`: estricto `α = B/(P+2B)`; 33% (thin/block) => 19.9% (cuota propia sobre TODO el valor fino, nunca > 22%); 125% => 35.7%.
**Protocolo Dual:** Modo GTO (vs Reg_GTO) exige `Δ Nash <= 3.5%` por calle. Modo Exploit: `Δ Exploit = |Freq_Motor - Freq_GTO|` y
demostración `EV_Exploit(bb) > EV_GTO(bb)` por spot con `ActionEVCalculator` bajo el perfil asumido.
**Prohibido** publicar winrates bb/100 o $/manos sin datos reales de frecuencia de spots y del pool: solo métricas derivables (rake por bote, EV por spot).

## 9. SKILL INTERNA: [ASYMMETRIC_EXPLOIT_AND_NASH_ANCHOR]
Arquitectura de decisión en 2 capas. Origen de datos internos: `RangeSource.calibratedHeuristicBase` (no exports de solver).
- **CAPA 1 — ANCLA NASH (`GTO_Baseline`, inmutable):** siempre se calcula en segundo plano la decisión vs `Reg_GTO` (MDF, α geométrico, EV_GTO en bb). Referencia de seguridad: `Δ Nash <= 2.5%` en `cold_numbers_benchmark.dart` (modo Reg_GTO).
- **CAPA 2 — EXPLOTACIÓN ASIMÉTRICA (`Default_Engine_Mode = FULL_EXPLOIT`):** sin lectura individual, la capa de aplicación usa `Pool_Exploit_Default` (= `poolDefault` en NL2-NL25 con priors de `mda_consensus_db.dart`; `Reg_GTO`/Unknown_Reg en NL50-NL200 sin HUD, con `Anti_Counter_Exploit_Shield` activo). `Reg_GTO` puro solo cuando el usuario etiqueta al rival como `Reg_GTO / Bot`. El API de `lib/core/` mantiene `gtoBase` como valor por defecto (contrato estable de tests y auditorías).
  1. **Over-Folder** (`Pool_Turn_Barrel`, `Scared_Capped`, `Nit_Blind_Defense`, `Insta_Check_Turn`): `Exploit_Bluff_Factor` acotado a [1.6, 2.2]; `Redline_Auto_Profit_Bet` solo si `FE_pool > α_sizing` y `EV(bet) > EV(check)`.
  2. **Under-Bluffer** (`Pool_River_Raise`, `Pool_Triple_Barrel_NL2_NL50`, `Rec_Pot_Donk`, `Trapper_Limp_3Bet`): `MDF_Override = OFF` => `Disciplined_Overfold` de bluff-catchers puros (1 par / overpair sin redraw).
  3. **Inelastic-Caller** (`Fish / CallingStation`): `River_Bluff_Freq = 0%`; thin value expandido; `Greedy_Value_Sizing` 80-125% con TopPair_GoodKicker+.
- Toda desviación expone `DecisionOutput.exploitDeltaEV = EV_Exploit - EV_GTO` (bb, ambos bajo el EV del perfil asumido); una regla explotativa con Δ <= 0 no se aplica (ej.: c-bet de aire vs Nit en board húmedo => sustituido por `Delayed_Turn_Probe` / steal solo en boards secos).

## 10. SKILL INTERNA: [STAKE_CRUSHER_TERMINAL_EXPLOITS]
**Directiva Suprema:** maximizar EV real en bb (`argmax(EV_Exploit)`). En calles de cierre (Turn/River) se rompe deliberadamente MDF / α de Nash
cuando se activa un gatillo de nivel (`Stake_Gate`) y `ActionEVCalculator` certifica `EV_Exploit > EV_GTO` (`exploitDeltaEV`) tras `EV_Sanity_Guard`.
Nunca vs `Reg_GTO` (ancla intacta). Implementación: `lib/core/postflop/terminal_exploit_closers.dart`. FE / cuotas de farol = priors declarados por el usuario.
- **T1 B-X-B River Overbet Punish** (NL2-NL100, Pool/Scared): river check => overbet 115% con valor o nut-blocker sin SDV; probe <=33% => raise 3.2x (TwoPair+ / nut-blocker). FE pool 65%.
- **T2 Triple Barrel / River Raise Shutdown** (NL2-NL50, Pool/Nit/Scared/Fish): B-B-B (turn y river >=75%) o raise river => `MDF_Override 0%`, 100% fold de 1-par si farol real (12%) < pot odds. Maniac excluido.
- **T3 Sizing asimétrico vs Fish** (NL2-NL200): TPGK+ 100% (85-115); top/2º par débil 30% (25-33); farol River 0%.
- **T4 Turn Capped Double Barrel Blitz** (NL10-NL200, IP, c-bet <=40% pagada, turn sin completar): 80% con semifaroles, valor y overcards con blocker; FE pool 62% >= 58%.
- **T5 Small River Bet-Fold** (NL2-NL100, rango condensado): 25% con Marginal_Made_Showdown; si resube => fold (T2).
- **T6 Delayed Probe OOP** (NL50-NL200, flop X-X, turn sin completar): probe 70% con valor/draws + ~55% del resto (mezcla determinista).
Auditoría: tabla T1-T6 en `docs/cold_numbers_audit.md` (barrido exhaustivo de combos; 0 desviaciones con Δ <= 0 exigido).

## 11. SKILL INTERNA: [PURE_READ_AND_BAYESIAN_FUNNEL_ENGINE]
Inferencia sin HUD por desequilibrio acción/sizing vs equilibrio (`Equilibrium_Deviation_Read`), activa con `Pool_Default` y perfiles etiquetados (nunca vs `Reg_GTO`).
Multiplicadores por tier = priors declarados por el usuario; se combinan con `min()` (sin cascada) y piso 0.05. Implementación: `lib/core/reads/read_presets_catalog.dart`,
`lib/core/reads/unmapped_spots_resolver.dart`, `VillainRangeInspector`.
1. `Sizing_Compression_Law`: apuesta < 25% (Turn/River; 10-22% en cualquier calle) => nuts x0.10, faroles puros x0.15 => `Capped_Block_Or_Draw_Price`.
2. `Polarization_Truncated_Law`: River >= 90% en NL2-NL50 => faroles <= 12% salvo `Busted_Draws_Present` (flop coordinado + turn/river brick).
3. `Inaction_Cap_Law`: PFA hace check-back en flop/turn A-high/K-high/seco => nuts (y overpair/TPTK) x0.20.
**5 spots:** Micro_Block_Punisher (raise 3.8x con TopPair+/semifarol/blocker), PFA_Missed_CBet_Cap (Turn_Probe 70% + River_Follow_Up),
Busted_Draw_Runout (+/-14pp aire según blocker de Hero; decisión por `Bluff_Combo_Audit`; T2 cede), ThreeBet_Underpair_Pain_Guard (TT-QQ en A/K-x-x 3BP:
<=33% call, >=65% fold en NL2-NL50 salvo veto de `EV_Sanity_Guard`), Multi_Limper_Iso (3.5+1.2N IP / 4.5+1.5N OOP; limp-caller sin AA-JJ/AK).
**8 presets:** CAPPED_BY_CHECKBACK, MINBET_WEAKNESS, POLAR_NUTTED_BARREL, BUSTED_FD_BLUFF_HEAVY, COMPLETED_DRAW_DANGER, 3BP_BIG_SIZING_HONESTY, LIMP_CALL_CAPPED, FLOAT_AND_STAB.
Toda acción de spot pasa por `exploitDeltaEV` (ancla Nash) y `EV_Sanity_Guard`.
