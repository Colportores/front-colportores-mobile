// Arnés del QA de #580 (abrir las cuotas desde la cobranza de la Agenda y desde su aviso): reusa el de
// la implementación (`cuotas_desde_agenda_arnes.dart`, `detalle_agenda_arnes.dart`) y le suma las
// fuentes reales, los tamaños del QA, los estados que una persona alcanza en el detalle de una cuota y
// la app entera con los enganches de verdad. Las capturas solo se sacan con
// `--dart-define=QA_CAPTURAS=true` y van a `.dart_tool/qa_capturas/`.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/error/failure.dart' show FailureCuotasNoDisponibles;
import 'package:colportores_mobile/core/notificaciones/fakes/permiso_notificaciones_sistema_en_memoria.dart';
import 'package:colportores_mobile/core/notificaciones/notificaciones_providers.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/detalle_de_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/estado_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_detalle_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/pages/detalle_agenda_page.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/agenda_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/cobranzas/presentation/providers/cobranzas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/permiso_notificaciones_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/notificaciones_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show casaMataojo, mariaFernandez;
import 'cuotas_arnes.dart' show hoyDeLasCuotas;
import 'cuotas_desde_agenda_arnes.dart';
import 'db_local_repository_en_memoria.dart';
import 'detalle_agenda_arnes.dart';
import 'persona_falsos.dart';
import 'plan_de_cuotas_arnes.dart';
import 'qa_vista23_408_arnes.dart' show cargarFuentes408, conCapturas408, usarFuentesReales408;

export 'qa_vista23_408_arnes.dart' show conCapturas408, usarFuentesReales408;

const chico580 = Size(360, 640);
const grande580 = Size(412, 915);

/// Después de la cuota 2 (09/11): la cuota 1 (02/11) y la 2 están vencidas, la 3 no.
final DateTime despuesDeLaCuota2 = DateTime(2026, 11, 10, 9);

final botonCuotas580 = find.byKey(ClavesDetalleAgenda.verLasCuotas);

/// Una nota larga, como la que pegaría una persona.
final notaLarga580 = List.filled(30, 'Pidió volver con el esposo').join(' ');

/// Los estados del detalle donde se juega «Ver las cuotas».
enum Estado580 {
  programada('detalle de una cuota programada', true),
  cumplida('detalle de una cuota cumplida', true),
  cancelada('detalle de una cuota cancelada', true),
  conNotaLarga('detalle de una cuota con nota larga', true),
  sinCasa('detalle de una cuota sin la casa', true),
  sinRegistrar('detalle de una cuota sin «Registrar resultado»', true),
  noEsCuota('detalle de una cobranza sin plan', false),
  entrevista('detalle de una entrevista', false),
  cargando('detalle cargando', false),
  errorAlLeer('detalle: error al leer', false);

  const Estado580(this.rotulo, this.conAcceso);
  final String rotulo;

  /// Si el estado ofrece «Ver las cuotas».
  final bool conAcceso;
}

Future<ArnesDetalle> llegarA580(
  WidgetTester tester,
  Estado580 estado, {
  Size tamano = chico580,
  double escala = 1,
}) async {
  await cargarFuentes408(tester);
  final plan = planDeLaVenta();
  addTearDown(plan.cerrar);
  Future<ArnesDetalle> montar({
    DetalleDeAgenda? detalle,
    AgendaRepositorioDetalle? repo,
    bool sinCasa = false,
    bool conRegistrar = true,
  }) => montarDetalle(
    tester,
    detalle: detalle,
    repo: repo,
    sinCasa: sinCasa,
    conRegistrar: conRegistrar,
    extras: overridesDeLasCuotas(plan),
    escala: escala,
    tamano: tamano,
  );
  DetalleDeAgenda cuota({EstadoAgenda e = EstadoAgenda.programada, String? nota}) =>
      DetalleDeAgenda(
        agenda: agendaDeCuota(estado: e),
        nota: nota,
      );

  switch (estado) {
    case Estado580.programada:
      return montar(detalle: cuota(nota: 'Pidió volver con el esposo'));
    case Estado580.cumplida:
      return montar(detalle: cuota(e: EstadoAgenda.cumplida));
    case Estado580.cancelada:
      return montar(detalle: cuota(e: EstadoAgenda.cancelada));
    case Estado580.conNotaLarga:
      return montar(detalle: cuota(nota: notaLarga580));
    case Estado580.sinCasa:
      return montar(detalle: cuota(), sinCasa: true);
    case Estado580.sinRegistrar:
      return montar(detalle: cuota(), conRegistrar: false);
    case Estado580.noEsCuota:
      return montar(
        detalle: DetalleDeAgenda(agenda: agendaDelDetalle(tipo: agendaDeCuota().tipo)),
      );
    case Estado580.entrevista:
      return montar();
    case Estado580.cargando:
      return montar(
        repo: AgendaRepositorioDetalle(cuota())..compuertaDeLectura = Completer<void>(),
      );
    case Estado580.errorAlLeer:
      return montar(
        repo: AgendaRepositorioDetalle(cuota())
          ..fallasDeLectura.add(const FailureCuotasNoDisponibles()),
      );
  }
}

