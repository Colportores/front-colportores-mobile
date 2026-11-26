// HU-NOT-004 / #516: el estado de la sección AVISOS: leer, cambiar de a uno o de a varios, fallar sin
// perder nada y sincronizar en silencio la copia de «Recordatorios de agenda».
import 'dart:async';

import 'package:colportores_mobile/features/notificaciones/data/repositories/avisos_del_servidor_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/data/repositories/preferencias_recordatorios_repository_impl.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/avisos_del_servidor_providers.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/preferencias_recordatorios_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

({
  ProviderContainer c,
  AvisosDelServidorEnMemoria servidor,
  PreferenciasRecordatoriosRepositoryEnMemoria telefono,
})
_armar({
  AvisosDelServidor? avisos,
  bool recordatoriosActivados = true,
  bool miraPreferencias = false,
  Completer<void>? lecturaDemorada,
}) {
  final servidor = AvisosDelServidorEnMemoria(avisos: avisos ?? const AvisosDelServidor())
    ..lecturaDemorada = lecturaDemorada;
  final telefono = PreferenciasRecordatoriosRepositoryEnMemoria(
    preferencias: PreferenciasRecordatorios(activados: recordatoriosActivados),
  );
  final c = ProviderContainer(
    overrides: [
      avisosDelServidorRepositoryProvider.overrideWithValue(servidor),
      preferenciasRecordatoriosRepositoryProvider.overrideWithValue(telefono),
    ],
  );
  addTearDown(c.dispose);
  // La pantalla lo mira: sin oyente el `autoDispose` lo soltaría.
  c.listen(avisosDelServidorProvider, (_, _) {});
  // La pantalla también mira las preferencias del teléfono (sin oyente se sueltan).
  if (miraPreferencias) c.listen(preferenciasRecordatoriosProvider, (_, _) {});
  return (c: c, servidor: servidor, telefono: telefono);
}

Future<EstadoAvisosDelServidor> _listo(ProviderContainer c) =>
    c.read(avisosDelServidorProvider.future);

Future<void> _esperar() => Future<void>.delayed(Duration.zero);

