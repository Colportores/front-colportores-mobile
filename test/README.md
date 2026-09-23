# Tests — plantilla y convenciones

Este documento fija el patrón de testing que ya usa el repo, para que el resto de Fase 1 lo
siga sin reinventarlo (issue #9). No inventa reglas nuevas: describe lo que hoy ya está en
`test/` y enlaza a los archivos reales que lo ilustran.

Normativa transversal: [`convenciones-desarrollo.md` §6](https://github.com/Colportores/docs-organizacion/blob/main/docs/convenciones-desarrollo.md) y `.claude/CLAUDE.md` §Tests (en
`docs-organizacion`). Este README es la vista "cómo se ve en código" de esas reglas.

## 1. Estructura de carpetas

Los tests reflejan la estructura de `lib/`, con un prefijo por tipo de test:

```
test/
├── unit/
│   ├── arquitectura/     ← reglas transversales que barren TODO lib/ (no una feature puntual)
│   ├── core/             ← test/unit/core/<módulo>/..., espejo de lib/core/<módulo>/...
│   └── features/
│       └── <feature>/
│           ├── domain/{entities,usecases,repositories}/
│           ├── data/{models,datasources,repositories}/
│           └── presentation/...  (cuando la feature llega a esa capa)
├── widget/               ← tests de widgets/páginas completas (no siguen el árbol de lib/,
│                            se nombran por pantalla: login_page_test.dart, flujo_login_test.dart)
├── integration/          ← reservado, todavía sin uso
└── helpers/              ← utilidades compartidas entre tests (ver §4)
```

Ejemplo real: `lib/features/mapa/domain/entities/espacio.dart` →
[`test/unit/features/mapa/domain/entities/espacio_test.dart`](unit/features/mapa/domain/entities/espacio_test.dart).

## 2. Paquete de test según la capa

- **Domain y data**: `package:test/test.dart` (Dart puro, sin Flutter). Ver el comentario en
  [`pubspec.yaml`](../pubspec.yaml) junto a la dependencia `test:` — es deliberado, no un
  descuido: si un test de dominio necesitara `flutter_test`, sería señal de que el dominio dejó
  de ser Dart puro (ADR-009, ver `arquitectura/dominio_puro_test.dart` en §5).
- **Widget/presentation**: `package:flutter_test/flutter_test.dart` — ver
  [`test/widget/login_page_test.dart`](../test/widget/login_page_test.dart).

## 3. Naming

**Archivos**: mismo path que `lib/` con sufijo `_test.dart`
(`convenciones-desarrollo.md` §6.1):

```
lib/features/ventas/domain/entities/venta.dart
test/unit/features/ventas/domain/entities/venta_test.dart
```

**Casos** (§6.2): `group` por entidad/clase, subgrupos por estado/contexto, `test` en la forma
`dado que [estado], cuando [acción], [resultado esperado]`. Ejemplo real en
[`test/unit/features/mapa/domain/entities/espacio_test.dart`](unit/features/mapa/domain/entities/espacio_test.dart):

```dart
group('Espacio', () {
  test('dado que dos instancias tienen los mismos campos, cuando se comparan, son iguales y '
      'comparten hashCode', () { ... });
  test('dado que numeroDepto difiere, cuando se comparan, no son iguales', () { ... });
  test('dado que auditoria.deletedAt tiene valor, cuando se consulta estaBorrada, es true', () { ... });
});
```

## 4. Fixtures: el helper `construir()`

Cuando una entidad o caso de uso tiene varios campos obligatorios, el patrón es un helper local
`construir({...})` con overrides opcionales, en vez de repetir el constructor completo en cada
test. Se declara dentro de `main()`, no exportado — es local al archivo. Ejemplo real en
`espacio_test.dart` (§3) y en
[`test/unit/features/ventas/domain/entities/venta_test.dart`](unit/features/ventas/domain/entities/venta_test.dart).

Cuando el fixture se comparte entre varios archivos de test (p. ej. un logger mudo), va en
`test/helpers/`, no duplicado — ver §6.

## 5. Tests de `arquitectura/`

No prueban una feature: escanean `lib/` completo para verificar una regla transversal, y fallan
si algún archivo nuevo la rompe (así la regla no depende de que el reviewer se acuerde de
chequearla a mano). Los tres que existen hoy:

| Archivo | Qué verifica |
|---|---|
| [`dominio_puro_test.dart`](unit/arquitectura/dominio_puro_test.dart) | ADR-009: ningún archivo bajo `*/domain/` (features) ni `core/{domain,error,usecases}` importa Flutter, Riverpod, Drift, Supabase o HTTP. |
| [`fechas_utc_test.dart`](unit/arquitectura/fechas_utc_test.dart) | Toda entidad normaliza sus `DateTime` a UTC en el constructor (evita el bug de `hashCode` que no distingue `isUtc`). |
| [`sin_pii_en_tostring_test.dart`](unit/arquitectura/sin_pii_en_tostring_test.dart) | convenciones-desarrollo.md §7.5: ninguna entidad con campos sensibles filtra PII por `toString()` (fuerza `EquatableConfig.stringify = true`, el peor caso). |

Si agregás una entidad o un caso de uso nuevo, estos tests corren solos sobre el código nuevo —
no hace falta escribir un test de arquitectura por feature.

## 6. Mocking: dos técnicas, cada una con su rol

El repo usa **mocktail** (no `mockito`, que solo aparece como dependencia transitiva — no lo
importa ningún test) para mockear la dependencia inmediata que un test unitario no necesita
implementar de verdad:

```dart
// test/unit/features/auth/domain/usecases/iniciar_sesion_use_case_test.dart
class _MockAuthRepository extends Mock implements AuthRepository {}
...
when(() => repository.iniciarSesion(email: any(named: 'email'), password: any(named: 'password')))
    .thenAnswer((_) async => Right(sesion));
```

Para la capa `data` (repository impl contra sus datasources), el patrón es distinto: **fakes en
memoria** hechos a mano que implementan la interfaz real (`.../data/datasources/fakes/`), más
clases fake puntuales por archivo de test cuando hace falta simular un caso límite (p. ej.
`_RemoteQueLanzaExcepcionGenerica` en
[`auth_repository_impl_test.dart`](unit/features/auth/data/repositories/auth_repository_impl_test.dart),
que fuerza una excepción no tipada para probar el mapeo a `FailureInesperado`). No es una
inconsistencia: mocktail sirve para "no me importa el comportamiento, solo qué se llamó";
el fake en memoria sirve para "necesito comportamiento real pero sin infraestructura" (sin
Supabase, sin Drift). Elegí según qué está probando el test.

`test/helpers/logger_mudo.dart` es el ejemplo de fixture compartida: un `AppLogger` con nivel
`off` para no ensuciar la salida de los tests que reciben un logger inyectado.

## 7. Cobertura

Objetivo por capa (`convenciones-desarrollo.md` §6.4):

| Capa | Objetivo |
|---|---|
| Domain | ≥ 90% |
| Data | ≥ 70% |
| Presentation | ≥ 50% |
| Total proyecto | ≥ 70% (RA-MA02) |

**Lo que automatiza hoy [`scripts/coverage_check.sh`](../scripts/coverage_check.sh)** son los
dos umbrales que ya trae en su propio encabezado: **total ≥ 70%** y **dominio ≥ 90%**. No mide
Data ni Presentation por separado — hoy ambas cumplen sus objetivos igual (ver medición abajo),
pero eso no está verificado por script, queda a criterio del reviewer. Documentamos esto tal
cual está, sin agregar el chequeo: si se quiere automatizar Data/Presentation por separado es
una decisión de alcance del script, no de este README.

**Medición actual** (rama `develop`, 293 tests, `flutter test --coverage` +
`coverage_check.sh`):

- Total: 92% · Dominio: 97%
- Por capa: domain 97%, data 94%, presentation 91%, core/otros 89%
- Por feature (excluye código generado `.g.dart`/`.freezed.dart`):

  | Feature | Cobertura | Capas presentes |
  |---|---|---|
  | `mapa` | 100% (17/17 líneas) | domain |
  | `ventas` | 100% (24/24 líneas) | domain |
  | `jornada` | 100% (16/16 líneas) | domain |
  | `agenda` | 100% (14/14 líneas) | domain |
  | `cobranzas` | 100% (13/13 líneas) | domain |
  | `auth` | 92% (794/855 líneas) | domain, data, presentation |

  `mapa`, `ventas`, `jornada`, `agenda` y `cobranzas` solo tienen la capa domain implementada
  todavía (Fase 1 en curso); sus entidades están 100% cubiertas por tests reales de
  comportamiento (igualdad, hash, `estaBorrada`, normalización UTC), no tests que pasan contra
  cualquier implementación. Esto ya satisface el "1 feature con coverage ≥ 90%" del issue —
  no hace falta escribir tests nuevos para inflar el número. `auth` es la única feature con las
  tres capas completas y está en 92%, pero está en desarrollo activo en paralelo (issues #19 y
  #38) así que su cifra es de referencia, no la que se cita como ejemplo fijo.

## 8. Cómo correr todo en Docker

Todo corre containerizado (`compose.dev.yml`), nunca contra un Flutter/Dart del host:

```sh
docker compose -f compose.dev.yml build                                   # una vez
docker compose -f compose.dev.yml run --rm flutter bash scripts/check.sh  # = CI completo
```

`scripts/check.sh` hace, en este orden exacto (no es arbitrario: `build_runner` tiene que correr
antes de `format`/`analyze` para que exista el código generado, y `pub get` antes que todo para
que el `pub.lock` esté resuelto):

```sh
flutter pub get
dart run build_runner build
git ls-files -z -- 'lib/*.dart' 'test/*.dart' | xargs -0 dart format --output=none --set-exit-if-changed
flutter analyze --fatal-infos
dart run custom_lint --fatal-infos
flutter test --coverage
bash scripts/coverage_check.sh
```

Solo tests: `docker compose -f compose.dev.yml run --rm flutter flutter test`.

**Nota para agentes trabajando en un git worktree** (`.claude/worktrees/...`): `scripts/check.sh`
usa `git ls-files`, que no resuelve bien cuando el `.git` del worktree apunta a una ruta de
Windows que el contenedor Linux no ve. En ese caso corré los comandos sueltos en el mismo orden
de arriba, y para el chequeo de formato apuntá `dart format` solo a los archivos que tocaste en
vez de depender de `git ls-files`.
