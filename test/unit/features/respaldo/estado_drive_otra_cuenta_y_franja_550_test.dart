// #550 (HU-SYNC-004) — El estado del respaldo en Drive en la app con otra cuenta de Google (16E) y la
// franja del Drive de Hoy (16F): una sola operación a la vez, nada queda trabado, la franja oculta
// vuelve mañana.
import 'dart:async';

import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart';
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_drive_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/respaldo_drive_falsos.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

Sesion _sesion(String usuarioId) => Sesion(
  usuarioId: usuarioId,
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2026, 12, 30),
);

const _otra = CuentaGoogle(id: 'g-200', email: 'ana.casa@gmail.com');

void main() {
  late RespaldoDriveArmado a;
  late PrimerRespaldoFalso primero;
  var ahora = DateTime(2026, 11, 20, 22, 30);

  ProviderContainer armar() {
    ahora = DateTime(2026, 11, 20, 22, 30);
    primero = PrimerRespaldoFalso();
    a = RespaldoDriveArmado(primerRespaldo: primero, ahora: () => ahora);
    final c = ProviderContainer(
      overrides: [
        sesionProvider.overrideWith(() => _SesionFija(_sesion('u-1'))),
        respaldoDriveRepositoryProvider.overrideWithValue(a.repo),
        relojRespaldoDriveProvider.overrideWithValue(() => ahora),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  Future<EstadoRespaldoDrive> leer(ProviderContainer c) async {
    await c.read(sesionProvider.future);
    return c.read(estadoRespaldoDriveProvider.future);
  }

  EstadoRespaldoDriveNotifier notifier(ProviderContainer c) =>
      c.read(estadoRespaldoDriveProvider.notifier);

  /// Ana tenía su respaldo en `cuentaDeAna` y ahora Google devuelve otra.
  Future<ProviderContainer> conOtraCuentaPorConfirmar() async {
    final c = armar();
    await leer(c);
    await notifier(c).conectar();
    a.google.cuenta = _otra;
    final r = await notifier(c).conectar();
    expect(r, isA<DriveQuedoEnOtraCuenta>());
    return c;
  }

  group('16E·01 Otra cuenta', () {
    test('conectar con otra cuenta devuelve las dos y deja el estado por confirmar', () async {
      final c = await conOtraCuentaPorConfirmar();

      final estado = c.read(estadoRespaldoDriveProvider).value;
      expect(
        estado,
        const DriveCuentaPorConfirmar(
          email: 'ana.casa@gmail.com',
          cuentaId: 'g-200',
          anteriorEmail: 'ana.gomez@gmail.com',
          anteriorCuentaId: 'g-100',
        ),
      );
      expect(primero.llamadas, 1, reason: 'solo el primer respaldo de la primera conexión');
    });

    test('Seguir con la nueva: conectada, con su primer respaldo', () async {
      final c = await conOtraCuentaPorConfirmar();

      final r = await notifier(c).confirmarCuentaNueva();

      expect(r, isA<DriveQuedoConectado>());
      expect((r as DriveQuedoConectado).primerRespaldoHecho, isTrue);
      final estado = c.read(estadoRespaldoDriveProvider).value;
      expect(estado, isA<DriveConectada>());
      expect((estado! as DriveConectada).cuentaId, 'g-200');
    });

    test('Volver a la anterior: conectar de nuevo con la cuenta del respaldo', () async {
      final c = await conOtraCuentaPorConfirmar();
      a.google.cuenta = cuentaDeAna;

      final r = await notifier(c).conectar();

      expect(r, isA<DriveQuedoConectado>());
      expect((c.read(estadoRespaldoDriveProvider).value! as DriveConectada).cuentaId, 'g-100');
    });

    test('doble toque en «Seguir»: una sola confirmación, la segunda dice «ocupado»', () async {
      final c = await conOtraCuentaPorConfirmar();
      primero.llamadas = 0;

      final r1 = notifier(c).confirmarCuentaNueva();
      final r2 = notifier(c).confirmarCuentaNueva();

      expect(await r2, isA<DriveOcupado>());
      expect(await r1, isA<DriveQuedoConectado>());
      expect(primero.llamadas, 1);
    });

    test('«Seguir» mientras hay una conexión en curso no se pisa', () async {
      final c = await conOtraCuentaPorConfirmar();
      final compuerta = Completer<void>();
      a.google.compuertaConectar = compuerta;
      a.google.cuenta = cuentaDeAna;

      final conectando = notifier(c).conectar();
      await Future<void>.delayed(Duration.zero);
      expect(await notifier(c).confirmarCuentaNueva(), isA<DriveOcupado>());
      compuerta.complete();

      expect(await conectando, isA<DriveQuedoConectado>());
    });

    test('si falla a mitad, nada queda trabado: se puede volver a tocar', () async {
      final c = await conOtraCuentaPorConfirmar();
      a.almacen.alEscribir = true;

      final falla = await notifier(c).confirmarCuentaNueva();
      expect(falla, isA<DriveNoQuedoConectado>());
      expect(c.read(estadoRespaldoDriveProvider).value, isA<DriveCuentaPorConfirmar>());

      a.almacen.alEscribir = false;
      expect(await notifier(c).confirmarCuentaNueva(), isA<DriveQuedoConectado>());
    });

    test('sin sesión no hace nada', () async {
      final c = ProviderContainer(
        overrides: [
          sesionProvider.overrideWith(() => _SesionFija(null)),
          respaldoDriveRepositoryProvider.overrideWithValue(RespaldoDriveArmado().repo),
        ],
      );
      addTearDown(c.dispose);
      await c.read(sesionProvider.future);
      await c.read(estadoRespaldoDriveProvider.future);

      expect(
        await c.read(estadoRespaldoDriveProvider.notifier).confirmarCuentaNueva(),
        isA<DriveOcupado>(),
      );
    });
  });

  group('16F La franja del Drive en Hoy', () {
    /// Lo que Hoy dibuja ahora, leído después de esperar a que se vuelva a leer el día oculto.
    Future<({ProblemaDeRespaldoEnHoy? franja, bool marca})> hoy(ProviderContainer c) async {
      await c.read(franjaDriveOcultaProvider.future);
      return franjaDriveEnHoy(
        estado: c.read(estadoRespaldoDriveProvider).value,
        oculta: c.read(franjaDriveOcultaProvider),
        ahora: ahora,
      );
    }

    Future<ProviderContainer> conProblema(Future<void> Function(RespaldoDriveArmado) causa) async {
      final c = armar();
      await leer(c);
      await notifier(c).conectar();
      await causa(a);
      await notifier(c).recargar();
      return c;
    }

    test('16F·01 permiso revocado: la franja sale', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));
      final lectura = await hoy(c);
      expect(lectura.franja, ProblemaDeRespaldoEnHoy.permisoRevocado);
      expect(lectura.marca, isFalse);
    });

    test('16F·02 Drive lleno: la franja sale', () async {
      final c = await conProblema((a) => a.repo.marcarSinEspacio('u-1'));
      expect((await hoy(c)).franja, ProblemaDeRespaldoEnHoy.sinEspacio);
    });

    test('sin problema (conectada, sin conectar) no hay franja ni marca', () async {
      final c = armar();
      await leer(c);
      expect(await hoy(c), (franja: null, marca: false), reason: 'sin conectar');
      await notifier(c).conectar();
      expect(await hoy(c), (franja: null, marca: false), reason: 'conectada');
    });

    test(
      'con otra cuenta por confirmar el respaldo está frenado: la franja sale (R7, 23/11)',
      () async {
        final c = armar();
        await leer(c);
        await notifier(c).conectar();
        a.google.cuenta = _otra;
        await notifier(c).conectar();

        expect(await hoy(c), (franja: ProblemaDeRespaldoEnHoy.cuentaPorConfirmar, marca: false));

        await c.read(franjaDriveOcultaProvider.notifier).ocultar();
        expect(await hoy(c), (franja: null, marca: true));
      },
    );

    test('mientras todavía lee si estaba oculta, no dibuja nada (sin parpadeo)', () {
      final lectura = franjaDriveEnHoy(
        estado: const DrivePermisoRevocado(email: 'a@x.com', cuentaId: 'g-1'),
        oculta: const AsyncLoading<DateTime?>(),
        ahora: ahora,
      );
      expect(lectura, (franja: null, marca: false));
    });

    test('16F·04 ocultar: la franja se va, el engranaje lleva la marca y sale mañana', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));

      expect(await c.read(franjaDriveOcultaProvider.notifier).ocultar(), isTrue);

      expect(await hoy(c), (franja: null, marca: true));

      // Pasa la medianoche y la app vuelve al frente: se vuelve a mirar contra el día de ahora.
      ahora = DateTime(2026, 11, 21, 7, 5);
      expect(await hoy(c), (franja: ProblemaDeRespaldoEnHoy.permisoRevocado, marca: false));
    });

    test('ocultada hoy a las 23:59 vuelve apenas pasa la medianoche', () async {
      final c = await conProblema((a) => a.repo.marcarSinEspacio('u-1'));
      ahora = DateTime(2026, 11, 20, 23, 59);
      await c.read(franjaDriveOcultaProvider.notifier).ocultar();
      expect((await hoy(c)).franja, isNull);

      ahora = DateTime(2026, 11, 21, 0, 0, 1);
      expect((await hoy(c)).franja, ProblemaDeRespaldoEnHoy.sinEspacio);
    });

    test('doble toque en «Ocultar»: una sola vez, la segunda devuelve false', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));
      final n = c.read(franjaDriveOcultaProvider.notifier);

      final r1 = n.ocultar();
      final r2 = n.ocultar();

      expect(await r2, isFalse);
      expect(await r1, isTrue);
    });

    test('si no se pudo anotar, la franja sigue y «Ocultar» no queda trabado', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));
      a.almacen.alEscribir = true;

      expect(await c.read(franjaDriveOcultaProvider.notifier).ocultar(), isFalse);
      expect((await hoy(c)).franja, ProblemaDeRespaldoEnHoy.permisoRevocado);

      a.almacen.alEscribir = false;
      expect(await c.read(franjaDriveOcultaProvider.notifier).ocultar(), isTrue);
      expect((await hoy(c)).franja, isNull);
    });

    test(
      'un cambio de estado la vuelve a mostrar el mismo día (de «sin espacio» a «revocado»)',
      () async {
        final c = await conProblema((a) => a.repo.marcarSinEspacio('u-1'));
        await c.read(franjaDriveOcultaProvider.notifier).ocultar();
        expect((await hoy(c)).franja, isNull);

        await a.repo.marcarPermisoRevocado('u-1');
        await notifier(c).recargar();

        expect((await hoy(c)).franja, ProblemaDeRespaldoEnHoy.permisoRevocado);
      },
    );

    test('resuelto el problema (reconecta) no hay ni franja ni marca', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));
      await c.read(franjaDriveOcultaProvider.notifier).ocultar();
      expect((await hoy(c)).marca, isTrue);

      await notifier(c).conectar();

      expect(await hoy(c), (franja: null, marca: false));
    });

    test('resuelto y vuelve a fallar el mismo día: la franja ya no está oculta', () async {
      final c = await conProblema((a) => a.repo.marcarPermisoRevocado('u-1'));
      await c.read(franjaDriveOcultaProvider.notifier).ocultar();
      await notifier(c).conectar();

      await notifier(c).permisoRevocado();

      expect((await hoy(c)).franja, ProblemaDeRespaldoEnHoy.permisoRevocado);
    });
  });
}
