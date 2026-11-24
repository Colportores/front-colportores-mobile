import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/campania_para_el_pago.dart';

/// A qué campaña paga el alquiler que deposita el colportor (decisión «Alq. campaña»: el saldo de
/// alquiler es uno por campaña, y el servidor exige `campania_id` con el concepto alquiler).
///
/// Lee la réplica local de `campania` y `campania_colportor`: las campañas en curso en las que está
/// inscripto el colportor ([hoy] entre su inicio y su fin, o sin fin), la más reciente primero. Si
/// alguna cobra alquiler (`alquiler_monto` mayor que 0) solo cuentan las que cobran: no se paga el
/// alquiler de una campaña que no lo cobra; si ninguna lo cobra (o el pull todavía no trajo el monto)
/// cuentan todas. Sin ninguna en curso, la lista es vacía: el alquiler no se puede registrar. Con más de
/// una, la pantalla le pide al colportor que elija a cuál paga.
final class CampaniaDelAlquilerDrift {
  const CampaniaDelAlquilerDrift(this._db);

  final AppDatabase _db;

  /// La campaña a la que paga cuando es una sola, o la que empezó última; `null` si no hay ninguna.
  /// [hoy] es el día de calendario de Montevideo (sin hora).
  Future<String?> leer(String colportorId, DateTime hoy) async =>
      (await enCurso(colportorId, hoy)).firstOrNull?.id;

  /// Las campañas a las que puede pagar el alquiler, la más reciente primero.
  Future<List<CampaniaParaElPago>> enCurso(String colportorId, DateTime hoy) async {
    final dia = '${_cuatro(hoy.year)}-${_dos(hoy.month)}-${_dos(hoy.day)}';
    final campanias = _db.campanias;
    final inscripciones = _db.campaniasColportor;
    final consulta =
        _db.select(campanias).join([
            innerJoin(inscripciones, inscripciones.campaniaId.equalsExp(campanias.id)),
          ])
          ..where(
            inscripciones.usuarioId.equals(colportorId) &
                inscripciones.deletedAt.isNull() &
                campanias.deletedAt.isNull() &
                campanias.fechaInicio.isSmallerOrEqualValue(dia) &
                (campanias.fechaFin.isNull() | campanias.fechaFin.isBiggerOrEqualValue(dia)),
          )
          ..orderBy([OrderingTerm.desc(campanias.fechaInicio), OrderingTerm.asc(campanias.id)]);
    final filas = [for (final f in await consulta.get()) f.readTable(campanias)];
    final cobran = filas.where((c) => (c.alquilerMonto ?? 0) > 0).toList();
    return [
      for (final c in cobran.isEmpty ? filas : cobran)
        CampaniaParaElPago(id: c.id, nombre: c.nombre),
    ];
  }

  static String _dos(int n) => n.toString().padLeft(2, '0');

  static String _cuatro(int n) => n.toString().padLeft(4, '0');
}
