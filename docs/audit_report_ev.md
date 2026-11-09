# Deep EV Leak Audit — Sol-ver (commit `c52584b`)

Alcance: `lib/core/` (preflop, postflop, reads, discipline). Sin cambios de código fuente.
Método: análisis estático + medición empírica ejecutando el motor real combo a combo (scripts reproducibles en `docs/audit_scripts/`, ejecutar con `dart --packages=.dart_tool/package_config.json docs/audit_scripts/<script>.dart`).

Severidad: **S1** = imprime dinero para cualquier rival que lo detecte · **S2** = -EV recurrente en spots frecuentes · **S3** = -EV en spots de nicho / riesgo de mal read.

---

## 0. Resumen ejecutivo

| # | Fuga | Sev. | Evidencia medida |
|---|------|------|------------------|
| L1 | `Bluff_Combo_Audit` se ejecuta en **Turn** (diseñado para River) | S1 | BB continúa **1.4–33%** vs barrel 75% (MDF 57%) |
| L2 | Modelo de faroles "3 categorías equiponderadas" + `straightCompleted` sobre-disparado | S1 | `straightCompleted` = **69.7%** de runouts aleatorios; hero-fold forzado en **60%** de runouts incluso vs AGRO |
| L3 | Read Agro no rescata cuando categorías = 0 (`0 × 1.5 = 0`) | S1 | Set `33` **foldea** a donk 47% de MANIAC en NL100 |
| L4 | Squeeze-or-fold aplicado a la **BB** (cierra acción, pot odds 18.8%) | S1 | BB continúa **5.9%** vs open CO + call BTN |
| L5 | Iso vs Fish/Station = `stationValue3Bet` (~7%) | S2 | BTN iso vs 1 limper fish **7.4%** vs 26–30% default |
| L6 | `trapperLimpReraiser → VillainProfile.nit` activa "c-bet 100% del rango" | S2 | C-bet con `5h4d` vs trapper en K83r |
| L7 | `DonkTell.nuttedUnbalancedValue` no exige read recreativo | S2 | QQ **foldea** a pot-donk de un reg desconocido NL50 |
| L8 | Rama `Insta_Call → River brick` ignora el gate de perfil | S2 | Farol 85% con A-high aire **vs Fish** |
| L9 | `bluffShare` reportado ≠ ejecutado (nodos muertos o sobre-farol) | S2 | Scared: 61.5% rep. / **75.7%** ejec.; Agro: 15.4% rep. / **0%** ejec. |
| L10 | Defensa de flop vs c-bet 33% por debajo de MDF | S2 | Continúa 54–70% en A/K/Q-high (MDF 75%) |
| L11 | Rake modelado solo sobre el bote del flop | S2 | Pot odds raked micro 28.71% vs mid 28.41% (Δ 0.3 pp) |
| L12 | Raise de valor con cualquier `nutsMonster` sin test de nut-ness | S3 | `_facing` → `raise` con sets/2P en rivers de 4-flush |
| L13 | Botes multiway / limpeados sin soporte postflop | S3 | `UnsupportedError` o tratamiento HU silencioso |

---

## 1. ¿QUÉ ROMPIMOS? — Integridad topológica

### 1.1 Frecuencias > 100%
- **No encontradas.** `RangeNode._compile` recorta por prioridad (`preflop_ranges_db.dart`), `bluffShare` está acotado a 1.0 (`turn_river_solver.dart:41`), `cold4BetBluffWeight` = 0.25. ✔

### 1.2 Nodos muertos (`Combo_Valor + Combo_Farol == 0` o rama inalcanzable)
1. **Nodo de farol muerto vs Agro (L9)** — `TurnRiverSolver._role` devuelve `check` para todo no-valor si `archetype == agroSpewy`, pero el plan sigue reportando `bluffShare = GTO × 0.5`. Medido en Kd7s2s-4h: **0.0% de faroles ejecutados** vs 15.4% reportados. La UI mostrará una métrica falsa.
2. **Nodo de valor muerto en River tras `Insta_Call` + carta que completa** (`postflop_heuristic_engine.dart:123`): todo lo que no es `nutsMonster` hace check, incluido top pair vs Fish → se pierde el thin value que la Fase 4 exige.
3. **Bote limpeado** (`postflop_heuristic_engine.dart:67`): `throw UnsupportedError`. En NL2–NL10 es uno de los nodos más frecuentes (BB check vs limpers) → **nodo sin salida**.

