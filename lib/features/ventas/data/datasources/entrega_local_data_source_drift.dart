import 'dart:async';

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../../core/domain/instante.dart';
import '../../../../core/sync/encolador_sync.dart';
import '../../../agenda/data/datasources/agenda_local_data_source_drift.dart';
import '../../../agenda/data/models/agenda_model.dart';
import '../../../agenda/domain/entities/agenda.dart';
import '../../../agenda/domain/entities/estado_agenda.dart';
import '../../../agenda/domain/entities/tipo_agenda.dart';
import '../../../agenda/domain/services/texto_recordatorio.dart';
import '../../../mapa/domain/entities/color_house_status.dart';
import '../../../mapa/domain/services/house_status_updater.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/entrega_diferida.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/repositories/entrega_repository.dart';
import '../../domain/services/reglas_de_entrega.dart';
import '../models/entrega_model.dart';
import 'estado_de_entrega.dart';

/// La persistencia no pudo entregar: la venta de la entrega no está en el teléfono (o está dada de
/// baja). El repositorio la traduce a su `Failure`.
final class EntregaSinVentaException implements Exception {
  const EntregaSinVentaException();

  @override
  String toString() => 'EntregaSinVentaException';
}

/// La casa de la venta no está en el teléfono (su vínculo persona ↔ espacio falta o está dado de
/// baja): la cita de la agenda cuelga del espacio y sin él no se puede agendar. No se guarda nada.
final class EntregaSinCasaException implements Exception {
  const EntregaSinCasaException();

  @override
  String toString() => 'EntregaSinCasaException';
}

/// La venta no tiene nada pendiente de entregar (ya se entregó todo, o no tiene filas de entrega).
final class EntregaSinPendientesException implements Exception {
  const EntregaSinPendientesException({this.sinFilas = false});

  /// La venta no tiene ninguna fila de entrega (nunca se dejó para otro día ni se entregó).
  final bool sinFilas;

  @override
  String toString() => 'EntregaSinPendientesException';
}

/// Una de las filas pedidas no es de la venta (o no existe): no se entrega nada.
final class EntregaAjenaException implements Exception {
  const EntregaAjenaException();

  @override
  String toString() => 'EntregaAjenaException';
}

/// [EntregaRepository] sobre las tablas `entrega`, `venta` y `agenda` de la DB cifrada.
///
/// Cada escritura es **una transacción de Drift** (contrato-sync-engine §3: [EncoladorSync] se llama
/// adentro, así que si falla se revierte todo): las filas de la entrega, su encolado y el recálculo
/// del color de la casa (R-UB08). Drift serializa las transacciones: un doble toque ve una lo que
/// dejó la otra, así que la venta no se entrega dos veces por carrera.
///
/// La entrega diferida (HU-VEN-003) escribe también la cita `ENTREGA` de la agenda y la encola en esa
/// misma transacción, **después** de las filas de entrega a las que apunta (`agenda.entrega_id` es una
/// clave foránea en el servidor).
final class EntregaLocalDataSourceDrift {
  /// [_encolador] y [_estadoDeLasCasas] se pasan como `encolador:` y `estadoDeLasCasas:`.
  EntregaLocalDataSourceDrift(
    this._db, {
    required this._encolador,
    required this._estadoDeLasCasas,
  });

  final AppDatabase _db;
  final EncoladorSync _encolador;
  final HouseStatusUpdater _estadoDeLasCasas;

  /// Ver [EntregaRepository.entregarAhora]. Lanza [EntregaSinVentaException] si la venta no está.
  ///
  /// Lo que la venta ya dejó **pendiente** (HU-VEN-003) se cumple: esas filas pasan a entregadas con
  /// la fecha real (un `update`, no una fila nueva) y su cita `ENTREGA` se cumple como al marcarla
  /// entregada. Solo lo que no tenía fila se inserta. Así queda una sola fila por libro y el servidor
  /// descuenta el stock una vez (decisión del 30/10, QA #584).
  Future<EntregaRegistrada> entregarAhora(
    String ventaId, {
    required String colportorId,
    required DateTime ahora,
    required String Function() generarId,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);

    // Lo que falta: lo vendido menos lo ya entregado. Un segundo toque o un reintento no encuentra
    // nada que falte, no escribe y responde lo mismo que la primera.
    final faltante = ReglasDeEntrega.cantidadesFaltantes(
      await EstadoDeEntrega.vendidoDe(_db, ventaId),
      await EstadoDeEntrega.entregadoDe(_db, ventaId),
    );
    if (faltante.isEmpty) {
      return EntregaRegistrada(
        entregas: await _vivas(ventaId),
        colorDeLaCasa: await _colorActual(venta.espacioPersonaId),
        yaEstaba: true,
      );
    }

    final instante = instanteMs(ahora);
    final previas = await _vivas(ventaId);
    final reparto = await _reparto(ventaId, previas);
    // Lo pendiente que cabe en lo que falta se cumple; lo que sobra de un producto (más pendiente que
    // faltante, por una devolución) se deja como está: no se entrega lo que volvió.
    final restante = Map<String, int>.of(faltante);
    final cumplidas = <String>{};
    for (final fila in previas) {
      if (!fila.pendiente) continue;
      final falta = restante[fila.productoId] ?? 0;
      if (fila.cantidad > falta) continue;
      restante[fila.productoId] = falta - fila.cantidad;
      await _actualizar(fila.editada(ahora: instante, pendiente: false, fechaEntrega: instante));
      cumplidas.add(fila.id);
    }
    for (final MapEntry(:key, :value) in restante.entries) {
      if (value <= 0) continue;
      final fila = Entrega(
        id: generarId(),
        ventaId: ventaId,
        productoId: key,
        cantidad: value,
        pendiente: false,
        fechaEntrega: ahora,
        auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: colportorId),
      );
      await _db.into(_db.entregas).insert(_aFila(fila));
      await _encolador.encolar('entrega', OperacionSync.insert, EntregaModel.toJson(fila));
    }

