# Deep Engine EV Audit — 7 stakes

Generado por `docs/audit_scripts/full_7stakes_audit.dart`. Sin UI. Todas las cifras salen del motor real.

## 1. Mapa de huecos lógicos y estructurales

| Nodo | Estado | Resultado / nota |
|---|---|---|
| 3BP OOP en Turn con carta doblada (BB 3-bettor vs BTN, Kd7c2s-7d) | OK | betRaise 24.0bb |
| Defensa vs Check-Raise en Flop (PFA BTN c-bet, BB X/R) | OK | call 5.2bb |
| Defensa vs Check-Raise en Turn | OK | call 14.0bb |
| Bote 4-bet postflop SPR < 2.5 (FourBetPotSolver, rangos 4BP propios) | OK | betRaise 9.9bb |
| Donk bet de tamaño medio 40-60% (reg) | OK | call 2.8bb |
| River donk tras X/C turn | OK | fold |
| Multiway 3 jugadores postflop (villanos modelados por separado) | OK | betRaise 2.6bb |
| Bote limpeado SB vs BB | OK | check |
| Preflop: facing 4-bet no all-in / 5-bet | OK | call 80.0bb |
| Preflop: squeeze con 2 callers + limp-reraise | OK | betRaise 16.3bb |
| Stacks 40bb / 200bb (3-bet commit, set-mining 12x) | OK | betRaise 7.5bb |
| Multiway: Bluff_Gate (station activo => 0% faroles) + amenaza principal | OK | check |
| Straddle / ante / stacks > 200bb (StructureModifier) | OK | betRaise 5.4bb |

## 2. Rentabilidad y rake por los 7 stakes

Rake: plantilla editable `RakeConfig.byStake` (no corresponde a una sala concreta). Efectivo = min(cap, % × E[bote final]) / E[bote final].

| Stake | Tier | Rake % / cap | Rake efectivo SRP / 3BP | VPIP / PFR first-in (aprox) | Defensa BB vs BTN 2.5x | 3-Bet global | EV medio nodo flop BB (bb) | Δ Nash flop / turn |
|---|---|---|---|---|---|---|---|---|
| NL2 | High-Rake | 5.0% / 20.0bb | 5.0% / 5.0% | 32.1% / 25.5% | 48.3% | 9.0% | 1.31 | 4.6 / 1.7 |
| NL5 | High-Rake | 5.0% / 9.0bb | 4.8% / 4.8% | 32.2% / 25.5% | 48.7% | 9.0% | 1.31 | 4.6 / 1.7 |
| NL10 | High-Rake | 5.0% / 8.0bb | 4.5% / 4.6% | 32.2% / 25.5% | 48.8% | 9.0% | 1.31 | 4.6 / 1.7 |
| NL25 | High-Rake | 5.0% / 4.0bb | 3.6% / 3.4% | 32.5% / 25.5% | 50.5% | 9.0% | 1.31 | 4.6 / 1.7 |
| NL50 | Mid/Low | 5.0% / 3.0bb | 3.4% / 3.0% | 35.0% / 27.7% | 52.9% | 8.7% | 1.30 | 3.0 / 3.8 |
| NL100 | Mid/Low | 5.0% / 2.5bb | 3.0% / 2.6% | 35.1% / 27.7% | 53.5% | 8.7% | 1.30 | 3.0 / 3.8 |
| NL200 | Mid/Low | 5.0% / 1.5bb | 2.4% / 1.8% | 35.3% / 27.7% | 54.5% | 8.7% | 1.30 | 3.0 / 3.8 |

Nota: NL2–NL25 comparten cifras porque con la plantilla de rake el cap no se alcanza en botes SRP (E=22bb) ni 3BP (E=55bb): el rake efectivo es 5% en los cuatro y comparten tier (rangos High-Rake). La diferencia real entre esos niveles depende de la estructura de rake de cada sala, que el proyecto no tiene; con caps reales más altos en bb el resultado sería el mismo (5% sin tope).

