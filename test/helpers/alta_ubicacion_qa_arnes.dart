// Arnés de los tests de QA de las vistas 03 y 04 (#193): monta la pantalla de alta con los fakes de
// `alta_ubicacion_falsos.dart` y llega a los pasos que se prueban.
import 'dart:io';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/situacion_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/fuente_mapa.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/alta_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'alta_ubicacion_falsos.dart';

/// Carga las fuentes del proyecto. Sin esto `flutter_test` pinta cada letra como un cuadrado (Ahem) y
/// las medidas de texto no valen; con esto el texto antialiasado hace que `textContrastGuideline`
/// dé falsos negativos en letra chica, así que se usa solo en los tests de geometría y captura.
Future<void> cargarFuentesReales() async {
  for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
    final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
    final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
    await cargador.load();
  }
}

/// El mapa sin tiles y el aviso rojo de «Sin conexión a internet» (06C·05) dentro de la hoja.
const situacionSinConexion = SituacionMapa(
  fuente: FuenteMapa.sinTiles(),
  aviso: AvisoSinConexion(),
);

/// El GPS que no da ubicación por permiso denegado.
GpsFalso get gpsSinPermiso =>
    GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)));

class _Anfitrion extends StatelessWidget {
  const _Anfitrion(this.salidas);

  final List<SalidaAltaUbicacion?> salidas;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ElevatedButton(
        onPressed: () async =>
            salidas.add(await AltaUbicacionPage.abrir(context, colportorId: 'col-1')),
        child: const Text('abrir'),
      ),
    ),
  );
}

Future<void> asentar(WidgetTester tester, [int veces = 6]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Abre el alta y devuelve la lista donde queda cómo se cerró.
Future<List<SalidaAltaUbicacion?>> montarAlta(
  WidgetTester tester, {
  GpsFalso? gps,
  GeocodificadorFalso? geocodificador,
  RepoAltaFalso? repo,
  double escala = 1,
  Size tamano = const Size(390, 844),
  FuenteMapa? fuente,
  SituacionMapa? situacion,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final salidas = <SalidaAltaUbicacion?>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overridesAlta(
          gps: gps,
          geocodificador:
              geocodificador ??
              GeocodificadorFalso(
                (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1234'),
              ),
          repo: repo,
          ahora: DateTime.utc(2026, 10, 2, 12),
          fuente: fuente,
          situacion: situacion,
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(salidas),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await asentar(tester);
  return salidas;
}

Future<void> tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await asentar(tester);
}

Finder get botonRegistrar => find.widgetWithText(FilledButton, TextosAlta.registrar);

/// Llega al paso de justificación de la vista 04 (artboard B·03) con una candidata que admite
/// «Crear igual».
Future<RepoAltaFalso> hastaJustificacion(
  WidgetTester tester, {
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  final repo = RepoAltaFalso()
    ..comportamiento = (_) async => Right(AltaConDuplicados(candidatas: [candidata('a')]));
  await montarAlta(tester, repo: repo, escala: escala, tamano: tamano);
  await tocar(tester, find.text('Casa'));
  await tocar(tester, botonRegistrar);
  await tocar(tester, find.text('Crear igual'));
  expect(find.text('¿Por qué es otra ubicación?'), findsOneWidget);
  return repo;
}
