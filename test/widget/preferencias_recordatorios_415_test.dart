// HU-NOT-004 / issue #415 — Configuración › Notificaciones, grupo B de la vista 24 (preferencias de
// los recordatorios de agenda): 24B·01 a 24B·06 con todos sus casos límite.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/permiso_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

class _SesionFija extends SesionNotifier {
  _SesionFija(this._sesion);

  final Sesion? _sesion;

  @override
  Future<Sesion?> build() async => _sesion;
}

final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _slider = find.byKey(const Key('pref_anticipacion_slider'));
final _valor = find.byKey(const Key('pref_anticipacion_valor'));
final _apagadosAviso = find.byKey(const Key('pref_apagados_aviso'));
final _errorGuardar = find.byKey(const Key('pref_error_guardar'));
final _reintentarGuardar = find.byKey(const Key('pref_error_reintentar'));
final _errorLeer = find.byKey(const Key('pref_error_leer'));
final _reintentarLeer = find.byKey(const Key('pref_reintentar_leer'));
final _toast = find.byKey(const Key('pref_anticipacion_aviso'));
final _cargando = find.byKey(const Key('notificaciones_cargando'));
final _subir = find.semantics.byAction(SemanticsAction.increase);
final _bajar = find.semantics.byAction(SemanticsAction.decrease);

const _textoApagados =
    'Dejamos de programar los recordatorios, también los de las visitas que ya agendaste.';
const _textoError = 'No pudimos guardar el cambio. El interruptor volvió a como estaba.';
const _textoErrorVarios = 'No pudimos guardar los cambios. Volvieron a como estaban.';

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'ana@example.com',
  accessToken: 'jwt',
  expiraEn: DateTime.utc(2030),
);

/// Tres visitas agendadas dentro de unos días, para tener algo que reprogramar.
void _conVisitas(Telefono telefono, [int cuantas = 3]) {
  for (var n = 1; n <= cuantas; n++) {
    telefono.agendas.agendas.add(
      RecordatorioDeVisita(
        agendaId: 'ag-$n',
        tipo: TipoAgenda.entrevista,
        direccion: 'Av. Italia 1234',
        fechaProgramada: DateTime.now().add(Duration(days: n)),
      ),
    );
  }
}

