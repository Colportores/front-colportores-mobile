// HU-VEN-003 (vista 27, grupo C, «Marcar entregado», #435): un test por artboard (27C·03 el día de la
// entrega, 27C·04 la entrega parcial y 27C·08 sin conexión), los estados que el canvas no dibuja
// (cargando, error, nada pendiente) y cada caso límite: doble toque, falla a mitad del guardado,
// acciones seguidas, volver y reentrar, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_pendiente.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/cumplir_entrega_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/marcar_entregado_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/venta_ui_falsos.dart' show asentar, tocar;

Finder get _cta => find.byKey(const Key('venta_cta'));
Finder get _campo => find.byKey(const Key('entrega_campo_fecha'));

bool _habilitado(WidgetTester tester) => tester.widget<FilledButton>(_cta).onPressed != null;

String _textoDelBoton(WidgetTester tester) {
  final texto = find.descendant(of: _cta, matching: find.byType(Text));
  return tester.widget<Text>(texto).data!;
}

/// El repositorio que explota en vez de contestar (un error que ningún `Either` previó).
class _RepoQueExplota extends EntregasEnMemoria {
  @override
  Future<Either<Failure, EntregaCumplida>> cumplir(
    String ventaId, {
    required DateTime ahora,
    required String idDeLaCita,
    Set<String>? entregaIds,
    DateTime? nuevaFecha,
  }) => throw StateError('sin base abierta');
}

Route<ResultadoCumplirEntrega> _ruta() => MarcarEntregadoPage.ruta(ventaId: 'v-1');

/// Salud y Hogar (e-1) y Nuestros Hijos (e-2), pendientes de la venta v-1.
EntregaPendiente _pendiente({DateTime? fecha}) => pendienteDe(
  'v-1',
  fecha: fecha ?? DateTime(2026, 10, 28, 16, 30),
  lineas: [lineaDe('e-1', 'p-salud'), lineaDe('e-2', 'p-hijos')],
);

EntornoDeEntrega _entorno([EntregaPendiente? pendiente]) {
  final e = EntornoDeEntrega();
  e.entregas.emitirPendientes([pendiente ?? _pendiente()]);
  e.entregas.respuestaDeCumplir = cumplidaCon();
  return e;
}

