# Sol-ver vs Solver CFR+ (PioSOLVER / GTO Wizard / MonkerSolver) — Evaluación técnica

## 0. Advertencia metodológica (leer primero)
- **No existe medición directa.** En este entorno no hay ningún solver ni exports de solver; todos los rangos preflop son **semillas aproximadas** de charts públicos (`RangeSource.calibratedHeuristicBase`) y `freq_gto` es `null` en todas las decisiones.
- Los porcentajes de este documento son **estimaciones razonadas** a partir de la arquitectura y de las métricas internas medidas (`docs/final_metrics_audit.md`), **no** resultados de un benchmark. Pueden desviarse ±10–15 pp.
- Métrica de referencia propuesta: *acuerdo de acción por combo* (misma acción principal que la acción de mayor frecuencia del solver) y, sobre todo, *pérdida de EV en mbb/mano* frente a la estrategia del solver. La segunda es la que importa y **no la podemos calcular** sin el solver.

## 1. Estimación por calle

| Calle | Acuerdo de acción estimado | Dónde somos (casi) idénticos | Limitación estructural |
|---|---|---|---|
| **Preflop** | **75–88%** (RFI ~85–90%; vs RFI ~75–85%; vs 3-bet / 4-bet ~65–80%) | RFI por posición dentro de ±2 pp de los % públicos; 3-bet-or-fold en high-rake; estructura polar IP / lineal OOP; ratio 4-bet farol/valor ≈ α (Δ 1–4 pp); A5s-A3s como blockers; defensa BB vs BTN 48–54% | Estrategias **puras** (sin mezclas); sizing fijo por nodo; rangos semilla, no resueltos; BB defensa por modelo `equity × EQR × posición` (EQR paramétrico); sin 5-bet trees completos ni stacks ≠100bb resueltos |
| **Flop** | **55–70%** | Range-bet 33% en A/K-high secos (SRP IP / 3BP); check alto del PFA OOP en boards bajos conectados; donk 0% en A/K-high, donk en bajos conectados/pareados bajos; defensa vs c-bet ≈ MDF (Δ 0–7 pp vs reg) | 1755 flops colapsados en **20 buckets**; 6 HandTiers en vez de 1326 combos; 1 sizing por bucket (solver mezcla 2–4); sin check-raise frecuencial salvo monsters/combo draws; frecuencias derivadas de una política, no de un equilibrio |
| **Turn** | **45–60%** | Ratio de faroles = α del sizing (double barrel 80% → 30.8% exacto); fold vs barrel ≈ 1−MDF (Δ 0–2.5 pp); semifaroles priorizados por equity retenida; overcard A/K favorece al PFA | Clasificación de carta en 3 clases (brick / rank-shift / completa) vs evaluación exacta de cada carta; rango de llegada reconstruido por presupuesto MDF, no por la estrategia real de flop; sizings discretos (33/66–85/100/125) |
| **River** | **50–65%** | Indiferencia B/(P+2B); defensa ≈ MDF (Δ 0.5–3.6 pp vs reg NL100); prioridad de unblockers (57% vs 43%); conteo real de combos valor/farol con card removal; overbet con nut blocker vs rango capado | Selección de faroles por reglas de blocker (color/escalera/top pair), no por EV de cada combo; sin thin-value sizing óptimo ni raise-bluffs de equilibrio; rango del villano filtrado con pesos de línea paramétricos (0.4/0.6/1.0) |
| **Global ponderado** | **≈ 60–72%** de acuerdo de acción (sin medir EV loss) | — | — |

## 2. Capacidad de adaptación explotativa

| Capacidad | Solver CFR+ | Sol-ver |
|---|---|---|
| Estrategia por defecto | Equilibrio (no explota) | Línea base aproximada al equilibrio + desviaciones por read |
| Node-locking | Exacto: bloquea frecuencias del rival y **recalcula la mejor respuesta** (GTOW/Monker/Pio) | Reglas fijas por arquetipo (Fish, Maniac, Scared, Trapper, timing, MDA). **No recalcula**: aplica factores y gates acotados (piso 0.5, factores 0.82–1.15) |
| Lectura de HUD / timing | No | Sí (SmartHUD GGPoker + timing tells) — ventaja práctica, pero los priors (85%, 70%, 0.5×) son declarados, no estimados con muestra |
| Velocidad | Segundos-minutos por spot (turn/river en vivo); preflop pre-resuelto | < 5 ms por decisión, offline, móvil |
| Garantías | Explotabilidad medida (mbb/100) | Invariantes de cordura y monotonía verificados por fuzzer; explotabilidad **no medida** |

