# Deep Engine EV Audit — 7 stakes

Generado por `docs/audit_scripts/full_7stakes_audit.dart`. Sin UI. Todas las cifras salen del motor real.

## 1. Mapa de huecos lógicos y estructurales

| Nodo | Estado | Resultado / nota |
|---|---|---|
| 3BP OOP en Turn con carta doblada (BB 3-bettor vs BTN, Kd7c2s-7d) | OK | betRaise 24.0bb |
| Defensa vs Check-Raise en Flop (PFA BTN c-bet, BB X/R) | OK | call 5.2bb |
| Defensa vs Check-Raise en Turn | OK | call 14.0bb |
| Bote 4-bet postflop SPR < 2.5 | APROX | betRaise 14.8bb — rangos 4BP aproximados con los de 3BP (no hay nodos 4BP propios) |
| Donk bet de tamaño medio 40-60% (reg) | OK | call 2.8bb |
| River donk tras X/C turn | OK | fold |
| Multiway 3 jugadores postflop | APROX | betRaise 2.6bb — MDF por jugador y c-bet bluff -50%; rango de un solo villano |
| Bote limpeado SB vs BB | OK | check |
| Preflop: facing 4-bet no all-in / 5-bet | OK | call 80.0bb |
| Preflop: squeeze con 2 callers + limp-reraise | OK | betRaise 16.3bb |
| Stacks 40bb / 200bb (3-bet commit, set-mining 12x) | OK | betRaise 7.5bb |
| Multiway con >1 villano modelado por separado | HUECO | GameState admite un único villainPosition; el resto se resume en activePlayers |
| Straddle / ante / stacks > 200bb | HUECO | Fuera del modelo (100bb base, sin ante/straddle) |

## 2. Rentabilidad y rake por los 7 stakes

Rake: plantilla editable `RakeConfig.byStake` (no corresponde a una sala concreta). Efectivo = min(cap, % × E[bote final]) / E[bote final].

| Stake | Tier | Rake % / cap | Rake efectivo SRP / 3BP | VPIP / PFR first-in (aprox) | Defensa BB vs BTN 2.5x | 3-Bet global | EV medio nodo flop BB (bb) | Δ Nash flop / turn |
|---|---|---|---|---|---|---|---|---|
| NL2 | High-Rake | 5.0% / 15.0bb | 5.0% / 5.0% | 32.1% / 25.5% | 48.3% | 8.7% | 1.04 | 5.0 / 1.7 |
| NL5 | High-Rake | 5.0% / 10.0bb | 5.0% / 5.0% | 32.1% / 25.5% | 48.3% | 8.7% | 1.04 | 5.0 / 1.7 |
| NL10 | High-Rake | 5.0% / 6.0bb | 5.0% / 5.0% | 32.1% / 25.5% | 48.3% | 8.7% | 1.04 | 5.0 / 1.7 |
| NL25 | High-Rake | 5.0% / 4.0bb | 5.0% / 5.0% | 32.1% / 25.5% | 48.3% | 8.7% | 1.04 | 5.0 / 1.7 |
| NL50 | Mid/Low | 5.0% / 3.0bb | 5.0% / 5.0% | 34.7% / 27.7% | 50.6% | 8.4% | 1.04 | 5.1 / 1.7 |
| NL100 | Mid/Low | 4.5% / 2.5bb | 4.5% / 4.5% | 34.8% / 27.7% | 51.4% | 8.4% | 1.05 | 5.1 / 1.7 |
| NL200 | Mid/Low | 4.0% / 1.5bb | 4.0% / 2.7% | 34.9% / 27.7% | 51.9% | 8.4% | 1.06 | 5.1 / 1.7 |

Nota: NL2–NL25 comparten cifras porque con la plantilla de rake el cap no se alcanza en botes SRP (E=22bb) ni 3BP (E=55bb): el rake efectivo es 5% en los cuatro y comparten tier (rangos High-Rake). La diferencia real entre esos niveles depende de la estructura de rake de cada sala, que el proyecto no tiene; con caps reales más altos en bb el resultado sería el mismo (5% sin tope).

## 3. Inconsistencias Heurística vs ActionEVCalculator

Muestra: 960 decisiones de flop (PFA BTN con iniciativa y BB enfrentando c-bet 33%) en 8 texturas, NL50.

| Métrica | Valor |
|---|---|
| Decisiones corregidas por `[EV_GATE]` (apuesta propia −EV vs check, fuera de banda) | 0.0% |
| Apuestas finales con EV(bet) < EV(check) − banda (tras la puerta) | 0.0% |
| Calls con EV(call) < −banda según el modelo de 1 calle (mantenidos por MDF) | 1.0% |
| Decisiones protegidas por intervención documentada (guard, trap, gates de perfil) | 1.4% |
| Latencia mediana / p95 por decisión con EV | 0.77 ms / 1.95 ms |

Corrección aplicada: la puerta de EV des-escala apuestas propias −EV a check (o raise −EV a call). No convierte calls en folds: con ese modelo la defensa caía a 22–30% vs MDF 50% en River (Δ hasta 28%), es decir, el modelo de 1 calle infravalora los faroles del rival. Esos calls se reportan aquí pero los gobierna DefenseBudget / Bluff_Combo_Audit.

## 4. Scorecard de calidad (consistencia interna, NO acuerdo con solver)

Score = % de checks superados del submódulo (checks listados en las secciones 1–3, en `docs/final_metrics_audit.md` y en la suite `flutter test`).

| Submódulo | Checks superados | Score | Ajustes finos pendientes |
|---|---|---|---|
| Coverage | 6/10 | 60% | Multiway con >1 villano modelado, straddle/ante/stacks > 200bb, nodos 4BP propios |
| Preflop_Tree | 11/11 | 100% | Rangos semilla (no solver); 4BP/5BP sin nodos postflop propios; stacks > 200bb, ante/straddle fuera del modelo |
| Flop_Buckets | 7/7 | 100% | Matrices por tier son priors de modelo; calibrar contra agregados reales por bucket |
| Turn_River_Solver | 7/7 | 100% | Clasificación de carta en 3 clases; sizings discretos; faroles por reglas de blocker |
| Range_Funnel | 5/5 | 100% | Pesos de línea paramétricos (0.4/0.6/1.0, policyMix 0.15); multiway con un solo villano |
| Discipline_Auditor | 1/1 | 100% | Priors MDA/timing declarados, no estimados con muestra |
| EV_Calculator | 3/3 | 100% | Modelo de 1 calle (sin árbol); infravalora faroles del rival => no gobierna calls |

**Score global (media): 94%** — mide ausencia de fugas internas detectables, no similitud con un solver CFR+.

