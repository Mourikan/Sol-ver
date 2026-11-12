# Cold Numbers Audit — NL50 (Mid-Rake), 100bb, vs Reg_GTO

Generado por `docs/audit_scripts/cold_numbers_benchmark.dart` con el motor real.
- EV (bb): `ActionEVCalculator` (modelo de 1-2 calles, aproximado). En nodos sin apuesta enfrente la columna "EV Call" es EV(Check).
- Freq Motor: frecuencia agregada del rango que llega al nodo (ponderado). Freq GTO: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n, α = B/(P+2B), n = calles restantes (modelo geométrico polarizado); 3-bet = α del sizing.
- Δ Nash = |Freq Motor − Freq GTO|. Ojo: MDF es una cota mínima de defensa; preflop la defensa GTO real supera el MDF por pot odds/realización.

## Preflop

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs open BTN 2.5x — Kh9d | 0.00 | 0.24 | 1.52 | call 1.5bb | 54.4% | 53.0% | 1.4% |
| BB vs open CO 2.5x — Ah9d | 0.00 | 0.49 | 1.47 | call 1.5bb | 45.5% | 44.0% | 1.5% |
| BTN vs open CO: 3-bet polar 7.5bb (farol/total) — Ah5h | 0.00 | 1.02 | 2.85 | call 2.5bb | 35.8% | 36.6% | 0.8% |
| CO vs 3-bet BTN 8.0bb — KhQh | 0.00 | 0.42 | 2.60 | call 5.5bb | 28.5% | 33.3% | 4.8% |
| BTN vs 3-bet BB 10.0bb — AhJd | 0.00 | 2.88 | 6.49 | call 7.5bb | 28.2% | 30.8% | 2.6% |

## Flop

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs c-bet 33% As7d2c — Kd8c | 0.00 | -0.13 | 0.74 | call 1.8bb | 78.4% | 75.3% | 3.1% |
| BB vs c-bet 33% Qc7h2d — 8h8d | 0.00 | 3.21 | 3.67 | call 1.8bb | 78.3% | 75.3% | 3.0% |
| BB vs c-bet 33% 9h8h4c — 6s5d | 0.00 | -0.33 | 2.20 | betRaise 10.0bb | 78.5% | 75.3% | 3.2% |
| BTN c-bet 33% As7d2c (farol/apuestas) — KhJd | 0.00 | 2.29 | 4.95 | check | 46.4% | 48.6% | 2.2% |
| BTN c-bet 75% QhJh8d (farol/apuestas) — Ah5h | 0.00 | 3.52 | 4.61 | betRaise 4.1bb | 62.1% | 65.7% | 3.6% |

## Turn

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs barrel 75% As7d2c5h — 7h6h | 0.00 | 2.97 | 2.89 | call 6.8bb | 57.7% | 57.2% | 0.5% |
| BB vs barrel 75% Qc7h2dKs — Qd9d | 0.00 | 5.20 | 4.63 | call 6.8bb | 57.6% | 57.2% | 0.4% |
| BB vs barrel 75% Kd8s3s4c — 8h7h | 0.00 | 3.40 | 2.68 | call 6.8bb | 59.0% | 57.2% | 1.8% |
| BTN double barrel 80% Kd7s2s4h (farol/apuestas) — AsQd | 0.00 | 2.38 | 5.64 | betRaise 7.3bb | 51.6% | 52.1% | 0.5% |
| BTN double barrel 75% As7d2c5h (farol/apuestas) — KhQh | 0.00 | 2.15 | 6.38 | check | 45.1% | 51.0% | 5.9% |

## River

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB bluff-catch vs pot Kd8s3s4c2h — 8h7h | 0.00 | -6.17 | -20.70 | fold | 48.2% | 50.0% | 1.8% |
| BB bluff-catch vs pot As7d2c5h9s — Kd9c | 0.00 | -13.60 | -30.12 | fold | 47.7% | 50.0% | 2.3% |
| BB bluff-catch vs pot Qc7h2dKs3c — Qd9d | 0.00 | -3.77 | -16.29 | call 22.7bb | 45.5% | 50.0% | 4.5% |
| BTN river bet 125% Kd7s2s4h9s (farol/apuestas del mismo sizing) — AsQd | 0.00 | 0.78 | 8.48 | betRaise 28.4bb | 32.4% | 35.7% | 3.3% |
| BTN river bet 33% Ks8s3d4cTh (farol/apuestas del mismo sizing) — AhKd | 0.00 | 16.95 | 20.21 | betRaise 7.5bb | 19.8% | 19.9% | 0.1% |

