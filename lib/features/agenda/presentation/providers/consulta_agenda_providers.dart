import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/database/database_providers.dart';
import '../../data/datasources/cobranzas_sin_fecha_drift.dart';
import '../../data/repositories/consulta_agenda_repository_drift.dart';
import '../../domain/entities/cobranza_por_agendar.dart';
import '../../domain/entities/filtros_agenda.dart';
import '../../domain/entities/item_agenda.dart';
import '../../domain/entities/tipo_agenda.dart';
import '../../domain/repositories/consulta_agenda_repository.dart';
import '../../domain/services/armador_agenda.dart';

// Cableado de la pestaña Agenda (HU-VIS-002, vista 23B): qué lee, los filtros que el colportor puso
// y los dos destinos que llegan con otras HU (agendar, #408, y el detalle, #409).

/// Lee las agendas de la DB cifrada. Sin DB abierta no hay de dónde leer: lanza, y la pantalla lo
/// muestra como «No pudimos leer tu agenda.» (23B·09).
final consultaAgendaRepositoryProvider = Provider<ConsultaAgendaRepository>((ref) {
  final db = ref.watch(dbLocalProvider);
  if (db == null) throw StateError('La base de datos local no está abierta');
  return ConsultaAgendaRepositoryDrift(db);
});

/// El reloj de la agenda («hoy», «mañana», qué cita ya pasó de hora); un test lo reemplaza.
final relojAgendaProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Riverpod 3 reintenta 10 veces lo que falla: la pantalla muestra el error enseguida (23B·09) y el
/// «Reintentar» es de quien lo toca.
Duration? _sinReintentos(int intento, Object error) => null;

/// Qué ventana lee la agenda: el colportor y el día en que empieza (hoy a medianoche, hora local). Al
/// cambiar el día la clave cambia y se lee la ventana nueva.
typedef ClaveAgenda = ({String colportorId, DateTime inicioDeHoy});

/// Las agendas de la ventana «hoy + 7 días», de todos los estados, y las programadas que quedaron
/// atrás (las atrasadas), reactivas: agendar, cancelar o
/// registrar una visita las vuelve a emitir (stream-first, HU-VIS-002 «Stream reactivo»). Los filtros
/// se aplican después, en memoria, sobre lo ya leído: cambiarlos no vuelve a la base.
final agendaLeidaProvider = StreamProvider.autoDispose.family<List<ItemAgenda>, ClaveAgenda>((
  ref,
  clave,
) {
  final ventana = VentanaAgenda.de(clave.inicioDeHoy);
  return ref
      .watch(consultaAgendaRepositoryProvider)
      .observar(colportorId: clave.colportorId, desde: ventana.desdeUtc, hasta: ventana.hastaUtc);
}, retry: _sinReintentos);

/// Las agendas de **la campaña en curso**, de todos los estados, reactivas: la lista de un estado
/// cerrado o «Todas» (HU-VIS-002, decisión de Cristian, 27/10, «Rango filtro»). Igual que
/// [agendaLeidaProvider], los filtros y el «Ver más» se aplican después, en memoria. Al cambiar el día
/// la clave cambia y se vuelve a leer.
final agendaCampaniaLeidaProvider = StreamProvider.autoDispose
    .family<List<ItemAgenda>, ClaveAgenda>(
      (ref, clave) => ref
          .watch(consultaAgendaRepositoryProvider)
          .observarCampania(colportorId: clave.colportorId, hoy: clave.inicioDeHoy),
      retry: _sinReintentos,
    );

/// Las ventas del colportor con saldo y sin ninguna cobranza agendada (el grupo «Sin fecha» del final
/// de la Agenda, 42B·01G; decisión del 10/11, P4 del PR #681), reactivas: agendarles la cobranza las
/// saca solas.
final cobranzasSinFechaProvider = StreamProvider.autoDispose
    .family<List<CobranzaPorAgendar>, String>((ref, colportorId) {
      final db = ref.watch(dbLocalProvider);
      if (db == null) throw StateError('La base de datos local no está abierta');
      return CobranzasSinFechaDrift(db).observar(colportorId);
    }, retry: _sinReintentos);

