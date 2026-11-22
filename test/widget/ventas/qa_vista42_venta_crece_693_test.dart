// QA de «Venta crece» (vista 42, 42B·09A a 09D; HU-VEN-001, #693). Lo que no cubren los tests del
// implementador: la hoja de la casa REAL y la ficha REAL con «Sumar un libro» enchufado (por persona, en
// vivo, una acción a la vez), «¿A qué venta lo sumás?» con muchas ventas y textos largos, la venta que
// crece con textos largos / fallas / entradas hostiles, el cierre 09D y el recorrido.
// Con `--dart-define=QA_HALLAZGOS=true` corren los tests que documentan un hallazgo (van con `skip`);
// con `--dart-define=QA_CAPTURAS=true` se guardan capturas en `.dart_tool/qa_capturas/`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_venta_que_crece.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart'
    show CampaniaTerminada;
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show VentaRegistradaEnLaCasa;
import 'package:colportores_mobile/features/ventas/domain/entities/cliente_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/precios_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart'
    show ContextoDeCobroDeLaVenta, cobrarDespuesDeLaVentaProvider;
import 'package:colportores_mobile/features/ventas/presentation/textos_venta_que_crece.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/fila_sumar_un_libro.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_a_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/hoja_casa_falsos.dart' show itemDeLaHoja;
import '../../helpers/persona_falsos.dart' show clienteDePersonas;
import '../../helpers/qa_vista42_venta_crece_693_arnes.dart';
import '../../helpers/venta_ui_falsos.dart';
import '../mapa/ficha_persona_arnes.dart'
    show MundoFicha, contextoBajaDesde22, historialDelCanvas, mariaDePrueba;

const _conHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// Los tamaños de la matriz de QA con el escalado de texto.
const _matriz = <({String nombre, Size tamano, double escala})>[
  (nombre: '360x640 ×1,0', tamano: telefonoChico693, escala: 1),
  (nombre: '360x640 ×2,0', tamano: telefonoChico693, escala: 2),
  (nombre: '412x915 ×1,0', tamano: telefonoGrande693, escala: 1),
  (nombre: '412x915 ×2,0', tamano: telefonoGrande693, escala: 2),
];

final _v39 = ventaAbierta693('v-39');
final _v31 = ventaAbierta693(
  'v-31',
  numero: '0031',
  fecha: DateTime.utc(2026, 10, 12, 15),
  total: 24000,
  cobrado: 0,
  descripcion: 'Vida Feliz × 2',
);

