// La declaración de §2 del contrato de sync para las tablas que hoy tiene la DB local.
//
// Es la única parte del motor que la app mantiene: una línea por tabla. El motor deduce de acá qué
// sube, qué baja y qué no sale nunca del teléfono, y `SpecRegistry` revienta al arrancar si una
// tabla de la DB quedó sin declarar: agregar una tabla con datos personales y olvidarse no puede
// ser silencioso.

import 'package:sync_engine/sync_engine.dart';

/// Las tablas de la DB local que **no** son entidades del contrato: la cola, los watermarks y los
/// metadatos del motor. No se declaran ni se sincronizan.
const tablasDelMotor = {'sync_queue', 'sync_watermark', 'sync_meta'};

/// Lo que dice §2 para cada tabla local.
final specsDeLaApp = <SyncSpec>[
  // push: lo que escribe el colportor. `critical` sube al instante (§5.2).
  SyncSpec.push('jornada', critical: true),
  // `alsoPull` (la réplica de las casas de la ciudad, §2.1) llega con I2 (#181): el pull por
  // ciudad y el aviso de fuera del área.
  SyncSpec.push('ubicacion'),
  SyncSpec.push('espacio'),
  // §2 y backend 0032: sube y sobrevive a una reinstalación. Hoy la tabla local no tiene `id` ni
  // columnas de sync y nada la encola: eso es un seguimiento de #178.
  SyncSpec.push('ubicacion_par_decidido'),
  // ADR-017: el vínculo persona ↔ espacio sube con ids opacos y sin `alsoPull` (un solo escritor). La
  // persona y sus notas (abajo) no suben nunca: solo el backup E2E (HU-UBI-008, #140).
  SyncSpec.push('espacio_persona'),
  // La agenda y las visitas del colportor (BACK-HU-VIS-001, #404): suben enteras, porque sus notas
  // son filas de `nota` (ADR-017) y la fila no lleva dato personal. Sin `alsoPull`: un solo escritor.
  SyncSpec.push('agenda'),
  SyncSpec.push('visita'),
  // La cache del color de la casa (ADR-003): sube sin PII, con una fila por ubicación (su clave es
  // `ubicacion_id`, no `id`). El `alsoPull` (las casas de la ciudad, §2.1) llega con el pull de las
  // casas (#181).
  SyncSpec.push('house_status', pk: 'ubicacion_id'),

  // pull: el mapa de la campaña, por el canal de catálogo (§2). La app nunca las escribe.
  SyncSpec.pull('campania_ciudad'),
  SyncSpec.pull('zona'),
  SyncSpec.pull('zona_vertice'),

  // local: jamás sale del teléfono por sync (Ley 18.331). Solo el backup E2E.
  SyncSpec.local('audit_log'),
  // La copia local del nombre del usuario (#243): viene de Auth, no del sync.
  SyncSpec.local('sesion_usuario'),
  // El cliente del colportor y sus notas: PII (Ley 18.331), solo en el teléfono.
  SyncSpec.local('persona'),
  SyncSpec.local('nota'),
  // El historial del centro de notificaciones (HU-NOT-005): avisos de este teléfono, con la
  // dirección de la visita en el texto; nunca sube.
  SyncSpec.local('notificacion_historial'),
];

/// El registro validado contra [tablasLocales] (todas las de la DB, sin [tablasDelMotor]).
SpecRegistry registroDeLaApp(Iterable<String> tablasLocales) =>
    SpecRegistry(specsDeLaApp, allEntities: tablasLocales.toSet().difference(tablasDelMotor));

/// Las tablas en las que el motor puede escribir: las que bajan por pull y las `push`, que reciben
/// la `server_row` de un LWW y la `sync_version` que vuelve después de subir (§5.4). Nunca una
/// `local`.
final entidadesQueEscribeElMotor = {
  for (final s in specsDeLaApp)
    if (s.policy != SyncPolicy.local) s.entity,
};