    // Cada cita cuyos libros quedaron todos entregados se hizo: pasa a CUMPLIDA. Una venta puede
    // tener una por cada grupo de libros diferido (decisión de Cristian del 11/11, «Entrega cita»).
    final cumplidasLasCitas = <String>[];
    for (final cita in reparto.citas) {
      final grupo = reparto.filasDe(cita, previas);
      if (grupo.isEmpty || !grupo.every((e) => cumplidas.contains(e.id))) continue;
      await _escribirCita(
        cita.id,
        AgendasCompanion(estado: Value(EstadoAgenda.cumplida.codigo), updatedAt: Value(instante)),
      );
      cumplidasLasCitas.add(cita.id);
    }
    final color = await _recalcular(venta.espacioPersonaId, ahora: ahora, colportorId: colportorId);
    return EntregaRegistrada(
      entregas: await _vivas(ventaId),
      colorDeLaCasa: color,
      citaCumplidaId: cumplidasLasCitas.firstOrNull,
      otrasCitasCumplidas: cumplidasLasCitas.skip(1).toList(),
    );
  });

  /// Ver [EntregaRepository.registrarEntrega]. Lanza [EntregaSinVentaException] si la venta no está.
  Future<EntregaRegistrada> registrarEntrega(
    String ventaId,
    List<Entrega> filas, {
    DateTime? soloDesde,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);

    final existentes = _desde(await _vivas(ventaId), soloDesde);
    if (existentes.isNotEmpty) {
      // Un segundo toque o un reintento: no se escribe nada y la respuesta dice lo mismo que la
      // primera.
      return EntregaRegistrada(
        entregas: existentes,
        colorDeLaCasa: await _colorActual(venta.espacioPersonaId),
        yaEstaba: true,
      );
    }

    for (final fila in filas) {
      await _db.into(_db.entregas).insert(_aFila(fila));
      await _encolador.encolar('entrega', OperacionSync.insert, EntregaModel.toJson(fila));
    }
    final color = await _recalcular(
      venta.espacioPersonaId,
      ahora: filas.isEmpty ? venta.updatedAt : filas.first.auditoria.updatedAt,
      colportorId: venta.colportorId,
    );
    return EntregaRegistrada(
      entregas: _desde(await _vivas(ventaId), soloDesde),
      colorDeLaCasa: color,
    );
  });

  /// [filas] creadas desde [desde] (lo que se sumó a una venta abierta); todas sin [desde].
  static List<Entrega> _desde(List<Entrega> filas, DateTime? desde) => desde == null
      ? filas
      : [
          for (final f in filas)
            if (!f.auditoria.createdAt.isBefore(desde)) f,
        ];

  /// Ver [EntregaRepository.deLaVenta].
  Future<List<Entrega>> deLaVenta(String ventaId) => _vivas(ventaId);

  /// Ver [EntregaRepository.diferir]. Lanza [EntregaSinVentaException], [EntregaSinCasaException],
  /// [EntregaSinPendientesException] o [EntregaAjenaException].
  ///
  /// Los libros que se difieren (todos, los sumados desde [soloDesde] o las filas [entregaIds]) quedan
  /// para [fechaPrevista] con **su** cita (decisión de Cristian del 11/11, «Entrega cita»: una cita
  /// viva por cada grupo de libros diferido). Lo pendiente de otro grupo de la venta, con su cita, no
  /// se toca. La cita de los libros:
  /// - si la venta ya tiene una cita a esa misma hora, es esa (la misma visita);
  /// - si no, la que ya tenían esos libros se mueve a la fecha nueva;
  /// - si no tenían, se crea una.
  /// Una cita que se queda sin libros porque los suyos pasaron a otra de la misma hora se cancela.
  Future<EntregaDiferida> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
    DateTime? soloDesde,
    Set<String>? entregaIds,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);
    final espacioId = await _espacioDe(venta.espacioPersonaId);
    if (espacioId == null) throw const EntregaSinCasaException();
    final cuando = instanteMs(fechaPrevista);

    final todas = await _vivas(ventaId);
    if (entregaIds != null && !entregaIds.every((id) => todas.any((e) => e.id == id))) {
      throw const EntregaAjenaException();
    }
    List<Entrega> objetivoDe(List<Entrega> filas) => [
      for (final f in _desde(filas, soloDesde))
        if (entregaIds == null || entregaIds.contains(f.id)) f,
    ];

    var cambio = false;
    // Las citas y sus grupos como estaban antes de mover nada.
    final reparto = await _reparto(ventaId, todas);
    final objetivo = objetivoDe(todas);
    if (objetivo.isEmpty) {
      // Sin filas y sin productos que dejar: no hay entrega que agendar.
      if (filasNuevas.isEmpty) throw const EntregaSinPendientesException(sinFilas: true);
      for (final fila in filasNuevas) {
        await _db.into(_db.entregas).insert(_aFila(fila));
        await _encolador.encolar('entrega', OperacionSync.insert, EntregaModel.toJson(fila));
      }
      cambio = true;
    } else if (!objetivo.any((e) => e.pendiente)) {
      throw const EntregaSinPendientesException();
    }
    final ids = {
      for (final e in objetivo.isEmpty ? filasNuevas : objetivo)
        if (e.pendiente) e.id,
    };

    // La cita que ya está a esa hora (de estos libros o de otros de la venta) es la de esta visita.
    Agenda? cita = reparto.citas
        .where((c) => c.fechaProgramada.isAtSameMomentAs(cuando))
        .firstOrNull;
    // Las citas que hoy llevan estos libros y se quedan sin ninguno al moverlos.
    final vacias = [
      for (final c in reparto.citas)
        if (reparto.filasDe(c, todas) case final grupo
            when grupo.isNotEmpty && grupo.every((e) => ids.contains(e.id)))
          c,
    ];

    for (final fila in objetivoDe(await _vivas(ventaId))) {
      if (!fila.pendiente || fila.fechaPrevista == cuando) continue;
      await _actualizar(fila.editada(ahora: ahora, fechaPrevista: cuando));
      cambio = true;
    }
    final filas = objetivoDe(await _vivas(ventaId));
    // La cita apunta a una fila de la entrega: la primera de las pendientes.
    final ancla = filas.firstWhere((e) => e.pendiente);

    var nueva = false;
    if (cita == null && vacias.isNotEmpty) {
      cita = await _escribirCita(
        vacias.first.id,
        AgendasCompanion(
          fechaProgramada: Value(cuando),
          entregaId: Value(ancla.id),
          updatedAt: Value(instanteMs(ahora)),
        ),
      );
      cambio = true;
    } else if (cita == null) {
      cita = await _crearCita(
        id: idDeLaCita,
        venta: venta,
        espacioId: espacioId,
        cuando: cuando,
        ancla: ancla,
        ahora: ahora,
      );
      nueva = true;
      cambio = true;
    }

    final canceladas = <String>[];
    for (final c in vacias) {
      if (c.id == cita.id) continue;
      await _escribirCita(
        c.id,
        AgendasCompanion(
          estado: Value(EstadoAgenda.cancelada.codigo),
          updatedAt: Value(instanteMs(ahora)),
        ),
      );
      canceladas.add(c.id);
      cambio = true;
    }

    final color = await _recalcularEspacio(espacioId, ahora: ahora, colportorId: venta.colportorId);
    return EntregaDiferida(
      entregas: filas,
      cita: cita,
      direccion: await _direccionDe(espacioId),
      colorDeLaCasa: color,
      yaEstaba: !cambio,
      citaNueva: nueva,
      citasCanceladas: canceladas,
    );
  });

  /// Ver [EntregaRepository.cumplir]. Lanza [EntregaSinVentaException],
  /// [EntregaSinPendientesException] (`sinFilas` si la venta no tiene ninguna fila) o
  /// [EntregaAjenaException].
  ///
  /// Una venta puede tener una cita por cada grupo de libros diferido (decisión de Cristian del 11/11,
  /// «Entrega cita»): marcar una entrega toca solo los libros de esa cita ([agendaId]) o del grupo de
  /// las filas pedidas ([entregaIds]). Sin ninguno de los dos, toda la venta.
  Future<EntregaCumplida> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
    String? agendaId,
  }) => _db.transaction(() async {
    final venta = await _ventaViva(ventaId);
    final previas = await _vivas(ventaId);
    if (previas.isEmpty) throw const EntregaSinPendientesException(sinFilas: true);
    if (entregaIds != null && !entregaIds.every((id) => previas.any((e) => e.id == id))) {
      throw const EntregaAjenaException();
    }
    final espacioId = await _espacioDe(venta.espacioPersonaId);
    final pendientes = [
      for (final fila in previas)
        if (fila.pendiente) fila,
    ];
    final reparto = await _reparto(ventaId, previas);

    // Lo que se pide entregar y el alcance: los grupos (citas) de eso. Lo de otra cita no se toca.
    final laCita = agendaId == null
        ? null
        : reparto.citas.where((c) => c.id == agendaId).firstOrNull;
    final Set<String>? pedidas;
    if (entregaIds != null) {
      pedidas = entregaIds;
    } else if (agendaId != null) {
      pedidas = {
        if (laCita != null)
          for (final e in reparto.filasDe(laCita, previas)) e.id,
      };
    } else {
      pedidas = null;
    }
    final fechas = {
      for (final e in pendientes)
        if (pedidas == null || pedidas.contains(e.id)) _ms(e.fechaPrevista),
    };
    final alcance = [
      for (final e in pendientes)
        if (pedidas == null || fechas.contains(_ms(e.fechaPrevista))) e,
    ];
    final citas = [
      for (final c in reparto.citas)
        if (pedidas == null ||
            c.id == laCita?.id ||
            reparto.filasDe(c, previas).any((e) => alcance.any((a) => a.id == e.id)))
          c,
    ];

    // Solo lo que falta entregar del neto (decisión del 30/10, «Devol. s/ent»): un libro devuelto sin
    // entregarse no se marca, aunque su fila siga pendiente; una fila devuelta en parte se entrega con
    // lo que queda.
    final neto = await _pendienteNeto(ventaId, [
      for (final fila in pendientes)
        (id: fila.id, productoId: fila.productoId, cantidad: fila.cantidad),
    ]);
    final aEntregar = [
      for (final fila in alcance)
        if (neto.containsKey(fila.id) && (pedidas == null || pedidas.contains(fila.id))) fila,
    ];

    Future<List<Agenda>> cumplirLas(Iterable<Agenda> cuales) async {
      final cerradas = <Agenda>[];
      for (final c in cuales) {
        cerradas.add(
          await _escribirCita(
            c.id,
            AgendasCompanion(
              estado: Value(EstadoAgenda.cumplida.codigo),
              updatedAt: Value(instanteMs(ahora)),
            ),
          ),
        );
      }
      return cerradas;
    }

    if (aEntregar.isEmpty && alcance.isNotEmpty && !alcance.any((f) => neto.containsKey(f.id))) {
      // Hay filas pendientes pero todo lo que tenían se devolvió sin entregarse: no hay nada que
      // entregar y no es «ya estaba entregada». La visita de la entrega ya no hace falta: su cita se
      // cierra (CUMPLIDA, como cuando no queda nada pendiente) para que no quede programada para
      // siempre. Las filas no se tocan (decisión del 30/10, «Devol. s/ent»).
      final cerradas = await cumplirLas(citas);
      return EntregaCumplida(
        entregas: previas,
        entregadas: const [],
        cita: cerradas.firstOrNull,
        citaCumplida: cerradas.isNotEmpty,
        otrasCitasCumplidas: [for (final c in cerradas.skip(1)) c.id],
        direccion: espacioId == null ? '' : await _direccionDe(espacioId),
        colorDeLaCasa: espacioId == null ? null : await _colorDelEspacio(espacioId),
        todoDevuelto: true,
        quedaPendiente: pedidas == null ? null : alcance.isNotEmpty,
      );
    }
    if (aEntregar.isEmpty) {
      // Sin nada pendiente que se haya pedido entregar: ya estaba entregado (un segundo toque o un
      // reintento), con ids o sin ellos. «Marcar de nuevo lo hecho» no es un error (QA #433, P2).
      return EntregaCumplida(
        entregas: previas,
        entregadas: const [],
        cita: laCita ?? citas.firstOrNull,
        direccion: espacioId == null ? '' : await _direccionDe(espacioId),
        colorDeLaCasa: espacioId == null ? null : await _colorDelEspacio(espacioId),
        yaEstaba: true,
        quedaPendiente: pedidas == null ? null : alcance.isNotEmpty,
      );
    }

    for (final fila in aEntregar) {
      await _actualizar(
        fila.editada(ahora: ahora, pendiente: false, fechaEntrega: ahora, cantidad: neto[fila.id]),
      );
    }
    final restantes = [
      for (final fila in alcance)
        if (neto.containsKey(fila.id) && !aEntregar.any((e) => e.id == fila.id)) fila,
    ];
    final cuando = nuevaFecha == null ? null : instanteMs(nuevaFecha);
    for (final fila in restantes) {
      // Lo que queda lleva la fecha nueva, o ninguna: la vieja ya pasó sin entregarse.
      if (fila.fechaPrevista == cuando) continue;
      await _actualizar(
        fila.editada(ahora: ahora, fechaPrevista: cuando, sinFechaPrevista: cuando == null),
      );
    }

    var cita = laCita ?? citas.firstOrNull;
    var cumplida = false;
    var conFechaNueva = false;
    var otras = <String>[];
    if (restantes.isEmpty || cuando == null) {
      // Nada pendiente, o lo que queda quedó sin fecha: la visita de la entrega se hizo.
      final primera = cita;
      final cerradas = await cumplirLas([
        ?primera,
        for (final c in citas)
          if (c.id != primera?.id) c,
      ]);
      if (cerradas.isNotEmpty) {
        cita = cerradas.first;
        cumplida = true;
        otras = [for (final c in cerradas.skip(1)) c.id];
      }
    } else {
      // Lo que queda tiene fecha nueva. Si otra cita de la venta ya está a esa hora, es la misma visita
      // y lo que queda pasa a ella; si no, la cita de estos libros se mueve (o se crea una).
      final enEsaHora = reparto.citas
          .where((c) => !citas.contains(c) && c.fechaProgramada.isAtSameMomentAs(cuando))
          .firstOrNull;
      final propia = cita;
      if (enEsaHora != null) {
        otras = [for (final c in await cumplirLas(citas)) c.id];
        cita = enEsaHora;
      } else if (propia != null) {
        otras = [
          for (final c in await cumplirLas([
            for (final c in citas)
              if (c.id != propia.id) c,
          ]))
            c.id,
        ];
        cita = await _escribirCita(
          propia.id,
          AgendasCompanion(
            fechaProgramada: Value(cuando),
            entregaId: Value(restantes.first.id),
            updatedAt: Value(instanteMs(ahora)),
          ),
        );
        conFechaNueva = true;
      } else if (espacioId != null) {
        // Lo que quedó salió de una entrega que no tenía cita (inmediata parcial, o la cita se
        // canceló a mano): la fecha nueva le agenda una.
        cita = await _crearCita(
          id: idDeLaCita,
          venta: venta,
          espacioId: espacioId,
          cuando: cuando,
          ancla: restantes.first,
          ahora: ahora,
        );
        conFechaNueva = true;
      }
    }

    final color = espacioId == null
        ? null
        : await _recalcularEspacio(espacioId, ahora: ahora, colportorId: venta.colportorId);
    final filas = await _vivas(ventaId);
    return EntregaCumplida(
      entregas: filas,
      entregadas: [
        for (final fila in filas)
          if (aEntregar.any((e) => e.id == fila.id)) fila,
      ],
      cita: cita,
      citaCumplida: cumplida,
      citaConFechaNueva: conFechaNueva,
      otrasCitasCumplidas: otras,
      direccion: espacioId == null ? '' : await _direccionDe(espacioId),
      colorDeLaCasa: color,
      // Lo de otra cita de la venta no cuenta como «quedó pendiente» de esta.
      quedaPendiente: pedidas == null ? null : alcance.any((f) => !aEntregar.contains(f)),
    );
  });

  /// Ver [EntregaRepository.observarPendientes].
  ///
  /// Lo pendiente es **neto de devoluciones** (decisión del 30/10, «Devol. s/ent»): un libro que volvió
  /// sin entregarse no figura, aunque su fila `entrega` siga pendiente ([_pendienteNeto]). Por eso se
  /// vuelve a leer también cuando cambian los renglones de la venta o sus devoluciones.
  Stream<List<EntregaPendiente>> observarPendientes({String? espacioPersonaId}) {
    final cambios = _db.tableUpdates(
      TableUpdateQuery.onAllTables([
        _db.entregas,
        _db.ventas,
        _db.ventaItems,
        _db.agendas,
        _db.espacioPersonas,
        _db.devoluciones,
      ]),
    );
    StreamSubscription<void>? suscripcion;
    late final StreamController<List<EntregaPendiente>> salida;
    var leyendo = false;
    var otraVez = false;
    Future<void> leer() async {
      // Un cambio mientras se lee pide otra lectura al terminar: nunca queda una vista vieja.
      if (leyendo) {
        otraVez = true;
        return;
      }
      leyendo = true;
      try {
        do {
          otraVez = false;
          final lista = await _pendientes(espacioPersonaId);
          if (!salida.isClosed) salida.add(lista);
        } while (otraVez && !salida.isClosed);
      } on Object catch (error, pila) {
        if (!salida.isClosed) salida.addError(error, pila);
      } finally {
        leyendo = false;
      }
    }

    salida = StreamController<List<EntregaPendiente>>(
      onListen: () {
        suscripcion = cambios.listen((_) => unawaited(leer()));
        unawaited(leer());
      },
      onCancel: () => suscripcion?.cancel(),
    );
    return salida.stream;
  }

  /// Una lectura de lo pendiente (ver [observarPendientes]): una [EntregaPendiente] por **grupo** de
  /// libros de cada venta, con su fecha y su cita (decisión de Cristian del 11/11, «Entrega cita»: lo
  /// que se sumó a una venta puede tener su propia cita).
  Future<List<EntregaPendiente>> _pendientes(String? espacioPersonaId) async {
    final entregas = _db.entregas;
    final ventas = _db.ventas;
    final vinculos = _db.espacioPersonas;
    final consulta =
        _db.select(entregas).join([
            innerJoin(ventas, ventas.id.equalsExp(entregas.ventaId)),
            leftOuterJoin(vinculos, vinculos.id.equalsExp(ventas.espacioPersonaId)),
          ])
          ..where(
            entregas.pendiente.equals(true) &
                entregas.deletedAt.isNull() &
                ventas.deletedAt.isNull() &
                (espacioPersonaId == null
                    ? const Constant(true)
                    : ventas.espacioPersonaId.equals(espacioPersonaId)),
          )
          ..orderBy([OrderingTerm.asc(entregas.createdAt), OrderingTerm.asc(entregas.id)]);
    final filas = await consulta.get();
    final ventasLeidas = <String, ({VentaFila venta, String? espacioId})>{};
    final filasPorVenta = <String, List<Entrega>>{};
    for (final fila in filas) {
      final venta = fila.readTable(ventas);
      ventasLeidas.putIfAbsent(
        venta.id,
        () => (venta: venta, espacioId: fila.readTableOrNull(vinculos)?.espacioId),
      );
      filasPorVenta
          .putIfAbsent(venta.id, () => [])
          .add(EntregaModel.desdeFila(fila.readTable(entregas)));
    }
    final grupos = <_VentaPendiente>[];
    for (final MapEntry(key: ventaId, value: propias) in filasPorVenta.entries) {
      final neto = await _pendienteNeto(ventaId, [
        for (final e in propias) (id: e.id, productoId: e.productoId, cantidad: e.cantidad),
      ]);
      final reparto = await _reparto(ventaId, propias);
      final (:venta, :espacioId) = ventasLeidas[ventaId]!;
      final porFecha = <int?, _VentaPendiente>{};
      for (final e in propias) {
        final cantidad = neto[e.id];
        if (cantidad == null) continue;
        porFecha
            .putIfAbsent(
              _ms(e.fechaPrevista),
              () => _VentaPendiente(
                venta.id,
                venta.espacioPersonaId,
                venta.fecha,
                espacioId,
                venta.numeroTalonario,
                fecha: e.fechaPrevista,
                agendaId: reparto.citaDe(e)?.id,
              ),
            )
            .lineas[e.id] = LineaPendiente(
          entregaId: e.id,
          productoId: e.productoId,
          cantidad: cantidad,
        );
      }
      grupos.addAll(porFecha.values);
    }
    grupos.sort(_VentaPendiente.comparar);
    return [for (final g in grupos) g.aEntidad()];
  }

  /// Cuánto de cada fila pendiente de [ventaId] falta entregar de verdad, `entrega.id` → cantidad:
  /// lo vendido **menos lo devuelto** y menos lo ya entregado se reparte entre las [pendientes] en su
  /// orden. Una fila de un libro que volvió sin entregarse no figura; una que volvió en parte figura
  /// con lo que queda (decisión del 30/10, «Devol. s/ent»: la fila no se borra ni toca el stock).
  Future<Map<String, int>> _pendienteNeto(
    String ventaId,
    List<({String id, String productoId, int cantidad})> pendientes,
  ) async {
    final restante = Map<String, int>.of(
      ReglasDeEntrega.cantidadesFaltantes(
        await EstadoDeEntrega.vendidoDe(_db, ventaId),
        await EstadoDeEntrega.entregadoDe(_db, ventaId),
      ),
    );
    final neto = <String, int>{};
    for (final fila in pendientes) {
      final falta = restante[fila.productoId] ?? 0;
      if (falta <= 0) continue;
      final cantidad = fila.cantidad < falta ? fila.cantidad : falta;
      neto[fila.id] = cantidad;
      restante[fila.productoId] = falta - cantidad;
    }
    return neto;
  }

  /// La venta [ventaId] sin baja, o [EntregaSinVentaException].
  Future<VentaFila> _ventaViva(String ventaId) async {
    final venta = await (_db.select(
      _db.ventas,
    )..where((v) => v.id.equals(ventaId))).getSingleOrNull();
    if (venta == null || venta.deletedAt != null) throw const EntregaSinVentaException();
    return venta;
  }

  /// El espacio (la casa o el depto) del vínculo [espacioPersonaId], o `null` si el vínculo o el
  /// espacio no están en el teléfono o están dados de baja.
  Future<String?> _espacioDe(String espacioPersonaId) async {
    final vinculo = await (_db.select(
      _db.espacioPersonas,
    )..where((v) => v.id.equals(espacioPersonaId))).getSingleOrNull();
    if (vinculo == null || vinculo.deletedAt != null) return null;
    final espacio = await (_db.select(
      _db.espacios,
    )..where((e) => e.id.equals(vinculo.espacioId))).getSingleOrNull();
    return espacio == null || espacio.deletedAt != null ? null : espacio.id;
  }

  /// Las citas `ENTREGA` `PROGRAMADA` de la venta, de la más antigua a la más nueva.
  Future<List<Agenda>> _citasVivas(String ventaId) async {
    final filas =
        await (_db.select(_db.agendas)
              ..where(
                (a) =>
                    a.ventaId.equals(ventaId) &
                    a.tipo.equals(TipoAgenda.entrega.codigo) &
                    a.estado.equals(EstadoAgenda.programada.codigo) &
                    a.deletedAt.isNull(),
              )
              ..orderBy([(a) => OrderingTerm.asc(a.createdAt), (a) => OrderingTerm.asc(a.id)]))
            .get();
    return [for (final f in filas) AgendaLocalDataSourceDrift.desdeFila(f)];
  }

  /// Las citas vivas de la venta, cada una con su grupo de las [filas] pendientes
  /// ([ReglasDeEntrega.repartirCitas]).
  Future<_Reparto> _reparto(String ventaId, List<Entrega> filas) async {
    final citas = await _citasVivas(ventaId);
    return _Reparto(
      citas,
      ReglasDeEntrega.repartirCitas(
        [for (final c in citas) (id: c.id, fecha: c.fechaProgramada.millisecondsSinceEpoch)],
        [
          for (final e in filas)
            if (e.pendiente) _ms(e.fechaPrevista),
        ],
      ),
    );
  }

  /// Agenda la entrega de [venta] para [cuando], apuntando a la fila [ancla], y encola el alta.
  Future<Agenda> _crearCita({
    required String id,
    required VentaFila venta,
    required String espacioId,
    required DateTime cuando,
    required Entrega ancla,
    required DateTime ahora,
  }) async {
    final cita = Agenda(
      id: id,
      espacioId: espacioId,
      espacioPersonaId: venta.espacioPersonaId,
      tipo: TipoAgenda.entrega,
      fechaProgramada: cuando,
      colportorId: venta.colportorId,
      ventaId: venta.id,
      entregaId: ancla.id,
      auditoria: Auditoria(createdAt: ahora, updatedAt: ahora, createdBy: venta.colportorId),
    );
    await _db.into(_db.agendas).insert(AgendaLocalDataSourceDrift.aFila(cita));
    await _encolador.encolar('agenda', OperacionSync.insert, AgendaModel.fromEntity(cita).toJson());
    return cita;
  }

  /// Aplica [cambios] a la cita [id], la lee y encola su `update` con la fila entera.
  Future<Agenda> _escribirCita(String id, AgendasCompanion cambios) async {
    await (_db.update(_db.agendas)..where((a) => a.id.equals(id))).write(cambios);
    final cita = AgendaLocalDataSourceDrift.desdeFila(
      await (_db.select(_db.agendas)..where((a) => a.id.equals(id))).getSingle(),
    );
    await _encolador.encolar('agenda', OperacionSync.update, AgendaModel.fromEntity(cita).toJson());
    return cita;
  }

  /// Escribe el estado y las fechas de la fila [e] y encola su `update` con la fila entera.
  Future<void> _actualizar(Entrega e) async {
    await (_db.update(_db.entregas)..where((x) => x.id.equals(e.id))).write(
      EntregasCompanion(
        cantidad: Value(e.cantidad),
        pendiente: Value(e.pendiente),
        fechaPrevista: Value(e.fechaPrevista),
        fechaEntrega: Value(e.fechaEntrega),
        updatedAt: Value(e.auditoria.updatedAt),
      ),
    );
    await _encolador.encolar('entrega', OperacionSync.update, EntregaModel.toJson(e));
  }

  /// «Av. Italia 1234»: la dirección de la ubicación del espacio, vacía si no está en el teléfono.
  Future<String> _direccionDe(String espacioId) async {
    final consulta =
        _db.selectOnly(_db.espacios).join([
            innerJoin(_db.ubicaciones, _db.ubicaciones.id.equalsExp(_db.espacios.ubicacionId)),
          ])
          ..addColumns([_db.ubicaciones.calle, _db.ubicaciones.numero])
          ..where(_db.espacios.id.equals(espacioId));
    final fila = await consulta.getSingleOrNull();
    if (fila == null) return '';
    return TextoRecordatorio.direccionDe(
      fila.read(_db.ubicaciones.calle),
      fila.read(_db.ubicaciones.numero),
    );
  }

  Future<String?> _ubicacionDelEspacio(String espacioId) async {
    final consulta = _db.selectOnly(_db.espacios)
      ..addColumns([_db.espacios.ubicacionId])
      ..where(_db.espacios.id.equals(espacioId));
    return (await consulta.getSingleOrNull())?.read(_db.espacios.ubicacionId);
  }

  /// El color guardado de la casa del espacio [espacioId], o `null` si no tiene.
  Future<ColorHouseStatus?> _colorDelEspacio(String espacioId) async {
    final ubicacionId = await _ubicacionDelEspacio(espacioId);
    if (ubicacionId == null) return null;
    return _colorGuardado(ubicacionId);
  }

  /// Recalcula el color de la casa del espacio [espacioId]. Si la ubicación no está en el teléfono no
  /// hay casa que pintar: se guarda igual.
  Future<ColorHouseStatus?> _recalcularEspacio(
    String espacioId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final ubicacionId = await _ubicacionDelEspacio(espacioId);
    if (ubicacionId == null) return null;
    final estado = await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: ahora,
      colportorId: colportorId,
    );
    return estado?.color;
  }

  Future<List<Entrega>> _vivas(String ventaId) async {
    final filas =
        await (_db.select(_db.entregas)
              ..where((e) => e.ventaId.equals(ventaId) & e.deletedAt.isNull())
              ..orderBy([(e) => OrderingTerm.asc(e.createdAt), (e) => OrderingTerm.asc(e.id)]))
            .get();
    return [for (final fila in filas) EntregaModel.desdeFila(fila)];
  }

  /// La ubicación del vínculo persona ↔ espacio, o `null` si no está en el teléfono.
  Future<String?> _ubicacionDe(String espacioPersonaId) async {
    final consulta =
        _db.selectOnly(_db.espacioPersonas).join([
            innerJoin(_db.espacios, _db.espacios.id.equalsExp(_db.espacioPersonas.espacioId)),
          ])
          ..addColumns([_db.espacios.ubicacionId])
          ..where(_db.espacioPersonas.id.equals(espacioPersonaId));
    final fila = await consulta.getSingleOrNull();
    return fila?.read(_db.espacios.ubicacionId);
  }

  /// Recalcula el color de la casa de la venta. Si la ubicación no está en el teléfono no hay casa que
  /// pintar: la entrega se guarda igual, porque no se pierde una entrega por una fila que falta.
  Future<ColorHouseStatus?> _recalcular(
    String espacioPersonaId, {
    required DateTime ahora,
    required String colportorId,
  }) async {
    final ubicacionId = await _ubicacionDe(espacioPersonaId);
    if (ubicacionId == null) return null;
    final estado = await _estadoDeLasCasas.recalcular(
      ubicacionId,
      ahora: ahora,
      colportorId: colportorId,
    );
    return estado?.color;
  }

  Future<ColorHouseStatus?> _colorActual(String espacioPersonaId) async {
    final ubicacionId = await _ubicacionDe(espacioPersonaId);
    if (ubicacionId == null) return null;
    return _colorGuardado(ubicacionId);
  }

  Future<ColorHouseStatus?> _colorGuardado(String ubicacionId) async {
    final fila = await (_db.select(
      _db.houseStatuses,
    )..where((h) => h.ubicacionId.equals(ubicacionId))).getSingleOrNull();
    if (fila == null || fila.deletedAt != null) return null;
    return ColorHouseStatus.desdeCodigo(fila.color);
  }

  static EntregasCompanion _aFila(Entrega e) => EntregasCompanion.insert(
    id: e.id,
    ventaId: e.ventaId,
    productoId: e.productoId,
    cantidad: e.cantidad,
    pendiente: Value(e.pendiente),
    fechaPrevista: Value(e.fechaPrevista),
    fechaEntrega: Value(e.fechaEntrega),
    createdAt: e.auditoria.createdAt,
    updatedAt: e.auditoria.updatedAt,
    createdBy: Value(e.auditoria.createdBy),
    deletedAt: Value(e.auditoria.deletedAt),
    syncVersion: Value(e.auditoria.syncVersion),
  );
}