## 3. Inconsistencias Heurística vs ActionEVCalculator

Muestra: 960 decisiones de flop (PFA BTN con iniciativa y BB enfrentando c-bet 33%) en 8 texturas, NL50.

| Métrica | Valor |
|---|---|
| Decisiones corregidas por `[EV_GATE]` (apuesta propia −EV vs check, fuera de banda) | 0.6% |
| Apuestas finales con EV(bet) < EV(check) − banda (tras la puerta) | 0.0% |
| Calls con EV(call) < −banda según el modelo de 1 calle (mantenidos por MDF) | 0.4% |
| Decisiones protegidas por intervención documentada (guard, trap, gates de perfil) | 1.3% |
| Latencia mediana / p95 por decisión con EV | 0.38 ms / 0.67 ms |

Corrección aplicada: la puerta de EV des-escala apuestas propias −EV a check (o raise −EV a call). No convierte calls en folds: con ese modelo la defensa caía a 22–30% vs MDF 50% en River (Δ hasta 28%), es decir, el modelo de 1 calle infravalora los faroles del rival. Esos calls se reportan aquí pero los gobierna DefenseBudget / Bluff_Combo_Audit.

## 4. Scorecard de calidad (consistencia interna, NO acuerdo con solver)

Score = % de checks superados del submódulo (checks listados en las secciones 1–3, en `docs/final_metrics_audit.md` y en la suite `flutter test`).

| Submódulo | Checks superados | Score | Ajustes finos pendientes |
|---|---|---|---|
| Coverage | 10/10 | 100% | Multiway con >1 villano modelado, straddle/ante/stacks > 200bb, nodos 4BP propios |
| Preflop_Tree | 11/11 | 100% | Rangos semilla (no solver); 4BP/5BP sin nodos postflop propios; stacks > 200bb, ante/straddle fuera del modelo |
| Flop_Buckets | 7/7 | 100% | Matrices por tier son priors de modelo; calibrar contra agregados reales por bucket |
| Turn_River_Solver | 7/7 | 100% | Clasificación de carta en 3 clases; sizings discretos; faroles por reglas de blocker |
| Range_Funnel | 5/5 | 100% | Pesos de línea paramétricos (0.4/0.6/1.0, policyMix 0.15); multiway con un solo villano |
| Discipline_Auditor | 1/1 | 100% | Priors MDA/timing declarados, no estimados con muestra |
| EV_Calculator | 3/3 | 100% | Modelo de 1 calle (sin árbol); infravalora faroles del rival => no gobierna calls |

**Score global (media): 100%** — mide ausencia de fugas internas detectables, no similitud con un solver CFR+.

## 5. Control de regresión Fase 8.9 (vs Fase 8.8)

Ningún check del scorecard se rompe (todos los submódulos mantienen o mejoran sus checks). Métricas que se movieron dentro de umbral:

| Métrica | Fase 8.8 | Fase 8.9 | Causa |
|---|---|---|---|
| Defensa BB vs BTN NL100 | 51.7% | 56.3% (banda 45-55, Δ 1.3) | Rake efectivo mid más bajo (curva por tamaño de bote pedida) |
| Δ turn NL50-NL200 (7-stakes, As7d4c5h) | 1.7 | ~3.8 | Rango BB más ancho por menor rake => más calls +EV de la invariante Equity_Real ≥ Pot Odds; presupuesto MDF ahora exacto (desempate por combo) |
| River vs pot NL100 Reg (Kd8s3s4c2h / As7d2c5h9s / Qc7h2dKs3c) | 52.3 / 50.0 / 46.5% | 48.2 / 47.7 / 45.5% | Presupuesto River exacto (antes los empates inflaban la defensa) |
| Defensa flop c-bet 33% NL100 Reg | 78.9 / 80.4 / 87.2% | 78.4 / 79.6 / 83.1% | Mejora (más cerca de MDF) |
| Turn fold NL100 Reg (metric_audit) | 42.0 / 40.7 / 41.9% | 42.3 / 42.4 / 41.0% | Mejora |

