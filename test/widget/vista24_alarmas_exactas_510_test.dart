// «Aviso exacto» (HU-NOT-002, #510), vista 24: con «Alarmas y recordatorios» apagado un aviso dice qué
// pasa («Los recordatorios pueden llegar tarde…») y «Abrir ajustes» lleva al ajuste del teléfono. Al
// volver, el aviso se va solo y los recordatorios ya programados se reprograman. Los dos caminos
// (permiso prendido y apagado), el regreso del ajuste y los casos límite: doble toque, falla al abrir,
// volver atrás y reentrar, texto al 200 %.
//
// El canvas (`24 Notificaciones.dc.html`) no dibuja este aviso: el texto y el botón son los del issue.
import 'dart:async';

import 'package:colportores_mobile/core/notificaciones/permiso_alarmas_exactas.dart';
import 'package:colportores_mobile/core/notificaciones/permiso_notificaciones_sistema.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/recordatorio_de_visita.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/preferencias_recordatorios.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/notificaciones_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/notificaciones_arnes.dart';

class _SesionFija extends SesionNotifier {
  @override
  Future<Sesion?> build() async => Sesion(
    usuarioId: 'col-1',
    email: 'ana@example.com',
    accessToken: 'jwt',
    expiraEn: DateTime.utc(2030),
  );
}

final _aviso = find.byKey(const Key('alarmas_exactas_aviso'));
final _abrir = find.byKey(const Key('alarmas_exactas_abrir_ajustes'));
final _noAbren = find.byKey(const Key('alarmas_exactas_ajustes_no_abren'));
final _apagadas = find.byKey(const Key('notificaciones_apagadas'));
final _interruptor = find.byKey(const Key('pref_recordatorios_interruptor'));
final _atras = find.byKey(const Key('notificaciones_atras'));

const _texto =
    'Los recordatorios pueden llegar tarde. Activá «Alarmas y recordatorios» para que suenen a la '
    'hora justa.';

Telefono _telefono({EstadoAlarmasExactas alarmas = EstadoAlarmasExactas.apagadas}) {
  final t = Telefono(estado: EstadoSistemaNotificaciones.activadas);
  t.alarmas.estado = alarmas;
  t.agendas.agendas.add(
    RecordatorioDeVisita(
      agendaId: 'ag-1',
      tipo: TipoAgenda.entrevista,
      direccion: 'Av. Italia 1234',
      fechaProgramada: DateTime.now().add(const Duration(days: 1)),
    ),
  );
  return t;
}

