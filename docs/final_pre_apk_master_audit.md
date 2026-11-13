# Auditoría Maestra Pre-APK (Fase 9.9)

Generado por `docs/audit_scripts/master_pre_apk_audit.dart` (2026-11-13T18:16 UTC).

## 1. Resumen ejecutivo y veredicto

**Veredicto: READY FOR APK RELEASE (configuración y código certificados).**

> El contenedor de auditoría **no tiene Android SDK**: `flutter build apk` no se ejecutó aquí. Código, tests, manifest y Gradle están certificados; el binario debe compilarse en una máquina con Android SDK (comando en §5).

| Vector | Estado | Detalle |
|---|---|---|
| V1 | PASS | analyze: 0 errors, 0 warnings, 0 infos | tests: 236/236 PASS | manifest main: sin permisos | pubspec: solo Flutter SDK | release: key.properties o firma debug |
| V2 | PASS | Δ Nash 2.4% | metric_audit fallos 0 | Coverage 10/10 | monotonía 169x7 OK | buckets fuera 0/7308 | NL50+ Unknown_Reg+escudo ON |
| V3 | PASS | exploitDeltaEV<0: 0 (6 arquetipos x 7 stakes) | colisiones abiertas 0 | módulos dev 1669, Δ<=0 0 | T1-T6 6/6 sin Δ<=0 |
| V4 | PASS | FSM tortura OK (closures=4 pot=119.00), Action_Closure_Invariant y rewind exacto |
| V5 | PASS | 0 overflows en 360x780, 390x844, 412x915 | narrativa 555/555 | RunoutForecast 370/370 | latencia p50 0.36 ms p99 1.26 ms | PackedLookupRepository 2.35 ms |
| V6 | PASS | 0 persistencia/red en lib/ (sin Hand History, sin BD, sin HTTP/sockets) |

## 2. Salud técnica

| Ítem | Resultado |
|---|---|
| `flutter analyze --no-pub` | 0 errors, 0 warnings, 0 infos |
| `flutter test` | 236 PASS / 0 FAIL |
| Latencia evaluación completa (370 decisiones postflop, 5 perfiles) | p50 0.36 ms · p99 1.26 ms |
| Arranque `PackedLookupRepository` | 2.35 ms |
| Manifest release (`src/main`) | sin permisos (100% offline; INTERNET solo en debug/profile para hot reload) |
| Dependencias `pubspec.yaml` | solo Flutter SDK (0 paquetes externos) |
| Firma release | firma debug en release (APK instalable por sideload; para Play Store añadir keystore propio) |
| Android SDK en el entorno | ausente (build no ejecutado aquí) |

## 3. Certificación matemática y explotativa

| Ítem | Resultado |
|---|---|
| Δ Nash global (Reg_GTO) | 2.4% (<= 2.5%) |
| metric_audit / Coverage | 0 fallos / 10/10 |
| exploitDeltaEV < 0 (6 arquetipos x 7 stakes x 30 nodos) | 0 |
| Módulos explotativos (benchmark) | dev 1669, Δ<=0 0 |
| Terminaciones | T1: dev 223, Δ<=0 0, +Δ 1.46bb · T2: dev 183, Δ<=0 0, +Δ 11.26bb · T3: dev 251, Δ<=0 0, +Δ 2.58bb · T4: dev 12, Δ<=0 0, +Δ 2.54bb · T5: dev 68, Δ<=0 0, +Δ 0.68bb · T6: dev 691, Δ<=0 0, +Δ 2.38bb |
| Índice de cesta EV Full-Exploit (bb/100 nodos, NO winrate) | nl2:362.2 nl5:362.4 nl10:348.3 nl25:347.6 nl50:363.8 nl100:364.2 nl200:366.0 |
| Parche NL50+ (Unknown_Reg + escudo) | ON en NL50-NL200; Pool en NL2-NL25 |
| Freak Fish (click-back, nano-bet, min-raise, all-in incompleto) | cubierto por `test/freak_fish_sizings_test.dart` y la tortura FSM |

## 4. Interfaz Obsidian Tactical HUD y máquina de estados

| Ítem | Resultado |
|---|---|
| HandFlowFSM tortura (click-back, re-raise, nano-bet, min-raise, all-in incompleto) | closures=4 pot=119.00 |
| Rewind (LiveLineBreadcrumb) | restauración exacta + reproducción idéntica del pot final |
| Narrativa en español (3 campos) | 555/555 nodos |
| RunoutForecast Flop/Turn | 370/370 |
| Overflows (360x780, 390x844, 412x915) incl. heatmap 13x13 | 0 |
| Privacidad | 0 persistencia/red en lib/ (sin Hand History, sin BD, sin HTTP/sockets) |

## 5. Compilación final

```
flutter build apk --release --split-per-abi
```

Salida: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (+ armeabi-v7a, x86_64). Peso estimado (no medido aquí): ~7-10 MB por ABI, típico de una app Flutter release sin assets pesados ni paquetes externos. Para Play Store: crear keystore y `android/key.properties` (storeFile, storePassword, keyAlias, keyPassword).