### 1.3 Colisiones de variables (Rake × Timing × Node-Locking)
| Colisión | Ruta | Efecto |
|----------|------|--------|
| Read Trapper → engineProfile `nit` | `gg_profiler.dart:30` → `ExploitModifier.adjustBetting(nit)` | El "nit" del modificador = **sobre-foldeador** → c-bet 100% a 33% contra un rango 85% AA/KK. Semántica invertida. |
| `VillainProfile.regAbc/nit` → `scaredMoneyReg` | `gg_profiler.dart:41` | Activa `Exploit_Bluff_Factor 2.0` y el conversor LLinus contra cualquier reg etiquetado manualmente como ABC, sin evidencia de rango capado. |
| Timing `Insta_Call` × Fish | `postflop_heuristic_engine.dart:123` precede a `BlockerBluffConverter.gate` y a `exploitBluffFactor` | El tell sobreescribe el gate "0% faroles vs Fish". |
| MDA (×0.85) × Timing falso-tank (×0.5) × categorías (k/3) | `bluff_catch_auditor.dart:73-103` | Penalizaciones **multiplicativas sin piso**: con 1 categoría → 0.33·0.85·0.5 = 0.14 × potOdds → fold forzado de sets y top two. |
| Agro × categorías = 0 | `bluff_catch_auditor.dart:96` | `0 × 1.5 = 0`: el read más farolero del pool **no** puede revertir un hero fold. |
| Auditor × Turn | `postflop_heuristic_engine.dart:116` | Ver L1: el auditor trata la mano del Turn como "final" — los proyectos aún vivos no cuentan como semi-faroles. |

---

## 2. VARIABLES NO RENTABLES (Heurísticas −EV)

### L1 — Auditor de River aplicado al Turn (S1)
`_discipline` se invoca para `street != flop`. En Turn, `BoardHistory` toma el board de 4 cartas como "final": `missedFlushDraw/missedStraightDraw` son falsos porque los proyectos **todavía no han fallado**, así que en boards secos sólo sobrevive `Air_From_Flop` ⇒ `bluffs = potOdds/3 < 0.6·potOdds` ⇒ **heroFoldDisciplined con top pair / overpair**.

Medido (BB vs BTN SRP, c-bet 33% → barrel 75% → river 100%):

| Stake | Runout | Read | Flop cont. (MDF 75) | Turn cont. (MDF 57) | River cont. (MDF 50) |
|-------|--------|------|------|------|------|
| NL10 | As7d2c-5h-9s | unknown / scared | 64.8% | **1.6%** | 100% |
| NL10 | Kd8s3s-4c-Js | unknown / scared | 69.0% | **11.8%** | **0.0%** |
| NL10 | 9h8h4c-2s-Td | unknown / scared | 83.6% | **17.8%** | **0.0%** |
| NL10 | Qc7h2d-Ks-3c | unknown / scared | 54.8% | **11.9%** | **0.0%** |
| NL100 | Ts9s6d-Kh-2c | unknown | 89.5% | 33.2% | 60.1% |
| NL10 | Qc7h2d-Ks-3c | agro | 54.8% | 73.6% | 69.5% |

EV de un farol puro del rival en Turn (bet 6.8 en 9.1, α = 42.8%): `EV = 9.1·f − 6.8·(1−f)`. Con f = 0.984 ⇒ **+8.85bb por farol**; con f = 0.822 ⇒ +6.27bb. Cualquier reg que barrilee Turn 100% de su rango imprime.

