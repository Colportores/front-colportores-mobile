// QA de #583 (PR #624), P6 — el aviso «Llevás N días sin respaldo» de Hoy cuando nunca hubo un respaldo:
// la cadena entera con las piezas de verdad (sesión → repositorio de Drive sobre el almacén seguro →
// `conectadaDesdeDriveProvider` → el aviso), solo con el servicio de respaldo y el último respaldo
// falsos. El aspecto del aviso no cambió (lo cubre `qa_aviso_sin_respaldo_185_test.dart`).
import 'dart:async';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/aviso_sin_respaldo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';
import '../helpers/respaldo_drive_falsos.dart';

final class _Servicio implements ServicioRespaldo {
  int pedidos = 0;
  ResultadoRespaldo resultado = RespaldoHecho(fecha: DateTime.utc(2026, 11, 4), esBase: true);

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    pedidos++;
    return resultado;
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async =>
      const VerificacionOmitida(MotivoOmision.sinWifi);
}

Finder get _aviso => find.byKey(const Key('aviso_sin_respaldo'));

void main() {
  late DateTime reloj;
  late RespaldoDriveArmado drive;
  late _Servicio servicio;
  late StreamController<DateTime?> ultimo;
  late ProviderContainer container;
  late String usuarioId;

  Future<void> preparar({bool ultimoCargando = false}) async {
    reloj = DateTime.utc(2026, 10, 20, 15);
    drive = RespaldoDriveArmado(ahora: () => reloj);
    servicio = _Servicio();
    ultimo = StreamController<DateTime?>.broadcast();
    container = ProviderContainer(
      overrides: [
        dbLocalRepositoryProvider.overrideWithValue(dbLocalYaPreparada()),
        authRemoteDataSourceProvider.overrideWithValue(
          AuthRemoteDataSourceEnMemoria(credenciales: const {'ana@example.com': 'secreto123'}),
        ),
        authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
        respaldoDriveRepositoryProvider.overrideWithValue(drive.repo),
        servicioRespaldoProvider.overrideWithValue(servicio),
        ultimoRespaldoDriveProvider.overrideWith((ref) async* {
          if (ultimoCargando) await Completer<void>().future;
          yield null;
          yield* ultimo.stream;
        }),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await ultimo.close();
    });
    await container.read(sesionProvider.future);
    await container
        .read(sesionProvider.notifier)
        .iniciarSesion(email: 'ana@example.com', password: 'secreto123');
    usuarioId = container.read(sesionProvider).value!.usuarioId;
  }

  /// Abre «Hoy» con el reloj de la app en [ahora] (el del repositorio es `reloj`).
  Future<void> abrirHoy(WidgetTester tester, DateTime ahora) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        key: UniqueKey(),
        container: container,
        child: MaterialApp(
          theme: temaClaro(),
          home: Scaffold(body: AvisoSinRespaldo(ahora: () => ahora)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Escenario: conectó Drive hace 10 días, el primer respaldo falló y nunca hubo uno', (
    tester,
  ) async {
    await preparar();
    await drive.repo.conectar(usuarioId);

    await abrirHoy(tester, reloj.add(const Duration(days: 10)));

    expect(
      find.text('Llevás 10 días sin respaldo. Revisá tu conexión y reintentá.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets(
    'conectó hace 7 días justos: todavía no avisa; a los 7 días y 1 hora, sí («8 días»)',
    (tester) async {
      await preparar();
      await drive.repo.conectar(usuarioId);

      await abrirHoy(tester, reloj.add(const Duration(days: 7)));
      expect(_aviso, findsNothing);

      await abrirHoy(tester, reloj.add(const Duration(days: 7, hours: 1)));
      expect(
        find.text('Llevás 8 días sin respaldo. Revisá tu conexión y reintentá.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('Drive sin conectar: no avisa aunque pasen los días', (tester) async {
    await preparar();
    await abrirHoy(tester, reloj.add(const Duration(days: 30)));

    expect(_aviso, findsNothing);
  });

  testWidgets('la persona desconectó Drive hace días: el aviso se va y no vuelve solo', (
    tester,
  ) async {
    await preparar();
    await drive.repo.conectar(usuarioId);
    await abrirHoy(tester, reloj.add(const Duration(days: 10)));
    expect(_aviso, findsOneWidget);

    await drive.repo.desconectar(usuarioId);
    container.invalidate(estadoRespaldoDriveProvider);
    await tester.pumpAndSettle();

    expect(_aviso, findsNothing);
  });

  testWidgets('desconectó y reconectó hace 2 días: la cuenta empieza de nuevo', (tester) async {
    await preparar();
    await drive.repo.conectar(usuarioId);
    await drive.repo.desconectar(usuarioId);
    reloj = reloj.add(const Duration(days: 8));
    await drive.repo.conectar(usuarioId);

    await abrirHoy(tester, reloj.add(const Duration(days: 2)));

    expect(_aviso, findsNothing, reason: 'reconectó hace 2 días, no hace 10');
  });

  testWidgets('Escenario: cuenta conectada antes de que se anotara la fecha — cuenta desde hoy', (
    tester,
  ) async {
    await preparar();
    await drive.repo.conectar(usuarioId);
    // Como la dejó la versión anterior: sin `conectado_en`.
    final crudo = (await drive.almacen.leer(ClaveSegura.respaldoDrive))!;
    final sinFecha = crudo.replaceAll(RegExp(r',"conectado_en":"[^"]*"'), '');
    expect(sinFecha, isNot(contains('conectado_en')));
    await drive.almacen.escribir(ClaveSegura.respaldoDrive, sinFecha);

    // Primer día con la versión nueva: no hay desde cuándo contar → no avisa.
    await abrirHoy(tester, reloj);
    expect(_aviso, findsNothing);

    // Ocho días después, sin un solo respaldo: ahora sí, contando desde aquella primera lectura.
    await abrirHoy(tester, reloj.add(const Duration(days: 8)));
    expect(
      find.text('Llevás 8 días sin respaldo. Revisá tu conexión y reintentá.'),
      findsOneWidget,
    );
  });

  testWidgets('mientras carga el último respaldo no cuenta desde la conexión (aviso falso)', (
    tester,
  ) async {
    await preparar(ultimoCargando: true);
    await drive.repo.conectar(usuarioId);

    await abrirHoy(tester, reloj.add(const Duration(days: 30)));

    expect(
      _aviso,
      findsNothing,
      reason: 'quien respaldó ayer no ve «Llevás 30 días» mientras carga',
    );
  });

  testWidgets('«Reintentar» con éxito: llega el respaldo y el aviso se va', (tester) async {
    await preparar();
    await drive.repo.conectar(usuarioId);
    await abrirHoy(tester, reloj.add(const Duration(days: 10)));

    await tester.tap(find.byKey(const Key('aviso_drive_accion')));
    await tester.pumpAndSettle();
    expect(servicio.pedidos, 1);

    ultimo.add(reloj.add(const Duration(days: 10)));
    await tester.pumpAndSettle();

    expect(_aviso, findsNothing);
  });

  testWidgets(
    '«Reintentar» que no sale: el aviso sigue, con su salida, y se puede volver a tocar',
    (tester) async {
      await preparar();
      servicio.resultado = const RespaldoOmitido(MotivoOmision.sinConexion);
      await drive.repo.conectar(usuarioId);
      await abrirHoy(tester, reloj.add(const Duration(days: 10)));

      await tester.tap(find.byKey(const Key('aviso_drive_accion')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Necesitás conexión'), findsOneWidget);

      await tester.tap(find.byKey(const Key('aviso_drive_accion')));
      await tester.pumpAndSettle();
      expect(servicio.pedidos, 2, reason: 'el botón no queda apagado después de una falla');
    },
  );

  testWidgets('el almacén seguro no se deja leer: no avisa (no se afirma lo que no se sabe)', (
    tester,
  ) async {
    await preparar();
    await drive.repo.conectar(usuarioId);
    drive.almacen.alLeer = true;

    await abrirHoy(tester, reloj.add(const Duration(days: 30)));

    expect(_aviso, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
