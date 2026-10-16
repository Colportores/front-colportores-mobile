// La declaración de §2 del contrato de sync para las tablas que hoy tiene la DB local.
//
// Es la única parte del motor que la app mantiene: una línea por tabla. El motor deduce de acá qué
// sube, qué baja y qué no sale nunca del teléfono, y `SpecRegistry` revienta al arrancar si una
// tabla de la DB quedó sin declarar: agregar una tabla con datos personales y olvidarse no puede
// ser silencioso.

import 'package:sync_engine/sync_engine.dart';

/// Las tablas de la DB local que **no** son entidades del contrato: la cola y los watermarks del
/// motor. No se declaran ni se sincronizan.
const tablasDelMotor = {'sync_queue', 'sync_watermark', 'sync_fuera_del_area'};

/// Lo que dice §2 para cada tabla local.
final specsDeLaApp = <SyncSpec>[
  // push: lo que escribe el colportor. `critical` sube al instante (§5.2).
  SyncSpec.push('jornada', critical: true),
  // Bidireccionales (§2.1): baja toda la ciudad de su zona, más lo que registró él. Lo que sale
  // del área se marca, no se borra (`sync_fuera_del_area`).
  SyncSpec.push('ubicacion', alsoPull: true),
  SyncSpec.push('espacio', alsoPull: true),
  // §2 y backend 0032: sube y sobrevive a una reinstalación. Hoy la tabla local no tiene `id` ni
  // columnas de sync y nada la encola: eso es un seguimiento de #178.
  SyncSpec.push('ubicacion_par_decidido'),

  // pull: réplicas de solo lectura, la app nunca las escribe (§2).
  // El mapa de la campaña, por el canal de catálogo.
  SyncSpec.pull('campania_ciudad'),
  SyncSpec.pull('zona'),
  SyncSpec.pull('zona_vertice'),
  SyncSpec.pull('pais'),
  SyncSpec.pull('ciudad'),
  SyncSpec.pull('campania'),
  // Solo las inscripciones propias (RLS): de acá sale la zona de cada campaña (HU-CAM-006).
  SyncSpec.pull('campania_colportor'),
  // El catálogo de venta: un cambio del administrador baja al instante (realtime, §5.6). Son las
  // cuatro tablas que el backend publica en `supabase_realtime` (0001).
  SyncSpec.pull('producto', realtime: true),
  SyncSpec.pull('coleccion', realtime: true),
  SyncSpec.pull('producto_coleccion', realtime: true),
  SyncSpec.pull('precio_por_ciudad', realtime: true),

  // local: jamás sale del teléfono por sync (Ley 18.331). Solo el backup E2E.
  // `persona` y `nota` todavía no tienen tabla; se declaran ya para que la suite de conformidad
  // (`test/unit/datos/conformidad_test.dart`) lo exija desde el primer día.
  SyncSpec.local('persona'),
  SyncSpec.local('nota'),
  SyncSpec.local('audit_log'),
  // La copia local del nombre del usuario (#243): viene de Auth, no del sync.
  SyncSpec.local('sesion_usuario'),
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
