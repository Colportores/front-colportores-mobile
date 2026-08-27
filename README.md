# front-colportores-mobile

App móvil del colportor: mapa offline, registro de visitas, ventas, cobranzas y jornada de trabajo. **Offline-first** — funciona sin conexión y sincroniza cuando la hay.

**Estado: en construcción** — repo creado según la nomenclatura de [ADR-015](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-015-nomenclatura-repositorios.md); todavía sin código.

## Contexto

Parte del sistema [Colportaje App](https://github.com/Colportores). La arquitectura, los flujos y las decisiones viven en la [documentación de la organización](https://github.com/Colportores/docs-organizacion).

- Habla con su BFF ([bff-colportores](https://github.com/Colportores/bff-colportores)) para lectura y escritura ([ADR-016](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-016-bff-por-aplicacion.md)). Mantiene camino directo a Supabase Realtime, a Google Drive (backup) y a Storage (PMTiles).
- Stack previsto: Flutter + Drift + SQLCipher + Riverpod 2.x + flutter_map ([ADR-007](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-007-stack-flutter.md)).
- Arquitectura interna: Clean Architecture, `presentation → domain → data → infrastructure` ([ADR-009](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-009-clean-architecture.md)). El dominio es Dart puro.
- Toda escritura que va al cloud pasa primero por `sync_queue` ([ADR-006](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-006-arquitectura-sync.md), [ADR-013](https://github.com/Colportores/docs-organizacion/blob/main/docs/decisiones/ADR-013-sync-robusto.md)).

## Privacidad

Los datos personales de clientes (`persona.nombre`, `persona.apellido`, `persona.telefono`, `nota.texto`) son **local-only**: viven solo en el dispositivo del colportor y nunca llegan al cloud, por la Ley 18.331 de Uruguay. Ver [`02-restricciones.md`](https://github.com/Colportores/docs-organizacion/blob/main/docs/02-restricciones.md).

Este repositorio es **el único lugar del sistema donde esos datos existen**. La base local se abre con SQLCipher y la clave vive en `secure_storage`; las tablas `persona` y `nota` nunca se sincronizan.

## Licencia

Uso propio — todos los derechos reservados. Ver [LICENSE](./LICENSE).