## 3. Limitaciones estructurales exactas donde un solver CFR+ nos supera
1. **No hay cálculo de EV por acción.** Ninguna decisión compara EV(call) vs EV(raise) vs EV(fold) en el árbol completo; todas son reglas locales (MDF, α, pot odds, tiers). Un solver optimiza el EV global del árbol.
2. **Sin equilibrio recursivo.** Nuestras frecuencias en una calle no se ajustan a cómo responde el rival en las siguientes; CFR+ converge iterativamente en todo el árbol.
3. **Sin estrategias mixtas.** Cada combo tiene una única acción (salvo el hash determinista para mezclas importadas). Los solvers mezclan frecuencias por combo y por sizing; eso nos hace más predecibles.
4. **Abstracción gruesa.** 20 buckets de flop, 6 tiers de mano, 3 clases de carta de turn y sizings discretos. El solver resuelve cada board y cada combo.
5. **Rangos semilla.** El preflop no proviene de un solver, así que todo el postflop hereda ese error de rango.
6. **Multiway, SPR ≠ 100bb y 5-bet trees** solo están cubiertos de forma heurística (factor multiway, MDF compartido, call-off fijo).
7. **Parámetros de modelo no derivados de solver:** EQR paramétrico, pesos de línea del auditor, `policyMix` 0.15, EQR multiway 0.80, `Exploit_Defense_Factor`, priors MDA/timing.
8. **Explotabilidad desconocida.** Sin best-response no podemos cuantificar cuántos mbb/100 pierde Sol-ver frente a un bot que juegue la mejor respuesta contra él.

## 4. Cómo cerrar la brecha (medible)
1. Importar exports de GTO Wizard / Pio al `PackedLookupRepository` (`RangeSource.solverImport`) y activar `freq_gto` con mezclas deterministas por hash.
2. Benchmark: para N spots resueltos, medir acuerdo de acción por combo y pérdida de EV (mbb/mano) usando el EV del solver por acción.
3. Sustituir los buckets de flop por estrategias agregadas de solver por bucket (frecuencias por tier) y validar que Δ por bucket < 5 pp.
4. Calibrar EQR y pesos de línea contra la realización de equity que reporta el solver por combo.

---

## 5. Actualización Fase 8.5 (cierre parcial de brecha CFR+)

### 5.1 Qué cambió (y qué NO)
| Capacidad | Antes | Ahora | Origen de los números |
|---|---|---|---|
| Estrategias mixtas preflop | Puras | Mezclas por combo exacto con `DeterministicActionMixer` (hash de cartas con palos + board + bote) | A5s BTN vs CO 75/25/0 y 88 CO vs MP 35/65/0 · 35/0/65: **valores del usuario**. Frontera BB: **derivada por margen de equity ±3%** + corrección isotónica. Etiqueta `modelCalibrated`, **no** `solverCalibrated` |
| `freq_gto` | `null` | Poblado en el 100% de decisiones (`{acción: %}`, acción mayoritaria, `freq_source`) | Verificado en `test/solver_calibration_test.dart` |
| Stacks 40–200bb | Solo 100bb | Set-mining ≥12x, commit 3-bet ≥25% del stack, EQR por profundidad | Parámetros de modelo |
| Flop | 1 sizing por bucket, tier→acción pura | Matriz por tier `[Check, B33, B75]` + trap 20% de monsters en boards dinámicos / sin RA | Parámetros de modelo ordenados por RA/NA |
| Check-raise flop OOP | Solo monsters / FD+OESD | Frecuencial por tier; **10.7% global** vs c-bet 33% en 8 boards (objetivo del usuario 10–14%) | Cuotas por tier calibradas al objetivo del usuario, no a un solver |
| EQR postflop | EQR preflop × posición | `EQR(categoría, IP/OOP, SPR)` | Anclas del usuario (SC IP SPR>6 = 1.00; offsuit broadway OOP SPR bajo = 0.68), resto interpolado |
| Rango de llegada | Recorte plano por MDF | Peso por la probabilidad con la que **nuestra política** habría tomado la línea observada (bet/check por matriz, call = presupuesto − X/R) | Política propia, no la del solver |
| River thin value | 50–66% | 33% vs rango condensado medio; 50–66% vs fish; 75–125% solo monsters + faroles | Regla del usuario |

### 5.2 Métricas tras el cambio (docs/final_metrics_audit.md)
- 0 nodos con Δ Nash > 8% sin justificación (54 nodos).
- Range bet A/K-high secos: 72–81% (antes 58–83%).
- Defensa BB vs c-bet 33% (Reg): 77–88%; la parte por encima de MDF son calls +EV de la invariante Equity_Real ≥ Pot Odds.
- Turn: fold vs barrel 75% = 41–43% (objetivo 42.8%). River vs pot (Reg NL100): 47–50%.
- Rango de check del PFA con monsters en boards dinámicos: 2.7–4.5% (antes 0%).

### 5.3 Acuerdo estimado actualizado (sigue SIN benchmark contra solver)
| Calle | Fase 8 | Fase 8.5 | Por qué sube |
|---|---|---|---|
| Preflop | 75–88% | 77–89% | Mezclas en fronteras; mismos rangos semilla |
| Flop | 55–70% | 60–74% | Multisizing por tier, X/R frecuencial, trap |
| Turn | 45–60% | 48–62% | Rango de llegada por política ejecutada |
| River | 50–65% | 53–67% | Sizing thin/block vs polar |
| Global | 60–72% | **63–75%** | — |

Las limitaciones estructurales de la sección 3 (sin cálculo de EV por acción, sin equilibrio recursivo, abstracción por buckets/tiers, rangos semilla) **siguen vigentes**. Las mezclas y matrices nuevas son priors del modelo: reducen la predictibilidad y la abstracción, pero no garantizan que las frecuencias coincidan con las del solver. La única forma de validarlas es importar exports reales (`RangeSource.solverImport`) y medir pérdida de EV.
