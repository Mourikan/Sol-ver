# Final Metrics Audit — Δ Nash por calles

Generado por `docs/audit_scripts/metric_audit.dart` simulando el motor combo a combo. Δ Nash = |métrica del motor − referencia teórica| en puntos porcentuales (o distancia fuera de banda). Umbral: Δ > 8% sin justificación explotativa ⇒ fallo.

## Preflop

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| BB defensa vs BTN 2.5x | nl10 (microHighRake) | 45–55% (MDF ajustado EQR+rake) | 49.6% | 0.0 | OK |
| BB defensa vs BTN 2.5x | nl100 (midRake) | 45–55% (MDF ajustado EQR+rake) | 56.3% | 1.3 | OK |
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
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Reg | MDF 75.3% | 78.4% | 3.1 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Reg | MDF 75.3% | 78.3% | 3.0 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Reg | MDF 75.3% | 78.5% | 3.2 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl10 Reg | MDF 75.3% | 75.9% | 0.6 | OK |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl10 Reg | MDF 75.3% | 79.9% | 4.6 | OK |
| Defensa BB vs c-bet 33% (9h8h4c) | nl10 Reg | MDF 75.3% | 80.0% | 4.7 | OK |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Scared | MDF 75.3% | 71.0% | 4.3 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Scared | MDF 75.3% | 75.9% | 0.6 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Scared | MDF 75.3% | 78.0% | 2.7 | OK (Scared ≤NL50 factor 0.90) |
| Defensa BB vs c-bet 33% (As7d2c) | nl25 Fish | MDF 75.3% | 68.5% | 6.8 | OK (Regla Fish (factor 0.82)) · ALERTA <70% |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl25 Fish | MDF 75.3% | 70.3% | 5.0 | OK (Regla Fish (factor 0.82)) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl25 Fish | MDF 75.3% | 77.8% | 2.5 | OK (Regla Fish (factor 0.82)) |
| Defensa BB vs c-bet 33% (As7d2c) | nl100 Maniac | MDF 75.3% | 86.7% | 11.4 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (Qc7h2d) | nl100 Maniac | MDF 75.3% | 87.0% | 11.7 | Justificado: Regla Maniac (factor 1.15) |
| Defensa BB vs c-bet 33% (9h8h4c) | nl100 Maniac | MDF 75.3% | 87.5% | 12.2 | Justificado: Regla Maniac (factor 1.15) |

## Turn

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Double barrel 80% Kd7s2s-4h (semi 36 / puro 48 / valor 79) | Reg | geo2 = 51.5% | 51.5% | 0.0 | OK |
| Double barrel 80% Kd7s2s-4h (semi 36 / puro 283 / valor 79) | Scared (pot>35bb, capado) | geo2 = 51.5% x 2.0 = 100.0% | 80.1% | 19.9 | Justificado: Exploit_Bluff_Factor 2.0 (scaredMoneyReg) |
| Double barrel 80% Kd7s2s-4h (semi 28 / puro 0 / valor 79) | Fish | geo2 = 51.5% x 0.5 = 25.8% | 26.1% | 0.3 | OK (Exploit_Bluff_Factor 0.5 (recPassiveFish)) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Reg | 1-MDF = 42.8% | 42.3% | 0.5 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Reg | 1-MDF = 42.8% | 42.4% | 0.4 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Reg | 1-MDF = 42.8% | 41.0% | 1.8 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl10 Reg | 1-MDF = 42.8% | 42.5% | 0.3 | OK |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl10 Reg | 1-MDF = 42.8% | 42.6% | 0.2 | OK |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl10 Reg | 1-MDF = 42.8% | 40.2% | 2.6 | OK |
| Fold BB vs barrel 75% (As7d2c5h) | nl25 Scared | 1-MDF = 42.8% | 45.5% | 2.7 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl25 Scared | 1-MDF = 42.8% | 45.7% | 2.9 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl25 Scared | 1-MDF = 42.8% | 40.7% | 2.1 | OK (Scared ≤NL50 factor 0.90) |
| Fold BB vs barrel 75% (As7d2c5h) | nl100 Maniac | 1-MDF = 42.8% | 34.0% | 8.7 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Qc7h2dKs) | nl100 Maniac | 1-MDF = 42.8% | 34.0% | 8.7 | Justificado: Regla Maniac (factor 1.15) |
| Fold BB vs barrel 75% (Kd8s3s4c) | nl100 Maniac | 1-MDF = 42.8% | 34.1% | 8.6 | Justificado: Regla Maniac (factor 1.15) |

## River

| Spot/Nodo | Stake/Perfil | Métrica Teórica (MDF/α) | Métrica del Motor | Explotabilidad (Δ Nash %) | Estado |
|---|---|---|---|---|---|
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 55.9% vs blockers 36.0% | nl100 Reg | MDF 50.0% | 48.2% | 1.8 | OK |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 47.7% | 2.3 | OK |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Reg | MDF 50.0% | 45.5% | 4.5 | OK |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 58.0% vs blockers 19.9% | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 44.8% | 5.2 | OK (Ley MDA NL2-NL50 (CLAUDE.md §4)) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 37.3% | 12.7 | Justificado: Ley MDA NL2-NL50 (CLAUDE.md §4) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl10 Reg (MDA: triple barrel overbet) | MDF 50.0% | 36.0% | 14.0 | Justificado: Ley MDA NL2-NL50 (CLAUDE.md §4) |
| Bluff-catch vs pot (Kd8s3s4c2h) — unblockers 65.4% vs blockers 60.6% | nl100 Maniac | MDF 50.0% | 57.7% | 7.7 | OK (Regla Maniac (piso agro + factor 1.15)) |
| Bluff-catch vs pot (As7d2c5h9s) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 57.6% | 7.6 | OK (Regla Maniac (piso agro + factor 1.15)) |
| Bluff-catch vs pot (Qc7h2dKs3c) — n/a (sin proyecto de color) | nl100 Maniac | MDF 50.0% | 57.7% | 7.7 | OK (Regla Maniac (piso agro + factor 1.15)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Scared | >0% | 42.3% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | Reg NL50 | >0% | 42.3% | 0.0 | OK (Regla LLinus (rango capado)) |
| Conversión LLinus (overbet/all-in de no-valor) QhJh4c2h8d capado | CallingStation | 0% estricto | 0.0% | 0.0 | OK (Gate Fish/Station) |

**Nodos con Δ > 8% sin justificación: 0**