/// Baja la lista (perezosa) hasta que [f] se pueda tocar: `ensureVisible` no alcanza lo que todavía no se armó.
Future<void> _bajarHasta(WidgetTester tester, Finder f, Finder scrollable) async {
  for (var i = 0; i < 60 && f.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(scrollable.first, const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder get _filaSumar => find.byKey(ClavesSumarUnLibro.fila);
Finder get _tocarSumar => find.byKey(ClavesSumarUnLibro.tocar);

void main() {
  group('42B·09A · «Sumar un libro» en la hoja de la casa real (C·01)', () {
    testWidgets('con una venta abierta de Pedro la fila va debajo de la persona y dice a cuál', (
      tester,
    ) async {
      await montarHoja693(tester, repo: VentasAbiertasQA(abiertas: [_v39]));

      expect(_filaSumar, findsOneWidget);
      expect(find.text('A la venta 0039 de Pedro, sin otro talonario'), findsOneWidget);
      // Debajo de la persona (su saldo y «$ Cobrar»), no encima.
      final cobrar = tester.getTopLeft(find.text(r'$ Cobrar')).dy;
      expect(tester.getTopLeft(_filaSumar).dy, greaterThan(cobrar));
    });

    testWidgets('lee las ventas de la persona de la casa, no las de otra', (tester) async {
      final repo = VentasAbiertasQA(
        porPersona: {
          'p-pedro': [_v39],
          'p-otra': [_v31],
        },
      );
      await montarHoja693(tester, repo: repo);

      expect(repo.lecturas.toSet(), {'p-pedro'});
      expect(find.text('A la venta 0039 de Pedro, sin otro talonario'), findsOneWidget);
    });

    testWidgets('si solo la otra persona de la casa tiene una venta abierta, Pedro no la ve', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(
        porPersona: {
          'p-otra': [_v31],
        },
      );
      await montarHoja693(tester, repo: repo);

      expect(_filaSumar, findsNothing);
    });

    testWidgets('con dos ventas abiertas no nombra una sola: se elige después', (tester) async {
      await montarHoja693(tester, repo: VentasAbiertasQA(abiertas: [_v39, _v31]));

      expect(find.text(TextosVentaQueCrece.aUnaDeSusVentas('Pedro')), findsOneWidget);
    });

    testWidgets('sin venta abierta no se dibuja nada ni deja un hueco', (tester) async {
      await montarHoja693(tester, repo: VentasAbiertasQA());

      expect(_filaSumar, findsNothing);
      expect(find.text(TextosVentaQueCrece.sumarUnLibro), findsNothing);
    });

    testWidgets('si la venta se paga y se entrega con la hoja abierta, la fila se va', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39]);
      await montarHoja693(tester, repo: repo);
      expect(_filaSumar, findsOneWidget);

      repo.cambiar('p-pedro', const []);
      await asentar693(tester);

      expect(_filaSumar, findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si aparece una venta abierta con la hoja abierta, la fila se suma sola', (
      tester,
    ) async {
      final repo = VentasAbiertasQA();
      await montarHoja693(tester, repo: repo);
      expect(_filaSumar, findsNothing);

      repo.cambiar('p-pedro', [_v39]);
      await asentar693(tester);

      expect(_filaSumar, findsOneWidget);
    });

    testWidgets('si no se puede leer, la hoja sigue usable y sin fila ni excepción', (
      tester,
    ) async {
      final repo = VentasAbiertasQA()..errorAlLeer = StateError('sin base');
      await montarHoja693(tester, repo: repo);

      expect(_filaSumar, findsNothing);
      expect(find.text(r'$ Cobrar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('mientras la lectura no llega no se dibuja la fila (no hay botón que mienta)', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39])..compuertaLectura = Completer<void>();
      await montarHoja693(tester, repo: repo);
      expect(_filaSumar, findsNothing);

      repo.compuertaLectura!.complete();
      await asentar693(tester);

      expect(_filaSumar, findsOneWidget);
    });

    testWidgets('sin destino enchufado no se ofrece', (tester) async {
      await montarHoja693(tester, repo: VentasAbiertasQA(abiertas: [_v39]), sinDestino: true);

      expect(_filaSumar, findsNothing);
    });

    testWidgets('con la casa de baja no se ofrece', (tester) async {
      await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        item: itemDeLaHoja(baja: DateTime.utc(2026, 10, 20)),
      );

      expect(_filaSumar, findsNothing);
    });

    testWidgets('tocarla abre el destino con la casa y la persona, y si se sumó cierra la hoja', (
      tester,
    ) async {
      final destino = DestinoQA();
      final cierres = await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await tester.tap(_tocarSumar);
      await asentar693(tester);

      expect(destino.recibidos, [(ubicacionId: 'u-1', espacioId: 'esp-1', personaId: 'p-pedro')]);
      expect(cierres, hasLength(1), reason: 'el mapa queda libre, la hoja se cierra una vez');
    });

    testWidgets('si se salió sin sumar (false) la hoja sigue y se puede volver a tocar', (
      tester,
    ) async {
      final destino = DestinoQA(false);
      final cierres = await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await tester.tap(_tocarSumar);
      await asentar693(tester);
      await tester.tap(_tocarSumar);
      await asentar693(tester);

      expect(cierres, isEmpty);
      expect(destino.recibidos, hasLength(2));
    });

    testWidgets('un doble toque con el flujo abierto lo abre una sola vez', (tester) async {
      final destino = DestinoQA()..compuerta = Completer<void>();
      final cierres = await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await tester.tap(_tocarSumar);
      await tester.tap(_tocarSumar, warnIfMissed: false);
      await tester.pump();
      destino.compuerta!.complete();
      await asentar693(tester);

      expect(destino.recibidos, hasLength(1));
      expect(cierres, hasLength(1));
    });

    testWidgets('mientras el flujo está abierto, «\$ Cobrar» no abre otro (una acción a la vez)', (
      tester,
    ) async {
      final destino = DestinoQA()..compuerta = Completer<void>();
      var cobros = 0;
      await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
        cobrar: (_) => cobros++,
      );

      await tester.tap(_tocarSumar);
      await tester.pump();
      await tester.tap(find.text(r'$ Cobrar'), warnIfMissed: false);
      await tester.pump();
      destino.compuerta!.complete();
      await asentar693(tester);

      expect(cobros, 0);
      expect(destino.recibidos, hasLength(1));
    });

    testWidgets('si el destino lanza, la hoja avisa qué pasó y la fila se puede volver a tocar', (
      tester,
    ) async {
      final destino = DestinoQA()..lanzar = StateError('sin sesión');
      await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await tester.tap(_tocarSumar);
      await asentar693(tester);

      expect(find.text(TextosVentaQueCrece.noPudimosAbrir), findsOneWidget);
      destino.lanzar = null;
      destino.respuesta = false;
      await tester.tap(_tocarSumar);
      await asentar693(tester);
      expect(destino.recibidos, hasLength(2));
      expect(find.text(TextosVentaQueCrece.noPudimosAbrir), findsNothing);
    });

    testWidgets('el lector de pantalla la lee como un botón con su detalle y puede tocarla', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final destino = DestinoQA(false);
      await montarHoja693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
        lector: true,
      );

      expect(
        find.bySemanticsLabel('Sumar un libro. A la venta 0039 de Pedro, sin otro talonario'),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(_filaSumar),
        isSemantics(isButton: true, hasTapAction: true, isEnabled: true, hasEnabledState: true),
      );
      handle.dispose();
    });

    for (final c in _matriz) {
      testWidgets('${c.nombre}: la hoja con la fila no desborda y la fila se alcanza', (
        tester,
      ) async {
        await cargarFuentes693(tester);
        await montarHoja693(
          tester,
          repo: VentasAbiertasQA(abiertas: [_v39]),
          escala: c.escala,
          tamano: c.tamano,
        );
        await asentar693(tester);

        expect(tester.takeException(), isNull);
        await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
        await tester.pump();
        expect(_tocarSumar.hitTestable(), findsOneWidget);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        await capturar693(tester, '09A_hoja_${c.tamano.width.toInt()}_x${c.escala.toInt()}');
      });
    }

    testWidgets('con el nombre larguísimo de la persona el detalle se lee entero y sin desbordar', (
      tester,
    ) async {
      await cargarFuentes693(tester);
      final repo = VentasAbiertasQA(abiertas: [_v39]);
      await montarHoja693(
        tester,
        repo: repo,
        escala: 2,
        tamano: telefonoChico693,
        contexto: _contextoConNombre('Maximiliano Alejandro Fernández de la Santísima Trinidad'),
      );
      await asentar693(tester);

      expect(tester.takeException(), isNull);
      expect(textosFueraDeLaPantalla693(tester, telefonoChico693), isEmpty);
    });
  });

  group('42B·09A · «Sumar un libro» en la ficha real (32B)', () {
    testWidgets('con una venta abierta la fila está en la ficha y abre el destino', (tester) async {
      final destino = DestinoQA(false);
      await montarFicha693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
      expect(find.text('A la venta 0039 de María, sin otro talonario'), findsOneWidget);
      await tester.tap(_tocarSumar);
      await asentar693(tester);

      expect(destino.recibidos.single.personaId, 'per-1');
      expect(destino.recibidos.single.espacioId, 'esp-1');
    });

    testWidgets('sin venta abierta no hay fila', (tester) async {
      await montarFicha693(tester, repo: VentasAbiertasQA());

      expect(_filaSumar, findsNothing);
    });

    testWidgets('sin destino no hay fila', (tester) async {
      await montarFicha693(tester, repo: VentasAbiertasQA(abiertas: [_v39]), sinDestino: true);

      expect(_filaSumar, findsNothing);
    });

    testWidgets('con la persona de baja (solo lectura) no se ofrece', (tester) async {
      await montarFicha693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        mundo: MundoFicha(
          persona: mariaDePrueba(baja: DateTime(2026, 10, 22)),
          historial: historialDelCanvas(),
          contexto: contextoBajaDesde22(),
        ),
      );

      expect(_filaSumar, findsNothing);
    });

    testWidgets('un doble toque abre el destino una sola vez', (tester) async {
      final destino = DestinoQA(false)..compuerta = Completer<void>();
      await montarFicha693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
      await tester.tap(_tocarSumar);
      await tester.tap(_tocarSumar, warnIfMissed: false);
      await tester.pump();
      destino.compuerta!.complete();
      await asentar693(tester);

      expect(destino.recibidos, hasLength(1));
    });

    testWidgets('si el destino lanza, la ficha avisa y la fila se puede volver a tocar', (
      tester,
    ) async {
      final destino = DestinoQA(false)..lanzar = StateError('x');
      await montarFicha693(
        tester,
        repo: VentasAbiertasQA(abiertas: [_v39]),
        destino: destino,
      );

      await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
      await tester.tap(_tocarSumar);
      await asentar693(tester);
      expect(find.byType(SnackBar), findsOneWidget);

      destino.lanzar = null;
      await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
      await tester.tap(_tocarSumar, warnIfMissed: false);
      await asentar693(tester);
      expect(destino.recibidos, hasLength(2));
    });

    for (final c in _matriz) {
      testWidgets('${c.nombre}: la ficha con la fila no desborda', (tester) async {
        await cargarFuentes693(tester);
        await montarFicha693(
          tester,
          repo: VentasAbiertasQA(abiertas: [_v39]),
          escala: c.escala,
          tamano: c.tamano,
        );
        await asentar693(tester);

        expect(tester.takeException(), isNull);
        await _bajarHasta(tester, _tocarSumar, find.byType(Scrollable));
        await tester.pump();
        expect(_tocarSumar.hitTestable(), findsOneWidget);
        await capturar693(tester, '09A_ficha_${c.tamano.width.toInt()}_x${c.escala.toInt()}');
      });
    }
  });

  group('42B·09B · «¿A qué venta lo sumás?»', () {
    Future<List<VentaAbierta?>> abrir(
      WidgetTester tester,
      List<VentaAbierta> ventas, {
      double escala = 1,
      Size tamano = const Size(390, 844),
      String subtitulo = 'Pedro Gómez · Grecia 3307',
    }) async {
      await cargarFuentes693(tester);
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final elegidas = <VentaAbierta?>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: RepaintBoundary(key: raiz693, child: child!),
          ),
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => elegidas.add(
                await mostrarHojaAQueVenta(context, ventas: ventas, subtitulo: subtitulo),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('abrir'));
      await asentar693(tester);
      return elegidas;
    }

    for (final c in _matriz) {
      testWidgets('${c.nombre}: con 2 ventas no desborda y los dos botones se alcanzan', (
        tester,
      ) async {
        await abrir(tester, [_v39, _v31], escala: c.escala, tamano: c.tamano);

        expect(tester.takeException(), isNull);
        expect(find.byKey(ClavesAQueVenta.sumar).hitTestable(), findsOneWidget);
        expect(find.byKey(ClavesAQueVenta.cancelar).hitTestable(), findsOneWidget);
        await capturar693(tester, '09B_${c.tamano.width.toInt()}_x${c.escala.toInt()}');
      });
    }

    for (final c in _matriz) {
      testWidgets('${c.nombre}: con 12 ventas abiertas se puede llegar a elegir y a confirmar', (
        tester,
      ) async {
        final muchas = [
          for (var i = 0; i < 12; i++)
            ventaAbierta693(
              'v-$i',
              numero: (100 + i).toString().padLeft(4, '0'),
              fecha: DateTime.utc(2026, 10, 1 + i, 15),
              descripcion: 'Colección de ${i + 1} libros de la familia',
            ),
        ];
        final elegidas = await abrir(
          tester,
          muchas.reversed.toList(),
          escala: c.escala,
          tamano: c.tamano,
        );

        expect(tester.takeException(), isNull, reason: 'una hoja con muchas ventas no desborda');
        final ultima = find.byKey(ClavesAQueVenta.fila('v-0'));
        await _bajarHasta(
          tester,
          ultima,
          find.descendant(of: find.byKey(ClavesAQueVenta.lista), matching: find.byType(Scrollable)),
        );
        await tester.tap(ultima);
        await tester.pump();
        expect(find.byKey(ClavesAQueVenta.sumar).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(ClavesAQueVenta.sumar));
        await asentar693(tester);

        expect(elegidas.single?.ventaId, 'v-0');
      });
    }

    testWidgets('con textos larguísimos (subtítulo y descripción) no desborda a 320×568 ×2', (
      tester,
    ) async {
      final larga = ventaAbierta693(
        'v-larga',
        descripcion:
            'Colección de 3 libros: Salud y Hogar, El camino a Cristo, La gran esperanza y Vida Feliz',
      );
      await abrir(
        tester,
        [larga, _v31],
        escala: 2,
        tamano: const Size(320, 568),
        subtitulo:
            'Maximiliano Alejandro Fernández de la Santísima Trinidad · Avenida Rivera 3307 bis',
      );

      expect(tester.takeException(), isNull);
      expect(textosFueraDeLaPantalla693(tester, const Size(320, 568)), isEmpty);
    });

    testWidgets('tocar fuera de la hoja (o el atrás) la cierra sin elegir ninguna', (tester) async {
      final elegidas = await abrir(tester, [_v39, _v31]);

      await tester.tapAt(const Offset(195, 40));
      await asentar693(tester);

      expect(elegidas.single, isNull);
    });

    testWidgets('una venta sin descripción ni saldo dice qué falta («falta entregar»)', (
      tester,
    ) async {
      final pagadaSinEntregar = ventaAbierta693(
        'v-p',
        numero: '0044',
        total: 50000,
        cobrado: 50000,
        entregada: false,
        descripcion: '',
      );
      await abrir(tester, [pagadaSinEntregar, _v31]);

      expect(find.text(TextosVentaQueCrece.faltaEntregar), findsOneWidget);
    });

    testWidgets('el lector sabe cuál está elegida', (tester) async {
      final handle = tester.ensureSemantics();
      await abrir(tester, [_v39, _v31]);

      final elegida = find.byKey(ClavesAQueVenta.fila('v-39'));
      final otra = find.byKey(ClavesAQueVenta.fila('v-31'));
      expect(
        tester.getSemantics(elegida),
        isSemantics(
          isChecked: true,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasCheckedState: true,
        ),
      );
      expect(
        tester.getSemantics(otra),
        isSemantics(
          isChecked: false,
          isInMutuallyExclusiveGroup: true,
          hasTapAction: true,
          hasCheckedState: true,
        ),
      );
      handle.dispose();
    });
  });

  group('42B·09C · la venta que crece (la pantalla de 27A·05 sobre la 0039)', () {
    final v39Larga = ventaAbierta693(
      'v-39',
      motivo: null,
      renglones: const [
        RenglonYaVendido(
          nombre: 'Colección de 3 libros de la familia con un nombre bastante largo',
          cantidad: 1,
          precioUnitarioCentavos: 120000,
          subtotalCentavos: 120000,
          esCombo: true,
          librosDelCombo: 3,
          componentes: [
            'Salud y Hogar con un título larguísimo que no entra en una línea',
            'El camino a Cristo',
            'Vida Feliz',
          ],
        ),
        RenglonYaVendido(
          nombre: 'Nuestros Hijos',
          cantidad: 2,
          precioUnitarioCentavos: 30000,
          subtotalCentavos: 60000,
        ),
      ],
    );

    Future<void> sumarSaludYHogar(WidgetTester tester) async {
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
    }

    for (final c in _matriz) {
      testWidgets('${c.nombre}: vacía, con el libro y con el monto cambiado, sin desbordes', (
        tester,
      ) async {
        await cargarFuentes693(tester);
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [v39Larga]));
        await montarNuevaVenta(
          tester,
          e,
          creceSobre: v39Larga,
          escala: c.escala,
          tamano: c.tamano,
          cliente: maria,
        );
        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        await capturarPantalla693(
          tester,
          '09C_vacia_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );

        await sumarSaludYHogar(tester);
        expect(tester.takeException(), isNull);
        await verVisible(tester, find.byKey(const Key('venta_saldo')));
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        expect(find.byKey(const Key('venta_cta')).hitTestable(), findsOneWidget);
        await capturarPantalla693(
          tester,
          '09C_conLibro_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );

        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
        expect(tester.takeException(), isNull);
        expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
        expect(find.byKey(const Key('venta_cta')).hitTestable(), findsOneWidget);
        await capturarPantalla693(
          tester,
          '09C_monto_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
      });
    }

    testWidgets('textos larguísimos del cliente y la dirección no desbordan a 320×568 ×2', (
      tester,
    ) async {
      await cargarFuentes693(tester);
      final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [v39Larga]));
      await montarNuevaVenta(
        tester,
        e,
        creceSobre: v39Larga,
        escala: 2,
        tamano: const Size(320, 568),
        cliente: const ClienteDeLaVentaLargo().cliente,
      );
      await sumarSaludYHogar(tester);

      expect(tester.takeException(), isNull);
      expect(textosFueraDeLaPantalla693(tester, const Size(320, 568)), isEmpty);
    });

    testWidgets('lo ya vendido puede ser mucho (12 renglones): se llega al total y al botón', (
      tester,
    ) async {
      await cargarFuentes693(tester);
      final muchos = ventaAbierta693(
        'v-39',
        renglones: [
          for (var i = 0; i < 12; i++)
            RenglonYaVendido(
              nombre: 'Libro $i',
              cantidad: 1,
              precioUnitarioCentavos: 10000,
              subtotalCentavos: 10000,
            ),
        ],
      );
      final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [muchos]));
      await montarNuevaVenta(tester, e, creceSobre: muchos, escala: 2, tamano: telefonoChico693);
      await sumarSaludYHogar(tester);
      await verVisible(tester, find.byKey(const Key('venta_saldo')));

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('venta_cta')).hitTestable(), findsOneWidget);
    });

    testWidgets(
      'si falla el guardado con una excepción, el botón vuelve y el libro sigue cargado',
      (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39])..lanzarAlSumar = StateError('base cerrada');
        final e = EntornoDeVenta(crece: repo);
        final salida = await montarNuevaVenta(tester, e, creceSobre: _v39);
        await sumarSaludYHogar(tester);

        await tocar(tester, find.byKey(const Key('venta_cta')));

        expect(find.text(TextosVenta.errorAlGuardar), findsOneWidget);
        expect(
          find.text(TextosVentaQueCrece.nuevo),
          findsOneWidget,
          reason: 'lo cargado no se pierde',
        );
        expect(
          tester.widget<FilledButton>(find.byKey(const Key('venta_cta'))).onPressed,
          isNotNull,
        );
        expect(salida.cerrada, isFalse);

        repo.lanzarAlSumar = null;
        await tocar(tester, find.byKey(const Key('venta_cta')));
        expect(salida.guardada, isA<VentaQueCrecio>());
        expect(repo.sumas, hasLength(2));
        expect(
          repo.sumas[0].items.first.id,
          repo.sumas[1].items.first.id,
          reason: 'mismo id: idempotente',
        );
      },
    );

    for (final c in _matriz.where((c) => c.escala == 2)) {
      testWidgets('${c.nombre}: el aviso de «No pudimos guardar» queda a la vista junto al botón', (
        tester,
      ) async {
        await cargarFuentes693(tester);
        final repo = VentasAbiertasQA(abiertas: [v39Larga])
          ..respuestas.add(const FailureVentaNoGuardada());
        final e = EntornoDeVenta(crece: repo);
        await montarNuevaVenta(tester, e, creceSobre: v39Larga, escala: c.escala, tamano: c.tamano);
        await sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));

        await capturarPantalla693(
          tester,
          '09C_errorGuardar_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
        );
        final aviso = find.byKey(const Key('venta_error'));
        expect(aviso, findsOneWidget);
        final r = tester.getRect(aviso);
        expect(
          r.top >= 0 && r.bottom <= c.tamano.height,
          isTrue,
          reason: 'el aviso rojo tiene que verse (queda en $r de ${c.tamano})',
        );
      });
    }

    testWidgets(
      '«venta cerrada» mientras se sumaba: dice qué hacer y no se puede salir sin salida',
      (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39])
          ..respuestas.add(const FailureVentaCerrada(numeroTalonario: '0039'));
        final e = EntornoDeVenta(crece: repo);
        final salida = await montarNuevaVenta(tester, e, creceSobre: _v39);
        await sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));

        expect(find.textContaining('Registrá el libro como una venta nueva'), findsOneWidget);
        // La salida: ✕ pregunta y deja salir, sin perder la venta.
        await tocar(tester, find.byKey(const Key('venta_atras')));
        await tocar(tester, find.text(TextosVenta.salirSalir));
        expect(salida.cerrada, isTrue);
        expect(salida.guardada, isNull);
      },
    );

    testWidgets(
      'tras «venta cerrada» el botón no debe decir «Reintentar»: reintentar no puede andar',
      (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39])
          ..respuestas.add(const FailureVentaCerrada(numeroTalonario: '0039'));
        final e = EntornoDeVenta(crece: repo);
        await montarNuevaVenta(tester, e, creceSobre: _v39);
        await sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cta')));

        expect(find.text(TextosVenta.reintentar), findsNothing);
        // Decisión del 11/11 (P1 del QA): el botón dice «Volver».
        expect(find.text(TextosVenta.volver), findsOneWidget);
      },
    );

    testWidgets('«venta cerrada»: «Volver» sale sin preguntar, sin sumar nada ni trabarse', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39])
        ..respuestas.addAll(const [
          FailureVentaCerrada(numeroTalonario: '0039'),
          FailureVentaCerrada(numeroTalonario: '0039'),
        ]);
      final e = EntornoDeVenta(crece: repo);
      final salida = await montarNuevaVenta(tester, e, creceSobre: _v39);
      await sumarSaludYHogar(tester);

      await tocar(tester, find.byKey(const Key('venta_cta')));
      expect(find.textContaining('Registrá el libro como una venta nueva'), findsOneWidget);
      // Decisión del 11/11 (P1 del QA): el segundo toque es «Volver», sin la pregunta de salir.
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text(TextosVenta.salirTitulo), findsNothing);
      expect(salida.cerrada, isTrue);
      expect(salida.guardada, isNull);
      expect(repo.sumas, hasLength(1));
    });

    testWidgets('con la venta anulada o con todo devuelto el aviso no dice «pagada y entregada»', (
      tester,
    ) async {
      // El mismo `FailureVentaCerrada` sirve para pagada y entregada, anulada y devuelta entera.
      const f = FailureVentaCerrada(numeroTalonario: '0039');

      expect(f.mensaje, isNot(contains('pagada y entregada')));
      expect(f.mensaje, contains('ya está cerrada'));
    });

    group('entradas del monto de lo que se suma', () {
      Future<EntornoDeVenta> abrirConMonto(WidgetTester tester) async {
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
        await montarNuevaVenta(tester, e, creceSobre: _v39);
        await sumarSaludYHogar(tester);
        await tocar(tester, find.byKey(const Key('venta_cambiar_monto')));
        return e;
      }

      Finder campo(String clave) =>
          find.descendant(of: find.byKey(Key(clave)), matching: find.byType(TextField));
      bool habilitado(WidgetTester tester) =>
          tester.widget<FilledButton>(find.byKey(const Key('venta_cta'))).onPressed != null;

      testWidgets('monto vacío, solo letras o solo espacios: el botón queda apagado', (
        tester,
      ) async {
        await abrirConMonto(tester);

        for (final t in ['', 'abc', '   ', '--', '1,5,5']) {
          await escribir(tester, campo('venta_monto'), t);
          await escribir(tester, campo('venta_motivo'), 'por pago en efectivo');
          expect(habilitado(tester), isFalse, reason: 'monto «$t» no es un monto válido');
        }
      });

      testWidgets('motivo vacío o solo espacios: apagado; con texto: encendido', (tester) async {
        await abrirConMonto(tester);
        await escribir(tester, campo('venta_monto'), '1.500');

        for (final t in ['', '   ', '\n\t ']) {
          await escribir(tester, campo('venta_motivo'), t);
          expect(habilitado(tester), isFalse, reason: 'motivo «${t.trim()}» vacío');
        }
        await escribir(tester, campo('venta_motivo'), 'descuento 🎁 por pago en efectivo');
        expect(habilitado(tester), isTrue);
      });

      testWidgets('un monto enorme no revienta: apaga el botón o lo acota', (tester) async {
        await abrirConMonto(tester);

        await escribir(tester, campo('venta_monto'), '99999999999999999999');
        await escribir(tester, campo('venta_motivo'), 'x');

        expect(tester.takeException(), isNull);
        expect(habilitado(tester), isFalse);
      });

      testWidgets('un motivo larguísimo (pegado) se acota y no rompe la pantalla', (tester) async {
        final e = await abrirConMonto(tester);
        await escribir(tester, campo('venta_monto'), '1.500');
        await escribir(tester, campo('venta_motivo'), 'a' * 900);

        expect(tester.takeException(), isNull);
        await tocar(tester, find.byKey(const Key('venta_cta')));
        final motivo = (e.crece as VentasAbiertasQA).sumas.single.motivo;
        expect(motivo, isNotNull);
        expect(motivo!.length, lessThanOrEqualTo(500));
      });

      testWidgets('tras un error lo tipeado no se pierde', (tester) async {
        final e = await abrirConMonto(tester);
        (e.crece as VentasAbiertasQA).respuestas.add(const FailureVentaNoGuardada());
        await escribir(tester, campo('venta_monto'), '1.500');
        await escribir(tester, campo('venta_motivo'), 'descuento del libro nuevo');

        await tocar(tester, find.byKey(const Key('venta_cta')));

        expect(find.text(TextosVenta.errorAlGuardar), findsOneWidget);
        expect(tester.widget<TextField>(campo('venta_monto')).controller!.text, isNotEmpty);
        expect(
          tester.widget<TextField>(campo('venta_motivo')).controller!.text,
          'descuento del libro nuevo',
        );
      });

      testWidgets('con el total de la venta cerca del tope, sumar un libro lo dice y no guarda', (
        tester,
      ) async {
        final casiTope = ventaAbierta693('v-39', total: 2147400000, cobrado: 0);
        final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [casiTope]));
        final salida = await montarNuevaVenta(tester, e, creceSobre: casiTope);
        await sumarSaludYHogar(tester);

        await tocar(tester, find.byKey(const Key('venta_cta')));

        expect(salida.guardada, isNull);
        expect((e.crece as VentasAbiertasQA).sumas, isEmpty);
        expect(find.byKey(const Key('venta_error')), findsOneWidget);
      });
    });

    testWidgets('con la campaña terminada no se suma: lo dice y deja volver', (tester) async {
      final e = EntornoDeVenta(
        crece: VentasAbiertasQA(abiertas: [_v39]),
        precios: SinCampaniaVigente(
          terminada: CampaniaTerminada(nombre: 'Primavera 2026', terminoEl: DateTime(2026, 12, 15)),
        ),
      );
      final salida = await montarNuevaVenta(tester, e, creceSobre: _v39);

      expect(find.text('Primavera 2026 terminó el 15/12'), findsOneWidget);
      expect(find.text('Sumar a la venta 0039'), findsNothing);
      await tocar(tester, find.text('Volver'));
      expect(salida.cerrada, isTrue);
      expect((e.crece as VentasAbiertasQA).sumas, isEmpty);
    });

    testWidgets('sin los precios del teléfono lo dice y deja reintentar (no se suma nada)', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
      e.fuente.fallas = 1;
      await montarNuevaVenta(tester, e, creceSobre: _v39);

      expect(find.text(TextosVenta.errorPrecios), findsOneWidget);
      await tocar(tester, find.text(TextosVenta.reintentar));
      await sumarSaludYHogar(tester);
      expect(find.byKey(const Key('venta_cta')), findsOneWidget);
    });

    testWidgets('✕ mientras se guarda no saca ni pregunta (la suma ya se está yendo a la base)', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39])..compuerta = Completer<void>();
      final e = EntornoDeVenta(crece: repo);
      final salida = await montarNuevaVenta(tester, e, creceSobre: _v39);
      await sumarSaludYHogar(tester);
      await verVisible(tester, find.byKey(const Key('venta_cta')));
      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.pump();

      await tester.tap(find.byKey(const Key('venta_atras')), warnIfMissed: false);
      await tester.pump();
      expect(find.text(TextosVentaQueCrece.salirTitulo), findsNothing);
      expect(salida.cerrada, isFalse);

      repo.compuerta!.complete();
      await asentar693(tester);
      expect(salida.guardada, isA<VentaQueCrecio>());
      expect(repo.sumas, hasLength(1));
    });

    testWidgets('mientras guarda no se puede agregar otro libro ni quitar el cargado', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39])..compuerta = Completer<void>();
      final e = EntornoDeVenta(crece: repo);
      await montarNuevaVenta(tester, e, creceSobre: _v39);
      await sumarSaludYHogar(tester);
      await verVisible(tester, find.byKey(const Key('venta_cta')));
      await tester.tap(find.byKey(const Key('venta_cta')));
      await tester.pump();

      await tester.tap(find.text(TextosVenta.agregar), warnIfMissed: false);
      await tester.pump();
      final quitar = find.byTooltip(TextosVenta.quitar);
      if (quitar.evaluate().isNotEmpty) {
        await tester.tap(quitar.first, warnIfMissed: false);
        await tester.pump();
      }
      repo.compuerta!.complete();
      await asentar693(tester);

      expect(repo.sumas, hasLength(1));
      expect(repo.sumas.single.items, hasLength(1), reason: 'se suma lo que se vio al tocar');
    });

    testWidgets('«Agregar» más libros suma al mismo renglón de la venta y el total los cuenta', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39]);
      final e = EntornoDeVenta(crece: repo);
      await montarNuevaVenta(tester, e, creceSobre: _v39);
      await sumarSaludYHogar(tester);
      await tocar(tester, find.text(TextosVenta.agregar));
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Vida sin estrés'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));

      expect(find.text(TextosVentaQueCrece.nuevo), findsNWidgets(2));
      await tocar(tester, find.byKey(const Key('venta_cta')));
      expect(repo.sumas.single.items, hasLength(2));
      expect(repo.sumas.single.items.map((i) => i.id).toSet(), hasLength(2));
      expect(repo.sumas.single.sumado, 200000 + 200002);
    });
  });

  group('42B·09D · cierre «Libro sumado a la venta 0039»', () {
    Future<List<SeguimientoDeLaVenta?>> montarCierre(
      WidgetTester tester, {
      String? cuotas,
      double escala = 1,
      Size tamano = const Size(390, 844),
      bool conCobro = true,
      bool conAhora = true,
      bool conOtroDia = true,
      String nombre = 'Pedro Gómez',
      int unidades = 1,
    }) async {
      await cargarFuentes693(tester);
      tester.view.physicalSize = tamano;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final salidas = <SeguimientoDeLaVenta?>[];
      final guardada = VentaQueCrecio(
        venta: ventaDe('v-39', talonario: '0039', monto: 160000),
        items: [itemDe('n-1', 'v-39', cantidad: unidades, precio: 40000)],
        totalAnteriorCentavos: 120000,
        sumadoEl: DateTime.utc(2026, 11, 11),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: RepaintBoundary(key: raiz693, child: child!),
          ),
          home: VentaRegistradaPage(
            guardada: guardada,
            nombreDelCliente: nombre,
            conEntregarAhora: conAhora,
            conEntregarOtroDia: conOtroDia,
            conCobro: conCobro,
            crece: TextosDelCierreQueCrece(
              eyebrow: TextosVentaQueCrece.eyebrowCierre('0039'),
              titulo: TextosVentaQueCrece.tituloCierre('0039', unidades),
              subtitulo: TextosVentaQueCrece.subtituloCierre(nombre, 160000, 120000),
              rotuloEntrega: TextosVentaQueCrece.entregaDelLibroNuevo,
              detalleCobro: TextosVentaQueCrece.saldoDeLaVenta(120000),
              detalleModificarCuotas: cuotas,
            ),
            alContinuar: salidas.add,
            alTerminar: () => salidas.add(null),
          ),
        ),
      );
      await asentar693(tester);
      return salidas;
    }

    for (final c in _matriz) {
      testWidgets('${c.nombre}: con y sin «Modificar cuotas», sin desbordes y con botones a mano', (
        tester,
      ) async {
        for (final cuotas in [null, TextosVentaQueCrece.modificarCuotasSub(120000)]) {
          await montarCierre(tester, escala: c.escala, tamano: c.tamano, cuotas: cuotas);
          expect(tester.takeException(), isNull);
          expect(textosFueraDeLaPantalla693(tester, c.tamano), isEmpty);
          expect(find.text(TextosVenta.continuar).hitTestable(), findsOneWidget);
          expect(find.text(TextosVenta.terminarSinNada).hitTestable(), findsOneWidget);
          await capturar693(
            tester,
            '09D_${cuotas == null ? 'sin' : 'con'}Cuotas_${c.tamano.width.toInt()}_x${c.escala.toInt()}',
          );
        }
      });
    }

    testWidgets('en plural dice «Libros sumados a la venta 0039»', (tester) async {
      await montarCierre(tester, unidades: 3);

      expect(find.text('Libros sumados a la venta 0039'), findsOneWidget);
    });

    testWidgets('con un nombre larguísimo el subtítulo no desborda a 320×568 ×2', (tester) async {
      await montarCierre(
        tester,
        nombre: 'Maximiliano Alejandro Fernández de la Santísima Trinidad',
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(textosFueraDeLaPantalla693(tester, const Size(320, 568)), isEmpty);
    });

    testWidgets(
      '«Terminar sin entregar ni cobrar» termina una sola vez aunque se toque dos veces',
      (tester) async {
        final salidas = await montarCierre(tester);

        await tester.tap(find.text(TextosVenta.terminarSinNada));
        await tester.tap(find.text(TextosVenta.terminarSinNada), warnIfMissed: false);
        await tester.pump();

        expect(salidas, hasLength(1));
        expect(salidas.single, isNull);
      },
    );

    testWidgets('sin entrega ni cobro posibles queda la confirmación con un solo botón', (
      tester,
    ) async {
      final salidas = await montarCierre(
        tester,
        conCobro: false,
        conAhora: false,
        conOtroDia: false,
      );

      expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      expect(find.text(TextosVenta.continuar), findsNothing);
      expect(salidas, isEmpty);
    });

    testWidgets('con cuotas pero sin cobro posible, «Modificar cuotas» se ofrece sola', (
      tester,
    ) async {
      final salidas = await montarCierre(
        tester,
        conCobro: false,
        conAhora: false,
        conOtroDia: false,
        cuotas: TextosVentaQueCrece.modificarCuotasSub(120000),
      );

      await tester.tap(find.byKey(const Key('venta_modificar_cuotas')));
      await tester.pump();
      await tester.tap(find.text(TextosVenta.continuar));
      await tester.pump();

      expect(salidas.single?.modificarCuotas, isTrue);
      expect(salidas.single?.cobrarAhora, isFalse);
    });

    testWidgets('el atrás del sistema no sale de 09D (se sale con «Continuar» o «Terminar»)', (
      tester,
    ) async {
      final salidas = await montarCierre(tester);

      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      expect(salidas, isEmpty);
    });
  });

  group('El recorrido desde la casa (FlujoVentaQueCrece)', () {
    Future<List<Object?>> abrirDesdeLaCasa(
      WidgetTester tester,
      EntornoDeVenta e, {
      Future<bool> Function(ContextoDeCobroDeLaVenta)? cobrar,
    }) async {
      final salidas = <Object?>[];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...e.overrides,
            if (cobrar != null) cobrarDespuesDeLaVentaProvider.overrideWithValue(cobrar),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: TextButton(
                    onPressed: () async => salidas.add(
                      await FlujoVentaQueCrece.abrir(context, (
                        ubicacionId: 'ub-1',
                        espacioId: 'esp-1',
                        personaId: 'per-1',
                      ), colportorId: 'col-1'),
                    ),
                    child: const Text('sumar'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('sumar'));
      await asentar693(tester);
      return salidas;
    }

    testWidgets('si la lectura de las ventas no llega en 3 s lo dice y no abre nada', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39])..compuertaLectura = Completer<void>();
      final salidas = await abrirDesdeLaCasa(tester, EntornoDeVenta(crece: repo));
      expect(salidas, isEmpty, reason: 'sigue esperando la lectura');

      await tester.pump(const Duration(seconds: 4));
      await asentar693(tester);

      expect(find.text(TextosVentaQueCrece.noPudimosLeer), findsOneWidget);
      expect(salidas.single, isFalse);
    });

    testWidgets('con varias ventas elige otra que la reciente y suma a esa', (tester) async {
      final repo = VentasAbiertasQA(abiertas: [_v31, _v39]);
      final e = EntornoDeVenta(crece: repo);
      await abrirDesdeLaCasa(tester, e);

      expect(find.text(TextosVentaQueCrece.aQueVenta), findsOneWidget);
      await tester.tap(find.byKey(ClavesAQueVenta.fila('v-31')));
      await tester.pump();
      await tester.tap(find.byKey(ClavesAQueVenta.sumar));
      await asentar693(tester);
      expect(find.text('VENTA 0031 · SUMAR UN LIBRO'), findsOneWidget);
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(repo.sumas.single.ventaId, 'v-31');
    });

    testWidgets('con una sola, sin cita de nada: el cierre ofrece entregar otro día y cobrar', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39]);
      final e = EntornoDeVenta(crece: repo);
      await abrirDesdeLaCasa(tester, e, cobrar: (_) async => false);
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      expect(find.text(TextosVenta.entregarOtroDia), findsOneWidget);
      expect(find.text(r'Saldo de la venta: $ 2.800'), findsOneWidget);
      expect(find.text(TextosVentaQueCrece.entregaDelLibroNuevo), findsOneWidget);
    });

    testWidgets('el aviso del mapa dice el saldo nuevo y el flujo devuelve la casa libre', (
      tester,
    ) async {
      final repo = VentasAbiertasQA(abiertas: [_v39], citas: (cobranzaAgendada: true));
      final e = EntornoDeVenta(crece: repo);
      final salidas = await abrirDesdeLaCasa(tester, e);
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await tocar(tester, find.byKey(const Key('venta_cta')));
      await tocar(tester, find.byKey(const Key('venta_terminar')));
      // Sin entregar el libro nuevo, se pide su fecha (27C·01, «Entrega cita» #706): se vuelve sin
      // elegirla.
      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(find.text(r'Libro sumado a la venta 0039. Saldo $ 2.800.'), findsOneWidget);
      expect(salidas.single, isA<VentaRegistradaEnLaCasa>());
    });

    testWidgets(
      '«Cobrar ahora» abre el cobro con la venta que creció y la persona (no una venta nueva)',
      (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39], citas: (cobranzaAgendada: true));
        final e = EntornoDeVenta(crece: repo);
        final contextos = <ContextoDeCobroDeLaVenta>[];
        await abrirDesdeLaCasa(
          tester,
          e,
          cobrar: (c) async {
            contextos.add(c);
            return false;
          },
        );
        await tocar(tester, find.text('Libros'));
        await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
        await tocar(tester, find.text(TextosVenta.agregarALaVenta));
        await tocar(tester, find.byKey(const Key('venta_cta')));

        await tocar(tester, find.text(TextosVenta.cobrarAhora));
        await tocar(tester, find.text(TextosVenta.continuar));

        expect(contextos, hasLength(1));
        expect(contextos.single.ventaId, 'v-39');
        expect(contextos.single.espacioId, 'esp-1');
        expect(contextos.single.colportorId, 'col-1');
        // El cobro no se hizo (false): vuelve a «¿y ahora?» sin perder la venta que creció.
        expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      },
    );

    testWidgets(
      'si el cobro se hizo pero no se puede leer el saldo, el aviso no dice un saldo mayor al que se debe',
      (tester) async {
        final repo = VentasAbiertasQA(abiertas: [_v39], citas: (cobranzaAgendada: true));
        final e = EntornoDeVenta(crece: repo);
        await abrirDesdeLaCasa(tester, e, cobrar: (_) async => true);
        await tocar(tester, find.text('Libros'));
        await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
        await tocar(tester, find.text(TextosVenta.agregarALaVenta));
        await tocar(tester, find.byKey(const Key('venta_cta')));
        await tocar(tester, find.text(TextosVenta.cobrarAhora));
        await tocar(tester, find.text(TextosVenta.continuar));

        // Debía $ 2.800 (total $ 3.200 menos lo pagado $ 400): nunca más que eso.
        expect(find.textContaining(r'Saldo $ 3.200'), findsNothing);
      },
      // skip: QA #693 - con el cobro hecho y el saldo ilegible el aviso del mapa dice el total de la venta en vez del saldo (menor)
      skip: !_conHallazgos,
    );

    testWidgets('si no hay sesión (sin colportor) lanza en vez de abrir una venta sin dueño', (
      tester,
    ) async {
      final e = EntornoDeVenta(crece: VentasAbiertasQA(abiertas: [_v39]));
      Object? lanzado;
      await tester.pumpWidget(
        ProviderScope(
          overrides: e.overrides,
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  try {
                    await FlujoVentaQueCrece.abrir(context, (
                      ubicacionId: 'ub-1',
                      espacioId: 'esp-1',
                      personaId: 'per-1',
                    ), colportorId: '  ');
                  } on Object catch (x) {
                    lanzado = x;
                  }
                },
                child: const Text('sumar'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('sumar'));
      await asentar693(tester);

      expect(lanzado, isA<StateError>());
    });
  });
}

/// Un cliente con nombre y dirección larguísimos para los textos límite.
final class ClienteDeLaVentaLargo {
  const ClienteDeLaVentaLargo();

  ClienteDeLaVenta get cliente => const ClienteDeLaVenta(
    espacioPersonaId: 'ep-1',
    nombre: 'Maximiliano Alejandro Fernández de la Santísima Trinidad',
    direccion: 'Avenida Doctor Luis Alberto de Herrera 3307 bis · Depto 12B · Torre Norte',
  );
}

/// El contexto de la hoja con la persona destacada con [nombre] (para los textos largos).
ContextoDeLaCasa _contextoConNombre(String nombre) => ContextoDeLaCasa(
  espacioId: 'esp-1',
  personas: [clienteDePersonas('p-pedro', nombre)],
  saldosCentavos: const {'p-pedro': 80000},
);
