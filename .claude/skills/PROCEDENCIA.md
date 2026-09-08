# Procedencia de las skills de este repo

Las 23 skills de `dart-*` y `flutter-*` son el paquete oficial de Google para Flutter/Dart — no son de autoría del equipo de Colportores. Instaladas completas porque son guías puntuales de una sola tarea (~8-20 KB cada una); no llenan el contexto salvo cuando Claude decide cargar una.

| Fuente oficial | Repos | Commit al instalar | Licencia |
|---|---|---|---|
| [flutter/agent-plugins](https://github.com/flutter/agent-plugins) → `skills/*` | 23 skills `dart-*` / `flutter-*` | `df9bebe` (2026-09-01) | BSD-3-Clause (The Flutter Authors) |
| [dart-lang/skills](https://github.com/dart-lang/skills) | fuente upstream de las `dart-*` (se sincronizan a `flutter/agent-plugins` vía `tool/sync_skills.dart`) | — | BSD-3-Clause |

Documentación: [docs.flutter.dev/ai/agent-skills](https://docs.flutter.dev/ai/agent-skills).

## Las más relevantes para este proyecto ahora mismo

- `flutter-apply-architecture-best-practices` — complementa ADR-009; la app usa Clean Architecture feature-first en vez del MVVM que sugiere por defecto, pero la sección de testing/DI aplica igual.
- `dart-add-unit-test`, `flutter-add-widget-test`, `flutter-add-integration-test`, `dart-generate-test-mocks`, `dart-collect-coverage` — la plantilla `auth` (`lib/features/auth/`) ya sigue este patrón.
- `flutter-implement-json-serialization` — para los `*Model.fromJson/toJson` de cada feature (ver `SesionModel`).
- `dart-run-static-analysis`, `dart-resolve-package-conflicts`, `dart-fix-runtime-errors` — troubleshooting de `flutter analyze` / `pub get` dentro del contenedor.
- `flutter-setup-declarative-routing` — para cuando entre `go_router` (ADR-007, Sprint 5).

## No instalado a propósito

El bundle oficial incluye un `.mcp.json` con `dart-mcp-server` (`command: dart, args: [mcp-server]`). No se agregó: ese servidor MCP se ejecuta en el host vía el binario `dart`, y este proyecto desarrolla íntegramente dentro de Docker (ver `dockerfile.dev`) sin asumir un SDK de Flutter instalado en el host. Si el equipo quiere habilitarlo, corre `dart mcp-server` desde dentro del contenedor y expone el puerto, o instala Flutter en el host.

## Cómo refrescarlas

```sh
git clone --depth 1 https://github.com/flutter/agent-plugins /tmp/flutter-agent-plugins
for d in /tmp/flutter-agent-plugins/skills/*/; do
  n=$(basename "$d")
  rm -rf .claude/skills/$n
  cp -r "$d" .claude/skills/$n
  cp /tmp/flutter-agent-plugins/LICENSE .claude/skills/$n/LICENSE
done
```
