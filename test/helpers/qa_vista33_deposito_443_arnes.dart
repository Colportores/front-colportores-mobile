// Arnés del QA de «Registrar depósito» (vista 33 D, HU-CTA-004, #443): los estados que una persona
// puede alcanzar, los teléfonos de la matriz, las fuentes reales y las capturas.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/depositos/domain/repositories/deposito_repository.dart';
import 'package:colportores_mobile/features/depositos/presentation/pages/registrar_deposito_page.dart';
import 'package:colportores_mobile/features/depositos/presentation/providers/depositos_providers.dart';
import 'package:colportores_mobile/features/tickets/domain/services/captura_de_foto.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart'
    show CompresorDeImagen;
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'deposito_arnes.dart';
import 'tickets_falsos.dart';

export 'deposito_arnes.dart';

const conCapturas443 = bool.fromEnvironment('QA_CAPTURAS');

/// Los hallazgos del QA llevan `skip`: `--dart-define=QA_HALLAZGOS=true` los corre para verlos fallar.
const verHallazgos443 = bool.fromEnvironment('QA_HALLAZGOS');

/// `false` en el archivo de contraste: con las fuentes reales `textContrastGuideline` da falsos
/// negativos (lee el fondo de una captura con glifos reales).
bool usarFuentesReales443 = true;

const t360x640 = Size(360, 640);
const t412x915 = Size(412, 915);
const tamanos443 = [t360x640, t412x915];
const escalas443 = [1.0, 2.0];

var _fuentesCargadas = false;

Future<void> cargarFuentes443(WidgetTester tester) async {
  if (_fuentesCargadas || !usarFuentesReales443) return;
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
  _fuentesCargadas = true;
}

