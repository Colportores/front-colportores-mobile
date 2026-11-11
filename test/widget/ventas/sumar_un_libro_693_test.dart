// «Venta crece» (vista 42, 42B·09A, 09B y 09D; HU-VEN-001, #693): la fila «Sumar un libro», «¿A qué
// venta lo sumás?», el cierre «Libro sumado a la venta 0039» y el recorrido entero desde la casa.
// Casos límite: sin venta abierta (se cerró mientras tanto), lectura que falla, cancelar, doble toque,
// la más reciente elegida, entrega ya agendada de antes, cobranza ya agendada y texto al 200 %.
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/presentation/flujo_venta_que_crece.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show VentaRegistradaEnLaCasa;
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/venta_registrada_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:colportores_mobile/features/ventas/presentation/textos_venta_que_crece.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/fila_sumar_un_libro.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_a_que_venta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/venta_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

VentaAbierta _venta(
  String id, {
  required String numero,
  required DateTime fecha,
  int total = 120000,
  int cobrado = 40000,
  bool entregada = true,
  String descripcion = 'Colección de 1 libro',
}) => VentaAbierta(
  ventaId: id,
  espacioPersonaId: 'ep-1',
  numeroTalonario: numero,
  fecha: fecha,
  montoTotalCentavos: total,
  cobradoCentavos: cobrado,
  entregada: entregada,
  descripcion: descripcion,
);

final _v39 = _venta('v-39', numero: '0039', fecha: DateTime.utc(2026, 10, 23, 15));
final _v31 = _venta(
  'v-31',
  numero: '0031',
  fecha: DateTime.utc(2026, 10, 12, 15),
  total: 24000,
  cobrado: 0,
  descripcion: 'Vida Feliz × 2',
);

Future<void> _montar(
  WidgetTester tester,
  Widget hijo, {
  required List<Override> overrides,
  double escala = 1,
  Size tamano = const Size(390, 844),
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Scaffold(body: hijo),
      ),
    ),
  );
  await asentar(tester);
}

