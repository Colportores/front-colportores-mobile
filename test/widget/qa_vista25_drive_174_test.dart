// QA de la vista 25 (#174, PR #489), tercera ronda sobre fe09f31: lo que cambió desde 4b39598.
//
// - 25-08: la fila «Último envío» dice «· por datos» cuando el motor sabe que salió por datos móviles.
// - 25-11: «Conectar Google Drive» del aviso sin respaldo abre la hoja del Drive (vista 16) y avisa cómo
//   salió; el aviso sale del estado real del Drive (`respaldoConfiguradoProvider`, sin override).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/sincronizacion/domain/entities/estado_sincronizacion.dart';
import 'package:colportores_mobile/features/sincronizacion/presentation/pages/sincronizacion_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/qa_vista25_174_arnes.dart';
import '../helpers/sincronizacion_falsos.dart';

/// Un Drive que cambia de estado de verdad al conectar, como el real.
final class _DriveQueConecta extends EstadoRespaldoDriveNotifier {
  _DriveQueConecta(this._inicial, this._alConectar);

  final EstadoRespaldoDrive _inicial;
  final ResultadoConexionDrive Function() _alConectar;

  @override
  Future<EstadoRespaldoDrive> build() async => _inicial;

  @override
  Future<ResultadoConexionDrive> conectar({bool conPrimerRespaldo = true}) async {
    final resultado = _alConectar();
    switch (resultado) {
      case DriveQuedoConectado():
        state = const AsyncData(DriveConectada(email: 'ana@gmail.com', cuentaId: 'cuenta-1'));
      case DriveQuedoEnOtraCuenta(:final estado):
        state = AsyncData(estado);
      default:
    }
    return resultado;
  }
}

/// La página con el Drive REAL (el provider de «hay respaldo» sin override), en [tam] y [escala].
Future<void> _montar(
  WidgetTester tester, {
  required EstadoRespaldoDrive drive,
  ResultadoConexionDrive Function()? alConectar,
  Size tam = const Size(390, 844),
  double escala = 1.0,
}) async {
  final t = TelefonoSync(estado: EstadoSincronizacion(ultimoEnvio: DateTime(2026, 10, 26, 14, 30)));
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      // Los cinco primeros son el motor, la red, el modo ahorro y la hora; los dos últimos fijan el
      // Drive y se reemplazan por los de esta prueba.
      overrides: [
        ...t.overrides.sublist(0, 5),
        estadoRespaldoDriveProvider.overrideWith(
          () => _DriveQueConecta(
            drive,
            alConectar ?? () => const DriveQuedoConectado(primerRespaldoHecho: false),
          ),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const SincronizacionPage(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  group('25-08 «· por datos» en cada tamaño', () {
    for (final tam in tamanos25) {
      for (final escala in escalas25) {
        testWidgets('por datos · ${tam.width.toInt()}×${tam.height.toInt()} · texto $escala', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          final t = TelefonoSync(
            estado: EstadoSincronizacion(
              ultimoEnvio: DateTime(2026, 10, 26, 14, 34),
              ultimoEnvioPorDatos: true,
              ultimaActualizacion: DateTime(2026, 10, 25, 21),
              ultimoRespaldo: DateTime(2026, 10, 25, 3, 10),
              actualizacionEnEspera: true,
            ),
            conexion: TipoConexion.datosMoviles,
            modoAhorro: true,
            respaldoConfigurado: true,
          );
          await montar25(tester, t, tamano: tam, escala: escala);

          expect(tester.takeException(), isNull, reason: 'sin overflow');
          expect(
            tester.widget<Text>(find.byKey(const Key('sincronizacion_ultimo_envio'))).data,
            'hace 1 min · por datos',
          );
          await guias25(tester);
          semantica.dispose();
        });
      }
    }
  });

  group('25-11 «Conectar Google Drive» con el Drive de verdad', () {
    for (final tam in tamanos25) {
      for (final escala in escalas25) {
        testWidgets('aviso y hoja · ${tam.width.toInt()}×${tam.height.toInt()} · texto $escala', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await _montar(tester, drive: const DriveSinConectar(), tam: tam, escala: escala);

          expect(avisoSinRespaldo, findsOneWidget);
          expect(conectarDriveBoton, findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'sin overflow');
          await guias25(tester);

          await _tocar(tester, conectarDriveBoton);
          expect(hojaConectarDrive, findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'sin overflow en la hoja');
          await guias25(tester);
          semantica.dispose();
        });
      }
    }

    testWidgets('should drop the notice and say it when the Drive got connected', (tester) async {
      await _montar(tester, drive: const DriveSinConectar());
      await _tocar(tester, conectarDriveBoton);

      await _tocar(tester, find.byKey(const Key('drive_conectar')));

      expect(hojaConectarDrive, findsNothing);
      expect(find.byKey(const Key('sincronizacion_drive_conectado')), findsOneWidget);
      expect(avisoSinRespaldo, findsNothing, reason: 'ya hay respaldo: el aviso se va');
      expect(conectarDriveBoton, findsNothing);
    });

    testWidgets('should keep the notice and the button when the person gives up', (tester) async {
      await _montar(
        tester,
        drive: const DriveSinConectar(),
        alConectar: () => const DriveNoQuedoConectado(FailureDriveCancelado()),
      );
      await _tocar(tester, conectarDriveBoton);
      await _tocar(tester, find.byKey(const Key('drive_conectar')));

      expect(find.byKey(const Key('sincronizacion_drive_cancelado')), findsOneWidget);
      expect(avisoSinRespaldo, findsOneWidget);
      await _tocar(tester, conectarDriveBoton);
      expect(hojaConectarDrive, findsOneWidget, reason: 'se puede volver a intentar');
    });

    testWidgets('should open the «otra cuenta» sheet when Google answers with another account', (
      tester,
    ) async {
      await _montar(
        tester,
        drive: const DriveSinConectar(),
        alConectar: () => const DriveQuedoEnOtraCuenta(
          DriveCuentaPorConfirmar(
            email: 'nueva@gmail.com',
            cuentaId: 'c2',
            anteriorEmail: 'vieja@gmail.com',
            anteriorCuentaId: 'c1',
          ),
        ),
      );
      await _tocar(tester, conectarDriveBoton);
      await _tocar(tester, find.byKey(const Key('drive_conectar')));

      expect(find.byKey(const Key('drive_otra_cuenta_volver')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (estado, hayAviso) in <(EstadoRespaldoDrive, bool)>[
      (const DriveSinConectar(), true),
      (const DrivePermisoRevocado(email: 'ana@gmail.com', cuentaId: 'c1'), true),
      (const DriveConectada(email: 'ana@gmail.com', cuentaId: 'c1'), false),
    ]) {
      testWidgets(
        'should ${hayAviso ? '' : 'not '}warn about the backup with ${estado.runtimeType}',
        (tester) async {
          await _montar(tester, drive: estado);
          expect(avisoSinRespaldo, hayAviso ? findsOneWidget : findsNothing);
        },
      );
    }
  });
}
