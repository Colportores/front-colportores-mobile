// HU-NOT-004 / #516 — Configuración › Notificaciones, sección AVISOS (vista 24, 24B·01 con la hora de
// Cuotas y del aviso de la agenda, decisiones del 04/11): todos los estados del grupo B y sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/avisos_del_servidor.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/avisos_del_servidor_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

final _pedidos = find.byKey(const Key('aviso_pedidos_interruptor'));
final _tickets = find.byKey(const Key('aviso_tickets_interruptor'));
final _cuotas = find.byKey(const Key('aviso_cuotas_interruptor'));
final _asignaciones = find.byKey(const Key('aviso_asignaciones_interruptor'));
final _horaCuota = find.byKey(const Key('aviso_cuotas_hora'));
final _horaCuotaValor = find.byKey(const Key('aviso_cuotas_hora_valor'));
final _horaAgenda = find.byKey(const Key('aviso_agenda_hora'));
final _horaAgendaValor = find.byKey(const Key('aviso_agenda_hora_valor'));
final _recordatorios = find.byKey(const Key('pref_recordatorios_interruptor'));
final _errorGuardar = find.byKey(const Key('avisos_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('avisos_error_reintentar'));
final _errorLeer = find.byKey(const Key('avisos_error_leer'));
final _reintentarLeer = find.byKey(const Key('avisos_reintentar_leer'));
final _cargando = find.byKey(const Key('avisos_cargando'));

const _textoError = 'No pudimos guardar el cambio. El interruptor volvió a como estaba.';
const _textoErrorHora = 'No pudimos guardar la hora. Volvió a como estaba.';
const _textoErrorVarios = 'No pudimos guardar los cambios. Volvieron a como estaban.';
const _textoSinConexion =
    'Sin conexión: no pudimos guardar el cambio. Volvió a como estaba. Probá de nuevo cuando '
    'tengas conexión.';

Telefono _activado() => Telefono(estado: EstadoSistemaNotificaciones.activadas);

bool _prendido(WidgetTester tester, Finder f) => tester.widget<SwitchListTile>(f).value;

/// Toca [f] después de traerlo a la vista (la pantalla es más alta que el teléfono).
Future<void> _tocar(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

Future<void> _abrir(WidgetTester tester, Telefono telefono) =>
    abrirPantalla(tester, telefono, const NotificacionesPage());

/// Elige [hora]:[minuto] en el selector del sistema (escribiéndola) y confirma.
Future<void> _elegirHora(WidgetTester tester, int hora, int minuto) async {
  await tester.tap(find.byIcon(Icons.keyboard_outlined));
  await tester.pumpAndSettle();
  final campos = find.byType(TextField);
  await tester.enterText(campos.at(0), '$hora');
  await tester.enterText(campos.at(1), '$minuto');
  await tester.pump();
  await tester.tap(find.text('OK'));
  await tester.pumpAndSettle();
}

void main() {
  group('24B·01 · Preferencias con la sección AVISOS', () {
    testWidgets('muestra los cuatro avisos prendidos, sin «Promociones», y las horas de siempre', (
      tester,
    ) async {
      await _abrir(tester, _activado());

      expect(find.text('AVISOS'), findsOneWidget);
      for (final t in ['Pedidos', 'Tickets', 'Cuotas', 'Asignaciones']) {
        expect(find.text(t), findsOneWidget, reason: t);
      }
      expect(find.text('Zona y campaña'), findsOneWidget);
      expect(find.text('Promociones'), findsNothing, reason: 'decisión de Cristian, 04/11');
      for (final f in [_pedidos, _tickets, _cuotas, _asignaciones]) {
        expect(_prendido(tester, f), isTrue);
      }
      expect(find.text('Hora del aviso'), findsOneWidget);
      expect(tester.widget<Text>(_horaCuotaValor).data, '09:00');
      expect(find.text('Aviso de las visitas de mañana'), findsOneWidget);
      expect(tester.widget<Text>(_horaAgendaValor).data, '20:00');
      expect(_errorGuardar, findsNothing);
      expect(_errorLeer, findsNothing);
      expect(_cargando, findsNothing);
    });

    testWidgets('lo guardado en el servidor se ve al entrar', (tester) async {
      final telefono = _activado();
      telefono.avisos.avisos = const AvisosDelServidor(
        pedidos: false,
        cuotas: false,
        horaCuota: HoraDelAviso(7, 30),
        horaAgenda: HoraDelAviso(21, 15),
      );

      await _abrir(tester, telefono);

      expect(_prendido(tester, _pedidos), isFalse);
      expect(_prendido(tester, _tickets), isTrue);
      expect(_prendido(tester, _cuotas), isFalse);
      expect(tester.widget<Text>(_horaCuotaValor).data, '07:30');
      expect(tester.widget<Text>(_horaAgendaValor).data, '21:15');
    });

    testWidgets('apagar un aviso lo guarda en el servidor con el objeto entero', (tester) async {
      final telefono = _activado();
      telefono.avisos.avisos = const AvisosDelServidor(otras: {'futuro': 1});
      await _abrir(tester, telefono);

      await _tocar(tester, _tickets);
      await tester.pumpAndSettle();

      expect(_prendido(tester, _tickets), isFalse);
      expect(telefono.avisos.guardados.single, {
        'futuro': 1,
        'pedidos': true,
        'tickets': false,
        'cuotas': true,
        'asignaciones': true,
        'agenda': true,
        'hora_cuota': '09:00',
        'hora_agenda': '20:00',
      });
      expect(_errorGuardar, findsNothing);
    });

    testWidgets('prender de nuevo lo que estaba apagado también se guarda', (tester) async {
      final telefono = _activado();
      telefono.avisos.avisos = const AvisosDelServidor(asignaciones: false);
      await _abrir(tester, telefono);

      await _tocar(tester, _asignaciones);
      await tester.pumpAndSettle();

      expect(telefono.avisos.avisos.asignaciones, isTrue);
    });

    testWidgets('el lector de pantalla anuncia cada aviso como un interruptor con su estado', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _activado());
      for (final (nombre, clave) in [
        ('Pedidos', _pedidos),
        ('Tickets', _tickets),
        ('Cuotas', _cuotas),
        ('Asignaciones\nZona y campaña', _asignaciones),
      ]) {
        await tester.ensureVisible(clave);
        await tester.pump();
        expect(
          tester.getSemantics(clave),
          isSemantics(
            label: nombre,
            hasToggledState: true,
            isToggled: true,
            hasEnabledState: true,
            isEnabled: true,
            hasTapAction: true,
            isFocusable: true,
          ),
          reason: nombre,
        );
      }
      semantica.dispose();
    });
  });

  group('La hora de los avisos (decisión «Hora avisos»)', () {
    testWidgets('elegir la hora de Cuotas la guarda en «HH:MM»', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      await _elegirHora(tester, 7, 5);

      expect(tester.widget<Text>(_horaCuotaValor).data, '07:05');
      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(7, 5));
      expect(telefono.avisos.guardados.last['hora_cuota'], '07:05');
      expect(_errorGuardar, findsNothing);
    });

    testWidgets('elegir la hora del aviso de la agenda la guarda', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _horaAgenda);
      await tester.pumpAndSettle();
      await _elegirHora(tester, 22, 30);

      expect(tester.widget<Text>(_horaAgendaValor).data, '22:30');
      expect(telefono.avisos.guardados.last['hora_agenda'], '22:30');
    });

    testWidgets('el selector abre en la hora de hoy y cerrarlo sin elegir no cambia nada', (
      tester,
    ) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(telefono.avisos.guardados, isEmpty);
      expect(tester.widget<Text>(_horaCuotaValor).data, '09:00');
    });

    testWidgets('confirmar la misma hora no guarda nada', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(telefono.avisos.guardados, isEmpty);
    });

    testWidgets('doble toque en el mismo cuadro: nunca dos selectores', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await tester.ensureVisible(_horaCuota);
      await tester.pump();
      await tester.tap(_horaCuota);
      await tester.tap(_horaCuota, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(TimePickerDialog).evaluate().length, lessThanOrEqualTo(1));
      expect(telefono.avisos.guardados, isEmpty);
    });

    testWidgets('con Cuotas apagado la hora queda a la vista y sin tocar', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _cuotas);
      await tester.pumpAndSettle();
      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(tester.widget<Text>(_horaCuotaValor).data, '09:00');
      expect(telefono.avisos.avisos.cuotas, isFalse);
      // Al prender Cuotas de nuevo, la hora vuelve a poder cambiarse.
      await _tocar(tester, _cuotas);
      await tester.pumpAndSettle();
      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
    });

    testWidgets('con los recordatorios de agenda apagados, la hora de la agenda queda sin tocar', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = telefono.preferencias.preferencias.copyWith(
        activados: false,
      );
      await _abrir(tester, telefono);

      await _tocar(tester, _horaAgenda);
      await tester.pumpAndSettle();

      expect(find.byType(TimePickerDialog), findsNothing);
      expect(tester.widget<Text>(_horaAgendaValor).data, '20:00');
    });

    testWidgets('el lector de pantalla la anuncia como un botón con su hora', (tester) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _activado());

      await tester.ensureVisible(_horaCuota);
      await tester.pump();
      expect(
        tester.getSemantics(_horaCuota),
        isSemantics(
          label: 'Hora del aviso',
          value: '09:00',
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });

    testWidgets('no se pierde ninguna de dos horas cambiadas una tras otra', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      final demora = Completer<void>();
      telefono.avisos.guardadoDemorado = demora;

      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      await _elegirHora(tester, 8, 0);
      await _tocar(tester, _horaAgenda);
      await tester.pumpAndSettle();
      await _elegirHora(tester, 21, 0);
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(telefono.avisos.avisos.horaCuota, const HoraDelAviso(8, 0));
      expect(telefono.avisos.avisos.horaAgenda, const HoraDelAviso(21, 0));
    });
  });

  group('«Recordatorios de agenda» y la copia del servidor', () {
    testWidgets('apagar el interruptor del teléfono avisa al servidor, en silencio', (
      tester,
    ) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await _tocar(tester, _recordatorios);
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.activados, isFalse);
      expect(telefono.avisos.avisos.agenda, isFalse);
      expect(_errorGuardar, findsNothing);
    });

    testWidgets('sin conexión el interruptor del teléfono igual se apaga y no sale ningún error', (
      tester,
    ) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      telefono.avisos.fallaAlGuardar = const AvisosSinConexionException();

      await _tocar(tester, _recordatorios);
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.activados, isFalse);
      expect(tester.widget<SwitchListTile>(_recordatorios).value, isFalse);
      expect(_errorGuardar, findsNothing);
    });

    testWidgets('al abrir, el teléfono apagado y el servidor no: se alinea el servidor', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = telefono.preferencias.preferencias.copyWith(
        activados: false,
      );

      await _abrir(tester, telefono);

      expect(telefono.avisos.avisos.agenda, isFalse);
    });
  });

  group('24B·05 · Cargando', () {
    testWidgets(
      'mientras el servidor no contesta: el cargando de AVISOS y los recordatorios a la vista',
      (tester) async {
        final telefono = _activado();
        final demora = Completer<void>();
        telefono.avisos.lecturaDemorada = demora;

        await abrirPantallaSinEsperar(tester, telefono, const NotificacionesPage());
        await tester.pump(const Duration(milliseconds: 50));

        expect(_cargando, findsOneWidget);
        expect(find.text('AVISOS'), findsOneWidget);
        expect(_pedidos, findsNothing);
        expect(_recordatorios, findsOneWidget, reason: 'lo del teléfono no espera al servidor');

        demora.complete();
        await tester.pumpAndSettle();
        expect(_cargando, findsNothing);
        expect(_pedidos, findsOneWidget);
      },
    );
  });

  group('Error al leer los avisos', () {
    testWidgets('sin conexión: lo dice, guía y deja reintentar; lo del teléfono sigue', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.avisos.fallaAlLeer = const AvisosSinConexionException();

      await _abrir(tester, telefono);

      expect(
        find.text(
          'Sin conexión: no pudimos leer tus avisos. Probá de nuevo cuando tengas conexión.',
        ),
        findsOneWidget,
      );
      expect(_pedidos, findsNothing);
      expect(_recordatorios, findsOneWidget);
      expect(_horaAgenda, findsNothing, reason: 'sin leer el servidor no se puede cambiar su hora');

      telefono.avisos.fallaAlLeer = null;
      await _tocar(tester, _reintentarLeer);
      await tester.pumpAndSettle();

      expect(_errorLeer, findsNothing);
      expect(_pedidos, findsOneWidget);
      expect(_horaAgenda, findsOneWidget);
    });

    testWidgets('el servidor con error dice que no pudo leer y deja reintentar', (tester) async {
      final telefono = _activado();
      telefono.avisos.fallaAlLeer = const AvisosServidorException(codigo: '42501');

      await _abrir(tester, telefono);

      expect(find.text('No pudimos leer tus avisos.'), findsOneWidget);
      expect(_reintentarLeer, findsOneWidget);
    });

    testWidgets('«Reintentar» dos veces seguidas con el servidor todavía caído vuelve al error', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.avisos.fallaAlLeer = const AvisosSinConexionException();
      await _abrir(tester, telefono);

      await _tocar(tester, _reintentarLeer);
      await tester.pumpAndSettle();
      await _tocar(tester, _reintentarLeer);
      await tester.pumpAndSettle();

      expect(_errorLeer, findsOneWidget);
      expect(_reintentarLeer, findsOneWidget);
    });
  });

  group('24B·06 · Error al guardar', () {
    testWidgets(
      'con el servidor en error: el interruptor vuelve a como estaba y se puede reintentar',
      (tester) async {
        final telefono = _activado();
        await _abrir(tester, telefono);
        telefono.avisos.fallaAlGuardar = const AvisosServidorException();

        await _tocar(tester, _pedidos);
        await tester.pumpAndSettle();

        expect(_prendido(tester, _pedidos), isTrue);
        expect(find.text(_textoError), findsOneWidget);

        telefono.avisos.fallaAlGuardar = null;
        await _tocar(tester, _reintentarGuardar);
        await tester.pumpAndSettle();

        expect(_errorGuardar, findsNothing);
        expect(_prendido(tester, _pedidos), isFalse);
        expect(telefono.avisos.avisos.pedidos, isFalse);
      },
    );

    testWidgets('sin conexión: lo dice y dice qué hacer', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      telefono.avisos.fallaAlGuardar = const AvisosSinConexionException();

      await _tocar(tester, _cuotas);
      await tester.pumpAndSettle();

      expect(_prendido(tester, _cuotas), isTrue);
      expect(find.text(_textoSinConexion), findsOneWidget);
    });

    testWidgets('si lo que no se guardó es una hora, el aviso habla de la hora', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();

      await _tocar(tester, _horaCuota);
      await tester.pumpAndSettle();
      await _elegirHora(tester, 7, 0);

      expect(find.text(_textoErrorHora), findsOneWidget);
      expect(tester.widget<Text>(_horaCuotaValor).data, '09:00');
    });

    testWidgets('varios cambios juntos que fallan: «Volvieron a como estaban»', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      final demora = Completer<void>();
      telefono.avisos
        ..guardadoDemorado = demora
        ..fallaAlGuardar = const AvisosServidorException();

      await _tocar(tester, _pedidos);
      await tester.pump();
      await _tocar(tester, _tickets);
      await tester.pump();
      telefono.avisos.guardadoDemorado = null;
      demora.complete();
      await tester.pumpAndSettle();

      expect(find.text(_textoErrorVarios), findsOneWidget);
      expect(_prendido(tester, _pedidos), isTrue);
      expect(_prendido(tester, _tickets), isTrue);

      telefono.avisos.fallaAlGuardar = null;
      await _tocar(tester, _reintentarGuardar);
      await tester.pumpAndSettle();
      expect(telefono.avisos.avisos.pedidos, isFalse);
      expect(telefono.avisos.avisos.tickets, isFalse);
    });

    testWidgets('tras la falla nada queda trabado: se puede volver a tocar otro interruptor', (
      tester,
    ) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await _tocar(tester, _pedidos);
      await tester.pumpAndSettle();

      telefono.avisos.fallaAlGuardar = null;
      await _tocar(tester, _asignaciones);
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsNothing, reason: 'un cambio nuevo limpia el aviso anterior');
      expect(telefono.avisos.avisos.asignaciones, isFalse);
      expect(_prendido(tester, _pedidos), isTrue);
    });

    testWidgets('el aviso de error se anuncia al lector de pantalla (región viva)', (tester) async {
      final semantica = tester.ensureSemantics();
      final telefono = _activado();
      await _abrir(tester, telefono);
      telefono.avisos.fallaAlGuardar = const AvisosServidorException();
      await _tocar(tester, _pedidos);
      await tester.pumpAndSettle();

      expect(
        tester.getSemantics(_errorGuardar),
        matchesSemantics(label: _textoError, isLiveRegion: true),
      );
      semantica.dispose();
    });
  });

  group('Casos límite', () {
    testWidgets(
      'doble toque sobre un interruptor: dos cambios, el último gana y no se pierde nada',
      (tester) async {
        final telefono = _activado();
        await _abrir(tester, telefono);
        final demora = Completer<void>();
        telefono.avisos.guardadoDemorado = demora;

        await _tocar(tester, _tickets);
        await _tocar(tester, _tickets);
        await tester.pump();
        telefono.avisos.guardadoDemorado = null;
        demora.complete();
        await tester.pumpAndSettle();

        expect(_prendido(tester, _tickets), isTrue);
        expect(telefono.avisos.avisos.tickets, isTrue);
        expect(_errorGuardar, findsNothing);
      },
    );

    testWidgets(
      'dos avisos distintos seguidos antes de que termine el primero: se guardan los dos',
      (tester) async {
        final telefono = _activado();
        await _abrir(tester, telefono);
        final demora = Completer<void>();
        telefono.avisos.guardadoDemorado = demora;

        await _tocar(tester, _pedidos);
        await tester.pump();
        await _tocar(tester, _asignaciones);
        await tester.pump();
        telefono.avisos.guardadoDemorado = null;
        demora.complete();
        await tester.pumpAndSettle();

        expect(telefono.avisos.avisos.pedidos, isFalse);
        expect(telefono.avisos.avisos.asignaciones, isFalse);
        expect(_prendido(tester, _pedidos), isFalse);
        expect(_prendido(tester, _asignaciones), isFalse);
      },
    );

    testWidgets(
      'volver atrás con un cambio guardándose y reentrar: se terminó de guardar y se ve',
      (tester) async {
        final telefono = _activado();
        await _abrir(tester, telefono);
        final demora = Completer<void>();
        telefono.avisos.guardadoDemorado = demora;
        await _tocar(tester, _pedidos);
        await tester.pump();

        await tester.pumpWidget(const SizedBox.shrink());
        telefono.avisos.guardadoDemorado = null;
        demora.complete();
        await tester.pumpAndSettle();
        expect(telefono.avisos.avisos.pedidos, isFalse, reason: 'se guardó igual');

        await _abrir(tester, telefono);
        expect(_prendido(tester, _pedidos), isFalse);
      },
    );

    testWidgets('volver atrás y reentrar vuelve a leer el servidor', (tester) async {
      final telefono = _activado();
      await _abrir(tester, telefono);
      expect(telefono.avisos.lecturas, 1);

      telefono.avisos.avisos = const AvisosDelServidor(tickets: false);
      await _abrir(tester, telefono);

      expect(telefono.avisos.lecturas, 2);
      expect(_prendido(tester, _tickets), isFalse);
    });

    for (final (nombre, tamano) in [
      ('360 × 640', const Size(360, 640)),
      ('320 × 568', const Size(320, 568)),
    ]) {
      testWidgets('texto al 200 % en $nombre: nada se corta y todo se alcanza', (tester) async {
        fijarTamano(tester, tamano: tamano, texto: 2);
        final telefono = _activado();
        telefono.avisos.avisos = const AvisosDelServidor(horaCuota: HoraDelAviso(23, 59));
        await _abrir(tester, telefono);

        expect(tester.takeException(), isNull);
        for (final f in [_pedidos, _tickets, _cuotas, _asignaciones, _horaCuota, _horaAgenda]) {
          await tester.ensureVisible(f);
          await tester.pump();
          expect(tester.takeException(), isNull);
          expect(tester.getSize(f).height, greaterThanOrEqualTo(48), reason: '$f');
        }
        await tester.ensureVisible(_horaCuotaValor);
        await tester.pump();
        expect(tester.widget<Text>(_horaCuotaValor).data, '23:59');
      });

      testWidgets('texto al 200 % en $nombre: el error de guardar se ve entero', (tester) async {
        fijarTamano(tester, tamano: tamano, texto: 2);
        final telefono = _activado();
        await _abrir(tester, telefono);
        telefono.avisos.fallaAlGuardar = const AvisosSinConexionException();

        await tester.ensureVisible(_cuotas);
        await _tocar(tester, _cuotas);
        await tester.pumpAndSettle();
        await tester.ensureVisible(_errorGuardar);
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(_textoSinConexion), findsOneWidget);
        await tester.ensureVisible(_reintentarGuardar);
        await tester.pump();
        expect(tester.getSize(_reintentarGuardar).shortestSide, greaterThanOrEqualTo(48));
      });
    }
  });

  group('24B·04 · Con el permiso del teléfono apagado', () {
    testWidgets('los avisos se ven y se pueden cambiar: valen cuando se active', (tester) async {
      final telefono = Telefono();
      await _abrir(tester, telefono);

      expect(find.text(textoApagadas), findsOneWidget);
      await _tocar(tester, _pedidos);
      await tester.pumpAndSettle();

      expect(telefono.avisos.avisos.pedidos, isFalse);
    });
  });
}
