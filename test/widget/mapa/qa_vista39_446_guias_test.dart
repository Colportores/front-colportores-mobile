// QA de la pestaña Historial de la hoja de la casa (vista 39, C·03 y C·04, #446, PR #677): las guías de
// accesibilidad de Flutter (objetivo táctil de Android y de iOS, etiqueta de lo tocable y contraste del
// texto) en cada estado y tamaño, y que ninguno desborde. Va aparte de los demás tests de la vista porque
// el contraste se mide con la fuente de prueba: con las fuentes reales `textContrastGuideline` da falsos
// negativos.
import 'dart:async';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart'
    show TipoResultadoVisita;
import 'package:colportores_mobile/features/cobranzas/domain/entities/cobranza.dart'
    show MedioCobranza;
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ficha_de_persona.dart'
    show LineaDeFicha;
import 'package:colportores_mobile/features/mapa/domain/services/historial_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/historial_de_la_casa_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pestana_historial_de_la_casa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime(2026, 10, 25, 16);

DateTime _local(int mes, int dia, [int hora = 12, int minuto = 0]) =>
    DateTime(2026, mes, dia, hora, minuto).toUtc();

const _pedro = PersonaDelEvento(nombre: 'Pedro', apellido: 'Gómez');

final _venta = VentaDeLaCasa(
  id: 'ven-1',
  fecha: _local(10, 12, 14),
  numeroTalonario: '0038',
  montoCentavos: 480000,
  pagadoCentavos: 360000,
  lineas: const [LineaDeFicha(nombre: 'Salud y Hogar', cantidad: 1)],
  persona: _pedro,
  espacioPersonaId: 'ep-pedro',
  nota: 'quiere Nuestros Hijos',
);

final _entrevista = VisitaDeLaCasa(
  id: 'vis-2',
  fecha: _local(10, 5, 17),
  resultado: TipoResultadoVisita.entrevista,
  persona: _pedro,
  nota: 'volver con la esposa',
  duracion: const Duration(minutes: 22),
);

final _noContesto = VisitaDeLaCasa(
  id: 'vis-1',
  fecha: _local(10, 3, 15),
  resultado: TipoResultadoVisita.noContesto,
);

final _c03 = <EventoDeLaCasa>[
  CobroDeLaCasa(
    id: 'cob-1',
    fecha: _local(10, 25, 14, 20),
    montoCentavos: 60000,
    medio: MedioCobranza.efectivo,
    ventaId: 'ven-1',
    numeroTalonario: '0038',
    persona: _pedro,
  ),
  _venta,
  _entrevista,
  _noContesto,
];

enum _Estado {
  c03,
  c03ConVerLaVenta,
  vacio,
  filtroSinResultados,
  cargando,
  error,
  detalleDeVenta,
  detalleDeEntrevista,
  detalleDeVisitaSinNota,
  avisoNoPudimosAbrirLaVenta,
  listaLarga,
}

final class _Historial implements HistorialDeLaCasa {
  _Historial(this._lectura);

  final Stream<List<EventoDeLaCasa>> Function() _lectura;

  @override
  Stream<List<EventoDeLaCasa>> observar(String espacioId) => _lectura();
}

const _tamanos = [Size(360, 640), Size(412, 915)];
const _escalas = [1.0, 2.0];

void main() {
  Future<void> asentar(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> llegarA(WidgetTester tester, _Estado estado, Size tamano, double escala) async {
    tester.view.physicalSize = tamano;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final conVerLaVenta =
        estado == _Estado.c03ConVerLaVenta ||
        estado == _Estado.detalleDeVenta ||
        estado == _Estado.avisoNoPudimosAbrirLaVenta;
    final lectura = switch (estado) {
      _Estado.vacio => () => Stream.value(const <EventoDeLaCasa>[]),
      _Estado.cargando => () => StreamController<List<EventoDeLaCasa>>().stream,
      _Estado.error => () => Stream<List<EventoDeLaCasa>>.error(StateError('falla')),
      _Estado.filtroSinResultados => () => Stream.value(<EventoDeLaCasa>[_venta]),
      _Estado.listaLarga => () => Stream.value([
        for (var i = 0; i < 40; i++)
          VisitaDeLaCasa(
            id: 'v-$i',
            fecha: _local(9, 1 + i % 28, 10),
            resultado: TipoResultadoVisita.noContesto,
          ),
      ]),
      _ => () => Stream.value(_c03),
    };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          historialDeLaCasaFuenteProvider.overrideWithValue(_Historial(lectura)),
          relojPersonaProvider.overrideWithValue(() => _ahora),
          verVentaDesdeLaCasaProvider.overrideWithValue(
            conVerLaVenta
                ? (_) => estado == _Estado.avisoNoPudimosAbrirLaVenta
                      ? throw StateError('sin sesión')
                      : true
                : null,
          ),
        ],
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: PestanaHistorialDeLaCasa(espacioId: 'esp-1', direccion: 'Grecia 3310'),
            ),
          ),
        ),
      ),
    );
    await asentar(tester);
    Future<void> abrirFila(String id) async {
      final fila = find.byKey(ClavesHistorialDeLaCasa.fila(id));
      await tester.ensureVisible(fila);
      await tester.tap(fila);
      await asentar(tester);
      expect(find.byKey(ClavesDetalleDeVisita.hoja), findsOneWidget, reason: 'abrió el detalle');
    }

    switch (estado) {
      case _Estado.filtroSinResultados:
        await tester.tap(find.byKey(ClavesHistorialDeLaCasa.filtro(FiltroDeLaCasa.entrevistas)));
        await asentar(tester);
      case _Estado.detalleDeVenta:
        await abrirFila('ven-1');
      case _Estado.avisoNoPudimosAbrirLaVenta:
        await abrirFila('ven-1');
        final boton = find.byKey(ClavesDetalleDeVisita.verLaVenta);
        await tester.ensureVisible(boton);
        await tester.tap(boton);
        await asentar(tester);
        expect(find.byKey(ClavesHistorialDeLaCasa.aviso), findsOneWidget);
      case _Estado.detalleDeEntrevista:
        await abrirFila('vis-2');
      case _Estado.detalleDeVisitaSinNota:
        await abrirFila('vis-1');
      default:
        break;
    }
  }

  for (final estado in _Estado.values) {
    for (final tamano in _tamanos) {
      for (final escala in _escalas) {
        final medida = '${tamano.width.toInt()}x${tamano.height.toInt()} x$escala';
        testWidgets('guías · ${estado.name} · $medida', (tester) async {
          final semantica = tester.ensureSemantics();
          await llegarA(tester, estado, tamano, escala);
          await tester.pump(const Duration(milliseconds: 100));

          expect(tester.takeException(), isNull, reason: 'sin desbordes');
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          semantica.dispose();
        });
      }
    }
  }
}
