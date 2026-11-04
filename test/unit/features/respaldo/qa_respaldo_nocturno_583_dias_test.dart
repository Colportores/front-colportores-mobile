// QA de #583 (PR #624), P6 — «días sin respaldo desde que se conectó Drive»: la fecha de conexión en el
// almacén seguro (`conectado_en`) y la cuenta de `diasSinRespaldo`. Más la ventana de las 03:00 con
// cambios de hora (se corre también con `TZ=Europe/Madrid`, `TZ=America/Santiago`…).
import 'dart:convert';

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/features/respaldo/data/services/servicio_google.dart'
    show CuentaGoogle;
import 'package:colportores_mobile/features/respaldo/domain/entities/estado_respaldo_drive.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/ventana_nocturna.dart';
import 'package:colportores_mobile/features/respaldo/presentation/providers/respaldo_automatico_providers.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/respaldo_drive_falsos.dart';

void main() {
  late DateTime reloj;
  late RespaldoDriveArmado d;

  setUp(() {
    reloj = DateTime.utc(2026, 10, 20, 15);
    d = RespaldoDriveArmado(ahora: () => reloj);
  });

  Future<DateTime?> desde([String usuario = 'u-1']) => d.repo.conectadaDesde(usuario);

  /// Una cuenta de una versión que no anotaba la fecha de conexión.
  Future<void> cuentaVieja(String usuario, {String estado = 'conectada'}) => d.almacen.escribir(
    ClaveSegura.respaldoDrive,
    jsonEncode({
      usuario: {'email': 'ana@example.com', 'id': 'g-1', 'estado': estado},
    }),
  );

  group('conectadaDesde — la fecha de conexión', () {
    test('sin cuenta no hay fecha', () async {
      expect(await desde(), isNull);
    });

    test('al conectar queda la hora de ese momento, en UTC', () async {
      await d.repo.conectar('u-1');

      final fecha = await desde();

      expect(fecha, reloj);
      expect(fecha!.isUtc, isTrue);
    });

    test('leerla muchas veces no la corre', () async {
      await d.repo.conectar('u-1');
      reloj = reloj.add(const Duration(days: 9));

      expect(await desde(), DateTime.utc(2026, 10, 20, 15));
      expect(await desde(), DateTime.utc(2026, 10, 20, 15));
    });

    test(
      'sigue siendo la misma si el permiso se revoca, se queda sin espacio o se recupera',
      () async {
        await d.repo.conectar('u-1');
        final original = await desde();
        reloj = reloj.add(const Duration(days: 3));

        await d.repo.marcarSinEspacio('u-1');
        expect(await desde(), original, reason: 'sin espacio');
        await d.repo.marcarRespaldoGuardado('u-1');
        expect(await desde(), original, reason: 'volvió a guardar');
        await d.repo.marcarPermisoRevocado('u-1');
        expect(await desde(), original, reason: 'permiso revocado');
      },
    );

    test('verificar el permiso con Google caído no la toca', () async {
      await d.repo.conectar('u-1');
      d.google.errorAlPedirToken = StateError('sin red');
      reloj = reloj.add(const Duration(days: 2));

      await d.repo.verificarPermiso('u-1');

      expect(await desde(), DateTime.utc(2026, 10, 20, 15));
    });

    test('desconectar la borra y volver a conectar anota la nueva', () async {
      await d.repo.conectar('u-1');
      await d.repo.desconectar('u-1');
      expect(await desde(), isNull);

      reloj = reloj.add(const Duration(days: 12));
      await d.repo.conectar('u-1');

      expect(await desde(), DateTime.utc(2026, 11, 1, 15));
    });

    test('reconectar con otra cuenta de Google también renueva la fecha', () async {
      await d.repo.conectar('u-1');
      reloj = reloj.add(const Duration(days: 5));
      d.google.cuenta = const CuentaGoogle(id: 'g-2', email: 'otra@example.com');

      await d.repo.conectar('u-1');

      expect(await desde(), DateTime.utc(2026, 10, 25, 15));
    });

    test('dos personas en el mismo teléfono no se mezclan', () async {
      await d.repo.conectar('u-1');
      reloj = reloj.add(const Duration(days: 4));
      await d.repo.conectar('u-2');

      expect(await desde('u-1'), DateTime.utc(2026, 10, 20, 15));
      expect(await desde('u-2'), DateTime.utc(2026, 10, 24, 15));

      await d.repo.desconectar('u-2');
      expect(await desde('u-1'), DateTime.utc(2026, 10, 20, 15));
    });
  });

  group('conectadaDesde — cuentas conectadas antes de que se anotara (P2 del implementador)', () {
    test('se anota hoy la primera vez y no se corre más', () async {
      await cuentaVieja('u-1');

      expect(await desde(), reloj, reason: 'no se inventa una fecha anterior');
      reloj = reloj.add(const Duration(days: 8));
      expect(await desde(), DateTime.utc(2026, 10, 20, 15), reason: 'la de la primera lectura');
    });

    test('anotarla no cambia el estado de la cuenta', () async {
      await cuentaVieja('u-1', estado: 'sin_espacio');

      await desde();

      expect((await d.repo.estado('u-1')).fold((f) => throw f, (e) => e), isA<DriveSinEspacio>());
    });

    test('dos lecturas a la vez (con relojes distintos) devuelven la misma fecha', () async {
      await cuentaVieja('u-1');
      final primera = desde();
      reloj = reloj.add(const Duration(hours: 5));
      final segunda = desde();

      expect(await segunda, await primera);
    });

    test('una fecha ilegible se vuelve a anotar hoy y no rompe', () async {
      await d.almacen.escribir(
        ClaveSegura.respaldoDrive,
        jsonEncode({
          'u-1': {
            'email': 'ana@example.com',
            'id': 'g-1',
            'estado': 'conectada',
            'conectado_en': 'ayer a la tarde',
          },
        }),
      );

      expect(await desde(), reloj);
    });

    test('un almacén que no se deja leer da «sin fecha» y no lanza', () async {
      await d.repo.conectar('u-1');
      d.almacen.alLeer = true;

      expect(await desde(), isNull);
    });

    test('un almacén que no se deja escribir no lanza y no inventa una fecha', () async {
      await cuentaVieja('u-1');
      d.almacen.alEscribir = true;

      expect(await desde(), isNull);
    });

    test('un almacén con JSON roto da «sin fecha»', () async {
      await d.almacen.escribir(ClaveSegura.respaldoDrive, '{{{');

      expect(await desde(), isNull);
    });
  });

  group('diasSinRespaldo — la cuenta con la fecha de conexión', () {
    final ahora = DateTime.utc(2026, 11, 4, 12);

    DateTime hace(int dias, {int horas = 0, int minutos = 0}) =>
        ahora.subtract(Duration(days: dias, hours: horas, minutes: minutos));

    test('sin respaldo y conectó hace 10 días: 10 (la decisión P6)', () {
      expect(diasSinRespaldo(ultimo: null, ahora: ahora, conectadaDesde: hace(10)), 10);
    });

    test('conectó hace 7 días justos: todavía no (más de 7)', () {
      expect(diasSinRespaldo(ultimo: null, ahora: ahora, conectadaDesde: hace(7)), isNull);
    });

    test('hace 7 días y un minuto: 8 (el día en curso cuenta, como el ejemplo de la HU)', () {
      expect(diasSinRespaldo(ultimo: null, ahora: ahora, conectadaDesde: hace(7, minutos: 1)), 8);
    });

    test('con un respaldo, manda el último y no la conexión', () {
      expect(
        diasSinRespaldo(ultimo: hace(9), ahora: ahora, conectadaDesde: hace(40)),
        9,
        reason: 'el respaldo de hace 9 días es más nuevo que la conexión de hace 40',
      );
      expect(diasSinRespaldo(ultimo: hace(1), ahora: ahora, conectadaDesde: hace(40)), isNull);
    });

    test('reconectó hace 1 día pero el último respaldo es de hace 30: avisa 30', () {
      expect(
        diasSinRespaldo(ultimo: hace(30), ahora: ahora, conectadaDesde: hace(1)),
        30,
        reason: 'lleva 30 días sin respaldo aunque acabe de reconectar',
      );
    });

    test('sin ninguna de las dos fechas no se afirma nada', () {
      expect(diasSinRespaldo(ultimo: null, ahora: ahora), isNull);
    });

    test('una fecha de conexión en el futuro (reloj corrido) no avisa ni lanza', () {
      expect(
        diasSinRespaldo(
          ultimo: null,
          ahora: ahora,
          conectadaDesde: ahora.add(const Duration(days: 3)),
        ),
        isNull,
      );
    });

    test('muchísimos días: la cuenta no se rompe', () {
      expect(diasSinRespaldo(ultimo: null, ahora: ahora, conectadaDesde: hace(3650)), 3650);
    });
  });

  group('esperaHastaLaVentanaNocturna — cada hora de un año cae en una 03:00 local', () {
    // Se corre con la zona de la PC y con `TZ=…` en Docker (hay tzdata).
    test('la espera termina siempre en las 03:00 locales y dura entre 0 y 25 h', () {
      var ahora = DateTime(2026, 1, 1);
      final fin = DateTime(2027, 1, 1);
      var revisadas = 0;
      while (ahora.isBefore(fin)) {
        final espera = esperaHastaLaVentanaNocturna(ahora);
        final llega = ahora.add(espera);
        expect(espera, greaterThan(Duration.zero), reason: 'desde $ahora');
        expect(espera, lessThanOrEqualTo(const Duration(hours: 25)), reason: 'desde $ahora');
        // Un día con cambio de hora puede no tener 03:00 (el reloj salta de 02:59 a 04:00): ahí
        // llega a la primera hora que existe después.
        expect(llega.hour == 3 || llega.hour == 4, isTrue, reason: 'desde $ahora llega $llega');
        if (llega.hour == 3) expect(llega.minute, 0, reason: 'desde $ahora');
        ahora = ahora.add(const Duration(hours: 1, minutes: 7));
        revisadas++;
      }
      expect(revisadas, greaterThan(7000));
    });

    test('la misma instancia en UTC y en local da la misma espera', () {
      final local = DateTime(2026, 6, 15, 22, 30);
      expect(esperaHastaLaVentanaNocturna(local.toUtc()), esperaHastaLaVentanaNocturna(local));
    });

    test('de fin de año a año nuevo y 29 de febrero', () {
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2026, 12, 31, 23, 59)),
        const Duration(hours: 3, minutes: 1),
      );
      expect(
        esperaHastaLaVentanaNocturna(DateTime(2028, 2, 28, 23)),
        const Duration(hours: 4),
        reason: '2028 es bisiesto: la 03:00 que sigue es la del 29',
      );
    });
  });
}
