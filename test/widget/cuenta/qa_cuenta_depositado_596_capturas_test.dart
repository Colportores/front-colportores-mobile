// Capturas de QA de Mi Cuenta con «Depositado» (#596): un PNG por estado, tamaño y escala, con las
// fuentes reales, en `.dart_tool/qa_capturas/` (no se commitean). Se corre con
// `--dart-define=QA_CAPTURAS=true`; sin eso no hace nada.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/cuenta/domain/entities/resumen_de_cuenta.dart';
import 'package:colportores_mobile/features/cuenta/presentation/providers/cuenta_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/cuenta_arnes.dart';

const _capturar = bool.fromEnvironment('QA_CAPTURAS');

final class _Conexion implements MonitorConectividad {
  _Conexion(this.tipo);
  final TipoConexion tipo;
  @override
  Future<TipoConexion> actual() async => tipo;
  @override
  Stream<TipoConexion> get cambios => const Stream.empty();
}

ResumenDeCuenta _r({CifraDeCuenta? dep, CifraDeCuenta? m, CifraDeCuenta? p, DateTime? al}) =>
    ResumenDeCuenta(
      depositado: dep,
      depositadoAl: dep == null ? null : (al ?? DateTime(2026, 10, 29, 21)),
      enMano: m ?? cifra(2400, variacion: 1800),
      porCobrar: p ?? cifra(9700, variacion: -1300),
    );

void main() {
  final estados = <String, (RepositorioDeCuentaControlable Function(), TipoConexion)>{
    '01_resumen': (
      () => RepositorioDeCuentaControlable(inicial: _r(dep: cifra(26900, variacion: 5300))),
      TipoConexion.wifi,
    ),
    '01b_bajo': (
      () => RepositorioDeCuentaControlable(inicial: _r(dep: cifra(21600, variacion: -5300))),
      TipoConexion.wifi,
    ),
    '01c_sin_bajada': (() => RepositorioDeCuentaControlable(inicial: _r()), TipoConexion.wifi),
    '02_sin_conexion': (
      () => RepositorioDeCuentaControlable(inicial: _r(dep: cifra(26900, variacion: 5300))),
      TipoConexion.sinConexion,
    ),
    '03_cargando': (() => RepositorioDeCuentaControlable(), TipoConexion.wifi),
    '04_cuenta_nueva': (
      () => RepositorioDeCuentaControlable(
        inicial: _r(dep: cifra(0), m: cifra(0), p: cifra(0)),
      ),
      TipoConexion.wifi,
    ),
    '05_error': (
      () => RepositorioDeCuentaControlable()..fallaAlSuscribir = true,
      TipoConexion.wifi,
    ),
    '06_monto_largo': (
      () => RepositorioDeCuentaControlable(
        inicial: _r(
          dep: const CifraDeCuenta(totalCentavos: 9999999999999, variacionCentavos: 8888888888888),
          m: const CifraDeCuenta(totalCentavos: 123456789012, variacionCentavos: -99999999),
        ),
      ),
      TipoConexion.sinConexion,
    ),
  };

  testWidgets('capturas', (tester) async {
    await tester.runAsync(() async {
      for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
        final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
        final c = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
        await c.load();
      }
    });
    Directory('.dart_tool/qa_capturas').createSync(recursive: true);
    final raiz = GlobalKey();
    for (final e in estados.entries) {
      for (final t in const {'360x640': Size(360, 640), '412x915': Size(412, 915)}.entries) {
        for (final esc in [1.0, 2.0]) {
          await montarCuenta(
            tester,
            e.value.$1(),
            tamano: t.value,
            escala: esc,
            boundary: raiz,
            overrides: [
              monitorConectividadProvider.overrideWithValue(_Conexion(e.value.$2)),
              relojCuentaProvider.overrideWithValue(() => DateTime(2026, 10, 30, 12)),
            ],
          );
          await tester.pump(const Duration(milliseconds: 50));
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(() async {
            final r = tester.renderObject<RenderRepaintBoundary>(find.byKey(raiz));
            final img = await r.toImage();
            final bd = (await img.toByteData(format: ui.ImageByteFormat.png))!;
            File(
              '.dart_tool/qa_capturas/596_${e.key}_${t.key}_x${esc.toInt()}.png',
            ).writeAsBytesSync(Uint8List.view(bd.buffer));
          });
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  }, skip: !_capturar);
}
