// QA de «PRÓXIMA VISITA» en la ficha de la persona (vista 23, 23A·05, y vista 32B, #405, PR #592):
// lo que no cubre `ficha_proxima_visita_405_test.dart`. La tarjeta convive con todo lo de develop (chips
// «+ Agendar cobranza» y «Registrar entrega», notas, historial) sin desbordar a 360×640 con el texto al
// 200 %; el aviso de error de la agenda se anuncia y guía; cada «Agendar» abre «Agendar visita» con su
// tipo; y capturas de cada estado (solo con `--dart-define=QA_CAPTURAS=true`, a
// `.dart_tool/qa_capturas/405_*.png`, gitignored). Las guías de accesibilidad van en
// `qa_ficha_proxima_visita_405_guias_test.dart` (con la letra de prueba).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/domain/entities/item_agenda.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/tipo_agenda.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_ficha_persona.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agenda_items_falsos.dart';
import '../../helpers/qa_ficha_persona_563_arnes.dart' show cargarFuentes563;
import 'ficha_persona_arnes.dart';

final _tarjeta = find.byKey(ClavesFicha.tarjetaProximaVisita);
final _agendar = find.byKey(ClavesFicha.botonAgendar);
final _agendarCobranza = find.byKey(ClavesFicha.botonAgendarCobranza);

ItemAgenda _visita(String id, DateTime cuando, {TipoAgenda tipo = TipoAgenda.entrevista}) =>
    itemAgenda(
      id,
      cuando,
      tipo: tipo,
      slotCodigo: 'early_afternoon',
      espacioPersonaId: 'ep-per-1',
      nombre: 'María',
      apellido: 'Pérez',
    );

/// La ficha con todo lo de develop a la vez: cuenta con saldo (chips), notas, historial.
MundoFicha _mundoCompleto({List<ItemAgenda> visitas = const []}) {
  final m = MundoFicha(historial: historialDelCanvas(), notasIniciales: notasDeLaFicha())
    ..conRegistrarEntrega = true
    ..conDetalleDeAgenda = true;
  m.cuentas.cuenta = cuentaConSaldo;
  m.consultaAgendas.items = visitas;
  m.personas.sembrar([clienteDePersonas('per-1', 'María', apellido: 'Pérez')]);
  m.telefono.recordatorios.permisoConcedido = true;
  return m;
}

/// Captura PNG de lo que se ve, a `.dart_tool/qa_capturas/405_<nombre>.png`. Solo con QA_CAPTURAS.
Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!const bool.fromEnvironment('QA_CAPTURAS')) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size);
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/405_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

bool _hayRegionViva(SemanticsNode nodo) {
  if (nodo.getSemanticsData().flagsCollection.isLiveRegion) return true;
  var viva = false;
  nodo.visitChildren((hijo) {
    viva = viva || _hayRegionViva(hijo);
    return !viva;
  });
  return viva;
}

