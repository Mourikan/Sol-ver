# Cold Numbers Audit — NL50 (Mid-Rake), 100bb, vs Reg_GTO

Generado por `docs/audit_scripts/cold_numbers_benchmark.dart` con el motor real.
- EV (bb): `ActionEVCalculator` (modelo de 1-2 calles, aproximado). En nodos sin apuesta enfrente la columna "EV Call" es EV(Check).
- Freq Motor: frecuencia agregada del rango que llega al nodo (ponderado). Freq GTO: defensa = MDF = P/(P+B); farol en apuesta polar = 1-(1-α)^n, α = B/(P+2B), n = calles restantes (modelo geométrico polarizado); 3-bet = α del sizing.
- Δ Nash = |Freq Motor − Freq GTO|. Ojo: MDF es una cota mínima de defensa; preflop la defensa GTO real supera el MDF por pot odds/realización.

## Preflop

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs open BTN 2.5x — Kh9d | 0.00 | 0.24 | 1.79 | call 1.5bb | 54.4% | 37.5% | 16.9% |
| BB vs open CO 2.5x — Ah9d | 0.00 | 0.49 | 1.72 | call 1.5bb | 45.5% | 37.5% | 8.0% |
| BTN vs open CO: 3-bet polar 7.5bb (farol/total) — Ah5h | 0.00 | 1.02 | 2.85 | call 2.5bb | 24.7% | 36.6% | 11.9% |
| CO vs 3-bet BTN 8.0bb — KhQh | 0.00 | 0.42 | 2.60 | call 5.5bb | 28.5% | 33.3% | 4.8% |
| BTN vs 3-bet BB 10.0bb — AhJd | 0.00 | 2.88 | 6.49 | call 7.5bb | 28.2% | 30.8% | 2.6% |

## Flop

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs c-bet 33% As7d2c — Kd8c | 0.00 | 0.13 | 0.79 | call 1.8bb | 78.4% | 75.3% | 3.1% |
| BB vs c-bet 33% Qc7h2d — 8h8d | 0.00 | 3.21 | 3.67 | call 1.8bb | 79.6% | 75.3% | 4.3% |
| BB vs c-bet 33% 9h8h4c — 6s5d | 0.00 | -0.09 | 2.41 | betRaise 10.0bb | 83.1% | 75.3% | 7.7% |
| BTN c-bet 33% As7d2c (farol/apuestas) — KhJd | 0.00 | 2.29 | 4.95 | check | 46.4% | 48.6% | 2.2% |
| BTN c-bet 75% QhJh8d (farol/apuestas) — Ah5h | 0.00 | 3.52 | 4.61 | betRaise 4.1bb | 62.1% | 65.7% | 3.6% |

## Turn

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB vs barrel 75% As7d2c5h — 7h6h | 0.00 | 2.97 | 2.89 | call 6.8bb | 57.7% | 57.2% | 0.5% |
| BB vs barrel 75% Qc7h2dKs — Qd9d | 0.00 | 5.20 | 4.63 | call 6.8bb | 57.6% | 57.2% | 0.4% |
| BB vs barrel 75% Kd8s3s4c — 8h7h | 0.00 | 3.40 | 2.68 | call 6.8bb | 59.0% | 57.2% | 1.8% |
| BTN double barrel 75% Kd7s2s4h (farol/apuestas) — AsQd | 0.00 | 2.38 | 5.64 | check | 30.9% | 51.0% | 20.1% |
| BTN double barrel 75% As7d2c5h (farol/apuestas) — KhQh | 0.00 | 2.15 | 6.38 | check | 38.8% | 51.0% | 12.2% |

## River

| Escenario y Mano | EV Fold (bb) | EV Call (bb) | EV Raise (bb) | Acción Tomada | Freq Motor | Freq GTO | Δ Nash |
|---|---|---|---|---|---|---|---|
| BB bluff-catch vs pot Kd8s3s4c2h — 8h7h | 0.00 | -6.17 | -20.70 | fold | 48.2% | 50.0% | 1.8% |
| BB bluff-catch vs pot As7d2c5h9s — Kd9c | 0.00 | -11.85 | -30.12 | fold | 47.7% | 50.0% | 2.3% |
| BB bluff-catch vs pot Qc7h2dKs3c — Qd9d | 0.00 | -3.77 | -16.29 | call 22.7bb | 45.5% | 50.0% | 4.5% |
| BTN river bet 125% Kd7s2s4h9s (farol/apuestas) — AsQd | 0.00 | 0.78 | 8.48 | betRaise 28.4bb | 29.0% | 35.7% | 6.7% |
| BTN river bet 33% Ks8s3d4cTh (farol/apuestas) — AhKd | 0.00 | 16.95 | 20.21 | betRaise 7.5bb | 35.9% | 19.9% | 16.0% |

## Promedio Δ Nash por calle

| Calle | Promedio Δ Nash | Estado |
|---|---|---|
| Preflop | 8.8% | **HUECO (> 5%)** |
| Flop | 4.2% | OK |
| Turn | 7.0% | **HUECO (> 5%)** |
| River | 6.3% | **HUECO (> 5%)** |

**Promedio global Δ Nash: 6.6%**