/// La app entera, con los enganches de verdad, para tocar avisos.
class AppConAvisos580 {
  AppConAvisos580({
    required this.recordatorios,
    required this.repo,
    required this.plan,
    required this.contenedor,
  });

  final RecordatoriosEnMemoria recordatorios;
  final AgendaRepositorioDetalle repo;
  final PlanDeCuotasEnMemoria plan;
  final ProviderContainer contenedor;
}

Future<AppConAvisos580> abrirApp580(
  WidgetTester tester, {
  AgendaRepositorioDetalle? repo,
  PlanDeCuotasEnMemoria? plan,
  Size tamano = const Size(390, 844),
  double escala = 1,
  DateTime? reloj,
  bool conSesion = true,
}) async {
  await cargarFuentes408(tester);
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final recordatorios = RecordatoriosEnMemoria();
  final repositorio = repo ?? AgendaRepositorioDetalle(DetalleDeAgenda(agenda: agendaDeCuota()));
  final elPlan = plan ?? planDeLaVenta();
  addTearDown(elPlan.cerrar);
  final personas = PersonaRepositorioFalso()..sembrar([mariaFernandez]);
  final dia = reloj ?? hoyDeLasCuotas;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        permisoNotificacionesSistemaProvider.overrideWithValue(
          PermisoNotificacionesSistemaEnMemoria(),
        ),
        permisoNotificacionesRepositoryProvider.overrideWithValue(
          PermisoNotificacionesRepositoryEnMemoria(),
        ),
        recordatoriosProvider.overrideWithValue(recordatorios),
        toquesDeRecordatoriosProvider.overrideWithValue(recordatorios),
        agendaRepositoryProvider.overrideWithValue(repositorio),
        relojVisitaProvider.overrideWithValue(ahoraDelDetalle),
        personaRepositoryProvider.overrideWithValue(personas),
        espacioRepositoryProvider.overrideWithValue(EspacioRepositorioParaPersonas(casaMataojo())),
        planDeCuotasRepositoryProvider.overrideWithValue(elPlan),
        relojCobroProvider.overrideWithValue(() => dia),
        ...FlujoDetalleAgenda.enganches(navigatorKeyColportores),
      ],
      child: const ColportoresApp(),
    ),
  );
  await tester.pumpAndSettle();
  if (conSesion) await ingresar580(tester);
  final contexto = tester.element(find.byType(ColportoresApp));
  return AppConAvisos580(
    recordatorios: recordatorios,
    repo: repositorio,
    plan: elPlan,
    contenedor: ProviderScope.containerOf(contexto),
  );
}

Future<void> ingresar580(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('login_email')), 'ana@example.com');
  await tester.enterText(find.byKey(const Key('login_password')), 'secreto123');
  await tester.ensureVisible(find.byKey(const Key('login_enviar')));
  await tester.tap(find.byKey(const Key('login_enviar')));
  await tester.pumpAndSettle();
}

/// Deja correr los fotogramas sin esperar a los indicadores que giran para siempre.
Future<void> asentar580(WidgetTester tester, [int veces = 20]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// La pantalla completa como PNG, solo con `QA_CAPTURAS`.
Future<void> capturar580(WidgetTester tester, String nombre) async {
  if (!conCapturas408) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/580_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Ningún texto de la pantalla se corta: ni por renglones de más ni con puntos suspensivos.
void sinTextoCortado580(WidgetTester tester) {
  for (final e in find.byType(RichText).evaluate()) {
    if (e.findAncestorWidgetOfExactType<InputDecorator>() != null) continue;
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: 'texto cortado: ${p.text.toPlainText()}');
  }
}

/// Solo para las guías de contraste de Flutter (con las fuentes reales dan falsos negativos).
void sinFuentesReales580() => usarFuentesReales408 = false;

/// Cuántas pantallas de cuotas hay apiladas (las construidas, vivas).
int pantallasDeCuotas580(WidgetTester tester) =>
    find.byKey(const Key('cuotas_lista_pagina'), skipOffstage: false).evaluate().length;

/// La agenda de [id] que es cuota de la venta [ventaId].
Agenda cuotaDeLaVenta580(String id, String ventaId) => agendaDelDetalle(
  id: id,
  tipo: agendaDeCuota().tipo,
  slot: null,
  ventaId: ventaId,
  montoPrevistoCentavos: 83300,
);
