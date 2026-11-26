import 'package:sync_engine/adapters.dart';
import 'package:sync_engine/sync_engine.dart';

import '../../catalogo.dart';
import '../../datos/drift_job_store.dart';
import '../../datos/drift_local_store.dart';
import '../../datos/drift_snapshot.dart';
import '../../datos/drift_sync_meta.dart';
import '../../datos/encolador_sync_motor.dart';
import '../../features/cobranzas/data/services/casas_de_cobros_bajados.dart';
import '../../features/respaldo/data/services/crypto_con_dek.dart';
import '../database/app_database.dart';
import '../secure_storage/clave_db.dart';
import 'encolador_sync.dart';

/// Arma el motor de sync sobre la DB local abierta (contrato-sync-engine §3).
///
/// Lo usan dos lugares con la misma receta, para que el respaldo de la noche sea el mismo que el de
/// la pantalla: `motorSyncProvider` (la app, con la UI) y el respaldo nocturno (HU-SYNC-005, un
/// isolate de segundo plano sin UI, `ArmadorDeRespaldoNocturno`).
///
/// El backup E2E en el Drive de la persona (ADR-006): la DB exportada, comprimida y cifrada con la
/// DEK antes de salir, hacia el `appDataFolder`. La DEK se pide con [leerDek] en cada cifrado (no se
/// guarda acá) y el token de Drive con [tokenDrive] en cada pedido: sin Drive conectado el respaldo
/// simplemente no corre (`ServicioRespaldo` lo mira antes), y armar esto no toca el almacén.
///
/// [archivo] reemplaza al Drive de Google (los tests le dan un Drive en memoria); en la app no se pasa.
///
/// [recalcularCasasAlBajarCobros] (solo el motor de la app: el respaldo de la noche no baja nada y la
/// recuperación trae los colores ya calculados): al bajar un cobro anulado por la coordinación
/// (HU-COB-006, «Anul. al tel»), vuelve a calcular el color de su casa, que depende del saldo.
SyncEngine armarMotorDeSync({
  required AppDatabase db,
  required Future<ClaveDb?> Function() leerDek,
  required Future<String?> Function() tokenDrive,
  required SyncTransport transporte,
  required ConnectivityPort conectividad,
  RealtimePort? realtime,
  ArchivePort? archivo,
  bool recalcularCasasAlBajarCobros = false,
}) {
  final cripto = CryptoConDek(leerDek);
  // El encolador necesita al motor y el motor al store que recalcula: se ata al final.
  late final SyncEngine motor;
  final casasDeCobros = recalcularCasasAlBajarCobros
      ? CasasDeCobrosBajados(db, encolador: _EncoladorDiferido(() => motor))
      : null;
  motor = SyncEngine(
    specs: registroDeLaApp(db.allTables.map((t) => t.actualTableName)),
    backup: BackupService(
      archive: archivo ?? GoogleDriveArchive(token: tokenDrive, digest: cripto.digest),
      crypto: cripto,
      snapshot: DriftSnapshot(db, tablas: entidadesDelBackup),
    ),
    transport: transporte,
    jobs: DriftJobStore(db),
    meta: DriftSyncMeta(db),
    store: DriftLocalStore(
      db,
      entidades: entidadesQueEscribeElMotor,
      despuesDeAplicar: casasDeCobros?.call,
    ),
    connectivity: conectividad,
    realtime: realtime,
  );
  return motor;
}

/// [EncoladorSync] sobre un motor que todavía se está armando: lo busca recién al encolar.
final class _EncoladorDiferido implements EncoladorSync {
  const _EncoladorDiferido(this._motor);

  final SyncEngine Function() _motor;

  @override
  Future<void> encolar(String entidad, OperacionSync operacion, Map<String, Object?> payload) =>
      EncoladorSyncMotor(_motor()).encolar(entidad, operacion, payload);
}