/// Qué casa lee «Visitas agendadas»: el colportor y la ubicación.
typedef ClaveVisitasDeLaCasa = ({String colportorId, String ubicacionId});

/// Las visitas `PROGRAMADA` de una casa, reactivas (la lista «Visitas agendadas» de la hoja de la casa,
/// vista 23, 23B·10, #491). Agendar, cancelar o registrar una visita, o dar de baja la casa o el
/// depto, las vuelve a emitir.
final visitasAgendadasDeLaCasaProvider = StreamProvider.autoDispose
    .family<List<ItemAgenda>, ClaveVisitasDeLaCasa>(
      (ref, clave) => ref
          .watch(consultaAgendaRepositoryProvider)
          .observarDeLaCasa(colportorId: clave.colportorId, ubicacionId: clave.ubicacionId),
      retry: _sinReintentos,
    );

/// Qué visitas agendadas se leen en la ficha de una persona.
typedef ClaveVisitasDeLaPersona = ({String colportorId, String personaId});

/// Las visitas `PROGRAMADA` de una persona, reactivas (la tarjeta «PRÓXIMA VISITA» de su ficha, vista
/// 32, 23A·05, #405). Agendar, cancelar o registrar una visita, o dar de baja el depto, las vuelve a
/// emitir.
final visitasAgendadasDeLaPersonaProvider = StreamProvider.autoDispose
    .family<List<ItemAgenda>, ClaveVisitasDeLaPersona>(
      (ref, clave) => ref
          .watch(consultaAgendaRepositoryProvider)
          .observarDeLaPersona(colportorId: clave.colportorId, personaId: clave.personaId),
      retry: _sinReintentos,
    );

/// Los filtros de la agenda del colportor [colportorId]: por tipo y por estado. Se conservan mientras
/// la pantalla esté montada (la hoja «Agendados» del mapa usa los mismos).
final class FiltrosAgendaNotifier extends Notifier<FiltrosAgenda> {
  FiltrosAgendaNotifier(this.colportorId);

  final String colportorId;

  @override
  FiltrosAgenda build() => FiltrosAgenda.porDefecto;

  /// `null` = «Todas».
  void elegirTipo(TipoAgenda? tipo) => state = state.conTipo(tipo);

  void elegirEstado(EstadoFiltroAgenda estado) => state = state.conEstado(estado);

  void limpiar() => state = FiltrosAgenda.porDefecto;
}

final filtrosAgendaProvider = NotifierProvider.autoDispose
    .family<FiltrosAgendaNotifier, FiltrosAgenda, String>(FiltrosAgendaNotifier.new);

/// A dónde lleva «+ Agendar» (vista 23B, #568): elige la casa en la lista de ubicaciones, pregunta con
/// quién y abre «Agendar visita» (23A·01) con ellas. Devuelve `true` si se agendó. **Sin destino**
/// (`null`) el botón no se muestra, como los de la hoja de la casa: los botones llegan con la HU que
/// los resuelve.
final agendarDesdeLaAgendaProvider = Provider<FutureOr<Object?> Function()?>((ref) => null);

/// A dónde lleva «+ Agendar» del rótulo de un **día futuro** (23B·01, #568): lo mismo que
/// [agendarDesdeLaAgendaProvider], con ese día como fecha inicial de «Agendar visita». Recibe el día a
/// medianoche. Sin destino (`null`) el rótulo usa [agendarDesdeLaAgendaProvider], con la fecha de siempre.
final agendarEnUnDiaDesdeLaAgendaProvider = Provider<FutureOr<Object?> Function(DateTime dia)?>(
  (ref) => null,
);

/// A dónde lleva tocar una agenda (vista 23C·01, #409): su detalle. Recibe el `id` de la agenda.
/// **Sin destino** (`null`) las filas no se tocan y no llevan la flecha «›».
final abrirDetalleDeAgendaProvider = Provider<FutureOr<Object?> Function(String agendaId)?>(
  (ref) => null,
);