/// Las citas vivas de entrega de una venta con el grupo de libros pendientes de cada una (ver
/// [ReglasDeEntrega.repartirCitas]).
final class _Reparto {
  _Reparto(this.citas, this._fechaDe);

  /// De la más antigua a la más nueva.
  final List<Agenda> citas;

  /// Por id de cita, la fecha (ms) de su grupo; una cita sin grupo no figura.
  final Map<String, int?> _fechaDe;

  /// Las filas pendientes de [filas] que son de [cita]; vacío si la cita no tiene grupo.
  List<Entrega> filasDe(Agenda cita, List<Entrega> filas) {
    if (!_fechaDe.containsKey(cita.id)) return const [];
    final fecha = _fechaDe[cita.id];
    return [
      for (final e in filas)
        if (e.pendiente && _ms(e.fechaPrevista) == fecha) e,
    ];
  }

  /// La cita del grupo de [fila], o `null` si no tiene (sin fecha, o la cita se canceló a mano).
  Agenda? citaDe(Entrega fila) {
    final fecha = _ms(fila.fechaPrevista);
    if (fecha == null) return null;
    for (final c in citas) {
      if (_fechaDe.containsKey(c.id) && _fechaDe[c.id] == fecha) return c;
    }
    return null;
  }
}

int? _ms(DateTime? instante) => instante?.millisecondsSinceEpoch;

