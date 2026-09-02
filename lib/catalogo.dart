// La declaración de §2 del contrato, tal como la escribe la app.
//
// Es la única parte que la app tiene que mantener: una línea por entidad. El
// motor deduce de acá qué sube, qué baja, qué se suscribe a realtime y qué no
// sale nunca del dispositivo.

import 'package:sync_engine/sync_engine.dart';

final specsV1 = <SyncSpec>[
  // pull — réplica de solo lectura, la app nunca las escribe
  SyncSpec.pull('producto', realtime: true),
  SyncSpec.pull('precio_por_zona', realtime: true),
  SyncSpec.pull('coleccion'),
  SyncSpec.pull('campania'),
  SyncSpec.pull('zona'),
  SyncSpec.pull('ciudad'),
  SyncSpec.pull('pais'),

  // push — lo que sube el colportor.  sube al instante.
  SyncSpec.push('venta', critical: true),
  SyncSpec.push('venta_item', critical: true),
  SyncSpec.push('cobranza', critical: true),
  SyncSpec.push('jornada', critical: true),
  SyncSpec.push('entrega'),
  SyncSpec.push('entrega_item'),
  SyncSpec.push('visita'),
  SyncSpec.push('agenda'),
  SyncSpec.push('ubicacion', alsoPull: true),
  SyncSpec.push('espacio', alsoPull: true),
  SyncSpec.push('house_status', alsoPull: true),

  // local — jamás sale del dispositivo por sync (Ley 18.331)
  SyncSpec.local('persona'),
  SyncSpec.local('nota'),
  // Quién vive en qué espacio. No lleva datos personales adentro —son dos FK—
  // pero apunta a `persona`, así que subirla sería subir el vínculo con el
  // cliente por la puerta de atrás. Se queda acá, y declararla es lo que evita
  // que alguien la agregue al esquema local y el registro reviente al arrancar.
  SyncSpec.local('espacio_persona'),
];

/// Todas las tablas de la DB local. El registro se cruza con esto y revienta al
/// arrancar si alguna quedó sin declarar: agregar una tabla con datos
/// personales y olvidarse no puede ser silencioso.
final entidadesV1 = {for (final s in specsV1) s.entity};

/// Token de desarrollo, emitido por `bff-colportores/dev/arrancar.sh` con el
/// secreto local. Dura 30 días y no sirve contra nada real; en producción lo
/// emite Supabase Auth.
const tokenDeDesarrollo = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMTExMTExMS0xMTExLTQxMTEtODExMS0xMTExMTExMTExMTEiLCJyb2xlIjoiYXV0aGVudGljYXRlZCIsImlhdCI6MTc4Nzk0ODAwOCwiZXhwIjoxNzkwNTQwMDA4fQ.85YN2uMypvGgSCuCdpa6nE6PZjrYAiE0M_OspLnvadU';
