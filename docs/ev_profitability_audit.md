# Auditoría Integral de EV por Stake, Rentabilidad Post-Rake y Caza de Huecos (Fase 9.55)

Generado por `docs/audit_scripts/full_ev_profitability_and_leaks_audit.dart` (30 nodos, 7560 decisiones auditadas en 9265 ms).

> **No es un winrate (CLAUDE.md §8).** Los pesos `w_i` de la cesta son una plantilla declarada, no frecuencias medidas; el EV es el de `ActionEvCalculator` desde el nodo (rake incluido en el bote final), no el EV de la mano completa. Por eso no se emite el veredicto "RENTABLE / PERDEDOR por rake": requiere frecuencias reales de spots y del pool, que el proyecto no tiene ni debe registrar.

## Tabla 1 — Índice de cesta por stake (bb por 100 nodos ponderados; pool del nivel en FULL_EXPLOIT)

| Stake | Rake del bote en nodo (bb/100 nodos) | EV Ancla GTO (bb/100 nodos) | EV Full-Exploit (bb/100 nodos) | Ganancia Pura Exploit (+bb/100 nodos) | Estado |
|---|---|---|---|---|---|
| NL2 | 36.5 | 342.2 | 362.2 | +20.0 | EXPLOIT +EV (Δ>0) |
| NL5 | 36.5 | 342.4 | 362.4 | +20.0 | EXPLOIT +EV (Δ>0) |
| NL10 | 36.5 | 336.1 | 348.3 | +12.2 | EXPLOIT +EV (Δ>0) |
| NL25 | 36.5 | 335.1 | 347.6 | +12.5 | EXPLOIT +EV (Δ>0) |
| NL50 | 36.5 | 363.8 | 363.8 | +0.0 | NEUTRO (ancla Nash) |
| NL100 | 36.5 | 364.2 | 364.2 | +0.0 | NEUTRO (ancla Nash) |
| NL200 | 35.5 | 366.0 | 366.0 | +0.0 | NEUTRO (ancla Nash) |

NL50-NL200: sin lectura individual el motor usa Reg_GTO/Unknown_Reg con escudo (CLAUDE.md §9, parche vector NL50) => Δ = 0 por diseño. Con etiqueta explotativa ver barrido por arquetipo.

### Barrido adversario por arquetipo (30 nodos x 7 stakes x hasta 6 manos)

| Arquetipo | Desviaciones vs ancla | Desviaciones con Δ < 0 | Δ medio por desviación (bb) |
|---|---|---|---|
| Fish | 322 | 0 | 2.73 |
| Nit | 182 | 0 | 1.99 |
| Scared_Reg | 136 | 0 | 2.30 |
| Maniac | 160 | 0 | 4.08 |
| Trapper | 344 | 0 | 5.79 |
| Pool_Default | 132 | 0 | 2.11 |

## Tabla 2 — Aporte de EV por bloque explotativo (+bb por spot desviado, todos los arquetipos y stakes)

| Bloque | Spots desviados | +Δ EV medio (bb/spot) | Δ total (bb) |
|---|---|---|---|
| SmartHUD Tags (perfil) | 708 | 3.24 | 2291.5 |
| Terminaciones T1-T6 | 249 | 3.54 | 882.1 |
| Geo-2E / Monocolor / Squeeze | 90 | 7.38 | 663.8 |
| Guardas (Sanity/Ancla/Gate) | 77 | 5.95 | 458.1 |
| Timing Tells | 78 | 1.18 | 92.3 |
| Presets / Spots sin HUD | 74 | 1.18 | 87.5 |

## Tabla 3 — Mapa de huecos y colisiones auditadas

