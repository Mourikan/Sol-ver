# Final Metrics Audit — Δ Nash por calles

Generado por `docs/audit_scripts/metric_audit.dart` simulando el motor combo a combo. Δ Nash = |métrica del motor − referencia teórica| en puntos porcentuales (o distancia fuera de banda). Umbral: Δ > 8% sin justificación explotativa ⇒ fallo.

## Preflop

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| BB defensa vs BTN 2.5x | nl10 (microHighRake) | 45–55% (MDF ajustado EQR+rake) | 48.4% | 0.0 | OK |
| BB defensa vs BTN 2.5x | nl100 (midRake) | 45–55% (MDF ajustado EQR+rake) | 54.4% | 0.0 | OK |
| 4-bet farol/(valor+farol): CO vs 3-bet BTN (OOP 2.5x) | Reg/GTO | α = 28.9% | 26.1% (12 farol / 34 valor) | 2.8 | OK |
| 4-bet farol/(valor+farol): CO vs 3-bet BTN (OOP 2.5x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 34 valor) | 0.0 | OK |
| 4-bet farol/(valor+farol): BTN vs 3-bet BB (IP 2.2x) | Reg/GTO | α = 27.0% | 26.1% (12 farol / 34 valor) | 0.9 | OK |
| 4-bet farol/(valor+farol): BTN vs 3-bet BB (IP 2.2x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 34 valor) | 0.0 | OK |
| 4-bet farol/(valor+farol): UTG vs 3-bet CO (OOP 2.5x) | Reg/GTO | α = 28.9% | 33.3% (8 farol / 16 valor) | 4.4 | OK |
| 4-bet farol/(valor+farol): UTG vs 3-bet CO (OOP 2.5x) | Fish | 0% (Recreativo) | 0.0% (0 farol / 16 valor) | 0.0 | OK |

## Flop

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Range bet 33% BTN vs BB (As7d2c, aceHighDry) | SRP IP | ≥60% (definición range-bet) | 65.9% | 0.0 | OK |
| Range bet 33% BTN vs BB (AsKd2c, aceHighDry) | SRP IP | ≥60% (definición range-bet) | 83.1% | 0.0 | OK |
| Range bet 33% BTN vs BB (Kd7c2h, kingHighDry) | SRP IP | ≥60% (definición range-bet) | 57.8% | 2.2 | OK |
| Range bet 33% BTN vs BB (KsQd2h, kingHighDry) | SRP IP | ≥60% (definición range-bet) | 77.0% | 0.0 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Reg | MDF 75.3% | 76.4% | 1.1 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Reg | MDF 75.3% | 76.4% | 1.1 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Reg | MDF 75.3% | 75.4% | 0.1 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl10 Reg | MDF 75.3% | 75.4% | 0.1 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl10 Reg | MDF 75.3% | 75.6% | 0.3 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl10 Reg | MDF 75.3% | 75.6% | 0.3 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Scared | MDF 75.3% | 68.7% | 6.6 | OK (Scared ≤NL50 factor 0.90) · ALERTA <70% |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Scared | MDF 75.3% | 70.2% | 5.1 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Scared | MDF 75.3% | 69.1% | 6.2 | OK (Scared ≤NL50 factor 0.90) · ALERTA <70% |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Fish | MDF 75.3% | 62.3% | 13.0 | Justificado: Regla Fish (factor 0.82) · ALERTA <70% |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Fish | MDF 75.3% | 61.9% | 13.4 | Justificado: Regla Fish (factor 0.82) · ALERTA <70% |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Fish | MDF 75.3% | 62.0% | 13.3 | Justificado: Regla Fish (factor 0.82) · ALERTA <70% |
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Maniac | MDF 75.3% | 87.2% | 11.9 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Maniac | MDF 75.3% | 86.8% | 11.5 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Maniac | MDF 75.3% | 86.9% | 11.6 | Justificado: Regla Maniac (factor 1.15) |

## Turn

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Double barrel 80% Kd7s2s-4h (semi 36 / puro 0 / valor 81) | Reg | α = 30.8% | 30.8% | 0.0 | OK |
| Double barrel 80% Kd7s2s-4h (semi 85 / puro 45 / valor 81) | Scared (pot>35bb, capado) | α = 30.8% x 2.0 = 61.5% | 61.6% | 0.1 | OK (Exploit_Bluff_Factor 2.0 (scaredMoneyReg)) |
| Double barrel 80% Kd7s2s-4h (semi 15 / puro 0 / valor 81) | Fish | α = 30.8% x 0.5 = 15.4% | 15.6% | 0.2 | OK (Exploit_Bluff_Factor 0.5 (recPassiveFish)) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Reg | 1-MDF = 42.8% | 42.0% | 0.7 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Reg | 1-MDF = 42.8% | 42.3% | 0.5 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Reg | 1-MDF = 42.8% | 42.7% | 0.1 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl10 Reg | 1-MDF = 42.8% | 42.8% | 0.0 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl10 Reg | 1-MDF = 42.8% | 41.9% | 0.9 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl10 Reg | 1-MDF = 42.8% | 40.9% | 1.8 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl25 Scared | 1-MDF = 42.8% | 46.9% | 4.1 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl25 Scared | 1-MDF = 42.8% | 46.9% | 4.1 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl25 Scared | 1-MDF = 42.8% | 47.6% | 4.8 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Maniac | 1-MDF = 42.8% | 30.9% | 11.9 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Maniac | 1-MDF = 42.8% | 34.0% | 8.8 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Maniac | 1-MDF = 42.8% | 34.1% | 8.6 | Justificado: Regla Maniac (factor 1.15) |

## River

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 57.1% vs blockers 43.1% | nl100 Reg | MDF 50.0% | 50.5% | 0.5 | OK |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 52.0% | 2.0 | OK |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 46.4% | 3.6 | OK |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 61.9% vs blockers 25.9% | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 47.2% | 2.8 | OK (Ley MDA NL2-NL50 (CLAUDE.md §4)) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 47.7% | 2.3 | OK (Ley MDA NL2-NL50 (CLAUDE.md §4)) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 38.5% | 11.5 | Justificado: Ley MDA NL2-NL50 (CLAUDE.md §4) |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 66.9% vs blockers 48.1% | nl100 Maniac | MDF 50.0% | 58.5% | 8.5 | Justificado: Regla Maniac (piso agro + factor 1.15) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 58.1% | 8.1 | Justificado: Regla Maniac (piso agro + factor 1.15) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 57.9% | 7.9 | OK (Regla Maniac (piso agro + factor 1.15)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Scared | >0% | 32.4% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Reg NL50 | >0% | 32.4% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | CallingStation | 0% estricto | 0.0% | 0.0 | OK (Gate Fish/Station) |

**Nodos con Δ > 8% sin justificación: 0**