void main() {
  group('leer', () {
    test('muestra lo que hay en el servidor', () async {
      final t = _armar(
        avisos: const AvisosDelServidor(cuotas: false, horaCuota: HoraDelAviso(7, 0)),
      );
      final estado = await _listo(t.c);
      expect(estado.avisos.cuotas, isFalse);
      expect(estado.avisos.horaCuota, const HoraDelAviso(7, 0));
      expect(estado.falla, isNull);
    });

    test('si no se puede leer queda en error (y no se guarda nada)', () async {
      final t = _armar()..servidor.fallaAlLeer = const AvisosServidorException();
      await expectLater(_listo(t.c), throwsA(isA<AvisosServidorException>()));
      expect(t.c.read(avisosDelServidorProvider).hasError, isTrue);
      expect(
        await t.c.read(avisosDelServidorProvider.notifier).cambiarPedidos(activado: false),
        isFalse,
      );
      expect(
        t.servidor.guardados,
        isEmpty,
        reason: 'sin leer, reescribir el objeto borraría lo que no se ve',
      );
    });

    test('un cambio mientras todavía carga no hace nada', () async {
      final t = _armar();
      t.servidor.lecturaDemorada = Completer<void>();
      t.c.invalidate(avisosDelServidorProvider);
      t.c.listen(avisosDelServidorProvider, (_, _) {});
      expect(
        await t.c.read(avisosDelServidorProvider.notifier).cambiarTickets(activado: false),
        isFalse,
      );
      t.servidor.lecturaDemorada!.complete();
      await _listo(t.c);
      expect(t.servidor.guardados, isEmpty);
    });
  });

  group('cambiar', () {
    test('un interruptor se ve enseguida y se guarda el objeto entero', () async {
      final t = _armar(avisos: const AvisosDelServidor(otras: {'x': 1}));
      await _listo(t.c);
      final futuro = t.c.read(avisosDelServidorProvider.notifier).cambiarPedidos(activado: false);
      expect(
        t.c.read(avisosDelServidorProvider).value!.avisos.pedidos,
        isFalse,
        reason: 'optimista',
      );
      expect(await futuro, isTrue);
      expect(t.servidor.guardados.single, {
        'x': 1,
        'pedidos': false,
        'tickets': true,
        'cuotas': true,
        'asignaciones': true,
        'agenda': true,
        'hora_cuota': '09:00',
        'hora_agenda': '20:00',
      });
      expect(t.c.read(avisosDelServidorProvider).value!.falla, isNull);
    });

    test('cada aviso y cada hora cambia solo lo suyo', () async {
      final t = _armar();
      await _listo(t.c);
      final n = t.c.read(avisosDelServidorProvider.notifier);
      await n.cambiarTickets(activado: false);
      await n.cambiarCuotas(activado: false);
      await n.cambiarAsignaciones(activado: false);
      await n.cambiarHoraCuota(const HoraDelAviso(6, 45));
      await n.cambiarHoraAgenda(const HoraDelAviso(22, 0));
      expect(
        t.servidor.avisos,
        const AvisosDelServidor(
          tickets: false,
          cuotas: false,
          asignaciones: false,
          horaCuota: HoraDelAviso(6, 45),
          horaAgenda: HoraDelAviso(22, 0),
        ),
      );
    });

    test('pedir lo que ya está no manda nada', () async {
      final t = _armar();
      await _listo(t.c);
      expect(
        await t.c.read(avisosDelServidorProvider.notifier).cambiarPedidos(activado: true),
        isFalse,
      );
      expect(t.servidor.guardados, isEmpty);
    });

    test(
      'dos cambios seguidos mientras se guarda: se guardan los dos, de a uno y en orden',
      () async {
        final t = _armar();
        await _listo(t.c);
        final demora = Completer<void>();
        t.servidor.guardadoDemorado = demora;
        final n = t.c.read(avisosDelServidorProvider.notifier);
        final a = n.cambiarPedidos(activado: false);
        final b = n.cambiarHoraCuota(const HoraDelAviso(8, 0));
        await _esperar();
        expect(t.c.read(avisosDelServidorProvider).value!.avisos.pedidos, isFalse);
        expect(
          t.c.read(avisosDelServidorProvider).value!.avisos.horaCuota,
          const HoraDelAviso(8, 0),
        );
        t.servidor.guardadoDemorado = null;
        demora.complete();
        expect(await Future.wait([a, b]), [true, true]);
        expect(t.servidor.avisos.pedidos, isFalse);
        expect(t.servidor.avisos.horaCuota, const HoraDelAviso(8, 0));
        expect(t.servidor.guardados.last['pedidos'], isFalse);
        expect(t.servidor.guardados.last['hora_cuota'], '08:00');
      },
    );

    test('un cambio y su contrario mientras se guarda: queda como estaba', () async {
      final t = _armar();
      await _listo(t.c);
      final demora = Completer<void>();
      t.servidor.guardadoDemorado = demora;
      final n = t.c.read(avisosDelServidorProvider.notifier);
      unawaited(n.cambiarTickets(activado: false));
      final volver = n.cambiarTickets(activado: true);
      await _esperar();
      t.servidor.guardadoDemorado = null;
      demora.complete();
      await volver;
      expect(t.servidor.avisos.tickets, isTrue);
      expect(t.c.read(avisosDelServidorProvider).value!.avisos.tickets, isTrue);
    });
  });

  group('cuando no se puede guardar', () {
    test('vuelve a como estaba y dice qué se quiso', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      final n = t.c.read(avisosDelServidorProvider.notifier);
      expect(await n.cambiarCuotas(activado: false), isFalse);
      final estado = t.c.read(avisosDelServidorProvider).value!;
      expect(estado.avisos.cuotas, isTrue);
      expect(estado.falla!.cuotas, isFalse);
      expect(estado.fallo, FalloDeAvisos.servidor);
    });

    test('con un código de la falla es el mismo fallo', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException(codigo: '23514');
      await t.c.read(avisosDelServidorProvider.notifier).cambiarTickets(activado: false);
      expect(t.c.read(avisosDelServidorProvider).value!.fallo, FalloDeAvisos.servidor);
    });

    test('«Reintentar» repite lo pedido (con todo lo que se juntó) y limpia la falla', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      final demora = Completer<void>();
      t.servidor.guardadoDemorado = demora;
      final n = t.c.read(avisosDelServidorProvider.notifier);
      final a = n.cambiarPedidos(activado: false);
      final b = n.cambiarHoraAgenda(const HoraDelAviso(21, 0));
      await _esperar();
      t.servidor.guardadoDemorado = null;
      demora.complete();
      await Future.wait([a, b]);
      expect(t.c.read(avisosDelServidorProvider).value!.falla!.pedidos, isFalse);
      expect(
        t.c.read(avisosDelServidorProvider).value!.falla!.horaAgenda,
        const HoraDelAviso(21, 0),
      );

      t.servidor.fallaAlGuardar = null;
      expect(await n.reintentar(), isTrue);
      expect(t.servidor.avisos.pedidos, isFalse);
      expect(t.servidor.avisos.horaAgenda, const HoraDelAviso(21, 0));
      expect(t.c.read(avisosDelServidorProvider).value!.falla, isNull);
    });

    test('«Reintentar» sin nada que reintentar no hace nada', () async {
      final t = _armar();
      await _listo(t.c);
      expect(await t.c.read(avisosDelServidorProvider.notifier).reintentar(), isFalse);
      expect(t.servidor.guardados, isEmpty);
    });

    test('un nuevo cambio después de la falla la limpia y se guarda', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      final n = t.c.read(avisosDelServidorProvider.notifier);
      await n.cambiarTickets(activado: false);
      t.servidor.fallaAlGuardar = null;
      await n.cambiarAsignaciones(activado: false);
      final estado = t.c.read(avisosDelServidorProvider).value!;
      expect(estado.falla, isNull);
      expect(estado.avisos.tickets, isTrue, reason: 'el que falló no se arrastra');
      expect(t.servidor.avisos.asignaciones, isFalse);
      expect(t.servidor.avisos.tickets, isTrue);
    });

    test('una falla que no es del servidor ni de la red igual vuelve todo a como estaba', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      await t.c.read(avisosDelServidorProvider.notifier).cambiarPedidos(activado: false);
      expect(t.c.read(avisosDelServidorProvider).value!.avisos.pedidos, isTrue);
    });
  });

  group('«Recordatorios de agenda»: la copia del servidor', () {
    test('al abrir, si el teléfono lo tiene apagado y el servidor no, el teléfono manda', () async {
      final t = _armar(recordatoriosActivados: false);
      await _listo(t.c);
      await _esperar();
      await _esperar();
      expect(t.servidor.avisos.agenda, isFalse);
      expect(t.servidor.guardados, hasLength(1));
    });

    test('al abrir, si coinciden no se manda nada', () async {
      final t = _armar();
      await _listo(t.c);
      await _esperar();
      expect(t.servidor.guardados, isEmpty);
    });

    test('al abrir, si el teléfono no se puede leer, no se toca el servidor', () async {
      final t = _armar(recordatoriosActivados: false)..telefono.fallaAlLeer = true;
      await _listo(t.c);
      await _esperar();
      expect(t.servidor.guardados, isEmpty);
    });

    test('cambiar el interruptor del teléfono lo sincroniza', () async {
      final t = _armar();
      await _listo(t.c);
      expect(
        await t.c.read(avisosDelServidorProvider.notifier).sincronizarAgenda(activados: false),
        isTrue,
      );
      expect(t.servidor.avisos.agenda, isFalse);
    });

    test(
      'cambiarRecordatoriosDeAgenda guarda en el teléfono y corrige la copia del servidor',
      () async {
        final t = _armar(miraPreferencias: true);
        await t.c.read(preferenciasRecordatoriosProvider.future);
        await _listo(t.c);

        await t.c
            .read(avisosDelServidorProvider.notifier)
            .cambiarRecordatoriosDeAgenda(activados: false);

        expect(t.telefono.preferencias.activados, isFalse);
        expect(t.servidor.avisos.agenda, isFalse);
      },
    );

    test(
      'si la pantalla se cierra mientras el teléfono guarda, la copia se corrige igual',
      () async {
        final servidor = AvisosDelServidorEnMemoria();
        final telefono = PreferenciasRecordatoriosRepositoryEnMemoria();
        final c = ProviderContainer(
          overrides: [
            avisosDelServidorRepositoryProvider.overrideWithValue(servidor),
            preferenciasRecordatoriosRepositoryProvider.overrideWithValue(telefono),
          ],
        );
        addTearDown(c.dispose);
        final pantalla = c.listen(avisosDelServidorProvider, (_, _) {});
        await _listo(c);
        // La pantalla también mira las preferencias del teléfono.
        final preferencias = c.listen(preferenciasRecordatoriosProvider, (_, _) {});
        await c.read(preferenciasRecordatoriosProvider.future);
        final demora = Completer<void>();
        telefono.guardadoDemorado = demora;

        final terminado = c
            .read(avisosDelServidorProvider.notifier)
            .cambiarRecordatoriosDeAgenda(activados: false);
        await _esperar();
        // Sale de la pantalla: nadie mira nada.
        pantalla.close();
        preferencias.close();
        await _esperar();
        telefono.guardadoDemorado = null;
        demora.complete();
        await terminado;

        expect(telefono.preferencias.activados, isFalse);
        expect(servidor.avisos.agenda, isFalse);
      },
    );

    test('si el teléfono no puede guardar, la copia queda con lo que el teléfono tiene', () async {
      final t = _armar(miraPreferencias: true);
      await t.c.read(preferenciasRecordatoriosProvider.future);
      await _listo(t.c);
      t.telefono.fallaAlGuardar = true;

      await t.c
          .read(avisosDelServidorProvider.notifier)
          .cambiarRecordatoriosDeAgenda(activados: false);

      expect(t.telefono.preferencias.activados, isTrue);
      expect(t.servidor.avisos.agenda, isTrue);
    });

    test(
      'antes de haber leído el servidor no hay copia que corregir: al leerlo se alinea',
      () async {
        final lectura = Completer<void>();
        final t = _armar(miraPreferencias: true, lecturaDemorada: lectura);
        await t.c.read(preferenciasRecordatoriosProvider.future);
        final n = t.c.read(avisosDelServidorProvider.notifier);

        await n.cambiarRecordatoriosDeAgenda(activados: false);
        expect(t.telefono.preferencias.activados, isFalse);
        expect(t.servidor.guardados, isEmpty);

        lectura.complete();
        await _listo(t.c);
        await _esperar();
        expect(t.servidor.avisos.agenda, isFalse);
      },
    );

    test('sin conexión no se le dice nada a la colportora y queda para la próxima vez', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      final n = t.c.read(avisosDelServidorProvider.notifier);
      expect(await n.sincronizarAgenda(activados: false), isFalse);
      final estado = t.c.read(avisosDelServidorProvider).value!;
      expect(
        estado.falla,
        isNull,
        reason: 'no hay aviso de error: lo suyo ya quedó en el teléfono',
      );
      expect(estado.fallo, isNull);
      expect(estado.avisos.agenda, isTrue);
    });

    test('si junto con la copia se pidió otro cambio y falla, sí se avisa', () async {
      final t = _armar();
      await _listo(t.c);
      t.servidor.fallaAlGuardar = const AvisosServidorException();
      final demora = Completer<void>();
      t.servidor.guardadoDemorado = demora;
      final n = t.c.read(avisosDelServidorProvider.notifier);
      final a = n.sincronizarAgenda(activados: false);
      final b = n.cambiarPedidos(activado: false);
      await _esperar();
      t.servidor.guardadoDemorado = null;
      demora.complete();
      await Future.wait([a, b]);
      expect(t.c.read(avisosDelServidorProvider).value!.falla, isNotNull);
    });

    test('guardar otro aviso lleva el valor de la agenda que ya tenía', () async {
      final t = _armar(
        avisos: const AvisosDelServidor(agenda: false),
        recordatoriosActivados: false,
      );
      await _listo(t.c);
      await _esperar();
      await t.c.read(avisosDelServidorProvider.notifier).cambiarTickets(activado: false);
      expect(t.servidor.avisos.agenda, isFalse);
    });
  });
}
