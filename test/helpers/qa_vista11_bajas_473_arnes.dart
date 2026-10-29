// Arnés de los tests de QA de «Dados de baja» al pie del edificio (vista 11, HU-UBI-007, #473, PR #559):
// lleva la hoja real, a los tamaños de la matriz de QA, a cada uno de sus estados nuevos (plegado,
// desplegado, con el aviso de «Deshacer», con el lector, con las fallas) y saca capturas a
// `.dart_tool/qa_capturas/473_*.png` (gitignored: nunca se commitean).
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/aviso_con_deshacer.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_espacios_baja.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'qa_vista11_211_arnes.dart';

export 'qa_vista11_211_arnes.dart';

final _baja473 = DateTime.utc(2026, 10, 22, 9);

/// Los seis deptos del canvas 11·01 y dos dados de baja (103 en el piso 1 y 301 en el 3).
List<Espacio> delEdificio473({int bajas = 2}) => [
  ...deptosDelCanvas(),
  for (var i = 0; i < bajas; i++)
    espacioDe(
      'b-${i + 1}',
      '${((i % 4) + 1) * 100 + 3 + i ~/ 4}',
      piso: '${(i % 4) + 1}',
      orden: 10 + i,
      baja: _baja473,
    ),
];

final cabecera473 = find.byKey(ClavesDadosDeBaja.cabecera);
Finder reactivar473(String id) => find.byKey(ClavesDadosDeBaja.reactivar(id));
Finder filaBaja473(String id) => find.byKey(ClavesDadosDeBaja.fila(id));
final textoAviso473 = find.byKey(ClavesAvisoDeshacer.texto);
final deshacer473 = find.byKey(ClavesAvisoDeshacer.deshacer);
final cerrarAviso473 = find.byKey(ClavesAvisoDeshacer.cerrar);
final avisoRojo473 = find.byKey(ClavesHojaUbicacion.aviso);
final tarjeta473 = find.byType(AvisoDeshacerEnHoja);
final errorBajas473 = find.byKey(ClavesDadosDeBaja.error);
final reintentarBajas473 = find.byKey(ClavesDadosDeBaja.reintentar);

final desplazable473 = find.descendant(of: hojaUbicacion, matching: find.byType(Scrollable)).first;

/// Lleva [destino] a la vista (la lista es perezosa) y deja la hoja quieta.
Future<void> irA473(WidgetTester tester, Finder destino) async {
  await tester.scrollUntilVisible(destino, 120, scrollable: desplazable473, maxScrolls: 400);
  await tester.ensureVisible(destino);
  await asentarHoja(tester);
}

Future<void> desplegar473(WidgetTester tester) async {
  await irA473(tester, cabecera473);
  await tester.tap(cabecera473);
  await asentarHoja(tester);
}

Future<void> tocarReactivar473(WidgetTester tester, String id) async {
  await irA473(tester, reactivar473(id));
  await tester.tap(reactivar473(id));
  await asentarHoja(tester);
}

/// Cada estado nuevo de la hoja.
enum EstadoBajas {
  plegado('plegado'),
  desplegado('desplegado'),
  desplegadoMuchas('desplegado con 8 bajas'),
  vacioConBajas('sin deptos activos y con bajas'),
  cargandoBajas('leyendo las bajas'),
  errorBajas('error al leer las bajas'),
  reactivando('reactivando'),
  reactivado('reactivado con «Deshacer»'),
  reactivadoLector('reactivado con lector'),
  deshecho('deshecho'),
  noPudoDeshacer('no pudo deshacer'),
  errorReactivar('error al reactivar'),
  numeroTomado('número tomado');

  const EstadoBajas(this.rotulo);

  final String rotulo;
}

/// Monta la hoja a [tamano] y [escala] y la lleva a [estado].
Future<MontajeHoja> llegarABajas(
  WidgetTester tester,
  EstadoBajas estado, {
  Size tamano = telefonoChico211,
  double escala = 1,
}) async {
  await cargarFuentes211(tester);
  Future<MontajeHoja> montar({List<Espacio>? espacios, bool abrir = true, bool lector = false}) =>
      montarHoja(
        tester,
        espacios: espacios ?? delEdificio473(),
        tamano: tamano,
        escala: escala,
        abrir: abrir,
        lector: lector,
      );
  switch (estado) {
    case EstadoBajas.plegado:
      return montar();
    case EstadoBajas.desplegado:
      final m = await montar();
      await desplegar473(tester);
      return m;
    case EstadoBajas.desplegadoMuchas:
      final m = await montar(espacios: delEdificio473(bajas: 8));
      await desplegar473(tester);
      return m;
    case EstadoBajas.vacioConBajas:
      return montar(
        espacios: [
          espacioDe('b-1', '103', piso: '1', orden: 1, baja: DateTime.utc(2026, 10, 22, 9)),
        ],
      );
    case EstadoBajas.cargandoBajas:
      final m = await montar(abrir: false);
      m.repo.esperaAlListarBajas = Completer<void>();
      await abrirLaHoja(tester);
      return m;
    case EstadoBajas.errorBajas:
      final m = await montar(abrir: false);
      m.repo.fallaAlListarBajas = const FailureInesperado(causa: 'x');
      await abrirLaHoja(tester);
      return m;
    case EstadoBajas.reactivando:
      final m = await montar();
      await desplegar473(tester);
      m.repo.espera = Completer<void>();
      await irA473(tester, reactivar473('b-1'));
      await tester.tap(reactivar473('b-1'));
      await tester.pump(const Duration(milliseconds: 60));
      return m;
    case EstadoBajas.reactivado:
      final m = await montar();
      await desplegar473(tester);
      await tocarReactivar473(tester, 'b-1');
      return m;
    case EstadoBajas.reactivadoLector:
      final m = await montar(lector: true);
      await desplegar473(tester);
      await tocarReactivar473(tester, 'b-1');
      return m;
    case EstadoBajas.deshecho:
      final m = await montar();
      await desplegar473(tester);
      await tocarReactivar473(tester, 'b-1');
      await tester.tap(deshacer473);
      await asentarHoja(tester);
      return m;
    case EstadoBajas.noPudoDeshacer:
      final m = await montar();
      await desplegar473(tester);
      await tocarReactivar473(tester, 'b-1');
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));
      await tester.tap(deshacer473);
      await asentarHoja(tester);
      return m;
    case EstadoBajas.errorReactivar:
      final m = await montar();
      await desplegar473(tester);
      m.repo.fallas.add(const FailureInesperado(causa: 'x'));
      await tocarReactivar473(tester, 'b-1');
      return m;
    case EstadoBajas.numeroTomado:
      final m = await montar(
        espacios: [
          ...delEdificio473(),
          // Otro depto activo con el número 103 (el de la baja b-1).
          espacioDe('a-103', '103', piso: '2', orden: 30),
        ],
      );
      await desplegar473(tester);
      await tocarReactivar473(tester, 'b-1');
      return m;
  }
}

/// Una captura PNG de todo lo que se ve en `.dart_tool/qa_capturas/473_<nombre>.png`. Solo con
/// `--dart-define=QA_CAPTURAS=true`.
Future<void> capturar473(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & (vista.size));
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/473_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}
