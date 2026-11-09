# Final Metrics Audit — Δ Nash por calles

Generado por `docs/audit_scripts/metric_audit.dart` simulando el motor combo a combo. Δ Nash = |métrica del motor − referencia teórica| en puntos porcentuales (o distancia fuera de banda). Umbral: Δ > 8% sin justificación explotativa ⇒ fallo.

## Preflop

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| BB defensa vs BTN 2.5x | nl10 (microHighRake) | 45–55% (MDF ajustado EQR+rake) | 49.6% | 0.0 | OK |
| BB defensa vs BTN 2.5x | nl100 (midRake) | 45–55% (MDF ajustado EQR+rake) | 53.5% | 0.0 | OK |
| 4-bet farol/(valor+farol): CO vs 3-bet BTN (OOP 2.5x) | Reg/GTO | α = 28.9% | 26.1% (12 farol / 34 valor) | 2.8 | OK |
| 4-bet farol/(valor+farol): CO vs 3-bet BTN (OOP 2.5x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 34 valor) | 0.0 | OK |
| 4-bet farol/(valor+farol): BTN vs 3-bet BB (IP 2.2x) | Reg/GTO | α = 27.0% | 26.1% (12 farol / 34 valor) | 0.9 | OK |
| 4-bet farol/(valor+farol): BTN vs 3-bet BB (IP 2.2x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 34 valor) | 0.0 | OK |
| 4-bet farol/(valor+farol): UTG vs 3-bet CO (OOP 2.5x) | Reg/GTO | α = 28.9% | 33.3% (8 farol / 16 valor) | 4.4 | OK |
| 4-bet farol/(valor+farol): UTG vs 3-bet CO (OOP 2.5x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 16 valor) | 0.0 | OK |

## Flop

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Range bet 33% BTN vs BB (As7d2c, aceHighDry) | SRP IP | ≥60% (definición range-bet) | 75.1% | 0.0 | OK |
| Range bet 33% BTN vs BB (AsKd2c, aceHighDry) | SRP IP | ≥60% (definición range-bet) | 80.9% | 0.0 | OK |
| Range bet 33% BTN vs BB (Kd7c2h, kingHighDry) | SRP IP | ≥60% (definición range-bet) | 72.2% | 0.0 | OK |
| Range bet 33% BTN vs BB (KsQd2h, kingHighDry) | SRP IP | ≥60% (definición range-bet) | 79.1% | 0.0 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Reg | MDF 75.3% | 78.2% | 2.9 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Reg | MDF 75.3% | 80.3% | 5.0 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Reg | MDF 75.3% | 88.2% | 12.9 | Justificado: Invariante Equity_Real ≥ Pot Odds: +12.2% de calls +EV directos sobre el presupuesto MDF (76.0%) |
| Defensa BB vs c-bet 33% (As7d2c) | nl10 Reg | MDF 75.3% | 77.2% | 1.9 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl10 Reg | MDF 75.3% | 80.9% | 5.6 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl10 Reg | MDF 75.3% | 86.4% | 11.1 | Justificado: Invariante Equity_Real ≥ Pot Odds: +10.2% de calls +EV directos sobre el presupuesto MDF (76.1%) |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Scared | MDF 75.3% | 71.7% | 3.6 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Scared | MDF 75.3% | 80.9% | 5.6 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Scared | MDF 75.3% | 86.1% | 10.8 | Justificado: Scared ≤NL50 factor 0.90; Invariante Equity_Real ≥ Pot Odds: +18.1% de calls +EV directos sobre el presupuesto MDF (68.0%) |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Fish | MDF 75.3% | 69.3% | 6.0 | OK (Regla Fish (factor 0.82)) · ALERTA <70% |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Fish | MDF 75.3% | 80.9% | 5.6 | OK (Regla Fish (factor 0.82)) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Fish | MDF 75.3% | 86.1% | 10.8 | Justificado: Regla Fish (factor 0.82) |
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Maniac | MDF 75.3% | 87.5% | 12.2 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Maniac | MDF 75.3% | 87.7% | 12.4 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Maniac | MDF 75.3% | 91.2% | 15.9 | Justificado: Regla Maniac (factor 1.15) |

## Turn

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Double barrel 80% Kd7s2s-4h (semi 35 / puro 0 / valor 79) | Reg | α = 30.8% | 30.9% | 0.1 | OK |
| Double barrel 80% Kd7s2s-4h (semi 36 / puro 92 / valor 79) | Scared (pot>35bb, capado) | α = 30.8% x 2.0 = 61.5% | 61.7% | 0.1 | OK (Exploit_Bluff_Factor 2.0 (scaredMoneyReg)) |
| Double barrel 80% Kd7s2s-4h (semi 15 / puro 0 / valor 79) | Fish | α = 30.8% x 0.5 = 15.4% | 15.8% | 0.4 | OK (Exploit_Bluff_Factor 0.5 (recPassiveFish)) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Reg | 1-MDF = 42.8% | 42.1% | 0.7 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Reg | 1-MDF = 42.8% | 42.3% | 0.5 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Reg | 1-MDF = 42.8% | 41.1% | 1.7 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl10 Reg | 1-MDF = 42.8% | 42.5% | 0.3 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl10 Reg | 1-MDF = 42.8% | 42.6% | 0.2 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl10 Reg | 1-MDF = 42.8% | 41.1% | 1.6 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl25 Scared | 1-MDF = 42.8% | 45.5% | 2.8 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl25 Scared | 1-MDF = 42.8% | 45.7% | 2.9 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl25 Scared | 1-MDF = 42.8% | 41.4% | 1.4 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Maniac | 1-MDF = 42.8% | 32.7% | 10.1 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Maniac | 1-MDF = 42.8% | 32.9% | 9.8 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Maniac | 1-MDF = 42.8% | 33.8% | 8.9 | Justificado: Regla Maniac (factor 1.15) |

## River

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 59.4% vs blockers 34.2% | nl100 Reg | MDF 50.0% | 49.8% | 0.2 | OK |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 48.1% | 1.9 | OK |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 47.4% | 2.6 | OK |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 62.1% vs blockers 19.9% | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 47.2% | 2.8 | OK (Ley MDA NL2-NL50 (CLAUDE.md §4)) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 38.5% | 11.5 | Justificado: Ley MDA NL2-NL50 (CLAUDE.md §4) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 36.0% | 14.0 | Justificado: Ley MDA NL2-NL50 (CLAUDE.md §4) |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 68.5% vs blockers 59.6% | nl100 Maniac | MDF 50.0% | 58.6% | 8.6 | Justificado: Regla Maniac (piso agro + factor 1.15) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 58.6% | 8.6 | Justificado: Regla Maniac (piso agro + factor 1.15) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 61.1% | 11.1 | Justificado: Regla Maniac (piso agro + factor 1.15) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Scared | >0% | 41.3% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Reg NL50 | >0% | 41.3% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | CallingStation | 0% estricto | 0.0% | 0.0 | OK (Gate Fish/Station) |

**Nodos con Δ > 8% sin justificación: 0**
