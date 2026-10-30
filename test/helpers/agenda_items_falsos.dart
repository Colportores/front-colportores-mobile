// Dobles de la agenda del colportor (HU-VIS-002): filas ya armadas y un lector que emite lo que
// el test le diga, sin tocar la base.
import 'dart:async';

import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/repositories/consulta_agenda_repository.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';

/// Una fila de la agenda a la hora local [cuando].
ItemAgenda itemAgenda(
  String id,
  DateTime cuando, {
  TipoAgenda tipo = TipoAgenda.entrevista,
  EstadoAgenda estado = EstadoAgenda.programada,
  String? nombre = 'Ana',
  String? apellido = 'Martínez',
  String? calle = 'Av. Italia',
  String? numero = '1234',
  TipoUbicacion tipoUbicacion = TipoUbicacion.casa,
  String? numeroDepto,
  bool conCasa = true,
  DateTime? actualizada,
  DateTime? borrada,
  String colportorId = 'col-1',
  String? espacioId,
  String? ubicacionId,
}) {
  final creada = DateTime.utc(2026, 10, 20, 12);
  return ItemAgenda(
    agenda: Agenda(
      id: id,
      espacioId: espacioId ?? 'esp-$id',
      espacioPersonaId: nombre == null ? null : 'ep-$id',
      tipo: tipo,
      fechaProgramada: cuando.toUtc(),
      estado: estado,
      colportorId: colportorId,
      auditoria: Auditoria(
        createdAt: creada,
        updatedAt: (actualizada ?? creada).toUtc(),
        createdBy: colportorId,
        deletedAt: borrada,
      ),
    ),
    personaNombre: nombre,
    personaApellido: apellido,
    casa: conCasa
        ? DireccionDeAgenda(
            ubicacionId: ubicacionId ?? 'ub-$id',
            tipo: tipoUbicacion,
            calle: calle,
            numero: numero,
          )
        : null,
    numeroDepto: numeroDepto,
  );
}

/// Un lector de la agenda que emite lo que se le pone en [items]. Con [error] falla; con [congelada]
/// no emite nunca (la agenda «cargando»). [emitir] empuja una lista nueva a quien esté mirando.
final class ConsultaAgendaFalsa implements ConsultaAgendaRepository {
  ConsultaAgendaFalsa([this.items = const []]);

  List<ItemAgenda> items;
  Object? error;
  bool congelada = false;

  final pedidos = <({String colportorId, DateTime desde, DateTime hasta})>[];
  final pedidosCampania = <({String colportorId, DateTime hoy})>[];
  final pedidosDeLaCasa = <({String colportorId, String ubicacionId})>[];
  final _abiertos = <({StreamController<List<ItemAgenda>> c, List<ItemAgenda> Function() lista})>[];

  Stream<List<ItemAgenda>> _abrir(List<ItemAgenda> Function() lista) {
    final c = StreamController<List<ItemAgenda>>();
    _abiertos.add((c: c, lista: lista));
    c.onListen = () {
      if (congelada) return;
      final e = error;
      if (e != null) {
        c.addError(e);
      } else {
        c.add(lista());
      }
    };
    return c.stream;
  }

  @override
  Stream<List<ItemAgenda>> observar({
    required String colportorId,
    required DateTime desde,
    required DateTime hasta,
  }) {
    pedidos.add((colportorId: colportorId, desde: desde, hasta: hasta));
    return _abrir(() => items);
  }

  @override
  Stream<List<ItemAgenda>> observarCampania({required String colportorId, required DateTime hoy}) {
    pedidosCampania.add((colportorId: colportorId, hoy: hoy));
    return _abrir(() => items);
  }

  @override
  Stream<List<ItemAgenda>> observarDeLaCasa({
    required String colportorId,
    required String ubicacionId,
  }) {
    pedidosDeLaCasa.add((colportorId: colportorId, ubicacionId: ubicacionId));
    return _abrir(
      () => [
        for (final i in items)
          if (i.agenda.estado == EstadoAgenda.programada &&
              i.casa?.ubicacionId == ubicacionId &&
              i.agenda.colportorId == colportorId)
            i,
      ]..sort((a, b) => a.agenda.fechaProgramada.compareTo(b.agenda.fechaProgramada)),
    );
  }

  /// Un error del lector después de haber emitido datos.
  void emitirError(Object e) {
    for (final a in _abiertos) {
      if (!a.c.isClosed && a.c.hasListener) a.c.addError(e);
    }
  }

  void emitir(List<ItemAgenda> nuevos) {
    items = nuevos;
    for (final a in _abiertos) {
      if (!a.c.isClosed && a.c.hasListener) a.c.add(a.lista());
    }
  }
}
