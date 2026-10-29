// HU-SYNC-005 — «Aviso por > 7 días sin backup»: «Llevás N días sin backup. Revisá tu conexión y
// reintentá.» con «Reintentar», en Inicio. Solo con Drive conectado y un respaldo anterior desde el
// cual contar. Casos límite: doble toque, falla a mitad, dos pedidos seguidos, volver y reentrar,
// texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/textos_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/aviso_sin_respaldo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime.utc(2026, 11, 10, 12);

/// El estado de Drive que diga el test, sin pasar por el almacén ni por la sesión.
class _EstadoFijo extends EstadoRespaldoDriveNotifier {
  _EstadoFijo(this._estado);

  final EstadoRespaldoDrive _estado;

  @override
  Future<EstadoRespaldoDrive> build() async => _estado;
}

/// Respaldo que hace lo que el test le diga: se frena, falla o sale bien.
final class _Servicio implements ServicioRespaldo {
  Completer<ResultadoRespaldo>? espera;
  Object? error;
  final List<OrigenRespaldo> pedidos = [];

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    pedidos.add(origen);
    if (espera case final e?) return e.future;
    if (error case final e?) throw e;
    return RespaldoHecho(fecha: _ahora, esBase: false);
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async =>
      const VerificacionOmitida(MotivoOmision.sinWifi);
}

const _conectada = DriveConectada(email: 'ana@example.com', cuentaId: 'g-1');