void main() {
  group('42B·09A «Sumar un libro»', () {
    testWidgets('con una venta abierta dice a cuál se suma, sin otro talonario', (tester) async {
      var tocada = 0;
      await _montar(
        tester,
        FilaSumarUnLibro(personaId: 'per-1', nombre: 'Pedro', alTocar: () => tocada++),
        overrides: [
          ventaQueCreceRepositoryProvider.overrideWithValue(
            VentaQueCreceEnMemoria(abiertas: [_v39]),
          ),
        ],
      );

      expect(find.text(TextosVentaQueCrece.sumarUnLibro), findsOneWidget);
      expect(find.text('A la venta 0039 de Pedro, sin otro talonario'), findsOneWidget);
      await tester.tap(find.byKey(ClavesSumarUnLibro.tocar));
      expect(tocada, 1);
    });

    testWidgets('con varias no nombra una: se elige después', (tester) async {
      await _montar(
        tester,
        FilaSumarUnLibro(personaId: 'per-1', nombre: 'Pedro', alTocar: () {}),
        overrides: [
          ventaQueCreceRepositoryProvider.overrideWithValue(
            VentaQueCreceEnMemoria(abiertas: [_v39, _v31]),
          ),
        ],
      );

      expect(find.text(TextosVentaQueCrece.aUnaDeSusVentas('Pedro')), findsOneWidget);
    });

    testWidgets('sin venta abierta, si no se puede leer o sin destino, no se dibuja', (
      tester,
    ) async {
      final repo = VentaQueCreceEnMemoria();
      await _montar(
        tester,
        FilaSumarUnLibro(personaId: 'per-1', nombre: 'Pedro', alTocar: () {}),
        overrides: [ventaQueCreceRepositoryProvider.overrideWithValue(repo)],
      );
      expect(find.byKey(ClavesSumarUnLibro.fila), findsNothing);

      repo.errorAlLeer = StateError('sin base');
      await _montar(
        tester,
        FilaSumarUnLibro(
          key: const Key('otra'),
          personaId: 'per-2',
          nombre: 'Pedro',
          alTocar: () {},
        ),
        overrides: [ventaQueCreceRepositoryProvider.overrideWithValue(repo)],
      );
      expect(find.byKey(ClavesSumarUnLibro.fila), findsNothing);

      await _montar(
        tester,
        const FilaSumarUnLibro(personaId: 'per-1', nombre: 'Pedro', alTocar: null),
        overrides: [
          ventaQueCreceRepositoryProvider.overrideWithValue(
            VentaQueCreceEnMemoria(abiertas: [_v39]),
          ),
        ],
      );
      expect(find.byKey(ClavesSumarUnLibro.fila), findsNothing);
    });

    testWidgets('ocupada (otra acción en curso) no se toca', (tester) async {
      var tocada = 0;
      await _montar(
        tester,
        FilaSumarUnLibro(
          personaId: 'per-1',
          nombre: 'Pedro',
          alTocar: () => tocada++,
          ocupada: true,
        ),
        overrides: [
          ventaQueCreceRepositoryProvider.overrideWithValue(
            VentaQueCreceEnMemoria(abiertas: [_v39]),
          ),
        ],
      );

      await tester.tap(find.byKey(ClavesSumarUnLibro.tocar));
      expect(tocada, 0);
    });

    testWidgets('al 200 % en un teléfono chico se lee entera, sin desbordes', (tester) async {
      await _montar(
        tester,
        FilaSumarUnLibro(personaId: 'per-1', nombre: 'Pedro', alTocar: () {}),
        overrides: [
          ventaQueCreceRepositoryProvider.overrideWithValue(
            VentaQueCreceEnMemoria(abiertas: [_v39]),
          ),
        ],
        escala: 2,
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('A la venta 0039 de Pedro, sin otro talonario'), findsOneWidget);
    });
  });

  group('42B·09B «¿A qué venta lo sumás?»', () {
    Future<List<VentaAbierta?>> abrir(WidgetTester tester, {double escala = 1}) async {
      final elegidas = <VentaAbierta?>[];
      await _montar(
        tester,
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => elegidas.add(
              await mostrarHojaAQueVenta(
                context,
                ventas: [_v39, _v31],
                subtitulo: 'Pedro Gómez · Grecia 3307',
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
        overrides: const [],
        escala: escala,
        tamano: escala > 1 ? const Size(320, 568) : const Size(390, 844),
      );
      await tester.tap(find.text('abrir'));
      await asentar(tester);
      return elegidas;
    }

    testWidgets('viene elegida la más reciente; «Sumar a esta venta» la devuelve', (tester) async {
      final elegidas = await abrir(tester);

      expect(find.text(TextosVentaQueCrece.aQueVenta), findsOneWidget);
      expect(find.text('Pedro Gómez · Grecia 3307'), findsOneWidget);
      expect(find.text('Venta 0039 · 23/10'), findsOneWidget);
      expect(find.text(r'Colección de 1 libro · saldo $ 800'), findsOneWidget);
      expect(find.text(r'Vida Feliz × 2 · saldo $ 240'), findsOneWidget);
      await tester.tap(find.byKey(ClavesAQueVenta.sumar));
      await asentar(tester);

      expect(elegidas.single?.ventaId, 'v-39');
    });

    testWidgets('se puede elegir otra; un doble toque cierra una sola vez', (tester) async {
      final elegidas = await abrir(tester);

      await tester.tap(find.byKey(ClavesAQueVenta.fila('v-31')));
      await tester.pump();
      await tester.tap(find.byKey(ClavesAQueVenta.sumar));
      await tester.tap(find.byKey(ClavesAQueVenta.sumar), warnIfMissed: false);
      await asentar(tester);

      expect(elegidas, hasLength(1));
      expect(elegidas.single?.ventaId, 'v-31');
    });

    testWidgets('«Cancelar» no elige ninguna', (tester) async {
      final elegidas = await abrir(tester);

      await tester.tap(find.byKey(ClavesAQueVenta.cancelar));
      await asentar(tester);

      expect(elegidas.single, isNull);
    });

    testWidgets('el lector de pantalla lee cada opción con su saldo y su total', (tester) async {
      final handle = tester.ensureSemantics();
      await abrir(tester);

      expect(
        find.bySemanticsLabel(
          RegExp(r'^Venta 0039 · 23/10\. Colección de 1 libro · saldo \$ 800\. Total'),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('al 200 % en un teléfono chico los botones se alcanzan, sin desbordes', (
      tester,
    ) async {
      await abrir(tester, escala: 2);

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAQueVenta.sumar).hitTestable(), findsOneWidget);
    });
  });

  group('42B·09D «Libro sumado a la venta 0039»', () {
    Future<List<SeguimientoDeLaVenta?>> montarCierre(
      WidgetTester tester, {
      String? cuotas,
      double escala = 1,
    }) async {
      final salidas = <SeguimientoDeLaVenta?>[];
      final guardada = VentaQueCrecio(
        venta: ventaDe('v-39', talonario: '0039', monto: 160000),
        items: [itemDe('n-1', 'v-39', cantidad: 1, precio: 40000)],
        totalAnteriorCentavos: 120000,
        sumadoEl: DateTime.utc(2026, 11, 11),
      );
      await _montar(
        tester,
        VentaRegistradaPage(
          guardada: guardada,
          nombreDelCliente: 'Pedro Gómez',
          conEntregarAhora: true,
          conEntregarOtroDia: true,
          conCobro: true,
          crece: TextosDelCierreQueCrece(
            eyebrow: TextosVentaQueCrece.eyebrowCierre('0039'),
            titulo: TextosVentaQueCrece.tituloCierre('0039', 1),
            subtitulo: TextosVentaQueCrece.subtituloCierre('Pedro Gómez', 160000, 120000),
            rotuloEntrega: TextosVentaQueCrece.entregaDelLibroNuevo,
            detalleCobro: TextosVentaQueCrece.saldoDeLaVenta(120000),
            detalleModificarCuotas: cuotas,
          ),
          alContinuar: salidas.add,
          alTerminar: () => salidas.add(null),
        ),
        overrides: const [],
        escala: escala,
        tamano: escala > 1 ? const Size(320, 568) : const Size(390, 844),
      );
      return salidas;
    }

    testWidgets('los textos del canvas: el libro nuevo, su entrega y el cobro del saldo entero', (
      tester,
    ) async {
      await montarCierre(tester);

      expect(find.text('VENTA 0039'), findsOneWidget);
      expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      expect(find.text(r'Pedro Gómez · total $ 1.600 · saldo $ 1.200'), findsOneWidget);
      expect(find.text('ENTREGA DEL LIBRO NUEVO'), findsOneWidget);
      expect(find.text(TextosVenta.entregarAhora), findsOneWidget);
      expect(find.text(TextosVenta.entregarOtroDia), findsOneWidget);
      expect(find.text(r'Saldo de la venta: $ 1.200'), findsOneWidget);
      expect(find.text(TextosVenta.terminarSinNada), findsOneWidget);
      expect(find.byKey(const Key('venta_modificar_cuotas')), findsNothing);
    });

    testWidgets('con cuotas abiertas ofrece «Modificar cuotas» y lo devuelve elegido', (
      tester,
    ) async {
      final salidas = await montarCierre(
        tester,
        cuotas: TextosVentaQueCrece.modificarCuotasSub(120000),
      );

      await tester.tap(find.byKey(const Key('venta_modificar_cuotas')));
      await tester.pump();
      await tester.tap(find.text(TextosVenta.continuar));
      await tester.pump();

      expect(salidas.single?.modificarCuotas, isTrue);
      expect(salidas.single?.cobrarAhora, isFalse);
    });

    testWidgets('«Continuar» dos veces sigue una sola vez', (tester) async {
      final salidas = await montarCierre(tester);

      await tester.tap(find.text(TextosVenta.entregarAhora));
      await tester.pump();
      await tester.tap(find.text(TextosVenta.continuar));
      await tester.tap(find.text(TextosVenta.continuar));
      await tester.pump();

      expect(salidas, hasLength(1));
      expect(salidas.single?.entrega, MomentoDeEntrega.ahora);
    });

    testWidgets('al 200 % en un teléfono chico, sin desbordes', (tester) async {
      await montarCierre(tester, escala: 2, cuotas: TextosVentaQueCrece.modificarCuotasSub(120000));

      expect(tester.takeException(), isNull);
    });
  });

  group('El recorrido desde la casa (FlujoVentaQueCrece)', () {
    Future<List<Object?>> abrirDesdeLaCasa(WidgetTester tester, EntornoDeVenta e) async {
      final salidas = <Object?>[];
      await _montar(
        tester,
        Builder(
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
        overrides: e.overrides,
      );
      await tester.tap(find.text('sumar'));
      await asentar(tester);
      return salidas;
    }

    testWidgets('sin venta abierta (se cerró mientras tanto) lo dice y no abre nada', (
      tester,
    ) async {
      final e = EntornoDeVenta();
      final salidas = await abrirDesdeLaCasa(tester, e);

      expect(find.text(TextosVentaQueCrece.sinVentaAbierta(null)), findsOneWidget);
      expect(salidas.single, isFalse);
    });

    testWidgets('si no puede leer las ventas lo dice y no abre nada', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria()..errorAlLeer = StateError('x'));
      final salidas = await abrirDesdeLaCasa(tester, e);

      expect(find.text(TextosVentaQueCrece.noPudimosLeer), findsOneWidget);
      expect(salidas.single, isFalse);
    });

    testWidgets('con varias pregunta a cuál; «Cancelar» no suma nada', (tester) async {
      final e = EntornoDeVenta(crece: VentaQueCreceEnMemoria(abiertas: [_v31, _v39]));
      final salidas = await abrirDesdeLaCasa(tester, e);

      expect(find.text(TextosVentaQueCrece.aQueVenta), findsOneWidget);
      await tester.tap(find.byKey(ClavesAQueVenta.cancelar));
      await asentar(tester);

      expect(salidas.single, isFalse);
      expect(e.crece.sumas, isEmpty);
    });

    testWidgets('con una sola va directo: suma, «¿y ahora?» del libro nuevo y el aviso en el mapa', (
      tester,
    ) async {
      final e = EntornoDeVenta(
        crece: VentaQueCreceEnMemoria(
          abiertas: [_v39],
          // Lo de antes ya tiene su entrega y su cobranza agendadas: no se agenda otra ni se pregunta.
          citas: (cobranzaAgendada: true, entregaAgendada: true),
        ),
      );
      final salidas = await abrirDesdeLaCasa(tester, e);

      expect(find.text('VENTA 0039 · SUMAR UN LIBRO'), findsOneWidget);
      await tocar(tester, find.text('Libros'));
      await tocar(tester, find.byTooltip('Uno más de Salud y Hogar'));
      await tocar(tester, find.text(TextosVenta.agregarALaVenta));
      await tocar(tester, find.byKey(const Key('venta_cta')));

      expect(find.text('Libro sumado a la venta 0039'), findsOneWidget);
      // La entrega de lo de antes ya está agendada: el libro nuevo se entrega ahora o queda pendiente.
      expect(find.text(TextosVenta.entregarOtroDia), findsNothing);
      expect(find.text(TextosVenta.entregarAhora), findsOneWidget);

      await tocar(tester, find.byKey(const Key('venta_terminar')));

      expect(find.text(r'Libro sumado a la venta 0039. Saldo $ 2.800.'), findsOneWidget);
      expect(salidas.single, isA<VentaRegistradaEnLaCasa>());
      expect(e.crece.sumas.single.ventaId, 'v-39');
    });
  });
}
