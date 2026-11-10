import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show listEquals;

import '../../../../core/database/app_database.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../../cobranzas/domain/entities/cobranza.dart' show MedioCobranza;
import '../../../cobranzas/domain/services/reparto_de_cuotas.dart';
import '../../../ventas/data/models/venta_model.dart' show VentaItemModel;
import '../../../ventas/domain/entities/componente_vendido.dart';
import '../../domain/entities/evento_de_la_casa.dart';
import '../../domain/entities/ficha_de_persona.dart' show LineaDeFicha;
import '../../domain/services/historial_de_la_casa.dart';
import 'notas_table.dart';

/// [HistorialDeLaCasa] leído de la DB cifrada: las visitas del espacio, las ventas de sus personas y los
/// cobros de esas ventas (vista 39, C·03). Solo lee.
///
/// - **Qué personas**: las ventas de **todos** los vínculos `espacio_persona` del espacio, también los
///   dados de baja, igual que la ficha de la persona: lo que pasó en la casa no se pierde porque alguien
///   ya no viva ahí.
/// - **Qué cobros**: los que cuentan para el saldo ([CobroValido]), la única definición del repo. Lo
///   pagado de cada venta es la suma de esos cobros.
/// - **Una venta y su visita**: la visita `VENTA` que una venta del espacio tiene como `visita_id` no se
///   lista aparte: la venta lleva la nota de esa visita (C·03 dibuja una sola fila).
/// - Lo dado de baja (visitas, ventas, cobros, notas) no se muestra.
/// - **Qué cuotas cubrió un cobro**: si la venta tiene plan (citas de cobranza con monto), se calcula
///   con [RepartoDeCuotas.cuotasDeCadaCobro], el mismo reparto que la vista 30 A.
/// - **La duración de la entrevista** (#466) es la salida menos la entrada que la visita guarda
///   (`entrevista_entrada` y `entrevista_salida`, esquema v34). Sin alguna de las dos (una visita de
///   antes, o sin entrevista) o con la salida antes de la entrada queda en `null`: no se inventa.
///
/// **local-only — PII**: los nombres y las notas viven solo en el teléfono y no van a ningún log.
final class HistorialDeLaCasaLocalDataSourceDrift implements HistorialDeLaCasa {
  HistorialDeLaCasaLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Cuántos ids lleva cada consulta: SQLite admite 32.766 variables por sentencia; el tope es solo un
  /// resguardo.
  static const _porConsulta = 500;

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) {
    // Drift comparte el stream de dos consultas con el mismo texto y se queda con las tablas de la
    // primera: el alias propio evita que otra fuente con un `SELECT 1` pelado tape estas tablas.
    final cambios = _db.customSelect(
      'SELECT 1 AS historial_de_la_casa',
      readsFrom: {
        _db.visitas,
        _db.ventas,
        _db.ventaItems,
        _db.cobranzas,
        _db.agendas,
        _db.espacioPersonas,
        _db.personas,
        _db.notas,
        _db.productos,
        _db.colecciones,
      },
    );
    return cambios.watch().asyncMap((_) => leer(espacioId)).distinct((a, b) => listEquals(a, b));
  }

  /// Cuánto duró la entrevista: [salida] menos [entrada]; `null` si falta alguna o no cierra.
  static Duration? _duracion(DateTime? entrada, DateTime? salida) {
    if (entrada == null || salida == null || salida.isBefore(entrada)) return null;
    return salida.difference(entrada);
  }

  /// Ver [observar], una sola vez.
  Future<List<EventoDeLaCasa>> leer(String espacioId) => _db.transaction(() async {
    final vinculos = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.espacioId.equals(espacioId))).get();
    final personaDe = await _personas({for (final v in vinculos) v.personaId});
    final porVinculo = <String, PersonaDelEvento>{};
    for (final v in vinculos) {
      final persona = personaDe[v.personaId];
      if (persona != null) porVinculo[v.id] = persona;
    }

    final visitas = await (_db.select(
      _db.visitas,
    )..where((v) => v.espacioId.equals(espacioId) & v.deletedAt.isNull())).get();
    final ventas = await _ventas([for (final v in vinculos) v.id]);
    final cobros = await _cobros([for (final v in ventas) v.id]);

    final visitasDeVentas = <String>{for (final v in ventas) ?v.visitaId};
    final notas = await _notasDeVisitas({for (final v in visitas) v.id, ...visitasDeVentas});
    final lineas = await _lineas([for (final v in ventas) v.id]);
    final pagado = <String, int>{};
    for (final c in cobros) {
      pagado.update(c.ventaId, (p) => p + c.monto, ifAbsent: () => c.monto);
    }
    final cuotasDe = await _cuotasDeLosCobros(cobros);
    final talonarioDe = {for (final v in ventas) v.id: v.numeroTalonario};
    final vinculoDeVenta = {for (final v in ventas) v.id: v.espacioPersonaId};

    final eventos = <EventoDeLaCasa>[
      for (final v in visitas)
        // Una visita de venta que tiene su venta se ve como la venta.
        if (!(v.tipoResultado == TipoResultadoVisita.venta.codigo &&
            visitasDeVentas.contains(v.id)))
          VisitaDeLaCasa(
            id: v.id,
            fecha: v.fecha,
            resultado: TipoResultadoVisita.desdeCodigo(v.tipoResultado),
            persona: porVinculo[v.espacioPersonaId],
            nota: notas[v.id],
            duracion: v.tipoResultado == TipoResultadoVisita.entrevista.codigo
                ? _duracion(v.entrevistaEntrada, v.entrevistaSalida)
                : null,
          ),
      for (final v in ventas)
        VentaDeLaCasa(
          id: v.id,
          fecha: v.fecha,
          numeroTalonario: v.numeroTalonario,
          montoCentavos: v.montoTotal,
          pagadoCentavos: pagado[v.id] ?? 0,
          lineas: lineas[v.id] ?? const [],
          persona: porVinculo[v.espacioPersonaId],
          espacioPersonaId: v.espacioPersonaId,
          nota: notas[v.visitaId],
        ),
      for (final c in cobros)
        CobroDeLaCasa(
          id: c.id,
          fecha: c.fecha,
          montoCentavos: c.monto,
          medio: c.medio,
          ventaId: c.ventaId,
          numeroTalonario: talonarioDe[c.ventaId],
          persona: porVinculo[vinculoDeVenta[c.ventaId]],
          cuotas: cuotasDe[c.id],
        ),
    ]..sort(_masNuevoPrimero);
    return List.unmodifiable(eventos);
  });

  static int _masNuevoPrimero(EventoDeLaCasa a, EventoDeLaCasa b) {
    final porFecha = b.fecha.compareTo(a.fecha);
    return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
  }

  Future<Map<String, PersonaDelEvento>> _personas(Set<String> ids) async {
    final salida = <String, PersonaDelEvento>{};
    for (final lote in _lotes(ids.toList())) {
      final filas = await (_db.select(_db.personas)..where((p) => p.id.isIn(lote))).get();
      for (final f in filas) {
        salida[f.id] = PersonaDelEvento(nombre: f.nombre, apellido: f.apellido);
      }
    }
    return salida;
  }

  Future<List<VentaFila>> _ventas(List<String> vinculos) async {
    final salida = <VentaFila>[];
    for (final lote in _lotes(vinculos)) {
      salida.addAll(
        await (_db.select(
          _db.ventas,
        )..where((v) => v.espacioPersonaId.isIn(lote) & v.deletedAt.isNull())).get(),
      );
    }
    return salida;
  }

  Future<List<_Cobro>> _cobros(List<String> ventaIds) async {
    final salida = <_Cobro>[];
    for (final lote in _lotes(ventaIds)) {
      final marcas = List.filled(lote.length, '?').join(', ');
      final filas = await _db
          .customSelect(
            'SELECT c.id AS id, c.venta_id AS venta_id, c.monto AS monto, c.medio AS medio, '
            'c.fecha AS fecha, c.created_at AS creado FROM cobranza c '
            'WHERE ${CobroValido.sql} AND c.venta_id IN ($marcas)',
            variables: [for (final id in lote) Variable<String>(id)],
            readsFrom: {_db.cobranzas},
          )
          .get();
      for (final f in filas) {
        salida.add(
          _Cobro(
            id: f.read<String>('id'),
            ventaId: f.read<String>('venta_id'),
            monto: f.read<int>('monto'),
            medio: _medio(f.read<String>('medio')),
            fecha: DateTime.fromMillisecondsSinceEpoch(f.read<int>('fecha'), isUtc: true),
            creado: DateTime.fromMillisecondsSinceEpoch(f.read<int>('creado'), isUtc: true),
          ),
        );
      }
    }
    return salida;
  }

  /// Qué cuotas cubrió cada cobro de una venta con plan, por `cobranza.id` (C·03: «Cuota 1 de 2»). Las
  /// cuotas son las citas de cobranza con monto de la venta (decisión «Plan cuotas»); sin citas, la
  /// venta no tiene plan y su cobro no figura.
  Future<Map<String, CuotasDeUnCobro>> _cuotasDeLosCobros(List<_Cobro> cobros) async {
    final porVenta = <String, List<_Cobro>>{};
    for (final c in cobros) {
      (porVenta[c.ventaId] ??= []).add(c);
    }
    final citas = <String, List<CitaDeCuota>>{};
    for (final lote in _lotes(porVenta.keys.toList())) {
      final filas =
          await (_db.select(_db.agendas)..where(
                (a) =>
                    a.ventaId.isIn(lote) &
                    a.tipo.equals(TipoAgenda.cobranza.codigo) &
                    a.montoPrevisto.isNotNull() &
                    a.deletedAt.isNull(),
              ))
              .get();
      for (final a in filas) {
        (citas[a.ventaId!] ??= []).add(
          CitaDeCuota(
            agendaId: a.id,
            fecha: a.fechaProgramada.toLocal(),
            montoCentavos: a.montoPrevisto!,
            estado: EstadoAgenda.desdeCodigo(a.estado),
            creadaEn: a.createdAt,
          ),
        );
      }
    }
    final salida = <String, CuotasDeUnCobro>{};
    for (final MapEntry(key: ventaId, value: deLaVenta) in porVenta.entries) {
      final plan = citas[ventaId];
      if (plan == null) continue;
      final cuotas = RepartoDeCuotas.cuotasDeCadaCobro(
        citas: plan,
        cobros: [
          for (final c in deLaVenta)
            CobroDelPlan(
              montoCentavos: c.monto,
              creadoEn: c.creado,
              fecha: c.fecha,
              medio: c.medio,
            ),
        ],
      );
      for (var i = 0; i < deLaVenta.length; i++) {
        final cubiertas = cuotas[i];
        if (cubiertas != null) salida[deLaVenta[i].id] = cubiertas;
      }
    }
    return salida;
  }

  static MedioCobranza _medio(String codigo) => switch (codigo) {
    'TARJETA' => MedioCobranza.tarjeta,
    'TRANSFERENCIA' => MedioCobranza.transferencia,
    _ => MedioCobranza.efectivo,
  };

  /// La nota más nueva de cada visita (`nota` con `target_type = VISITA`, que no esté borrada).
  Future<Map<String, String>> _notasDeVisitas(Set<String> visitaIds) async {
    final salida = <String, String>{};
    for (final lote in _lotes(visitaIds.toList())) {
      final filas =
          await (_db.select(_db.notas)
                ..where(
                  (n) =>
                      n.targetType.equals(TipoObjetivoNota.visita) &
                      n.targetId.isIn(lote) &
                      n.deletedAt.isNull(),
                )
                ..orderBy([(n) => OrderingTerm.desc(n.createdAt), (n) => OrderingTerm.desc(n.id)]))
              .get();
      for (final n in filas) {
        if (n.texto.trim().isEmpty) continue;
        salida.putIfAbsent(n.targetId, () => n.texto.trim());
      }
    }
    return salida;
  }

  /// Los renglones de cada venta con el nombre del producto o de la colección. Un producto que el
  /// catálogo ya no trae (la réplica es de solo lectura) queda como «Producto»: no se inventa un nombre.
  Future<Map<String, List<LineaDeFicha>>> _lineas(List<String> ventaIds) async {
    final salida = <String, List<LineaDeFicha>>{};
    for (final lote in _lotes(ventaIds)) {
      final items =
          await (_db.select(_db.ventaItems)
                ..where((i) => i.ventaId.isIn(lote) & i.deletedAt.isNull())
                ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
              .get();
      if (items.isEmpty) continue;
      final componentes = {
        for (final i in items)
          if (i.coleccionId != null)
            i.id: VentaItemModel.componentesDesdeJson(i.componentes) ?? const <ComponenteVendido>[],
      };
      final productos = await _nombres(
        [
          for (final i in items)
            if (i.productoId != null) i.productoId!,
          for (final c in componentes.values.expand((c) => c)) c.productoId,
        ],
        (lote) async => {
          for (final f in await (_db.select(_db.productos)..where((p) => p.id.isIn(lote))).get())
            f.id: f.nombre,
        },
      );
      final colecciones = await _nombres(
        [
          for (final i in items)
            if (i.coleccionId != null) i.coleccionId!,
        ],
        (lote) async => {
          for (final f in await (_db.select(_db.colecciones)..where((c) => c.id.isIn(lote))).get())
            f.id: f.nombre,
        },
      );
      for (final i in items) {
        final nombre = i.productoId != null
            ? productos[i.productoId] ?? 'Producto'
            : colecciones[i.coleccionId] ?? 'Colección';
        // Un combo lleva sus libros (los de una unidad): «Colección de N libros» cuenta libros y el
        // detalle los nombra (decisión del 10/11, rev 1120). Un libro sin nombre en el catálogo va vacío.
        final libros = componentes[i.id];
        (salida[i.ventaId] ??= []).add(
          LineaDeFicha(
            nombre: nombre,
            cantidad: i.cantidad,
            libros: libros == null
                ? null
                : [
                    for (final c in libros)
                      LineaDeFicha(nombre: productos[c.productoId] ?? '', cantidad: c.cantidad),
                  ],
          ),
        );
      }
    }
    return salida;
  }

  Future<Map<String, String>> _nombres(
    List<String> ids,
    Future<Map<String, String>> Function(List<String> lote) leer,
  ) async {
    final salida = <String, String>{};
    for (final lote in _lotes(ids.toSet().toList())) {
      salida.addAll(await leer(lote));
    }
    return salida;
  }

  Iterable<List<String>> _lotes(List<String> ids) sync* {
    for (var desde = 0; desde < ids.length; desde += _porConsulta) {
      yield ids.sublist(desde, (desde + _porConsulta).clamp(0, ids.length));
    }
  }
}

class _Cobro {
  const _Cobro({
    required this.id,
    required this.ventaId,
    required this.monto,
    required this.medio,
    required this.fecha,
    required this.creado,
  });

  final String id;
  final String ventaId;
  final int monto;
  final MedioCobranza medio;
  final DateTime fecha;

  /// Cuándo se registró (`created_at`): ordena los cobros para el reparto de las cuotas.
  final DateTime creado;
}
