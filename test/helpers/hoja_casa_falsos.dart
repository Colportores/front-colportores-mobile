// Dobles de la hoja de la casa (vista 39, C·01): el contexto (espacio, personas, saldos y nota) que
// la hoja lee, sin base de datos.
import 'dart:async';

import 'package:colportores_mobile/features/agenda/domain/repositories/consulta_agenda_repository.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/consulta_agenda_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_del_lugar.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/repositories/persona_repository.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart'
    show personaRepositoryProvider;
import 'package:flutter_riverpod/misc.dart' show Override;

import 'agenda_items_falsos.dart';
import 'modificar_ubicacion_falsos.dart';
import 'persona_falsos.dart';

/// La nota del canvas (C·01).
final notaDelCanvas = NotaDelLugar(
  id: 'nota-1',
  texto: 'Perro suelto: tocar timbre y esperar.',
  creadaEl: DateTime.utc(2026, 10, 24, 15),
);

/// La nota del canvas con otro [texto].
NotaDelLugar notaCon(String texto) =>
    NotaDelLugar(id: 'nota-1', texto: texto, creadaEl: notaDelCanvas.creadaEl);

/// «Pedro Gómez», que debe $ 1.200 (el canvas, C·01).
final pedroGomez = clienteDePersonas('p-pedro', 'Pedro', apellido: 'Gómez');

/// El contexto del canvas: Pedro Gómez debe $ 1.200 y hay una nota del lugar.
final contextoDelCanvas = ContextoDeLaCasa(
  espacioId: 'esp-1',
  personas: [pedroGomez],
  saldosCentavos: const {'p-pedro': 120000},
  nota: notaDelCanvas,
);

/// La fila de «Grecia 3310» a [metros] del colportor (el canvas: «a 20 m de vos»).
ItemListaUbicacion itemDeLaHoja({
  String id = 'u-1',
  String? calle = 'Grecia',
  String? numero = '3310',
  TipoUbicacion tipo = TipoUbicacion.casa,
  EstadoCasa? estado = EstadoCasa.cobranzaPendiente,
  double? metros = 20,
  DateTime? baja,
  String? motivoBaja,
}) => ItemListaUbicacion(
  ubicacion: ubicacionGuardada(id: id, calle: calle, numero: numero, tipo: tipo, deBajaDesde: baja),
  estado: estado,
  distanciaMetros: metros,
  motivoBaja: motivoBaja,
);

/// Los overrides que le dan a la hoja su contexto: [lectura] arma el `Stream` de cada casa (por
/// defecto, el del canvas, ya resuelto). Cuenta cuántas veces se leyó en [lecturas].
List<Override> overridesHojaCasa({
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lectura,
  List<ClaveDeLaCasa>? lecturas,
  FutureOr<void> Function(ContextoDeVisita)? registrarVisita,
  FutureOr<void> Function(ContextoDeCobro)? cobrar,
  ConsultaAgendaRepository? agendas,
  PersonaRepository? personas,
}) => [
  // La lista «Visitas agendadas» de la hoja lee la agenda local: por defecto, sin visitas (#491).
  consultaAgendaRepositoryProvider.overrideWithValue(agendas ?? ConsultaAgendaFalsa()),
  // «+ Agendar» pregunta con quién es la cita: con [personas] la hoja lee de ahí (#491).
  if (personas != null) personaRepositoryProvider.overrideWithValue(personas),
  contextoDeLaCasaProvider.overrideWith((ref, clave) {
    lecturas?.add(clave);
    return lectura != null ? lectura(clave) : Stream.value(contextoDelCanvas);
  }),
  registrarVisitaDesdeLaCasaProvider.overrideWithValue(registrarVisita),
  cobrarDesdeLaCasaProvider.overrideWithValue(cobrar),
];
