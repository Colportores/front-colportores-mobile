# Procedencia de las skills de este repo

Ninguna skill de este directorio es de autoría del equipo de Colportores. Hay dos fuentes:

- **22 skills `dart-*` y `flutter-*`**: el paquete oficial de Google para Flutter/Dart.
- **2 skills de QA, `testing` y `accessibility`**: de [evanca/flutter-ai-rules](https://github.com/evanca/flutter-ai-rules). Se sumaron el 23/09/2026 para el paso de QA de vistas de `/iterar-sprint`.

Están instaladas completas porque son guías puntuales de una sola tarea (~8-20 KB cada una), y no ocupan contexto salvo cuando Claude decide cargar una.

| Fuente | Skills | Commit al instalar | Licencia |
|---|---|---|---|
| [flutter/agent-plugins](https://github.com/flutter/agent-plugins) → `skills/*` (oficial) | 22 skills `dart-*` / `flutter-*` | `df9bebe` (2026-09-01) | BSD-3-Clause (The Flutter Authors) |
| [dart-lang/skills](https://github.com/dart-lang/skills) (oficial) | fuente upstream de las `dart-*` (se sincronizan a `flutter/agent-plugins` vía `tool/sync_skills.dart`) | — | BSD-3-Clause |
| [evanca/flutter-ai-rules](https://github.com/evanca/flutter-ai-rules) → `skills/testing`, `skills/accessibility` (comunidad, ~640★, mantenido) | `testing`, `accessibility` | `7b9cce2` (2026-09-23) | MIT |

Documentación oficial: [docs.flutter.dev/ai/agent-skills](https://docs.flutter.dev/ai/agent-skills).

## Por qué hay dos skills de fuera del paquete oficial

El paquete oficial enseña a *escribir* tests (`flutter-add-widget-test`, `flutter-add-integration-test`), pero no tiene nada de QA de producto ni de accesibilidad. El proyecto pasa cada vista por un QA antes del merge (paso de QA de vistas de `/iterar-sprint`, agente `sprint-qa`), y para eso se eligieron:

- `accessibility`: auditoría por POUR (lector de pantalla, contraste, tamaño de toque, texto grande, errores explicados con cómo arreglarlos, accesibilidad cognitiva). En Flutter se verifica con los matchers `meetsGuideline(...)` de `flutter_test`, y con capturas de cada estado con escala de texto grande.
- `testing`: criterios de validez de un test (qué hace que un test atrape regresiones reales y cuándo es un falso positivo), con `mocktail` como default, igual que este repo.

**Precedencia:** donde choquen con `test/README.md` o con las convenciones de `docs-organizacion`, mandan las del proyecto.

## Las más relevantes para este proyecto ahora mismo

- `flutter-apply-architecture-best-practices` — complementa ADR-009; la app usa Clean Architecture feature-first en vez del MVVM que sugiere por defecto, pero la sección de testing/DI aplica igual.
- `dart-add-unit-test`, `flutter-add-widget-test`, `flutter-add-integration-test`, `dart-collect-coverage` — la plantilla `auth` (`lib/features/auth/`) ya sigue este patrón. Donde `dart-add-unit-test` menciona `mockito`, en este repo es `mocktail` (`test/README.md`).
- `accessibility`, `testing` — QA de vistas (ver arriba).
- `flutter-implement-json-serialization` — para los `*Model.fromJson/toJson` de cada feature (ver `SesionModel`).
- `dart-run-static-analysis`, `dart-resolve-package-conflicts`, `dart-fix-runtime-errors` — troubleshooting de `dart analyze` / `pub get` dentro del contenedor.
- `flutter-setup-declarative-routing` — para cuando entre `go_router` (ADR-007, Sprint 5).

## No instalado a propósito

- **`dart-generate-test-mocks`** (del paquete oficial): genera mocks con `mockito` + `build_runner`, y este repo usa `mocktail` sin codegen (`test/README.md`). Un agente la cargaría por su descripción ("use when unit testing…") y metería otro estilo de mocks. Se desinstaló por decisión de Cristian del 23/09 (#9). **Al refrescar las skills, no reinstalarla.**
- **`dart-mcp-server`**: el bundle oficial trae un `.mcp.json` con `command: dart, args: [mcp-server]`. No se agregó porque ese servidor MCP corre en el host con el binario `dart`, y este proyecto se desarrolla íntegramente dentro de Docker (ver `dockerfile.dev`), sin asumir un SDK de Flutter en el host. Si el equipo quiere habilitarlo, se corre `dart mcp-server` dentro del contenedor y se expone el puerto, o se instala Flutter en el host.

## Cómo refrescarlas

```sh
# Oficiales (sin dart-generate-test-mocks)
git clone --depth 1 https://github.com/flutter/agent-plugins /tmp/flutter-agent-plugins
for d in /tmp/flutter-agent-plugins/skills/*/; do
  n=$(basename "$d")
  [ "$n" = "dart-generate-test-mocks" ] && continue
  rm -rf .claude/skills/$n
  cp -r "$d" .claude/skills/$n
  cp /tmp/flutter-agent-plugins/LICENSE .claude/skills/$n/LICENSE
done

# QA (evanca/flutter-ai-rules)
git clone --depth 1 https://github.com/evanca/flutter-ai-rules /tmp/flutter-ai-rules
for n in testing accessibility; do
  rm -rf .claude/skills/$n
  cp -r /tmp/flutter-ai-rules/skills/$n .claude/skills/$n
  cp /tmp/flutter-ai-rules/LICENSE .claude/skills/$n/LICENSE
done
```

Después de refrescar, actualizá el commit de la tabla de arriba.