### L2 — Modelo de categorías de farol (S1)
- Cada categoría (`Missed_FD`, `Missed_OESD`, `Air_From_Flop`) pesa exactamente 1/3 del share GTO, independientemente de la composición real del rango del villano. Un board monocolor sin escaleras posibles da `Missed_OESD = false` aunque el villano tenga 40 combos de aire con backdoors.
- `BoardHistory.straightCompleted` (`board_history.dart:57`) = "aumentó el nº de ventanas de 5 rangos con ≥3 cartas del board". No mide si un **proyecto real** del rival se completó. Muestreo 4000 runouts: `straightCompleted` **69.7%**, `flushCompleted` 36.6%, `brickOut` sólo **19.6%**, 0 categorías de proyecto en **33.7%**.
- Consecuencia: en línea X/C → X/C → agresión River, **60.0% de los runouts aleatorios** producen `heroFoldDisciplined` **incluso con read AGRO**.

### L3 — Hero Fold con sets/2P vs Maniac (S1)
Set `33` en `Ts7s3d-2c-9s`, NL100, MANIAC, donk river 10bb en 21.5 (pot odds 24.1%): `availableBluffs = 0.000` ⇒ **fold**. Un maniac (VPIP 45/PFR 35) llega a esta línea con pares, aire y semi-faroles fallidos; la regla de Oro de la Fase 5 se ejecuta fuera de su escenario (NL2-NL50, pool pasivo).

### L4 — Squeeze-or-fold forzado en la BB (S1)
`FullTreePreflop._squeeze` no tiene región de call. La BB cierra la acción con 1.5bb para un bote de 6.5bb (18.8% raw). Continúa **5.9%**. Un GTO bot defiende aquí ~5–7× más manos (suited, pares, broadways). El open+call de CO/BTN se convierte en robo automático.

### L5 — Aislamiento vs Fish demasiado estrecho (S2)
`isoRange(station: true)` = `88+, AJo+, KQo, KJs+` (**7.4%**). Contra un limper inelástico la ganancia viene de jugar HU con iniciativa y rangos dominantes; el rango por defecto ya era 26–30%. El ajuste "vs station" va en dirección **opuesta** a la fuente principal de EV de micro-stakes.

### L6 — Trapper tratado como "nit sobre-foldeador" (S2)
Confirmado: `5h4d` c-betea en K83r contra trapper (`ExploitModifier` nit ⇒ bet 100% @33%). Contra un rango 85% AA/KK/AKs esto es farol −EV puro.

### L7 — Pot-donk = nuts sin read (S2)
`DonkTellDecoder` (`gg_profiler.dart:83`) clasifica cualquier donk ≥75% en ≤NL50 como `nuttedUnbalancedValue` **sin exigir `read.isRec`**. Medido: QQ en T83r foldea a 5bb/5.5bb de un reg desconocido. Un reg sólo necesita donkear pot con aire.

### L8 — Timing override contra Fish (S2)
`instaCallTurnIntoRiver` (`postflop_heuristic_engine.dart:123`) devuelve `bet 85%` con aire (A-high) **contra fish**. Viola el gate "0% faroles en River vs Rec" de la Fase 4. La premisa "proyectos rotos hacen insta-fold" no aplica a quien paga con cualquier par.

### L9 — Ratio de faroles no ejecutado (S2)
`plan.bluffShare` se calcula pero la selección por mano (`_role`) es independiente. Turn Kd7s2s-4h, rango BTN completo:

| Read | Bet total | Faroles ejecutados | Faroles reportados |
|------|-----------|--------------------|--------------------|
| Scared (factor 2.0) | 59.7% | **75.7%** | 61.5% |
| Unknown | 23.3% | 37.7% | 30.8% |
| Fish (turn ×0.5) | 23.3% | **37.7%** | 15.4% |
| Agro (×0.5) | 14.5% | **0.0%** | 15.4% |

Contra Fish el turn farolea el doble de lo declarado; contra Agro el nodo de farol está muerto (L1.2).
*Nota: mide el rango BTN RFI completo, no el filtrado por c-bet de flop; el sesgo es el mismo en todas las filas.*

### L10 — Defensa de flop vs c-bet pequeño (S2)
Continuación BB vs 33% pot: 54–70% en boards A/K/Q-high (MDF 75%, α del rival = 24.7%). Fold de 45% en Qc7h2d ⇒ c-bet any-two del rival: `EV = 5.5·0.452 − 1.8·0.548 = +1.5bb` por intento. Causa: `airGiveUp` siempre foldea y `backdoorBlockerBluff` sólo paga ≤34% pot; no hay floats con backdoors+overcards para completar MDF.