/// Lo que se junta de un grupo de libros pendientes de una venta (los de una misma fecha prevista y
/// su cita) mientras se recorren las filas de la consulta de pendientes.
final class _VentaPendiente {
  _VentaPendiente(
    this.ventaId,
    this.espacioPersonaId,
    this.vendidaEl,
    this.espacioId,
    this.numeroTalonario, {
    this.fecha,
    this.agendaId,
  });

  final String ventaId;
  final String espacioPersonaId;
  final DateTime vendidaEl;
  final String? espacioId;
  final String numeroTalonario;
  final lineas = <String, LineaPendiente>{};
  final DateTime? fecha;
  final String? agendaId;

  EntregaPendiente aEntidad() => EntregaPendiente(
    ventaId: ventaId,
    espacioPersonaId: espacioPersonaId,
    lineas: lineas.values.toList(),
    fechaPrevista: fecha,
    agendaId: agendaId,
    espacioId: espacioId,
    numeroTalonario: numeroTalonario,
  );

  /// Primero las que tienen fecha, de la más próxima a la más lejana; después las que no, de la venta
  /// más vieja a la más nueva. El desempate final es el id, para que el orden no dependa del azar.
  static int comparar(_VentaPendiente a, _VentaPendiente b) {
    final fa = a.fecha;
    final fb = b.fecha;
    if (fa != null && fb == null) return -1;
    if (fa == null && fb != null) return 1;
    if (fa != null && fb != null) {
      final c = fa.compareTo(fb);
      if (c != 0) return c;
    }
    final c = a.vendidaEl.compareTo(b.vendidaEl);
    return c != 0 ? c : a.ventaId.compareTo(b.ventaId);
  }
}