| ID Hueco / Cruce | Módulos implicados | Fuga detectada (bb) | Resolución / Estado final |
|---|---|---|---|
| C1 T2 vs Busted_Draw | T2_Shutdown, Busted_Draw_Runout, Bluff_Combo_Audit | 0.00 (T2 cede) | SELLADO: T2 cede si runout de proyectos fallidos y Hero no bloquea; decide el auditor por combos (call, Δ 0.00bb) |
| C2 Insta-Check Overbet vs Four_To_A_Flush | Insta_Check_Overbet, MonotoneFourFlush, Profile_Gate | -1.17 (antes de sellar: overbet de farol frenado solo por el ancla) | SELLADO (9.55): el candado Four_To_A_Flush prevalece en el bloque Insta-Check y en un guard central de faroles explotativos |
| C3 Micro_Block vs Donk_Tell | Micro_Block_Punisher, DonkTellDecoder | 0.00 | SELLADO (9.4): los min-donks contra nuestra iniciativa los resuelve DonkTellDecoder |
| C4 Underpair_Pain_Guard vs EV_Sanity_Guard | ThreeBet_Underpair_Pain_Guard, EV_Sanity_Guard | 0.00 | Jerarquía correcta: el Sanity_Guard veta folds con equity realizada >= pot odds (decisión final call) |
| C5 T2 vs Shield (NL50 agresivo) | T2_Shutdown, Anti_Counter_Exploit_Shield | 0.00 | SELLADO: el escudo apaga T2 |
| B1 Geo-2E SPR 1.55 vs 1.60 | Geometric2EPlanner | sin Geo -> 55% | Discontinuidad de diseño: < 1.6 el sizing sale del nodo (75% o all-in por SPR); documentado, no es fuga de EV del ancla |
| B2 Stack 19.9bb vs 20bb (55 vs open CO) | StackTopologyResolver | call -> fold | Salto de frontera (ventana 20-48bb, prior del usuario) |
| B3 Morphology_Buckets suma 100% | VillainRangeInspector | 0 / 7308 fuera de tolerancia | OK |
| H1 Fish SB/BTN: 3-bet bluff eliminado sin puerta de EV (P3, 21 casos) | Station preflop, preflopEVs | -0.39 a -2.17 | SELLADO: FE preflop por perfil (station x0.5) + eliminación solo si EV(3-bet al sizing real) <= 0 |
| H2 Fish BB: 3-bet polar/valor vs station peor que call (P4/P5) | Station preflop | -0.22 a -0.69 | SELLADO: argmax(call, 3-bet) al sizing real; equity vs RFI del villano ancho |
| H3 Nit: FE x1.2 aplicado a su 3-bet nutted (P8) | profileFe, vs3Bet | -2.95 | SELLADO: vs 4-bet el 3-bet del nit (<= 4.5%) foldea x0.5 |
| H4 Trapper: modelo EV con rango posicional (no 85% AA/KK/AKs) => checks/folds del perfil con Δ < 0 (F1/F5/X2/R3/R4) | RangeEquity, ActionEvCalculator | hasta -1.0 | SELLADO: rango del trapper mezclado 85/15 por combos y FE <= 15% |
| H5 Maniac: expansión 3-bet +12% y calls extra (x1.18) con Δ < 0 (P4/P5/F4) | Maniac preflop, DefenseBudget | hasta -1.29 | SELLADO: expansión con puerta EV; call por encima del ancla con Δ < 0 vuelve a la defensa del ancla (MDF del ancla intacto) |
| H6 Station: FE flop/turn = 50% del bruto vs premisa de la regla (FE ~ 0) | ActionEvCalculator, Profile_Gate | -0.04 a -0.53 | SELLADO: FE station <= 5% en todas las calles; candado de farol solo en River (CLAUDE.md §1.3) |
| H7 Maniac: rango de apuesta con descuento de aire (sub-modelaba su sobre-farol) | RangeEquity | — | SELLADO: el maniac apuesta con todo su rango en el modelo |
| H8 Medición: EV preflop del 3-bet a 3x fijo vs sizing real 4-5x | preflopEVs | — | SELLADO: EV por defecto al sizing que el motor juega |
| N1 Nodos con exploitDeltaEV < 0 | Todas las capas explotativas | 0.00 | OK: 0 desviaciones con Δ < 0 en el barrido |

### Contra-explotación por nivel (regular agresivo PFR 26 / 3B 11 vs pool sin HUD)

| Stake | Escudo vs agresivo | Factor defensa vs agresivo | Perfil por defecto | Estado sin HUD |
|---|---|---|---|---|
| NL25 | OFF | 1.00 | poolDefault | Pool NL2-NL25: folds MDA/T2 (sin regulares agresivos dominantes) |
| NL50 | ON | 1.00 | unknownReg | protegido |
| NL100 | ON | 1.00 | unknownReg | protegido |
| NL200 | ON | 1.00 | unknownReg | protegido |

## Tabla 4 — Scorecard final del motor

| Eje | Nota | Fundamento |
|---|---|---|
| Consistencia Interna | 100% | Morphology_Buckets suman 100% en 7308 rangos; ancla/gate/sanity jerarquizados |
| Δ Nash Base | 96% | Δ Nash global 2.4% <= 2.5% (cold_numbers_benchmark, referencias teóricas, no solver) |
| Rentabilidad Explotativa Post-Rake | 100% | % de desviaciones explotativas con Δ EV >= 0 bajo el perfil asumido (EV con rake); no es winrate |
| Cero Huecos Lógicos | 100% | 0 nodos con Δ < 0; colisiones abiertas: 0; vector NL50 cerrado (Unknown_Reg + escudo por defecto); NL2-NL25 sin HUD sigue usando priors MDA del pool |

