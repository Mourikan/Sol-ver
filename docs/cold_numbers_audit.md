# Cold Numbers Audit — NL50 (Mid-Rake), 100bb, vs Reg_GTO

Generado por `docs/audit_scripts/cold_numbers_benchmark.dart` con el motor real.
- EV (bb): `ActionEVCalculator` (modelo de 1-2 calles, aproximado). En nodos sin apuesta enfrente la columna "EV Call" es EV(Check).
- Freq Motor: frecuencia agregada del rango que llega al nodo (ponderado). Freq GTO: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n, α = B/(P+2B), n = calles restantes (modelo geométrico polarizado); 3-bet = α del sizing.
- Δ Nash = |Freq Motor − Freq GTO|. Ojo: MDF es una cota mínima de defensa; preflop la defensa GTO real supera el MDF por pot odds/realización.

## Preflop

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs open BTN 2.5x — Kh9d | 0.00 | 0.24 | 1.79 | call 1.5bb | 54.4% | 53.0% | 1.4% |
| BB vs open CO 2.5x — Ah9d | 0.00 | 0.49 | 1.72 | call 1.5bb | 45.5% | 44.0% | 1.5% |
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
| NL2 | 2.17 | 4.04 | 1.65 | 0.42 | 1.48 | 0.24 |
| NL5 | 2.08 | 3.89 | 1.65 | 0.42 | 1.48 | 0.24 |
| NL10 | 1.98 | 3.74 | 1.65 | 0.42 | 1.48 | 0.24 |
| NL25 | 1.58 | 2.74 | 1.65 | 0.00 | 1.48 | 0.24 |
| NL50 | 1.48 | 2.39 | 1.80 | 0.00 | 1.27 | 0.48 |
| NL100 | 1.32 | 2.13 | 1.80 | 0.00 | 1.27 | 0.48 |
| NL200 | 1.02 | 1.42 | 1.80 | 0.00 | 1.27 | 0.48 |

### Auditoría Full_Exploit: todas las desviaciones (1 mano = 1 combo de Hero, NL10)

| Spot | Combos evaluados | Desviaciones vs ancla | Δ > 0 | Δ <= 0 | Δ EV medio de la desviación (bb) |
|---|---|---|---|---|---|
| Thin value River vs Fish (Inelastic-Caller) | 1081 | 243 | 243 | 0 | 2.15 |
| Overbet River vs Scared capado (Over-Folder) | 1081 | 212 | 212 | 0 | 3.31 |
| Steal_En_Secos Flop vs Nit (Over-Folder) | 1176 | 372 | 372 | 0 | 1.43 |
| Delayed_Turn_Probe vs Nit (Over-Folder) | 1128 | 287 | 287 | 0 | 0.92 |
| Pool_Turn_Barrel vs Pool_Exploit_Default NL10 | 1128 | 151 | 151 | 0 | 4.30 |
| Insta_Check Overbet_Bluff 125% vs Scared (SmartHUD 21/18/7/32) | 1081 | 270 | 270 | 0 | 5.24 |
| Trap_Check_Nuts 40% + flop vs Maniac (SmartHUD 40/32/14/62) | 1176 | 54 | 54 | 0 | 0.27 |

**Desviaciones Full_Exploit: 1589; con Δ EV <= 0: 0.** Las desviaciones de apuesta propia con Δ < 0 vuelven al ancla (`[EV_ANCHOR]`); las de call/fold quedan bajo MDF/`Bluff_Combo_Audit` (el modelo de 1-2 calles infravalora el valor de calls de rango).

Regla sustituida: "c-bet aire vs Nit en 7s6s5d" (Δ EV 0.00, rechazada por la puerta de EV) => `Steal_En_Secos` (solo matriz rangeBetSmall) + `Delayed_Turn_Probe` en turn tras check-check (factor Over-Folder 1.6x).
Δ EV = 0.00 en overbet NL25+ : la conversión LLinus ya está activa vs Reg en NL25+ (gate de la Fase 5), no hay desviación adicional.
El agregado bb/100 requiere frecuencias de spots y tendencias reales del pool por nivel (base de datos de manos), que este proyecto no tiene ni debe registrar (CLAUDE.md §5).

## Calificación de ingeniería (Claude, evaluación honesta)

| Eje | Nota | Fundamento |
|---|---|---|
| Precisión Matemática GTO | 60/100 | Δ Nash 2.4% vs referencias teóricas (MDF, α, presupuesto geométrico), pero rangos preflop semilla, targets BB declarados por el usuario y ninguna validación contra exports de solver. |
| Letalidad Explotativa vs Pool | 66/100 | Full_Exploit por defecto (Pool_Exploit_Default NL2-NL50), matriz asimétrica Over-Folder/Under-Bluffer/Inelastic-Caller y `exploitDeltaEV` > 0 en todas las desviaciones auditadas; el Δ se mide con el mismo modelo EV que asume el perfil: priors MDA/timing sin muestra real del pool. |
| Velocidad / Rendimiento APK | 70/100 | Lookups O(1) < 0.5 ms, decisión con EV ~1 ms, isolate persistente; el APK nunca se ha compilado ni medido en un dispositivo. |
| Seguridad Anti-Explotación | 70/100 | Presupuestos MDF exactos, EV_Sanity_Guard, invariantes y fuzzer de monotonía; las leyes MDA (folds en NL2-NL50) son explotables por regs que sobre-faroleen esas líneas. |

**Nota global: 67/100** — motor internamente consistente y auditado; la brecha principal es de datos (solver real y pool real), no de arquitectura.