/// Elige "mañana a las 08:30" en la hoja «Día y hora» desde el campo «NUEVA FECHA».
Future<void> _elegirNuevaFecha(WidgetTester tester, {int dia = 1}) async {
  await tocar(tester, _campo);
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.tap(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.pump();
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
  await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
  await asentar(tester);
}

void main() {
  group('27C·03 El día de la entrega', () {
    testWidgets('dice la venta, la persona y qué se entrega, con todo tildado', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text('Marcar entregado'), findsNWidgets(2)); // el título y el botón
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('QUÉ ENTREGÁS'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(_textoDelBoton(tester), 'Marcar entregado');
      expect(_habilitado(tester), isTrue);
      expect(_campo, findsNothing);
    });

    testWidgets('«Marcar entregado» entrega todo lo pendiente, avisa y vuelve', (tester) async {
      final e = _entorno();
      final salida = await montarPantalla(tester, e, _ruta);

      await tocar(tester, _cta);

      final llamada = e.entregas.cumplidas.single;
      expect(llamada.ventaId, 'v-1');
      expect(llamada.entregaIds, {'e-1', 'e-2'});
      expect(llamada.nuevaFecha, isNull);
      expect(salida.cerrada, isTrue);
      expect(salida.valor, isNotNull);
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });
  });

  group('27C·04 Entrega parcial', () {
    testWidgets('destildar un libro pregunta para cuándo queda y cambia el botón', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.text('Nuestros Hijos sigue pendiente. ¿Para cuándo?'), findsOneWidget);
      expect(find.text('NUEVA FECHA'), findsOneWidget);
      expect(find.text('Sin fecha'), findsOneWidget);
      expect(_textoDelBoton(tester), 'Marcar 1 entregado');
      expect(find.byIcon(Icons.check), findsNWidgets(1));
    });

    testWidgets('con fecha nueva: entrega lo tildado y deja lo demás para esa fecha', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.respuestaDeCumplir = cumplidaCon(
        quedan: [entregaDe('e-2', 'p-hijos', pendiente: true)],
      );
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await _elegirNuevaFecha(tester);
      expect(find.text('Mañana · 08:30'), findsOneWidget);
      await tocar(tester, _cta);

      final llamada = e.entregas.cumplidas.single;
      expect(llamada.entregaIds, {'e-1'});
      expect(llamada.nuevaFecha!.isAtSameMomentAs(DateTime(2026, 10, 29, 8, 30)), isTrue);
      expect(find.text('Entrega marcada. Lo que falta sigue pendiente.'), findsOneWidget);
    });

    testWidgets('sin elegir fecha, lo que falta queda «Sin fecha»', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await tocar(tester, _cta);

      final llamada = e.entregas.cumplidas.single;
      expect(llamada.entregaIds, {'e-1'});
      expect(llamada.nuevaFecha, isNull);
    });

    testWidgets('con dos filas sin tildar el texto las nombra a las dos', (tester) async {
      final e = _entorno(
        pendienteDe(
          'v-1',
          fecha: DateTime(2026, 10, 28, 16, 30),
          lineas: [
            lineaDe('e-1', 'p-salud'),
            lineaDe('e-2', 'p-hijos'),
            lineaDe('e-3', 'p-camino'),
          ],
        ),
      );
      await montarPantalla(tester, e, _ruta);

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Salud y Hogar × 1'));

      expect(
        find.text('Salud y Hogar y Nuestros Hijos siguen pendientes. ¿Para cuándo?'),
        findsOneWidget,
      );
      expect(_textoDelBoton(tester), 'Marcar 1 entregado');
    });

    testWidgets('volver a tildar lo deja como estaba y quita la pregunta', (tester) async {
      await montarPantalla(tester, _entorno(), _ruta);

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.textContaining('¿Para cuándo?'), findsNothing);
      expect(_campo, findsNothing);
      expect(_textoDelBoton(tester), 'Marcar entregado');
    });

    testWidgets('sin nada tildado no se puede marcar y dice por qué', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, find.text('Salud y Hogar × 1'));

      expect(_habilitado(tester), isFalse);
      expect(find.text('Elegí al menos un producto para marcar como entregado.'), findsOneWidget);
      expect(_campo, findsNothing);
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();
      expect(e.entregas.cumplidas, isEmpty);
    });

    testWidgets('el campo «Nueva fecha» se lee con su valor y que se puede cambiar', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await montarPantalla(tester, _entorno(), _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.bySemanticsLabel('Nueva fecha: Sin fecha. Tocá para cambiar'), findsOneWidget);
      handle.dispose();
    });
  });

  group('27C·08 y estados que el canvas no dibuja', () {
    testWidgets('27C·08 sin conexión: marca igual en el teléfono y no menciona la señal', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);

      expect(find.textContaining('conexión'), findsNothing);
      await tocar(tester, _cta);

      expect(e.entregas.cumplidas, hasLength(1));
      expect(find.textContaining('conexión'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
    });

    testWidgets('cargando: el esqueleto dice qué pasa y no ofrece marcar', (tester) async {
      final e = EntornoDeEntrega();
      await montarPantalla(tester, e, _ruta);

      expect(find.byKey(const Key('marcar_cargando')), findsOneWidget);
      expect(_cta, findsNothing);

      e.entregas.emitirPendientes([_pendiente()]);
      await asentar(tester);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('no se puede leer lo pendiente: avisa y «Reintentar» lo vuelve a leer', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.errorDePendientes = StateError('no se pudo leer');
      await montarPantalla(tester, e, _ruta);

      expect(find.text('No pudimos leer tus entregas.'), findsOneWidget);
      expect(_cta, findsNothing);

      e.entregas.errorDePendientes = null;
      e.entregas.pendientesActuales = [_pendiente()];
      await tocar(tester, find.text('Reintentar'));

      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('no se pueden leer los nombres: no inventa ninguno y deja reintentar', (
      tester,
    ) async {
      final e = _entorno();
      e.fuente.fallas = 1;
      await montarPantalla(tester, e, _ruta);

      expect(find.text('No pudimos leer qué se vendió. Probá de nuevo.'), findsOneWidget);
      expect(find.textContaining('Producto sin nombre'), findsNothing);
      expect(_cta, findsNothing);

      await tocar(tester, find.text('Reintentar'));

      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('si la venta ya no tiene nada pendiente, lo dice y no entrega de nuevo', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.emitirPendientes(const []);
      await montarPantalla(tester, e, _ruta);

      expect(find.text('Esta venta no tiene nada pendiente de entregar.'), findsOneWidget);
      expect(_cta, findsNothing);
      expect(e.entregas.cumplidas, isEmpty);
    });

    testWidgets('si el repositorio dice que ya estaba entregada, lo avisa sin alarmar', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.respuestaDeCumplir = cumplidaCon(yaEstaba: true);
      await montarPantalla(tester, e, _ruta);

      await tocar(tester, _cta);

      expect(find.text('Esa entrega ya estaba marcada como entregada.'), findsOneWidget);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en «Marcar entregado»: se marca una sola vez', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      e.entregas.compuertaDeDiferida = Completer<void>();

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();

      expect(e.entregas.cumplidas, hasLength(1));

      e.entregas.compuertaDeDiferida!.complete();
      await asentar(tester);

      expect(e.entregas.cumplidas, hasLength(1));
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });

    testWidgets('mientras se guarda: el botón no responde, las filas tampoco y no se sale', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      e.entregas.compuertaDeDiferida = Completer<void>();

      await tester.tap(_cta);
      await tester.pump();

      expect(_habilitado(tester), isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('venta_atras')), findsNothing);
      await tester.tap(find.text('Nuestros Hijos × 1'), warnIfMissed: false);
      await tester.pump();
      expect(find.textContaining('¿Para cuándo?'), findsNothing);

      e.entregas.compuertaDeDiferida!.complete();
      await asentar(tester);

      // Se entregó lo que estaba tildado cuando se tocó el botón.
      expect(e.entregas.cumplidas.single.entregaIds, {'e-1', 'e-2'});
    });

    testWidgets('la lista en vivo saca la venta antes de que termine: la pantalla no parpadea', (
      tester,
    ) async {
      final e = _entorno();
      final salida = await montarPantalla(tester, e, _ruta);
      e.entregas.compuertaDeDiferida = Completer<void>();

      await tester.tap(_cta);
      await tester.pump();
      // La base ya escribió y la lista en vivo emite sin la venta; el caso de uso todavía no volvió.
      e.entregas.emitirPendientes(const []);
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.textContaining('Producto sin nombre'), findsNothing);
      expect(find.textContaining('nada pendiente'), findsNothing);

      e.entregas.compuertaDeDiferida!.complete();
      await asentar(tester);

      expect(salida.cerrada, isTrue);
      expect(find.text('Entrega marcada.'), findsOneWidget);
    });

    testWidgets('falla al guardar: el aviso, lo tildado sigue y el botón vuelve', (tester) async {
      final e = _entorno();
      e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      final salida = await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await _elegirNuevaFecha(tester);

      await tocar(tester, _cta);

      expect(find.textContaining('No pudimos guardar la entrega en tu teléfono'), findsOneWidget);
      expect(_textoDelBoton(tester), 'Reintentar');
      expect(_habilitado(tester), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byIcon(Icons.check), findsNWidgets(1));
      expect(find.text('Mañana · 08:30'), findsOneWidget);
      expect(salida.cerrada, isFalse);

      await tocar(tester, _cta);

      expect(e.entregas.cumplidas, hasLength(2));
      expect(e.entregas.cumplidas.last.entregaIds, {'e-1'});
      expect(salida.cerrada, isTrue);
    });

    testWidgets('una excepción que nadie previó también deja reintentar', (tester) async {
      final e = EntornoDeEntrega(entregas: _RepoQueExplota());
      e.entregas.emitirPendientes([_pendiente()]);
      await montarPantalla(tester, e, _ruta);

      await tocar(tester, _cta);

      expect(find.textContaining('No pudimos guardar la entrega'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('tocar una fila después de un error limpia el aviso', (tester) async {
      final e = _entorno();
      e.entregas.fallasAlCumplir.add(const FailureEntregaNoGuardada());
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, _cta);
      expect(find.textContaining('No pudimos guardar'), findsOneWidget);

      await tocar(tester, find.text('Nuestros Hijos × 1'));

      expect(find.textContaining('No pudimos guardar'), findsNothing);
      expect(_textoDelBoton(tester), 'Marcar 1 entregado');
    });

    testWidgets('destildar, tildar y destildar seguido termina con lo último que se tocó', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);

      await tester.tap(find.text('Nuestros Hijos × 1'));
      await tester.tap(find.text('Salud y Hogar × 1'));
      await tester.tap(find.text('Nuestros Hijos × 1'));
      await tester.pump();
      await tester.tap(find.text('Salud y Hogar × 1'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tocar(tester, _cta);
      expect(e.entregas.cumplidas.single.entregaIds, {'e-1', 'e-2'});
    });

    testWidgets('elegir la fecha dos veces seguidas deja la última', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await _elegirNuevaFecha(tester);
      await _elegirNuevaFecha(tester, dia: 3);
      await tocar(tester, _cta);

      expect(e.entregas.cumplidas.single.nuevaFecha!.day, 31);
    });

    testWidgets('si se tilda de nuevo todo, la fecha elegida no se manda', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await _elegirNuevaFecha(tester);

      await tocar(tester, find.text('Nuestros Hijos × 1'));
      await tocar(tester, _cta);

      expect(e.entregas.cumplidas.single.entregaIds, {'e-1', 'e-2'});
      expect(e.entregas.cumplidas.single.nuevaFecha, isNull);
    });

    testWidgets('volver sin marcar y reentrar: no se marcó nada y arranca todo tildado', (
      tester,
    ) async {
      final e = _entorno();
      final salida = await montarPantalla(tester, e, _ruta);
      await tocar(tester, find.text('Nuestros Hijos × 1'));

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(salida.cerrada, isTrue);
      expect(salida.valor, isNull);
      expect(e.entregas.cumplidas, isEmpty);

      await abrirPantalla(tester);

      expect(find.byIcon(Icons.check), findsNWidgets(2));
      expect(_textoDelBoton(tester), 'Marcar entregado');
    });

    testWidgets('marcar, volver y reentrar: la venta ya no figura y no se entrega dos veces', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(tester, e, _ruta);
      await tocar(tester, _cta);
      e.entregas.emitirPendientes(const []);

      await abrirPantalla(tester);

      expect(find.text('Esta venta no tiene nada pendiente de entregar.'), findsOneWidget);
      expect(_cta, findsNothing);
      expect(e.entregas.cumplidas, hasLength(1));
    });

    testWidgets('40 productos con nombres largos: se recorre la lista y se llega al botón', (
      tester,
    ) async {
      final e = EntornoDeEntrega();
      e.entregas.emitirPendientes([
        pendienteDe(
          'v-1',
          fecha: DateTime(2026, 10, 28, 10),
          lineas: [for (var i = 0; i < 40; i++) lineaDe('e-$i', 'p-deseado', 2)],
        ),
      ]);
      e.entregas.respuestaDeCumplir = cumplidaCon();
      await montarPantalla(tester, e, _ruta, tamano: const Size(320, 568));

      expect(tester.takeException(), isNull);
      await tocar(tester, _cta);
      expect(tester.takeException(), isNull);
      expect(e.entregas.cumplidas.single.entregaIds, hasLength(40));
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'texto al ${(escala * 100).round()} % a 320 × 568: nada desborda y se alcanza todo',
        (tester) async {
          final e = _entorno();
          await montarPantalla(tester, e, _ruta, escala: escala, tamano: const Size(320, 568));

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_cta).height, greaterThanOrEqualTo(48));
          await tester.scrollUntilVisible(find.text('Nuestros Hijos × 1'), 100);
          await tocar(tester, find.text('Nuestros Hijos × 1'));
          expect(tester.takeException(), isNull);
          await tester.scrollUntilVisible(_campo, 100);
          expect(tester.getSize(_campo).height, greaterThanOrEqualTo(48));
          await _elegirNuevaFecha(tester);
          expect(tester.takeException(), isNull);
          await tocar(tester, _cta);
          expect(tester.takeException(), isNull);
          expect(e.entregas.cumplidas, hasLength(1));
        },
      );
    }
  });
}