void main() {
  group('Convive con lo de develop', () {
    testWidgets(
      'dada la ficha completa a 360×640 con el texto al 200 %, entonces nada desborda y todo se alcanza',
      (tester) async {
        await cargarFuentes563(tester);
        final mundo = _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 24, 14, 30))]);
        await montarFicha(tester, mundo, tamano: const Size(360, 640), escala: 2);

        for (final f in [
          _agendarCobranza,
          find.text('Registrar entrega'),
          _tarjeta,
          _agendar,
          find.byKey(ClavesFicha.botonNota),
          find.byKey(ClavesFicha.historial),
        ]) {
          await tester.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first);
          expect(f, findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('dada la ficha entera, entonces va cuenta, acciones, visita, notas e historial', (
      tester,
    ) async {
      final mundo = _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 24, 14, 30))]);
      await montarFicha(tester, mundo, tamano: const Size(390, 2400));
      double y(Finder f) => tester.getTopLeft(f).dy;
      expect(y(_agendarCobranza), lessThan(y(find.byKey(ClavesFicha.proximaVisita))));
      expect(y(find.byKey(ClavesFicha.proximaVisita)), lessThan(y(find.byKey(ClavesFicha.notas))));
      expect(y(find.byKey(ClavesFicha.notas)), lessThan(y(find.byKey(ClavesFicha.historial))));
    });

    testWidgets('dados los dos «Agendar», entonces cada uno abre «Agendar visita» con su tipo', (
      tester,
    ) async {
      final mundo = _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 24, 14, 30))]);
      await montarFicha(tester, mundo, tamano: const Size(390, 2400));

      await tester.tap(_agendar);
      await asentar(tester);
      expect(find.text('Agendar visita'), findsOneWidget);
      await tester.tap(find.text('Agendar'));
      await asentar(tester);
      expect(mundo.agendas.recibidas.last.agenda.tipo, TipoAgenda.entrevista);

      await tester.tap(_agendarCobranza);
      await asentar(tester);
      expect(find.text('Agendar visita'), findsOneWidget);
      await tester.tap(find.text('Agendar'));
      await asentar(tester);
      expect(mundo.agendas.recibidas.last.agenda.tipo, TipoAgenda.cobranza);
      expect(mundo.agendas.recibidas, hasLength(2));
    });

    testWidgets('dado «Registrar entrega» y la tarjeta, entonces cada uno abre lo suyo', (
      tester,
    ) async {
      final mundo = _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 24, 14, 30))]);
      await montarFicha(tester, mundo, tamano: const Size(390, 2400));

      await tester.tap(_tarjeta);
      await asentar(tester);
      expect(mundo.detallesAbiertos, ['a1']);
      expect(mundo.entregas, isEmpty);
      await tester.tap(find.text('Registrar entrega'));
      await asentar(tester);
      expect(mundo.entregas, hasLength(1));
      expect(mundo.detallesAbiertos, ['a1']);
    });
  });

  group('Aviso de error de la agenda', () {
    testWidgets('dada una falla al leer, entonces el aviso se anuncia y trae «Reintentar»', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      final mundo = _mundoCompleto()..consultaAgendas.error = StateError('sin base');
      await montarFicha(tester, mundo, tamano: const Size(390, 2400));

      final aviso = find.byKey(ClavesFicha.errorProximaVisita);
      expect(aviso, findsOneWidget);
      expect(find.text('No pudimos leer tu agenda.'), findsOneWidget);
      expect(find.text('Reintentar'), findsOneWidget);
      // Algún nodo del aviso es una región viva: el lector lo anuncia sin que haya que buscarlo.
      expect(_hayRegionViva(tester.getSemantics(aviso)), isTrue);
      expect(find.byKey(ClavesFicha.historial), findsOneWidget);
      h.dispose();
    });

    testWidgets(
      'dado «Reintentar» que vuelve a fallar, entonces el aviso sigue y se puede de nuevo',
      (tester) async {
        final mundo = _mundoCompleto()..consultaAgendas.error = StateError('sin base');
        await montarFicha(tester, mundo, tamano: const Size(390, 2400));

        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.byKey(ClavesFicha.errorProximaVisita), findsOneWidget);
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(find.byKey(ClavesFicha.errorProximaVisita), findsOneWidget);
        expect(mundo.consultaAgendas.pedidosDeLaPersona.length, greaterThanOrEqualTo(3));

        mundo.consultaAgendas
          ..error = null
          ..items = [_visita('a1', DateTime(2026, 10, 24, 14, 30))];
        await tester.tap(find.text('Reintentar'));
        await asentar(tester);
        expect(_tarjeta, findsOneWidget);
      },
    );
  });

  group(
    'Mientras se abre «Agendar visita»',
    () {
      testWidgets(
        'dado «+ Agendar» sin visita, entonces la sección no desaparece de la ficha mientras tanto',
        (tester) async {
          final mundo = _mundoCompleto();
          await montarFicha(tester, mundo, tamano: const Size(390, 2400));
          expect(_agendar, findsOneWidget);

          await tester.tap(_agendar);
          await tester.pump();
          await tester.pump();
          // Con «Agendar visita» encima, la ficha de abajo conserva la sección (apagada), igual que
          // «+ Nota» y los chips: si no, al volver el contenido salta.
          expect(find.byKey(ClavesFicha.proximaVisita, skipOffstage: false), findsOneWidget);
        },
      );
    },
    skip:
        'QA #592: con «Agendar visita» abierta «PRÓXIMA VISITA» sale de la ficha (alAgendar pasa a null) y reaparece al volver: el contenido salta',
  );

  group('Capturas (solo con QA_CAPTURAS)', () {
    final casos = <String, MundoFicha Function()>{
      'con_visita': () => _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 24, 14, 30))]),
      'vencida': () => _mundoCompleto(visitas: [_visita('a1', DateTime(2026, 10, 21, 10))]),
      'sin_visita': _mundoCompleto,
      'error': () => _mundoCompleto()..consultaAgendas.error = StateError('x'),
    };
    for (final e in casos.entries) {
      for (final (tamano, escala, etiqueta) in [
        (const Size(390, 1500), 1.0, 'alta'),
        (const Size(360, 640), 1.0, '360'),
        (const Size(360, 640), 2.0, '360_x2'),
      ]) {
        testWidgets('captura ${e.key} $etiqueta', (tester) async {
          await cargarFuentes563(tester);
          await montarFicha(tester, e.value(), tamano: tamano, escala: escala);
          if (etiqueta != 'alta') {
            await tester.scrollUntilVisible(
              find.byKey(ClavesFicha.proximaVisita),
              100,
              scrollable: find.byType(Scrollable).first,
            );
            await tester.pump(const Duration(milliseconds: 300));
          }
          expect(tester.takeException(), isNull);
          await _capturar(tester, '${e.key}_$etiqueta');
        });
      }
    }
  });
}
