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
│   ├── arquitectura/     ← reglas transversales, no una feature puntual; solo una de las tres
│   │                        barre lib/ completo, las otras dos se completan a mano (ver §5)
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

Verifican una regla transversal, no una feature puntual — pero **no los tres de la misma forma**.
Son dos mecanismos distintos, e importa la diferencia porque define si un archivo nuevo queda
cubierto solo o si alguien tiene que acordarse de sumarlo a mano:

| Archivo | Qué verifica | Cómo |
|---|---|---|
| [`dominio_puro_test.dart`](unit/arquitectura/dominio_puro_test.dart) | ADR-009: ningún archivo bajo `*/domain/` (features) ni `core/{domain,error,usecases}` importa Flutter, Riverpod, Drift, Supabase o HTTP. | **Barre el árbol**: `_directoriosDeDominio()` + `listSync(recursive: true)` sobre `lib/`. Un archivo nuevo queda cubierto solo, sin tocar el test. |
| [`fechas_utc_test.dart`](unit/arquitectura/fechas_utc_test.dart) | Toda entidad *conocida* normaliza sus `DateTime` a UTC en el constructor (evita el bug de `hashCode` que no distingue `isUtc`). | **Lista manual**: un `import` y un caso por entidad, escritos a mano. No escanea nada. |
| [`sin_pii_en_tostring_test.dart`](unit/arquitectura/sin_pii_en_tostring_test.dart) | convenciones-desarrollo.md §7.5: ninguna entidad *conocida* con campos sensibles filtra PII por `toString()` (fuerza `EquatableConfig.stringify = true`, el peor caso). | **Lista manual**, igual que el anterior: un caso por entidad ya agregada a mano. No escanea nada. |

Solo `dominio_puro_test.dart` corre solo sobre código nuevo. **Si tu entidad tiene un campo
`DateTime` o PII (email, teléfono, cédula, nombre, notas, tokens) en `props`, sumala a mano a
`fechas_utc_test.dart` y/o `sin_pii_en_tostring_test.dart`** — si no la agregás, la suite pasa en
verde igual, sin que esa entidad esté cubierta. Convertir estos dos en barridos automáticos
(recorrer el árbol y fallar ante cualquier `props` con un nombre de campo sensible o un
`DateTime`) es una decisión abierta de Cristian, ya anotada en el issue #43 — no se resuelve acá.

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
memoria** hechos a mano que implementan la interfaz real. El ejemplo real,
[`lib/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart`](../lib/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart),
vive en **`lib/`, no en `test/`** — a propósito, según su propio doc-comment: es de doble uso,
sirve tanto para desarrollar la UI contra un backend inexistente (modo demo de la app) como para
los tests del repositorio, y `main.dart` recién lo reemplaza por la implementación Supabase en
Sprint 3. Además hay clases fake puntuales por archivo de test cuando hace falta simular un caso
límite (p. ej. `_RemoteQueLanzaExcepcionGenerica` en
[`auth_repository_impl_test.dart`](unit/features/auth/data/repositories/auth_repository_impl_test.dart),
que fuerza una excepción no tipada para probar el mapeo a `FailureInesperado`) — esas sí viven en
`test/`, junto al test que las usa. No es una inconsistencia entre mocktail y fakes: mocktail
sirve para "no me importa el comportamiento, solo qué se llamó"; el fake en memoria sirve para
"necesito comportamiento real pero sin infraestructura" (sin Supabase, sin Drift). Elegí según
qué está probando el test.