### L11 — Rake insensible al tier (S2)
`rakedPotOdds` (`preflop_solver_engine.dart:88`) aplica rake sobre `pot + call` (bote del flop). La diferencia micro/mid es **0.3 pp** (28.71% vs 28.41%). El coste real del rake en micro es el % uncapped sobre el **bote final** (los botes SRP de 20–40bb no topan el cap en NL2–NL10). El tier casi no mueve la defensa de BB: vs BTN 2.5x 48.4% (NL10) vs 54.4% (NL100), y esa diferencia viene sobre todo del rango de apertura distinto, no del rake.

### L12 — Raise automático con cualquier "monster" (S3)
`_facing` (`postflop_heuristic_engine.dart:313`) sube por valor todo `nutsMonster` (sets bajos, dos pares, escaleras no-nut) sin comprobar si hay manos mejores plausibles en el rango del rival. En rivers de 4-flush / 4-straight subir sólo recibe call de manos mejores.

### L13 — Multiway y botes limpeados (S3)
`GameState` admite un solo `villainPosition`; los botes multiway que salen de iso/squeeze pagados se evalúan como HU con MDF/α incorrectos. Botes limpeados → excepción.

---

## 3. EXPLOTABILIDAD (fugas de MDF y α)

### 3.1 ¿Foldeamos > (1 − MDF)?
**Sí, de forma sistemática en Turn y River** para todo read distinto de Agro (tabla L1). El "Fold Disciplinado" se dispara por defecto (L1 + L2), no como excepción.

### 3.2 Cómo nos imprime un `Reg_Agro` / `GTO_Bot`
1. **Barrel Turn 100% del rango** (cualquier tamaño ≥ 50%): continuamos 1.6–33% ⇒ +6 a +9bb por farol (L1).
2. **Esperar a que caiga el 3er palo o cualquier carta que "abra" una escalera y apostar River** (69.7% de runouts disparan `straightCompleted`): fold forzado incluso con sets (L2/L3).
3. **Timebank antes de apostar River en NL25–NL50**: el multiplicador falso-tank ×0.5 baja aún más nuestro conteo de faroles (los bots y los regs usan timing constante o timebank deliberado).
4. **Pot-donk de flop con aire en ≤NL50**: foldeamos overpairs (L7).
5. **Open en CO/BTN con call intermedio**: la BB defiende 5.9% (L4).
6. **C-bet 33% any-two**: +1.5bb/intento en boards altos (L10).
7. **Insta-check del villano**: activa `capped` ⇒ overbet-farol del conversor LLinus. Un reg que insta-chequea su rango de trampa (timing balanceado) induce overbets contra sets.

### 3.3 Fugas de α en nuestras apuestas
- Conversor LLinus 125% (α = 55.6%) y factor 2.0 (scared): requieren que el rival foldee >55.6% del rango. Con funnel `cappedMedium` derivado de un solo check-call en board seco, un reg que hace slow-play de sets con X/C en flop no está capado ⇒ los overbets se pagan por encima de α.

---

## 4. IMPACTO A LARGO PLAZO POR LÍMITES

### 4.1 Micro (NL2–NL25, rake alto)
- **Defensa BB**: niveles razonables vs opens únicos (30% vs UTG, 48% vs BTN en NL10), pero el modelo **no aprende del rake** (L11); los calls offsuit marginales (EQR 0.76–0.78, p. ej. K5o) quedan dentro por 0.3 pp de diferencia de tier ⇒ ligeramente −EV en NL2–NL10.
- **La fuga dominante NO es preflop**: es el colapso de Turn (L1/L2) más el iso vs fish demasiado tight (L5) y los botes limpeados sin soporte (L13). Estos tres pesan más que cualquier umbral de defensa preflop.
- **3-bet/call**: correcto en estructura (0% cold call fuera de BTN/BB). La BB en squeeze (L4) y el SB vs nit "any two" sin conocer la otra ciega son los dos puntos a revisar.