Future<void> _montar(
  WidgetTester tester, {
  required _Servicio servicio,
  EstadoRespaldoDrive estado = _conectada,
  DateTime? ultimo,
  double escala = 1,
  Size pantalla = const Size(390, 844),
  Stream<DateTime?> Function()? ultimoEnVivo,
}) async {
  tester.view.physicalSize = pantalla;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        estadoRespaldoDriveProvider.overrideWith(() => _EstadoFijo(estado)),
        ultimoRespaldoDriveProvider.overrideWith(
          (ref) => ultimoEnVivo?.call() ?? Stream.value(ultimo),
        ),
        servicioRespaldoProvider.overrideWithValue(servicio),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(
          body: Column(
            children: [
              AvisoSinRespaldo(ahora: () => _ahora),
              const Expanded(child: Center(child: Text('Hoy'))),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _aviso => find.byKey(const Key('aviso_sin_respaldo'));
Finder get _reintentar => find.byKey(const Key('aviso_drive_accion'));

DateTime _haceDias(int dias, {int horas = 0}) =>
    _ahora.subtract(Duration(days: dias, hours: horas));

void main() {
  group('cuándo se muestra', () {
    testWidgets('más de 7 días sin respaldo, con Drive conectado: el texto literal de la HU', (
      tester,
    ) async {
      await _montar(tester, servicio: _Servicio(), ultimo: _haceDias(9, horas: 3));

      expect(_aviso, findsOneWidget);
      expect(
        find.text('Llevás 9 días sin backup. Revisá tu conexión y reintentá.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
    });

    testWidgets('con 7 días justos o menos no aparece', (tester) async {
      await _montar(tester, servicio: _Servicio(), ultimo: _haceDias(7));

      expect(_aviso, findsNothing);
    });

    testWidgets('sin ningún respaldo anterior no hay desde cuándo contar: no aparece', (
      tester,
    ) async {
      await _montar(tester, servicio: _Servicio());

      expect(_aviso, findsNothing);
    });

    for (final (nombre, estado) in <(String, EstadoRespaldoDrive)>[
      ('sin conectar', const DriveSinConectar()),
      ('con el permiso revocado', const DrivePermisoRevocado(email: 'a@b.c', cuentaId: 'g')),
      ('sin espacio', const DriveSinEspacio(email: 'a@b.c', cuentaId: 'g')),
    ]) {
      testWidgets('Drive $nombre: no aparece (ya hay otro aviso para eso)', (tester) async {
        await _montar(tester, servicio: _Servicio(), estado: estado, ultimo: _haceDias(20));

        expect(_aviso, findsNothing);
      });
    }

    testWidgets('si el respaldo se pone al día mientras está abierto, se va solo', (tester) async {
      final cambios = StreamController<DateTime?>();
      addTearDown(cambios.close);
      await _montar(tester, servicio: _Servicio(), ultimoEnVivo: () => cambios.stream);
      cambios.add(_haceDias(10));
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      cambios.add(_ahora);
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
    });
  });

  group('«Reintentar»', () {
    testWidgets('pide un respaldo como acción de la persona', (tester) async {
      final servicio = _Servicio();
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));

      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(servicio.pedidos, [OrigenRespaldo.pedidoPorLaPersona]);
    });

    testWidgets('doble toque: un solo pedido, y el botón queda apagado mientras corre', (
      tester,
    ) async {
      final servicio = _Servicio()..espera = Completer<ResultadoRespaldo>();
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));

      await tester.tap(_reintentar);
      await tester.pump();
      await tester.tap(_reintentar, warnIfMissed: false);
      await tester.pump();

      expect(servicio.pedidos, hasLength(1));
      expect(tester.widget<TextButton>(_reintentar).onPressed, isNull);
      expect(find.text(TextosRespaldoDrive.reintentando), findsOneWidget);

      servicio.espera!.complete(RespaldoHecho(fecha: _ahora, esBase: false));
      await tester.pumpAndSettle();
      expect(servicio.pedidos, hasLength(1));
    });

    testWidgets('falla a mitad: el botón vuelve a habilitarse y se puede reintentar', (
      tester,
    ) async {
      final servicio = _Servicio()..error = StateError('sin red');
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));

      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(_aviso, findsOneWidget, reason: 'sigue ahí: no se respaldó');
      expect(tester.widget<TextButton>(_reintentar).onPressed, isNotNull);
      expect(find.text('Reintentar'), findsOneWidget);

      servicio.error = null;
      await tester.tap(_reintentar);
      await tester.pumpAndSettle();
      expect(servicio.pedidos, hasLength(2));
    });

    testWidgets('el respaldo vuelve «omitido» (sin conexión): el botón también se libera', (
      tester,
    ) async {
      final servicio = _Servicio()
        ..espera = (Completer<ResultadoRespaldo>()
          ..complete(const RespaldoOmitido(MotivoOmision.sinConexion)));
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));

      await tester.tap(_reintentar);
      await tester.pumpAndSettle();

      expect(tester.widget<TextButton>(_reintentar).onPressed, isNotNull);
    });

    testWidgets('salir de la pantalla con el pedido en curso no rompe nada', (tester) async {
      final servicio = _Servicio()..espera = Completer<ResultadoRespaldo>();
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));
      await tester.tap(_reintentar);
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());
      servicio.espera!.complete(RespaldoHecho(fecha: _ahora, esBase: false));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('al reentrar el aviso sigue (nada se guarda: lo decide el último respaldo)', (
      tester,
    ) async {
      final servicio = _Servicio();
      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));
      await tester.pumpWidget(const SizedBox.shrink());

      await _montar(tester, servicio: servicio, ultimo: _haceDias(10));

      expect(_aviso, findsOneWidget);
      expect(tester.widget<TextButton>(_reintentar).onPressed, isNotNull);
    });
  });

  group('datos límite', () {
    testWidgets('texto al 200 % en un teléfono chico: se lee entero y no desborda', (tester) async {
      await _montar(
        tester,
        servicio: _Servicio(),
        ultimo: _haceDias(120),
        escala: 2,
        pantalla: const Size(320, 568),
      );

      expect(
        find.text('Llevás 120 días sin backup. Revisá tu conexión y reintentá.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      // El aviso no se come más del 40 % del alto: el resto de Inicio sigue a la vista.
      expect(tester.getSize(find.byType(AvisoSinRespaldo)).height, lessThanOrEqualTo(568 * 0.4));
      expect(find.text('Hoy'), findsOneWidget);
    });

    testWidgets('el botón mide al menos 48 dp, también al 200 %', (tester) async {
      await _montar(tester, servicio: _Servicio(), ultimo: _haceDias(10), escala: 2);

      final caja = tester.getSize(_reintentar);
      expect(caja.height, greaterThanOrEqualTo(48));
      expect(caja.width, greaterThanOrEqualTo(48));
    });

    testWidgets('el aviso es una región viva: el lector de pantalla lo anuncia', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, servicio: _Servicio(), ultimo: _haceDias(10));

      expect(
        tester.getSemantics(
          find.text('Llevás 10 días sin backup. Revisá tu conexión y reintentá.'),
        ),
        isNotNull,
      );
      semantica.dispose();
    });
  });
}
