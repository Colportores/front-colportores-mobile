import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/services/lector_de_lo_recuperado.dart';

/// [LectorDeLoRecuperado] sobre la DB local abierta. Se le da una función y no la base: la
/// recuperación puede reemplazar la base abierta, y cada lectura tiene que ver la de ahora.
final class LectorDeLoRecuperadoDrift implements LectorDeLoRecuperado {
  LectorDeLoRecuperadoDrift(this._db);

  final AppDatabase? Function() _db;

  AppDatabase get _abierta {
    final db = _db();
    if (db == null) throw StateError('No hay una base abierta para leer.');
    return db;
  }

  @override
  Future<bool> baseSinDatos() async {
    final db = _abierta;
    final tablas = <TableInfo<Table, Object?>>[
      db.jornadas,
      db.ubicaciones,
      db.personas,
      db.ventas,
      db.cobranzas,
      db.visitas,
      db.agendas,
      db.notas,
      db.depositos,
    ];
    for (final tabla in tablas) {
      if (await _contar(db, tabla) > 0) return false;
    }
    return true;
  }

  @override
  Future<ResumenDeLoRecuperado> resumen() async {
    final db = _abierta;
    return ResumenDeLoRecuperado(
      ubicaciones: await _contar(db, db.ubicaciones, sinBajas: db.ubicaciones.deletedAt),
      personas: await _contar(db, db.personas, sinBajas: db.personas.deletedAt),
      ventas: await _contar(db, db.ventas, sinBajas: db.ventas.deletedAt),
      cobros: await _contar(db, db.cobranzas, sinBajas: db.cobranzas.deletedAt),
    );
  }

  /// Filas de [tabla]; con [sinBajas] (su columna `deleted_at`), solo las que no están dadas de baja.
  Future<int> _contar(
    AppDatabase db,
    TableInfo<Table, Object?> tabla, {
    GeneratedColumn<Object>? sinBajas,
  }) async {
    final cuenta = countAll();
    final consulta = db.selectOnly(tabla)..addColumns([cuenta]);
    if (sinBajas != null) consulta.where(sinBajas.isNull());
    final fila = await consulta.getSingle();
    return fila.read(cuenta) ?? 0;
  }
}