El data source **sobre Drift** no se prueba con un fake sino contra la tabla real: un
`AppDatabase(NativeDatabase.memory(), logger: loggerMudo())` por test, con el mismo esquema y las
mismas restricciones que en el dispositivo (sin cifrado; eso lo cubre `database_helper_test.dart`).
Ejemplo real:
[`jornada_local_data_source_drift_test.dart`](unit/features/jornada/data/datasources/jornada_local_data_source_drift_test.dart),
que además fija que las columnas de la tabla sean las claves de `toJson()` del modelo y repite
contra Drift el test de concurrencia del fake. Las migraciones se prueban en
[`app_database_test.dart`](unit/core/database/app_database_test.dart): una DB en la versión
anterior (`setup` con `PRAGMA user_version`) migra y termina con el mismo esquema que una nueva.
**Ese test no es el patrón para la próxima versión del esquema**: arranca solo desde la versión 1
y compara el texto de `sqlite_master`, así que no detecta un paso `N → N+1` olvidado y daría un
falso fallo después de un `ALTER TABLE … ADD COLUMN`. El patrón que corresponde son los esquemas
versionados de Drift —congelar cada versión con `drift_dev make-migrations`, testear desde cada
versión congelada y comparar con `SchemaVerifier`—, que hoy no compila. El `drift_dev` 2.34.0 del
lock solo anda con `drift` 2.34.0 (con 2.34.1 a 2.34.4 falla), y `pubspec.yaml` pide
`drift: ^2.34.1`. Un `drift_dev` más nuevo pide analyzer 13, y eso lo impide `flutter_test`: fija
`test_api` 0.7.11, que obliga a `test` 1.31.0, que pide analyzer < 13. No es por
`riverpod_generator`: sin él falla igual. Hay dos salidas: fijar `drift` en 2.34.0 (falta validar
que la suite, `build_runner` y el APK anden con esa versión) o sacar `test` como dependencia
directa, lo que choca con la regla de CLAUDE.md de que los tests de dominio/data no importan
Flutter. Elegir es decisión de Cristian: está pendiente en #70 (ver `AppDatabase.migration`) y hay
que resolverlo antes de subir a la versión 3.

**Convención de fakes** (decisión de Cristian del 23/09, issue #9): todo fake en memoria vive **al
lado de su interfaz**, en `lib/<ruta de la interfaz>/fakes/<interfaz>_en_memoria.dart`, y la clase
se llama `<Interfaz>EnMemoria`, lo use el modo demo o solo los tests. Los mocks de mocktail
(`class _MockX extends Mock implements X`) se declaran dentro del archivo de test que los usa, y los
helpers sin interfaz (logger mudo, relojes fijos) van en `test/helpers/`.

**Mocks: mocktail, nunca mockito.** La skill oficial `dart-generate-test-mocks`, que generaba mocks
con mockito + `build_runner`, se desinstaló el 23/09 (#9; ver `.claude/skills/PROCEDENCIA.md`).
Donde otra skill mencione mockito, en este repo es mocktail.

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
dart analyze --fatal-infos
flutter test --coverage
bash scripts/coverage_check.sh
```

El análisis es `dart analyze` y **no** `flutter analyze`: las reglas de Riverpod
(`missing_provider_scope`, `scoped_providers_should_specify_dependencies`, etc.) vienen de
`riverpod_lint` como plugin del analyzer, y `flutter analyze` no muestra diagnósticos de plugins —
contesta "No issues found!" aunque haya violaciones. Tampoco sirve apuntarlo a una carpeta:
`dart analyze lib` no carga el plugin (verificado en #87); va sin argumentos, sobre el proyecto
entero. La primera corrida en un contenedor nuevo
tarda más (~45 s) porque compila el plugin.

Solo tests: `docker compose -f compose.dev.yml run --rm flutter flutter test`.

**Nota para agentes trabajando en un git worktree** (`.claude/worktrees/...`): `scripts/check.sh`
usa `git ls-files`, que no resuelve bien cuando el `.git` del worktree apunta a una ruta de
Windows que el contenedor Linux no ve. En ese caso corré los comandos sueltos en el mismo orden
de arriba (`flutter pub get` antes que `dart format`, que necesita el paquete resuelto para leer
`analysis_options.yaml`), y para el chequeo de formato apuntá `dart format` solo a los archivos que tocaste en
vez de depender de `git ls-files`.