## Promedio Δ Nash por calle

| Calle | Promedio Δ Nash | Estado |
|---|---|---|
| Preflop | 2.2% | OK |
| Flop | 3.0% | OK |
| Turn | 1.8% | OK |
| River | 2.4% | OK |

**Promedio global Δ Nash: 2.4%** (Modo GTO exige <= 3.5% por calle).

## Edge por nivel (Modo Full_Exploit) — por spot, no bb/100

Rake por bote = E[min(%·pot, cap)] con la distribución de tamaños de `RakeConfig.potDistribution` (plantilla, no tabla oficial de sala).
Δ EV = `exploitDeltaEV` = EV(acción del motor con el read) − EV(ancla Nash vs Reg_GTO), ambas bajo el perfil asumido (prior del usuario).

| Nivel | Rake medio SRP (bb/bote) | Rake medio 3BP (bb/bote) | Δ EV thin value vs Fish (bb) | Δ EV overbet vs Scared capado, insta-check river (bb) | Δ EV Steal_En_Secos vs Nit, Qh3c en Kc7d2s (bb) | Δ EV Delayed_Turn_Probe vs Nit, As2s en 7s6s5d-2h (bb) |
|---|---|---|---|---|---|---|
| NL2 | 2.17 | 4.04 | 0.77 | 0.00 | 1.48 | 0.24 |
| NL5 | 2.08 | 3.89 | 0.77 | 0.00 | 1.48 | 0.24 |
| NL10 | 1.98 | 3.74 | 0.77 | 0.00 | 1.48 | 0.24 |
| NL25 | 1.58 | 2.74 | 0.77 | 0.00 | 1.48 | 0.24 |
| NL50 | 1.48 | 2.39 | 0.87 | 0.00 | 1.27 | 0.48 |
| NL100 | 1.32 | 2.13 | 0.87 | 0.00 | 1.27 | 0.48 |
| NL200 | 1.02 | 1.42 | 0.87 | 0.00 | 1.27 | 0.48 |

### Auditoría Full_Exploit: todas las desviaciones (1 mano = 1 combo de Hero, NL10)

| Spot | Combos evaluados | Desviaciones vs ancla | Δ > 0 | Δ <= 0 | Δ EV medio de la desviación (bb) |
|---|---|---|---|---|---|
| Thin value River vs Fish (Inelastic-Caller) | 1081 | 251 | 251 | 0 | 2.58 |
| Overbet River vs Scared capado (Over-Folder) | 1081 | 218 | 218 | 0 | 3.09 |
| Steal_En_Secos Flop vs Nit (Over-Folder) | 1176 | 372 | 372 | 0 | 1.43 |
| Delayed_Turn_Probe vs Nit (Over-Folder) | 1128 | 287 | 287 | 0 | 0.92 |
| Pool_Turn_Barrel vs Pool_Exploit_Default NL10 | 1128 | 162 | 162 | 0 | 1.49 |
| Insta_Check Overbet_Bluff 125% vs Scared (SmartHUD 21/18/7/32) | 1081 | 290 | 290 | 0 | 4.17 |
| Trap_Check_Nuts 40% + flop vs Maniac (SmartHUD 40/32/14/62) | 1176 | 54 | 54 | 0 | 0.27 |

**Desviaciones Full_Exploit: 1634; con Δ EV <= 0: 0.** Las desviaciones de apuesta propia con Δ < 0 vuelven al ancla (`[EV_ANCHOR]`); las de call/fold quedan bajo MDF/`Bluff_Combo_Audit` (el modelo de 1-2 calles infravalora el valor de calls de rango).

Regla sustituida: "c-bet aire vs Nit en 7s6s5d" (Δ EV 0.00, rechazada por la puerta de EV) => `Steal_En_Secos` (solo matriz rangeBetSmall) + `Delayed_Turn_Probe` en turn tras check-check (factor Over-Folder 1.6x).
Δ EV = 0.00 en overbet NL25+ : la conversión LLinus ya está activa vs Reg en NL25+ (gate de la Fase 5), no hay desviación adicional.
El agregado bb/100 requiere frecuencias de spots y tendencias reales del pool por nivel (base de datos de manos), que este proyecto no tiene ni debe registrar (CLAUDE.md §5).


## Auditoría de Terminaciones Explotativas (T1–T6) por Stake (NL2 a NL200)

