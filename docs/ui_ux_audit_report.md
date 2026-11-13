# UI/UX Audit Report — Fase 16.5

Fuente: `test/ui_ux_exhaustive_audit_test.dart` (widget tests + escaneo estático de `lib/ui/`). `lib/core/` no se tocó.

## Tabla 1 — Estado de los 8 ejes del usuario

| Eje | Estado inicial | Fallos detectados | Corrección aplicada / Estado final |
|---|---|---|---|
| U1 Monochrome Titanium | PASS | 0 colores saturados hardcodeados (los alias `AppColors.amber/cyan/...` ya son grises) | Sin cambios · **PASS** |
| U2 Setup 1° mano → 2° posición + teclado abajo | PARCIAL | Teclas de rango a 41dp de ancho en 360px (padding del dock + sección) | Dock sin sección y gutter 4px: teclas ≥ 46dp; palos solo ♠♥♦♣ · **PASS** |
| U3 Preflop ordenado + folds implícitos | PASS | 0 deadlocks en OR→3B (asiento posterior y BB) y OR→3B→4B→5B→Call | Invariante "siempre hay un control activo" verificada en cada toque · **PASS** |
| U4 Barra contextual | FALLO | Si el Call de Hero cerraba la calle, la barra para re-ajustar la subida del villano desaparecía; re-ajustar no restauraba los folds implícitos (Hero no se re-evaluaba) | Barra de re-ajuste visible también mientras se piden las cartas del flop; al aplicar se restauran los folds y Hero se re-evalúa solo · **PASS** |
| U5 Auto-commit + Oráculo visible | PASS | — | Oráculo + porqué sin truncar visibles al cerrar la calle; `[Hice otra cosa]` presente · **PASS** |
| U6 Postflop calle a calle multiway | PASS | 0 corrupciones de orden (fold a mitad de flop 4-way + check-raise en turn) | — · **PASS** |
| U7 Dual-Table | PASS | — | Cambio de mesa 0.1 µs (estado) / 1 µs (con UI); Rush Reset 0.7 µs; aislamiento total A/B · **PASS** |
| U8 Geometría y targets | FALLO | `pos-*` 37×36 en 360px; `new-hand`/`override` 40dp alto; `hud-*` 24dp; chips de acción 40dp; flechas de barra 40dp; `rush-reset` 41dp | Densidad visual estándar, grid de posición 3×2 a ancho completo (46dp), chips 44dp, HUD 44dp, flechas 44dp, tabs 48dp · **PASS** (0 overflows en 360×780, 390×844, 412×915) |

## Tabla 2 — Conteo de toques (medido en los tests)

| Escenario | Toques |
|---|---|
| Steal preflop (2 cartas + posición + [Mi turno] + [Todos foldearon]) | 7 |
| Defensa vs 3-Bet (2 cartas + posición + [Mi turno] + 3-Bet BTN + [Mi turno]) | 8 |
| Mano completa hasta Showdown (BTN vs CO, 3 calles + river) | 22 |
| Cambio Mesa 1 ↔ 2 | 1 |

## Tabla 3 — Mejoras de pulido visual y ergonómico aplicadas

| Mejora | Archivo |
|---|---|
| `VisualDensity.standard` (targets ≥ 44dp) | `lib/ui/theme.dart` |
| Grid de posición 3×2 a ancho completo, botones 46dp | `lib/ui/screens/solver_cockpit_screen.dart` |
| Teclado de cartas sin sección extra, gutter 4px (teclas ≥ 46dp en 360px) | `solver_cockpit_screen.dart`, `two_step_card_picker.dart` |
| Chips de acción preflop 44dp, chip HUD 44dp, botón "Aplicar" 44dp | `lib/ui/widgets/preflop_ordered_table_view.dart` |
| Re-ajuste de la subida del villano visible al pedir el flop + restauración de folds + re-evaluación de Hero | `preflop_ordered_table_view.dart`, `solver_cockpit_screen.dart` |
| Flechas ◄ ► de la barra a 44dp | `lib/ui/widgets/bet_size_scrubber_bar.dart` |
| Tabs Mesa 1/2 a 48dp (Rush Reset ≥ 44dp) | `solver_cockpit_screen.dart` |
| Eliminado widget huérfano `live_line_breadcrumb.dart` | `lib/ui/widgets/` |