Future<void> _abrir(
  WidgetTester tester,
  Telefono telefono, {
  Key? clave,
  Sesion? sesion,
  bool esperar = true,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: clave ?? UniqueKey(),
      overrides: [
        ...telefono.overrides,
        sesionProvider.overrideWith(() => _SesionFija(sesion ?? _sesion)),
      ],
      child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Telefono _activado() => Telefono(estado: EstadoSistemaNotificaciones.activadas);

Text _texto(Finder f) => f.evaluate().single.widget as Text;

bool _switchEncendido(WidgetTester tester) => tester.widget<SwitchListTile>(_interruptor).value;

double _sliderValor(WidgetTester tester) => tester.widget<Slider>(_slider).value;

void main() {
  group('24B·01 · Preferencias', () {
    testWidgets('muestra «Recordatorios de agenda» prendido y la anticipación de 30 minutos', (
      tester,
    ) async {
      await _abrir(tester, _activado());

      expect(find.text('RECORDATORIOS'), findsOneWidget);
      expect(find.text('Recordatorios de agenda'), findsOneWidget);
      expect(find.text('Antes de cada visita agendada'), findsOneWidget);
      expect(find.text('Anticipación'), findsOneWidget);
      expect(_texto(_valor).data, '30 min antes');
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('120 min'), findsOneWidget);
      expect(_switchEncendido(tester), isTrue);
      expect(_sliderValor(tester), 30);
      expect(tester.widget<Slider>(_slider).onChanged, isNotNull);
      expect(_apagadosAviso, findsNothing);
      expect(_errorGuardar, findsNothing);
      expect(find.text(textoApagadas), findsNothing);
      // Solo lo que funciona sin la push (decisión «Notif. S8»): ni Pedidos, ni Tickets, ni Cuotas.
      for (final t in ['Pedidos', 'Tickets', 'Cuotas', 'Asignaciones', 'Promociones', 'AVISOS']) {
        expect(find.text(t), findsNothing);
      }
    });

    testWidgets('lo guardado se ve al entrar: apagado y 90 minutos', (tester) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(
        activados: false,
        anticipacionMinutos: 90,
      );

      await _abrir(tester, telefono);

      expect(_switchEncendido(tester), isFalse);
      expect(_texto(_valor).data, '90 min antes');
    });

    testWidgets('funciona sin conexión: es del teléfono y no avisa nada de eso', (tester) async {
      final telefono = _activado()..conexion.cambiarA(TipoConexion.sinConexion);
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.activados, isFalse);
      expect(_errorGuardar, findsNothing);
    });
  });

  group('24B·02 · Recordatorios apagados', () {
    testWidgets('apagar el interruptor lo guarda, dice que también se dejan los ya agendados y '
        'cancela los avisos', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono);
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_switchEncendido(tester), isFalse);
      expect(find.text(_textoApagados), findsOneWidget);
      expect(telefono.preferencias.preferencias.activados, isFalse);
      expect(telefono.recordatorios.llamadas, hasLength(3));
      expect(
        tester.widget<Slider>(_slider).onChanged,
        isNull,
        reason: 'la anticipación no se toca',
      );
      expect(_texto(_valor).data, '30 min antes');
    });

    testWidgets('volver a prenderlo saca el aviso y vuelve a habilitar la anticipación', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await _abrir(tester, telefono);
      expect(find.text(_textoApagados), findsOneWidget);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(find.text(_textoApagados), findsNothing);
      expect(_switchEncendido(tester), isTrue);
      expect(tester.widget<Slider>(_slider).onChanged, isNotNull);
      expect(telefono.preferencias.preferencias.activados, isTrue);
    });

    testWidgets('no hay toast de anticipación al apagar ni al prender', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono);
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_toast, findsNothing);
    });
  });

  group('24B·03 · Anticipación cambiada', () {
    testWidgets('subir la anticipación con el lector de pantalla (de a 5) guarda y dice a cuántos '
        'recordatorios les tocó', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono, 4);
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.anticipacionMinutos, 35);
      expect(_texto(_valor).data, '35 min antes');
      expect(find.text('Reprogramamos 4 recordatorios: te avisamos 35 min antes.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('arrastrar el control guarda al soltar, con un solo toast con los números reales', (
      tester,
    ) async {
      final telefono = _activado();
      _conVisitas(telefono);
      await _abrir(tester, telefono);

      await tester.drag(_slider, const Offset(120, 0));
      await tester.pumpAndSettle();

      final guardado = telefono.preferencias.preferencias.anticipacionMinutos;
      expect(guardado, greaterThan(30));
      expect(telefono.preferencias.guardados, ['minutos:$guardado']);
      expect(_texto(_valor).data, '$guardado min antes');
      expect(
        find.text('Reprogramamos 3 recordatorios: te avisamos $guardado min antes.'),
        findsOneWidget,
      );
    });

    testWidgets('mientras se arrastra solo se mueve lo que se ve: no se guarda hasta soltar', (
      tester,
    ) async {
      final telefono = _activado();
      _conVisitas(telefono);
      await _abrir(tester, telefono);

      final gesto = await tester.startGesture(tester.getCenter(_slider));
      await gesto.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(telefono.preferencias.guardados, isEmpty);
      expect(_texto(_valor).data, isNot('30 min antes'));

      await gesto.up();
      await tester.pumpAndSettle();
      expect(telefono.preferencias.guardados, hasLength(1));
    });

    testWidgets('con una sola visita agendada el aviso va en singular', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono, 1);
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();

      expect(find.text('Reprogramamos 1 recordatorio: te avisamos 35 min antes.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('sin visitas agendadas no hay nada que contar: «Guardado: …»', (tester) async {
      final telefono = _activado();
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();

      expect(find.text('Guardado: te avisamos 35 min antes.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('el control se lee como un control ajustable, con su valor y los pasos de 5', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester, _activado());

      final datos = _subir.evaluate().single.getSemanticsData();

      expect(datos.value, '30 min antes');
      expect(datos.increasedValue, '35 min antes');
      expect(datos.decreasedValue, '25 min antes');
      expect(datos.hasAction(SemanticsAction.increase), isTrue);
      expect(datos.hasAction(SemanticsAction.decrease), isTrue);
      semantica.dispose();
    });

    testWidgets('en el tope de 120 no se pasa, y en el piso de 5 tampoco', (tester) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(
        anticipacionMinutos: 120,
      );
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(telefono.preferencias.guardados, isEmpty);
      expect(_texto(_valor).data, '120 min antes');

      telefono.preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 5);
      await _abrir(tester, telefono);
      tester.semantics.performAction(_bajar, SemanticsAction.decrease);
      await tester.pumpAndSettle();
      expect(telefono.preferencias.guardados, isEmpty);
      expect(_texto(_valor).data, '5 min antes');
      semantica.dispose();
    });

    testWidgets('un valor guardado fuera de rango se ve acotado', (tester) async {
      final telefono = _activado();
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(
        anticipacionMinutos: 120,
      );

      await _abrir(tester, telefono);

      expect(_sliderValor(tester), 120);
      expect(tester.widget<Slider>(_slider).max, 120);
      expect(tester.widget<Slider>(_slider).min, 5);
    });
  });

  group('24B·04 · Permiso del teléfono apagado', () {
    testWidgets(
      'dice que las opciones valen cuando las active, ofrece «Activar» y deja cambiarlas',
      (tester) async {
        final telefono = Telefono(); // apagadas, sin pedir
        _conVisitas(telefono);
        await _abrir(tester, telefono);

        expect(find.text(textoApagadas), findsOneWidget);
        expect(find.text('Activar'), findsOneWidget);
        expect(_interruptor, findsOneWidget);

        await tester.tap(_interruptor);
        await tester.pumpAndSettle();

        expect(telefono.preferencias.preferencias.activados, isFalse);
        expect(find.text(_textoApagados), findsOneWidget);
      },
    );

    testWidgets('«Activar» pide el permiso y deja las preferencias como estaban', (tester) async {
      final telefono = Telefono();
      telefono.preferencias.preferencias = const PreferenciasRecordatorios(anticipacionMinutos: 60);
      await _abrir(tester, telefono);

      await tester.tap(find.byKey(const Key('notificaciones_activar')));
      await tester.pumpAndSettle();

      expect(find.text(textoApagadas), findsNothing);
      expect(_texto(_valor).data, '60 min antes');
    });

    testWidgets('con el permiso bloqueado en el teléfono, ofrece abrir los ajustes y las '
        'preferencias siguen ahí', (tester) async {
      final telefono = Telefono();
      telefono.recuerdo.pedido = PedidoNotificaciones.sistema;
      await _abrir(tester, telefono);

      expect(find.text(textoBloqueadas), findsOneWidget);
      expect(find.byKey(const Key('notificaciones_abrir_ajustes')), findsOneWidget);
      expect(_interruptor, findsOneWidget);
    });
  });

  group('24B·05 · Cargando', () {
    testWidgets('mientras se leen las preferencias se ven bloques grises y nada para tocar', (
      tester,
    ) async {
      final telefono = _activado();
      final demora = telefono.preferencias.lecturaDemorada = Completer<void>();
      await _abrir(tester, telefono, esperar: false);

      expect(_cargando, findsOneWidget);
      expect(_interruptor, findsNothing);
      expect(_slider, findsNothing);

      demora.complete();
      await tester.pumpAndSettle();
      expect(_cargando, findsNothing);
      expect(_interruptor, findsOneWidget);
    });

    testWidgets('el cargando se anuncia como «Cargando» al lector de pantalla', (tester) async {
      final semantica = tester.ensureSemantics();
      final telefono = _activado();
      telefono.preferencias.lecturaDemorada = Completer<void>();
      await _abrir(tester, telefono, esperar: false);

      expect(find.bySemanticsLabel('Cargando'), findsOneWidget);
      semantica.dispose();
    });
  });

  group('24B·06 · Error al guardar', () {
    testWidgets('si no se puede guardar, el interruptor vuelve a como estaba y lo dice con '
        '«Reintentar»', (tester) async {
      final telefono = _activado();
      telefono.preferencias.fallaAlGuardar = true;
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_switchEncendido(tester), isTrue);
      expect(find.text(_textoError), findsOneWidget);
      expect(_reintentarGuardar, findsOneWidget);
      expect(find.text(_textoApagados), findsNothing);
      expect(telefono.preferencias.preferencias.activados, isTrue);
    });

    testWidgets('«Reintentar» vuelve a pedir lo que no se pudo y, si anda, el error se va', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.fallaAlGuardar = true;
      await _abrir(tester, telefono);
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      telefono.preferencias.fallaAlGuardar = false;

      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsNothing);
      expect(_switchEncendido(tester), isFalse);
      expect(telefono.preferencias.preferencias.activados, isFalse);
    });

    testWidgets('si la anticipación no se pudo guardar, vuelve al valor de antes; al reintentar '
        'avisa cuántos se reprogramaron', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono, 2);
      telefono.preferencias.fallaAlGuardar = true;
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();
      expect(_texto(_valor).data, '30 min antes');
      expect(find.text(_textoErrorVarios), findsOneWidget);
      expect(find.text(_textoError), findsNothing);
      expect(_toast, findsNothing);

      telefono.preferencias.fallaAlGuardar = false;
      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();

      expect(_texto(_valor).data, '35 min antes');
      expect(find.text('Reprogramamos 2 recordatorios: te avisamos 35 min antes.'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('si fallan dos cambios juntos, el aviso dice que volvieron los dos y «Reintentar» '
        'repite los dos', (tester) async {
      final telefono = _activado();
      _conVisitas(telefono, 2);
      final demora = telefono.preferencias.guardadoDemorado = Completer<void>();
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono);

      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pump();
      await tester.tap(_interruptor);
      await tester.pump();
      telefono.preferencias.fallaAlGuardar = true;
      demora.complete();
      await tester.pumpAndSettle();

      expect(find.text(_textoErrorVarios), findsOneWidget);
      expect(_switchEncendido(tester), isTrue);
      expect(_texto(_valor).data, '30 min antes');

      telefono.preferencias
        ..fallaAlGuardar = false
        ..guardadoDemorado = null;
      await tester.tap(_reintentarGuardar);
      await tester.pumpAndSettle();

      expect(_errorGuardar, findsNothing);
      expect(
        telefono.preferencias.preferencias,
        const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 35),
      );
      expect(_switchEncendido(tester), isFalse);
      semantica.dispose();
    });

    testWidgets('si no se pueden reprogramar los recordatorios, también vuelve atrás', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.agendas.falla = true;
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_switchEncendido(tester), isTrue);
      expect(find.text(_textoError), findsOneWidget);
      expect(telefono.preferencias.preferencias.activados, isTrue);
    });

    testWidgets('falla a mitad: el interruptor no queda trabado y el siguiente toque anda', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.fallaAlGuardar = true;
      await _abrir(tester, telefono);
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      telefono.preferencias.fallaAlGuardar = false;

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_switchEncendido(tester), isFalse);
      expect(_errorGuardar, findsNothing);
      expect(telefono.preferencias.preferencias.activados, isFalse);
    });

    testWidgets('el error se anuncia al lector de pantalla (región viva)', (tester) async {
      final semantica = tester.ensureSemantics();
      final telefono = _activado();
      telefono.preferencias.fallaAlGuardar = true;
      await _abrir(tester, telefono);
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      final nodo = tester.getSemantics(find.text(_textoError));
      expect(nodo.getSemanticsData().label, contains('No pudimos guardar el cambio'));
      semantica.dispose();
    });
  });

  group('error al leer las preferencias', () {
    testWidgets('dice qué pasó y «Reintentar» las lee de verdad', (tester) async {
      final telefono = _activado();
      telefono.preferencias.fallaAlLeer = true;
      await _abrir(tester, telefono);

      expect(find.text('No pudimos leer tus preferencias de recordatorios.'), findsOneWidget);
      expect(_interruptor, findsNothing);
      telefono.preferencias.fallaAlLeer = false;

      await tester.tap(_reintentarLeer);
      await tester.pumpAndSettle();

      expect(_errorLeer, findsNothing);
      expect(_interruptor, findsOneWidget);
    });

    testWidgets('si sigue fallando, «Reintentar» sigue ahí y no queda cargando para siempre', (
      tester,
    ) async {
      final telefono = _activado();
      telefono.preferencias.fallaAlLeer = true;
      await _abrir(tester, telefono);

      await tester.tap(_reintentarLeer);
      await tester.pumpAndSettle();

      expect(_reintentarLeer, findsOneWidget);
      expect(_cargando, findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en el interruptor: se guarda lo último y queda una sola verdad', (
      tester,
    ) async {
      final telefono = _activado();
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(_switchEncendido(tester), telefono.preferencias.preferencias.activados);
      expect(_errorGuardar, findsNothing);
    });

    testWidgets(
      'dos acciones seguidas (anticipación y después el interruptor) se guardan las dos',
      (tester) async {
        final telefono = _activado();
        _conVisitas(telefono);
        final demora = telefono.preferencias.guardadoDemorado = Completer<void>();
        final semantica = tester.ensureSemantics();
        await _abrir(tester, telefono);

        tester.semantics.performAction(_subir, SemanticsAction.increase);
        await tester.pump();
        await tester.tap(_interruptor);
        await tester.pump();
        demora.complete();
        await tester.pumpAndSettle();

        expect(
          telefono.preferencias.preferencias,
          const PreferenciasRecordatorios(activados: false, anticipacionMinutos: 35),
        );
        expect(_switchEncendido(tester), isFalse);
        semantica.dispose();
      },
    );

    testWidgets('volver atrás y reentrar: lo que se cambió sigue ahí', (tester) async {
      final telefono = _activado();
      final semantica = tester.ensureSemantics();
      await _abrir(tester, telefono, clave: const ValueKey('a'));
      tester.semantics.performAction(_subir, SemanticsAction.increase);
      await tester.pumpAndSettle();
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      await tester.pumpWidget(const SizedBox.shrink());
      await _abrir(tester, telefono, clave: const ValueKey('b'));

      expect(_switchEncendido(tester), isFalse);
      expect(_texto(_valor).data, '35 min antes');
      semantica.dispose();
    });

    testWidgets('salir con un guardado en curso no pierde el cambio', (tester) async {
      final telefono = _activado();
      final demora = telefono.preferencias.guardadoDemorado = Completer<void>();
      await _abrir(tester, telefono);

      await tester.tap(_interruptor);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      demora.complete();
      await tester.pumpAndSettle();

      expect(telefono.preferencias.preferencias.activados, isFalse);
    });

    for (final (nombre, tamano, texto) in [
      ('texto al 200 %', const Size(390, 844), 2.0),
      ('texto al 300 % en un teléfono chico', const Size(320, 568), 3.0),
    ]) {
      testWidgets('$nombre: no se corta nada y los controles se alcanzan', (tester) async {
        fijarTamano(tester, tamano: tamano, texto: texto);
        final telefono = Telefono(); // con el permiso apagado: el caso más largo
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [
              ...telefono.overrides,
              sesionProvider.overrideWith(() => _SesionFija(_sesion)),
            ],
            child: MaterialApp(theme: temaClaro(), home: const NotificacionesPage()),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        for (final control in [_interruptor, _slider]) {
          await tester.ensureVisible(control);
          await tester.pump();
          final caja = tester.getRect(control);
          expect(caja.left, greaterThanOrEqualTo(0));
          expect(caja.right, lessThanOrEqualTo(tamano.width));
          // Con la letra de prueba (cada letra mide el tamaño de la fuente) la tarjeta puede ser más
          // alta que la pantalla: alcanza con que se llegue a ella; la altura real se mide con la
          // letra real en `preferencias_recordatorios_415_geometria_test.dart`.
          expect(caja.top, inInclusiveRange(0, tamano.height));
        }
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('cumple las guías de accesibilidad de Flutter (toques y etiquetas)', (
      tester,
    ) async {
      await _abrir(tester, _activado());

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    });

    testWidgets('el contraste del texto cumple AA a 390 × 844', (tester) async {
      await _abrir(tester, _activado());

      await expectLater(tester, meetsGuideline(textContrastGuideline));
    });
  });
}