Barrido de los 1081-1176 combos de Hero en la línea gatillo. EV en bb promediado sobre los combos donde la terminación desvía la acción del ancla Reg_GTO; ambos EV con `ActionEvCalculator` bajo el mismo contexto de línea (priors declarados por el usuario: FE pool T1 65%, T4 62%; farol real T2 12%). Acción = la más frecuente entre los combos desviados.

| Terminación | Nivel Óptimo | Acción GTO Base | Acción Explotativa | Combos desviados (Δ<=0) | EV GTO (bb) | EV Exploit (bb) | Ganancia Neta (+Δ EV bb) |
|---|---|---|---|---|---|---|---|
| T1 B-X-B River Overbet Punish | NL2-NL100 (NL10) | check | betRaise 115% | 223 (0) | 2.26 | 3.73 | +1.46 |
| T2 Triple Barrel Shutdown | NL2-NL50 (NL10) | call 78% | fold | 234 (0) | -11.26 | 0.00 | +11.26 |
| T3 Sizing asimétrico vs Fish | NL2-NL200 (NL10) | check | betRaise 100% | 251 (0) | 5.34 | 7.91 | +2.58 |
| T4 Turn Capped Double Barrel Blitz | NL10-NL200 (NL25) | check | betRaise 80% | 12 (0) | 1.47 | 4.01 | +2.54 |
| T5 Small River Bet-Fold | NL2-NL100 (NL10) | check | betRaise 25% | 68 (0) | 12.93 | 13.61 | +0.68 |
| T6 Delayed Probe OOP | NL50-NL200 (NL50) | check | betRaise 70% | 691 (0) | 1.87 | 4.25 | +2.38 |


## Módulos Fase 9.5 — Δ EV por spot (bb)

Mismo modelo EV para módulo ON y OFF (interruptores de auditoría). Priors de FE/umbrales declarados por el usuario. No es winrate.

| Módulo | Acción sin módulo | Acción con módulo | Perfil | +Δ EV (bb) |
|---|---|---|---|---|
| Geo-2E (set, SPR 2.3, Turn) | bet 75% (river SPR 0.63x) | bet 69% (river all-in 69%) | Reg_GTO | -0.48 |
| Short-Stack Topology (35bb, BTN vs CO, suma de manos) | 55 call->fold, 33 call->fold, KQo call->betRaise, A9s call->betRaise, 88 call->betRaise, AJo call->betRaise | 6 manos | Pool | +7.34 |
| Monotone Small Stab (AsQd en Ks9s4s) | ancla Reg_GTO | betRaise 28% | Pool NL10 | +0.02 |
| 4-Flush Blocker Steal (KsQd, 4 picas river) | ancla Reg_GTO | betRaise 115% | Pool NL10 | +0.11 |
| Sandwich Squeeze (A2s BB vs CO + BTN; FE 43% vs alpha 66%) | call/fold | gate cerrado (FE < alpha) | Pool NL10 | +0.00 |
| Anti-Counter-Exploit Shield (NL50, PFR 26/3B 11) | fold | call 80% | Agresivo (modelo de rango, sin prior T2) | +7.70 |

## Calificación de ingeniería (Claude, evaluación honesta)

| Eje | Nota | Fundamento |
|---|---|---|
| Precisión Matemática GTO | 60/100 | Δ Nash 2.4% vs referencias teóricas (MDF, α, presupuesto geométrico), pero rangos preflop semilla, targets BB declarados por el usuario y ninguna validación contra exports de solver. |
| Letalidad Explotativa vs Pool | 71/100 | Full_Exploit por defecto, matriz asimétrica, T1-T6, topología de stacks corta y monocolor/4-flush con +Δ EV > 0 en todos los combos desviados (barrido exhaustivo); la magnitud de T1/T2/T4 depende de priors de FE/farol del usuario; el Δ se mide con el mismo modelo EV que asume el perfil: priors MDA/timing sin muestra real del pool. |
| Velocidad / Rendimiento APK | 70/100 | Lookups O(1) < 0.5 ms, decisión con EV ~1 ms, isolate persistente; el APK nunca se ha compilado ni medido en un dispositivo. |
| Seguridad Anti-Explotación | 74/100 | Presupuestos MDF exactos, EV_Sanity_Guard, invariantes, fuzzer de monotonía y escudo anti-contra-explotación (NL50+ vs PFR>=24/3B>=10, Agro o Reg: sin hero-folds MDA, MDF x1.0); en NL2-NL25 las leyes MDA siguen siendo explotables por regs que sobre-faroleen esas líneas y el escudo depende de stats HUD. |

**Nota global: 69/100** — motor internamente consistente y auditado; la brecha principal es de datos (solver real y pool real), no de arquitectura.