/// Una captura PNG de lo que se ve en `.dart_tool/qa_capturas/443_<nombre>.png`, solo con
/// `QA_CAPTURAS`.
Future<void> capturar443(WidgetTester tester, String nombre) async {
  if (!conCapturas443) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/443_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String sufijo443(Size tamano, double escala) =>
    '${tamano.width.toInt()}x${tamano.height.toInt()}_x$escala';

/// Lo mismo que `ArnesDeDeposito.overrides`, pero con tres piezas que el test puede cambiar (Riverpod no
/// admite pisar dos veces el mismo proveedor en un contenedor).
List<Override> overrides443(
  ArnesDeDeposito arnes, {
  DepositoRepository? depositos,
  CompresorDeImagen? compresor,
  Future<String?> Function()? campania,
}) {
  var depositoIds = 0;
  var ticketIds = 0;
  return [
    resumenDeCuentaRepositoryProvider.overrideWithValue(arnes.cuenta),
    depositoRepositoryProvider.overrideWithValue(depositos ?? arnes.depositos),
    ticketRepositoryProvider.overrideWithValue(arnes.tickets),
    transaccionDeDepositoProvider.overrideWithValue(TransaccionDirecta()),
    almacenDeFotosDeTicketProvider.overrideWithValue(AlmacenDeFotosEnMemoria()),
    relojDepositoProvider.overrideWithValue(() => ahoraDeposito),
    relojTicketProvider.overrideWithValue(() => ahoraDeposito),
    generadorIdDepositoProvider.overrideWithValue(() => 'd-${++depositoIds}'),
    generadorIdTicketProvider.overrideWithValue(() => 't-${++ticketIds}'),
    capturadorDeFotoProvider.overrideWithValue(arnes.sinCamara ? null : arnes.capturador),
    compresorDeImagenProvider.overrideWithValue(
      compresor ?? CompresorDePrueba([900], legible: arnes.legible),
    ),
    campaniaDelAlquilerProvider.overrideWith(
      (ref, _) async => campania != null ? campania() : arnes.campania,
    ),
    conexionProvider.overrideWith((ref) => Stream.value(arnes.conexion)),
  ];
}

/// Monta la pantalla como [montarDeposito], con overrides de más (los últimos ganan) y fuentes reales.
Future<List<bool>> montar443(
  WidgetTester tester,
  ArnesDeDeposito arnes, {
  Size tamano = t360x640,
  double escala = 1,
  DepositoRepository? depositos,
  CompresorDeImagen? compresor,
  Future<String?> Function()? campania,
  bool abrir = true,
}) async {
  await cargarFuentes443(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final resultados = <bool>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides443(
        arnes,
        depositos: depositos,
        compresor: compresor,
        campania: campania,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_deposito'),
                onPressed: () async => resultados.add(
                  await RegistrarDepositoPage.abrir(context, colportorId: 'col-1'),
                ),
                child: const Text('Abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) await abrirDeposito(tester);
  return resultados;
}

/// Los estados de «Registrar depósito» a los que una persona puede llegar.
enum Estado443 {
  vacio,
  completo,
  mayorQueEnMano,
  montoInvalido,
  registrando,
  registradoBanco,
  registradoRetiro,
  registradoSinConexion,
  errorAlRegistrar,
  sinConexion,
  retiro,
  alquiler,
  alquilerSinCampania,
  sinCamara,
  fotoSinPermiso,
  hojaDeLaFoto,
}

ArnesDeDeposito arnesDe443(Estado443 e) => switch (e) {
  Estado443.sinConexion ||
  Estado443.registradoSinConexion => ArnesDeDeposito(conexion: TipoConexion.sinConexion),
  Estado443.alquilerSinCampania => ArnesDeDeposito(campania: null),
  Estado443.sinCamara => ArnesDeDeposito(sinCamara: true),
  Estado443.fotoSinPermiso => ArnesDeDeposito(
    capturador: CapturadorGuionado([const CapturaSinPermiso()]),
  ),
  Estado443.errorAlRegistrar =>
    ArnesDeDeposito()..depositos.fallarUnaVezCon = const FailureDepositoNoGuardado(),
  _ => ArnesDeDeposito(),
};

Future<void> _elegir(WidgetTester tester, String clave) async {
  await verEnElFormulario(tester, Key(clave));
  await tester.tap(find.byKey(Key(clave)));
  await tester.pump();
}

/// Monta la pantalla y la deja en [estado]. En `registrando` el registro queda esperando: el test
/// llama a [soltar443] al final.
Future<ArnesDeDeposito> llegarA443(
  WidgetTester tester,
  Estado443 estado, {
  Size tamano = t360x640,
  double escala = 1,
  ArnesDeDeposito? arnes,
}) async {
  final a = arnes ?? arnesDe443(estado);
  await montar443(tester, a, tamano: tamano, escala: escala);
  await tester.pumpAndSettle();
  switch (estado) {
    case Estado443.vacio || Estado443.sinConexion || Estado443.sinCamara:
      break;
    case Estado443.completo:
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
    case Estado443.mayorQueEnMano:
      await escribirMonto(tester, '3000');
    case Estado443.montoInvalido:
      await escribirMonto(tester, '1.8');
    case Estado443.registrando:
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      a.depositos.espera = Completer<void>();
      await tocarRegistrar(tester, esperar: false);
      await tester.pump(const Duration(milliseconds: 50));
    case Estado443.registradoBanco || Estado443.errorAlRegistrar || Estado443.registradoSinConexion:
      await escribirMonto(tester, '1800');
      await sacarLaFoto(tester);
      await tocarRegistrar(tester);
    case Estado443.registradoRetiro:
      await escribirMonto(tester, '1000');
      await _elegir(tester, 'deposito_destino_2');
      await tocarRegistrar(tester);
    case Estado443.retiro:
      await escribirMonto(tester, '1000');
      await _elegir(tester, 'deposito_destino_2');
    case Estado443.alquiler || Estado443.alquilerSinCampania:
      await escribirMonto(tester, '1500');
      await _elegir(tester, 'deposito_concepto_1');
    case Estado443.fotoSinPermiso:
      await verEnElFormulario(tester, const Key('deposito_foto'));
      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('deposito_foto_camara')));
      await tester.pumpAndSettle();
    case Estado443.hojaDeLaFoto:
      await verEnElFormulario(tester, const Key('deposito_foto'));
      await tester.tap(find.byKey(const Key('deposito_foto')));
      await tester.pumpAndSettle();
  }
  return a;
}

/// Suelta un registro que quedó esperando y deja el árbol quieto.
Future<void> soltar443(WidgetTester tester, ArnesDeDeposito arnes) async {
  final espera = arnes.depositos.espera;
  if (espera != null && !espera.isCompleted) espera.complete();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 600));
}

/// Un compresor que espera a que el test lo suelte (la foto «Preparando…»).
final class CompresorLento443 implements CompresorDeImagen {
  final espera = Completer<void>();
  @override
  Future<Uint8List?> comprimirComoJpeg(
    Uint8List original, {
    required int ladoMaximo,
    required int calidad,
  }) async {
    await espera.future;
    return Uint8List.fromList(List.filled(900, 7));
  }
}
