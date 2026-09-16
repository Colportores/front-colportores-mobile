# front-colportores-mobile

App móvil del colportor: mapa offline, registro de visitas, ventas, cobranzas y jornada de trabajo. **Offline-first** — funciona sin conexión y sincroniza cuando la hay.

**Estado: Sprint 2** — proyecto Flutter con Clean Architecture, la feature `auth` como plantilla (use case + repositorio + data sources, con tests), logger del proyecto, CI, custodia de la sal de cifrado y la DB local cifrada (Drift + SQLCipher, todavía sin tablas: el modelo de dominio es el issue #8). La derivación de la clave y el primer login que abre la DB llegan con HU-AUTH-009 (Sprint 3), junto con el login real contra Supabase.

## Contexto

Parte del sistema [Colportaje App](https://github.com/Colportores). La arquitectura, los flujos y las decisiones viven en la [documentación de la organización](https://github.com/Colportores/docs-organizacion).

- Habla con su BFF ([bff-colportores](https://github.com/Colportores/bff-colportores)) para lectura y escritura ([ADR-016](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-016-bff-por-aplicacion.md)). Mantiene camino directo a Supabase Realtime, a Google Drive (backup) y a Storage (PMTiles).
- Stack: Flutter 3.44 + Riverpod 3.x (codegen) + Drift/SQLCipher + flutter_map (S5) ([ADR-007](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-007-stack-flutter.md); el ADR dice Riverpod 2.x y `sqlcipher_flutter_libs` — ver notas en `pubspec.yaml`).
- Arquitectura interna: Clean Architecture, `presentation → domain → data → infrastructure` ([ADR-009](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-009-clean-architecture.md)). El dominio es Dart puro — y un test lo verifica (`test/unit/arquitectura/`).
- Toda escritura que va al cloud pasa primero por `sync_queue` ([ADR-006](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-006-arquitectura-sync.md), [ADR-013](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-013-sync-robusto.md)); el motor vive en `packages/sync_engine` ([ADR-017](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-017-sync-engine-paquete.md), dueño `@BrunoFCapri`).

## Estructura

Feature-first ([convenciones §1.2](https://github.com/Colportores/docs-organizacion/blob/main/docs/convenciones-desarrollo.md)). `auth` es la plantilla: copiar su forma para cada feature nueva.

```
lib/
├── main.dart                  ← composición: acá se eligen las implementaciones (overrides)
├── app.dart                   ← MaterialApp; sesión → inicio, sin sesión → login
├── core/
│   ├── error/failure.dart     ← sealed Failure (Either<Failure, T> en todo use case)
│   ├── usecases/use_case.dart ← UseCase<T, Params>, StreamUseCase, NoParams
│   ├── logging/app_logger.dart← [NIVEL][MÓDULO][OPERACIÓN] mensaje — {json}
│   ├── secure_storage/        ← Keystore/Keychain: custodia de la sal de cifrado (ADR-003)
│   │   ├── almacen_seguro.dart          (puerto + ClaveSegura: el inventario de secretos)
│   │   ├── almacen_seguro_keystore.dart (único archivo que conoce flutter_secure_storage)
│   │   ├── custodia_clave_db.dart       (sal de 256 bits + marca de DB inicializada)
│   │   ├── clave_db.dart                (ClaveDb y ProveedorClaveDb: lo que consume la DB)
│   │   └── fakes/…_en_memoria.dart      (para desarrollo y tests)
│   └── database/              ← DB local cifrada: Drift + SQLCipher (ADR-003, ADR-007)
│       ├── app_database.dart            (AppDatabase: GeneratedDatabase a mano; sin tablas hasta #8)
│       ├── database_helper.dart         (único archivo que conoce el PRAGMA key: abrir/cerrar/borrar)
│       └── database_providers.dart      (databaseHelperProvider + dbLocalProvider: AppDatabase? por sesión)
└── features/auth/
    ├── domain/                ← Dart puro
    │   ├── entities/sesion.dart
    │   ├── repositories/auth_repository.dart          (interfaz)
    │   └── usecases/iniciar_sesion_use_case.dart …    (validan, normalizan, delegan)
    ├── data/
    │   ├── models/sesion_model.dart                   (entidad + json)
    │   ├── datasources/auth_remote_data_source.dart   (interfaz; Supabase en S3)
    │   ├── datasources/auth_local_data_source.dart    (interfaz; secure_storage en S2)
    │   ├── datasources/fakes/…_en_memoria.dart        (para desarrollo y tests)
    │   └── repositories/auth_repository_impl.dart     (traduce excepciones → Failure)
    └── presentation/
        ├── providers/auth_providers.dart              (cableado Riverpod, codegen)
        ├── providers/sesion_notifier.dart             (estado de sesión)
        └── pages/login_page.dart · inicio_page.dart
test/
├── unit/          ← dominio y data con package:test (sin Flutter); core con flutter_test
├── widget/        ← flujo de login completo con los fakes
└── unit/arquitectura/dominio_puro_test.dart ← falla si domain/ importa Flutter/Drift/Supabase
```

Reglas que el código de `auth` ejemplifica y que aplican a todas las features:

- Los use cases validan y devuelven `Left(FailureValidacion)` con errores por campo; nunca lanzan.
- Los data sources lanzan excepciones tipadas; **solo** el repositorio las traduce a `Failure`.
- Los providers de data sources no tienen implementación por defecto: se inyectan en `main.dart` con `overrideWithValue`. Si alguien olvida cablear uno, la app falla al arrancar, no en producción.
- Logs solo con UUIDs y códigos. Nunca email, nombre ni teléfono.
- La DB local se toma de `dbLocalProvider` (`AppDatabase?`: `null` sin sesión). La abre el flujo de login con la clave derivada (`DatabaseHelper.abrir`, HU-AUTH-009) y la cierra `SesionNotifier.cerrarSesion`, que además destruye la clave. Nadie fuera de `core/database/` conoce el `PRAGMA key`.

## Desarrollo

Todo lo que no necesita un dispositivo corre en Docker (Flutter + Android SDK incluidos):

```sh
docker compose -f compose.dev.yml build                                   # una vez
docker compose -f compose.dev.yml run --rm flutter bash scripts/check.sh  # = CI: format, analyze, lint, tests, cobertura
docker compose -f compose.dev.yml run --rm flutter flutter test           # solo tests
docker compose -f compose.dev.yml run --rm flutter dart run build_runner build      # regenerar *.g.dart
docker compose -f compose.dev.yml run --rm flutter flutter build apk --debug
```

- `build/` y `android/.gradle` viven en volúmenes Linux (D8/dex falla sobre el bind mount de Windows). Para sacar el APK al host:
  `docker run --rm -v front-colportores-mobile_build_out:/b -v "$PWD":/out alpine cp /b/app/outputs/flutter-apk/app-debug.apk /out/`
- `*.g.dart` **no se commitea**: se genera con `build_runner` (CI lo hace en cada corrida).
- **SQLCipher** lo empaqueta `package:sqlite3` con [hooks](https://pub.dev/documentation/sqlite3/latest/topics/hook-topic.html) (`hooks.user_defines.sqlite3.source: sqlcipher` en `pubspec.yaml`): en el primer build o `flutter test` baja el binario precompilado de la plataforma desde los releases de GitHub del paquete (verificado por sha256) a `.dart_tool/hooks_runner/`. Hace falta red esa primera vez; no hay nada que instalar en el host ni en la imagen (en Linux linkea el `libcrypto.so.3` que Ubuntu ya trae). Los tests de `core/database` corren contra ese SQLCipher real, no contra un fake.
- **`drift_dev` todavía no está** (ver nota en `pubspec.yaml`): no resuelve junto a `custom_lint`. Mientras la DB no tiene tablas no hace falta; hay que destrabarlo antes de la primera tabla (#8).
- `dart format` usa 100 columnas (`formatter.page_width` en `analysis_options.yaml`).
- Para correr en un teléfono o emulador se usa `flutter run` desde el host: el contenedor no ve USB ni emuladores de Windows. Cuenta demo mientras no hay backend: `demo@colportores.app` / `demo1234`.
- Umbrales de cobertura (`scripts/coverage_check.sh`): total ≥ 70%, dominio ≥ 90%.

## CI

`ci.yml` (PR y push a `develop`/`staging`/`production`): `build_runner`, `dart format --set-exit-if-changed`, `flutter analyze --fatal-infos`, `custom_lint` (reglas de Riverpod), `flutter test --coverage` con umbrales, y un job aparte que compila el APK debug — con SQLCipher es el que valida que el hook resuelve los binarios de Android. La versión de Flutter de CI y de `dockerfile.dev` se suben juntas.

## Privacidad

Los datos personales de clientes (`persona.nombre`, `persona.apellido`, `persona.telefono`, `nota.texto`) son **local-only**: viven solo en el dispositivo del colportor y nunca llegan al cloud, por la Ley 18.331 de Uruguay. Ver [`02-restricciones.md`](https://github.com/Colportores/docs-organizacion/blob/main/docs/02-restricciones.md).

Este repositorio es **el único lugar del sistema donde esos datos existen**. La base local se abre con SQLCipher (AES-256, clave en formato crudo `x'…'`) y las tablas `persona` y `nota` nunca se sincronizan.

La clave de esa base **no se guarda en ningún lado**: se deriva con Argon2id de la contraseña del usuario y de una sal aleatoria de 256 bits, y esa sal —no la clave— es lo que vive en Keystore/Keychain ([ADR-003](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-003-backup-y-cifrado.md)). La custodia de la sal es `core/secure_storage/`; quien abre la DB con la clave ya derivada es `core/database/DatabaseHelper`; la derivación llega con HU-AUTH-009.

## Licencia

Uso propio — todos los derechos reservados. Ver [LICENSE](./LICENSE).