Future<void> _montar(
  WidgetTester tester,
  Telefono t, {
  Widget? pantalla,
  bool esperar = true,
  Size tamano = const Size(390, 844),
  double texto = 1,
}) async {
  fijarTamano(tester, tamano: tamano, texto: texto);
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [...t.overrides, sesionProvider.overrideWith(_SesionFija.new)],
      child: MaterialApp(theme: temaClaro(), home: pantalla ?? const NotificacionesPage()),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

void main() {
  group('los dos caminos', () {
    testWidgets('con «Alarmas y recordatorios» apagado, dice qué pasa y ofrece «Abrir ajustes»', (
      tester,
    ) async {
      final t = _telefono();
      await _montar(tester, t);

      expect(find.text(_texto), findsOneWidget);
      expect(find.descendant(of: _abrir, matching: find.text('Abrir ajustes')), findsOneWidget);
      expect(_noAbren, findsNothing);
      // Los recordatorios siguen a la vista: el aviso no los tapa.
      expect(_interruptor, findsOneWidget);
    });

    for (final estado in [EstadoAlarmasExactas.permitidas, EstadoAlarmasExactas.noAplica]) {
      testWidgets('con el permiso en $estado no hay aviso', (tester) async {
        await _montar(tester, _telefono(alarmas: estado));

        expect(_aviso, findsNothing);
        expect(_abrir, findsNothing);
        expect(find.text(_texto), findsNothing);
        expect(_interruptor, findsOneWidget);
      });
    }

    testWidgets('si el sistema no contesta, no se muestra nada y la vista sigue entera', (
      tester,
    ) async {
      final t = _telefono();
      t.alarmas.fallaAlLeer = true;
      await _montar(tester, t);

      expect(_aviso, findsNothing);
      expect(_interruptor, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('es un permiso aparte: se ve también con las notificaciones apagadas', (
      tester,
    ) async {
      final t = _telefono();
      t.sistema.estado = EstadoSistemaNotificaciones.apagadas;
      await _montar(tester, t);

      expect(_apagadas, findsOneWidget);
      expect(_aviso, findsOneWidget);
      expect(_abrir, findsOneWidget);
    });

    testWidgets('con «Recordatorios de agenda» apagados no hay aviso, y vuelve apenas se prenden', (
      tester,
    ) async {
      final t = _telefono();
      t.preferencias.preferencias = const PreferenciasRecordatorios(activados: false);
      await _montar(tester, t);

      expect(_aviso, findsNothing);
      expect(_abrir, findsNothing);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      await tester.tap(_interruptor);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);
    });

    testWidgets('el aviso es de lectura inmediata para el lector de pantalla y el botón tiene '
        'área táctil de 48', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, _telefono());

      final nodo = tester.getSemantics(_aviso);
      expect(nodo.label, contains('Los recordatorios pueden llegar tarde'));
      final boton = tester.getSize(_abrir);
      expect(boton.height, greaterThanOrEqualTo(48));
      expect(boton.width, greaterThanOrEqualTo(48));
      expect(
        tester.getSemantics(_abrir),
        matchesSemantics(
          label: 'Abrir ajustes',
          isButton: true,
          hasTapAction: true,
          hasFocusAction: true,
          isEnabled: true,
          hasEnabledState: true,
          isFocusable: true,
        ),
      );
      semantica.dispose();
    });
  });

  group('«Abrir ajustes»', () {
    testWidgets('abre los ajustes de «Alarmas y recordatorios», una sola vez aunque toque dos '
        'veces', (tester) async {
      final t = _telefono();
      final demora = t.alarmas.ajustesDemorados = Completer<void>();
      await _montar(tester, t);

      await tester.tap(_abrir);
      await tester.pump();
      await tester.tap(_abrir, warnIfMissed: false);
      await tester.pump();
      demora.complete();
      await tester.pumpAndSettle();

      expect(t.alarmas.ajustesAbiertos, 1);
      expect(_noAbren, findsNothing);
      expect(_aviso, findsOneWidget);
    });

    testWidgets('mientras se abren los ajustes el botón está apagado y después vuelve', (
      tester,
    ) async {
      final t = _telefono();
      final demora = t.alarmas.ajustesDemorados = Completer<void>();
      await _montar(tester, t);

      await tester.tap(_abrir);
      await tester.pump();
      expect(tester.widget<TextButton>(_abrir).onPressed, isNull);

      demora.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextButton>(_abrir).onPressed, isNotNull);
    });

    testWidgets('si el teléfono no tiene esa pantalla, dice cómo llegar a mano y deja reintentar', (
      tester,
    ) async {
      final t = _telefono();
      t.alarmas.puedeAbrirAjustes = false;
      await _montar(tester, t);

      await tester.tap(_abrir);
      await tester.pumpAndSettle();

      expect(_noAbren, findsOneWidget);
      expect(
        find.text(
          'No pudimos abrir los ajustes. Abrí los ajustes del teléfono, buscá esta app y activá '
          '«Alarmas y recordatorios».',
        ),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(_abrir).onPressed, isNotNull);

      t.alarmas.puedeAbrirAjustes = true;
      await tester.tap(_abrir);
      await tester.pumpAndSettle();

      expect(t.alarmas.ajustesAbiertos, 2);
      expect(_noAbren, findsNothing);
    });

    testWidgets('si la plataforma falla a mitad de la acción, el botón vuelve a habilitarse', (
      tester,
    ) async {
      final t = _telefono();
      t.alarmas.fallaAlAbrir = true;
      await _montar(tester, t);

      await tester.tap(_abrir);
      await tester.pumpAndSettle();

      expect(_noAbren, findsOneWidget);
      expect(tester.widget<TextButton>(_abrir).onPressed, isNotNull);
      expect(tester.takeException(), isNull);
    });
  });

  group('al volver del ajuste', () {
    testWidgets('con el permiso prendido, el aviso se va solo y los recordatorios ya programados '
        'se reprograman', (tester) async {
      final t = _telefono();
      await _montar(tester, t);
      // Al abrir la app ya se habían reprogramado una vez (inexactos).
      t.recordatorios.llamadas.clear();
      final consultas = t.agendas.consultas;

      await tester.tap(_abrir);
      await tester.pumpAndSettle();
      t.alarmas.estado = EstadoAlarmasExactas.permitidas;
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(_aviso, findsNothing);
      expect(_abrir, findsNothing);
      expect(t.agendas.consultas, consultas + 1);
      expect(t.recordatorios.llamadas, ['programar:ag-1']);
    });

    testWidgets('si vuelve sin haber prendido el permiso, el aviso sigue y no se reprograma', (
      tester,
    ) async {
      final t = _telefono();
      await _montar(tester, t);
      t.recordatorios.llamadas.clear();

      await tester.tap(_abrir);
      await tester.pumpAndSettle();
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(_aviso, findsOneWidget);
      expect(t.recordatorios.llamadas, isEmpty);
    });

    testWidgets('si lo quita después, el aviso vuelve a salir', (tester) async {
      final t = _telefono(alarmas: EstadoAlarmasExactas.permitidas);
      await _montar(tester, t);
      expect(_aviso, findsNothing);

      t.alarmas.estado = EstadoAlarmasExactas.apagadas;
      volverALaApp(tester);
      await tester.pumpAndSettle();

      expect(_aviso, findsOneWidget);
      expect(find.text(_texto), findsOneWidget);
    });

    testWidgets('el regreso no pisa lo que la persona hace en la vista: el interruptor sigue '
        'respondiendo', (tester) async {
      final t = _telefono();
      await _montar(tester, t);

      t.alarmas.estado = EstadoAlarmasExactas.permitidas;
      volverALaApp(tester);
      await tester.pumpAndSettle();
      await tester.tap(_interruptor);
      await tester.pumpAndSettle();

      expect(t.preferencias.preferencias.activados, isFalse);
      expect(_aviso, findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('volver atrás y reentrar: el aviso sigue ahí y el botón funciona', (tester) async {
      final t = _telefono();
      await _montar(
        tester,
        t,
        pantalla: Builder(
          builder: (contexto) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('ir'),
                onPressed: () => Navigator.of(contexto).push(NotificacionesPage.ruta()),
                child: const Text('ir'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('ir')));
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);

      await tester.tap(_atras);
      await tester.pumpAndSettle();
      expect(_aviso, findsNothing);

      await tester.tap(find.byKey(const Key('ir')));
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);
      await tester.tap(_abrir);
      await tester.pumpAndSettle();
      expect(t.alarmas.ajustesAbiertos, 1);
    });

    testWidgets('mientras el sistema todavía no contestó no se muestra el aviso, y al contestar '
        'aparece', (tester) async {
      final t = _telefono();
      final demora = t.alarmas.lecturaDemorada = Completer<void>();
      await _montar(tester, t, esperar: false);
      await tester.pump();

      expect(_aviso, findsNothing);
      expect(_interruptor, findsOneWidget);

      demora.complete();
      await tester.pumpAndSettle();
      expect(_aviso, findsOneWidget);
    });

    for (final (nombre, tamano) in [
      ('360×640', const Size(360, 640)),
      ('320×568', const Size(320, 568)),
    ]) {
      testWidgets('con el texto al 200 % en $nombre no desborda y el botón se alcanza', (
        tester,
      ) async {
        final t = _telefono();
        await _montar(tester, t, tamano: tamano, texto: 2);

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_abrir);
        await tester.pumpAndSettle();
        await tester.tap(_abrir);
        await tester.pumpAndSettle();

        expect(t.alarmas.ajustesAbiertos, 1);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('con el texto al 200 % y la falla al abrir, el texto de ayuda también entra', (
      tester,
    ) async {
      final t = _telefono();
      t.alarmas.puedeAbrirAjustes = false;
      await _montar(tester, t, tamano: const Size(320, 568), texto: 2);

      await tester.ensureVisible(_abrir);
      await tester.pumpAndSettle();
      await tester.tap(_abrir);
      await tester.pumpAndSettle();
      await tester.ensureVisible(_noAbren);
      await tester.pumpAndSettle();

      expect(_noAbren, findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