### 4.2 Mid (NL50–NL200, rake bajo/capado)
- **Hero Fold** se basa en priors de pool NL2–NL50 pero el modelo de categorías (L2) y el tratamiento del Turn (L1) se aplican **a cualquier stake**; sólo el ×0.85 de MDA está gateado por stake. Un reg equilibrado nos explota con barrels de Turn y River en cartas que "completan" algo.
- **Timing tells**: aplicados sin muestra mínima ni perfil por jugador; regs y bots usan timing constante o timebank ⇒ señal = ruido, pero el motor la trata como certeza (×0.5, `capped = true`).
- **Conversor LLinus activo vs `unknownReg` en NL25+** (`blocker_bluff_converter.dart:28`): sin read, contra rangos GTO no capados.

---

## 5. CORRECCIONES ARQUITECTÓNICAS EXIGIDAS (prioridad)

1. **[L1] Auditor sólo en River.** En Turn, sustituir por un `DefenseBudget` por rango: ordenar el rango de Hero que llega al nodo por equity/realización y continuar con el top `MDF × k` combos, donde `k ∈ [0.85, 1.0]` depende del read (`k < 1` sólo con read pasivo explícito y stake ≤ NL50).
2. **[L2] Conteo de faroles por combos, no por categorías.** Reconstruir el rango del villano desde preflop (`PostflopRanges.forPot`) filtrado por su línea (`RangeFunnel` como filtro de combos, no como enum), clasificar cada combo en valor/farol con `HandTierClassifier` en el River real y comparar `bluffCombos / (bluffCombos + valueCombos)` con pot odds. Eliminar la equiponderación 1/3.
3. **[L2] Redefinir `straightCompleted`**: sólo es verdadero si la carta nueva completa una escalera para combos que en la calle anterior eran OESD/gutshot (enumeración de combos de 2 cartas), no por aumento de ventanas.
4. **[L3] Precedencia de reads**: `agroSpewy` desactiva el hero fold forzado; piso de faroles `max(computed, minBluffFloor(read))`. Nunca foldear sets/2P a pot odds < 30% sin read pasivo explícito.
5. **[L4] Región de call en squeeze para BB/BTN**: pot odds multiway con EQR multiway (penalizar offsuit, premiar suited/pares).
6. **[L5] Iso vs Fish**: rango lineal **más ancho** que el default (top ~25–35% por equity vs rango de limp) con sizing mayor; nunca más estrecho.
7. **[L6/L7/L8] Separar `VillainProfile` (estilo de juego) de `ReadProfile` (rango esperado)**: `trapper` necesita su propio perfil (`premiumRange`: sin faroles, sin thin value); `DonkTell.nutted` exige `read.isRec`; toda rama de timing pasa por el gate de perfil antes de emitir faroles.
8. **[L9] Ejecutar el ratio**: seleccionar faroles de una lista ordenada (equity retenida → blockers → resto) hasta cubrir `valueCombos × bluffShare/(1−bluffShare)` con hash determinista por combo. La métrica mostrada debe ser la ejecutada.
9. **[L10] Floats de flop**: continuar con backdoors + overcards hasta MDF vs sizings ≤ 33%.
10. **[L11] Rake sobre bote esperado final**: `rakeEff = min(cap, pct × E[finalPot | potType, tier])`, con `E[finalPot]` tabulado por tipo de bote; cap y % configurables por sala.
11. **[L12] Raise de valor sólo con top-X% del rango propio en ese nodo** (nut-ness relativa), si no: call.
12. **[L13] Soporte explícito multiway/limped** o bloqueo en UI con mensaje (regla anti-alucinación #3) en lugar de tratarlo como HU.
13. **Timing**: exigir `n ≥ N` observaciones por jugador y desactivar por defecto en ≥ NL50.

---

## 6. Lo que está sano
- Matemática base exacta: MDF, α, geometría, B/(P+2B), outs por enumeración (verificado por tests).
- Sin frecuencias > 100% ni overlaps de rangos.
- Estructura preflop high-rake (0% cold call fuera de BTN/BB, sizings 3.2x/4–4.5x) coherente con la especificación.
- Detección de limp-reraise, thin value vs fish en River y blockers de nut flush funcionan como se especificó.
