import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../catalogo.dart';
import '../../../../core/conectividad/conectividad_providers.dart';
import '../../../../core/database/database_providers.dart';
import '../../../../core/secure_storage/secure_storage_providers.dart';
import '../../../../core/sync/armado_del_motor.dart';
import '../../../../core/sync/sync_providers.dart';
import '../../../../datos/drift_snapshot.dart';
import '../../../../plataforma/conectividad_del_motor.dart';
import '../../../tiles/domain/services/puertos_descarga.dart';
import '../../data/services/servicio_recuperacion_motor.dart';
import '../../domain/services/servicio_recuperacion.dart';
import 'respaldo_drive_providers.dart';

/// El asistente de recuperación de datos en un teléfono sin datos (HU-SYNC-006, vista 34). Lo usa la
/// pantalla del asistente (#175).
///
/// Se rearma con la DB: sin DB abierta no hay con qué recuperar y todo pedido vuelve fallido. Trae su
/// propio motor de sync (con la misma receta que la app, `armarMotorDeSync`) y lo cierra al terminar:
/// mientras el asistente está abierto, el de la app no existe (`motorSyncProvider` es `null`).
final servicioRecuperacionProvider = Provider<ServicioRecuperacion>((ref) {
  final db = ref.watch(dbLocalProvider);
  final archivo = ref.watch(archivoDriveProvider);
  final token = ref.watch(tokenDriveProvider);
  final monitor = ref.watch(monitorConectividadProvider);
  final cripto = ref.watch(criptoConDekProvider);
  final custodia = ref.watch(custodiaClaveDbProvider);

  return ServicioRecuperacionMotor(
    armarMotor: () => db == null
        ? null
        : armarMotorDeSync(
            db: db,
            leerDek: custodia.leerDek,
            tokenDrive: token,
            transporte: ref.read(transporteSyncProvider),
            conectividad: ConectividadDelMotor(monitor),
          ),
    archivo: () async => await token() == null ? null : (archivo, archivo),
    llavePropia: () async {
      try {
        return await cripto.keyId();
      } on Object {
        // Sin DEK legible no se sabe cuál cadena es la de este teléfono; la búsqueda sigue.
        return null;
      }
    },
    abrirEnvoltorio: custodia.abrirEnvoltorio,
    snapshot: () => DriftSnapshot(db!, tablas: entidadesDelBackup),
    hayConexion: () async => await monitor.actual() != TipoConexion.sinConexion,
  );
});
