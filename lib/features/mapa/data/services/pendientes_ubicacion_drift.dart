import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/logging/app_logger.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../cobranzas/data/datasources/cuotas_local_data_source_drift.dart';
import '../../../ventas/data/datasources/estado_de_devolucion.dart';
import '../../domain/entities/pendientes_ubicacion.dart';
import '../../domain/entities/ubicacion.dart' show TipoUbicacion;
import '../../domain/services/consultor_pendientes_ubicacion.dart';

/// Lo que la baja de una ubicación toca o impide (HU-UBI-005), leído de las tablas locales del
/// teléfono: venta, cobranza, agenda y visita (front-colportores-mobile#330).
///
/// Es el espejo, en el teléfono, de las dos reglas del servidor (backend 0018 y 0069), que es quien las
/// hace valer:
/// - **UB001** — cualquier venta de las personas de la ubicación bloquea. Se cuenta también la que
///   cuelga de un vínculo o un espacio dados de baja: el servidor no mira `deleted_at` ahí, y ante la
///   duda se bloquea (la baja no pierde ventas). Si además queda saldo en una venta viva, el bloqueo
///   es el de la cobranza, con el monto de la próxima cuota (o lo que falta de la venta sin plan) y a
///   dónde ir a cobrarlo.
/// - **UB002** — una visita registrada por otro colportor bloquea (por `visita.espacio_id`, sin mirar
///   `deleted_at`, como el servidor).
///
/// Lo que **no** bloquea: las entrevistas agendadas (`PROGRAMADA`) de la ubicación, que piden la
/// segunda confirmación y la baja cancela en su misma transacción (decisión de Cristian, 21/10). La
/// réplica de la agenda del teléfono es la del propio colportor. Una «visita pendiente» propia ES una
/// entrevista agendada: no hay otra fuente (decisión del 04/11, P3) y la entrevista lleva el aviso. Con
/// varias ventas con saldo, la cobranza es la de la más antigua y dice cuántas son (decisión del 04/11,
/// P4).
///
/// Una falla al leer no se traduce en «no hay nada»: devuelve [FailurePendientesNoDisponibles] y la
/// hoja ofrece «Reintentar» (mismo criterio que `PendientesUbicacionSinFuente`: ante la duda se
/// bloquea).
final class PendientesUbicacionDrift implements ConsultorPendientesUbicacion {
  PendientesUbicacionDrift(
    this._db, {
    required this._cuotas,
    required this._colportorId,
    AppLogger? logger,
  }) : _log = logger ?? AppLogger.instance;

  final AppDatabase _db;
  final CuotasLocalDataSourceDrift _cuotas;
  final String _colportorId;
  final AppLogger _log;

  @override
  Future<Either<Failure, PendientesUbicacion>> de(String ubicacionId) async {
    try {
      return Right(await _leer(ubicacionId));
    } on Object catch (e, st) {
      _log.error(
        LogModulo.map,
        'PENDIENTES_FALLO',
        'no se pudo revisar la ubicación en el teléfono',
        {'ubicacion_id': ubicacionId},
        e,
        st,
      );
      return const Left(FailurePendientesNoDisponibles());
    }
  }

  Future<PendientesUbicacion> _leer(String ubicacionId) async {
    final ventas = await _db
        .customSelect(
          'SELECT v.id AS id, v.monto_total AS monto, v.deleted_at AS borrada, '
          'v.espacio_persona_id AS ep, e.id AS espacio, '
          '(SELECT COALESCE(SUM(c.monto), 0) FROM cobranza c WHERE c.venta_id = v.id '
          'AND ${CobroValido.sql}) AS cobrado '
          'FROM venta v '
          'JOIN espacio_persona ep ON ep.id = v.espacio_persona_id '
          'JOIN espacio e ON e.id = ep.espacio_id '
          'WHERE e.ubicacion_id = ? ORDER BY v.fecha, v.id',
          variables: [Variable<String>(ubicacionId)],
        )
        .get();

    final cobranza = await _primeraCobranza(ventas);

    final tipo = await _db
        .customSelect(
          'SELECT tipo FROM ubicacion WHERE id = ?',
          variables: [Variable<String>(ubicacionId)],
        )
        .getSingleOrNull();

    final ajenas = await _db
        .customSelect(
          'SELECT 1 AS hay FROM visita vi JOIN espacio e ON e.id = vi.espacio_id '
          'WHERE e.ubicacion_id = ? AND vi.colportor_id <> ? LIMIT 1',
          variables: [Variable<String>(ubicacionId), Variable<String>(_colportorId)],
        )
        .get();

    final entrevistas = await _db
        .customSelect(
          'SELECT a.id AS id FROM agenda a JOIN espacio e ON e.id = a.espacio_id '
          'WHERE e.ubicacion_id = ? AND a.tipo = ? AND a.estado = ? AND a.deleted_at IS NULL '
          'ORDER BY a.fecha_programada, a.id',
          variables: [
            Variable<String>(ubicacionId),
            Variable<String>(TipoAgenda.entrevista.codigo),
            Variable<String>(EstadoAgenda.programada.codigo),
          ],
        )
        .get();

    return PendientesUbicacion(
      tipo: _tipoDe(tipo?.read<String>('tipo')),
      cobranzaPendiente: cobranza,
      tieneVentas: ventas.isNotEmpty,
      tieneVisitasDeOtros: ajenas.isNotEmpty,
      entrevistasAgendadas: [for (final f in entrevistas) f.read<String>('id')],
    );
  }

  static TipoUbicacion _tipoDe(String? codigo) => switch (codigo) {
    'EDIFICIO' => TipoUbicacion.edificio,
    'NEGOCIO' => TipoUbicacion.negocio,
    _ => TipoUbicacion.casa,
  };

  /// La cobranza de la primera venta viva (la más antigua) que todavía debe algo, con cuántas ventas
  /// deben, o `null`.
  Future<CobranzaPendiente?> _primeraCobranza(List<QueryRow> ventas) async {
    final vivas = [
      for (final v in ventas)
        if (v.data['borrada'] == null) v,
    ];
    if (vivas.isEmpty) return null;
    final resumenes = await EstadoDeDevolucion.resumenesDe(_db, [
      for (final v in vivas) v.read<String>('id'),
    ]);
    final conSaldo = <({QueryRow venta, int saldo})>[];
    for (final v in vivas) {
      final id = v.read<String>('id');
      final saldo = (resumenes[id] ?? ResumenDeDevoluciones.ninguna)
          .cuentaDe(
            montoTotalCentavos: v.read<int>('monto'),
            cobradoCentavos: v.read<int>('cobrado'),
          )
          .saldoCentavos;
      if (saldo > 0) conSaldo.add((venta: v, saldo: saldo));
    }
    if (conSaldo.isEmpty) return null;
    final (:venta, :saldo) = conSaldo.first;
    final id = venta.read<String>('id');
    final proxima = (await _cuotas.leerPlan(id))?.proxima;
    final falta = proxima?.faltanCentavos ?? 0;
    final deLaCuota = proxima != null && falta > 0 && falta <= saldo;
    return CobranzaPendiente(
      montoCentavos: deLaCuota ? falta : saldo,
      cantidad: conSaldo.length,
      numeroCuota: deLaCuota ? proxima.numero : null,
      ventaId: id,
      espacioId: venta.read<String>('espacio'),
      espacioPersonaId: venta.read<String>('ep'),
    );
  }
}
