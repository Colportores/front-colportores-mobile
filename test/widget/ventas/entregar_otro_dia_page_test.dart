// HU-VEN-003 (vista 27, grupo C, «Entregar otro día», #435): 27C·01 con los dos accesos (la venta
// recién guardada y «Poner fecha» de la lista), los estados que el canvas no dibuja (cargando, error de
// lectura, nada que entregar, error al guardar, sin conexión) y cada caso límite: doble toque, falla a
// mitad del guardado, acciones seguidas, volver y reentrar, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/agenda/data/recordatorios/fakes/recordatorios_en_memoria.dart';
import 'package:colportores_mobile/features/agenda/presentation/providers/recordatorios_providers.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/piezas_agendar_visita.dart'
    show ClavesAgendarVisita;
import 'package:colportores_mobile/features/ventas/domain/entities/entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/entrega_diferida.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/productos_de_la_entrega.dart';
import 'package:colportores_mobile/features/ventas/domain/usecases/diferir_entrega_use_case.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/entregar_otro_dia_page.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/entrega_diferida_ui_falsos.dart';
import '../../helpers/entrega_falsos.dart';
import '../../helpers/venta_falsos.dart';
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
  Future<Either<Failure, EntregaDiferida>> diferir(
    String ventaId, {
    required DateTime fechaPrevista,
    required DateTime ahora,
    required List<Entrega> filasNuevas,
    required String idDeLaCita,
  }) => throw StateError('sin base abierta');
}

Route<ResultadoDiferirEntrega> _desdeLaVenta(VentaGuardada guardada) =>
    EntregarOtroDiaPage.ruta(guardada: guardada, nombreDelCliente: 'María Fernández');

/// Abre la hoja «Día y hora», elige el día [dia] (0 = hoy, 1 = mañana) y toca «Listo».
Future<void> _elegir(WidgetTester tester, {int dia = 1, int masHora = 0}) async {
  await tocar(tester, _campo);
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.tap(find.byKey(ClavesAgendarVisita.dia(dia)));
  await tester.pump();
  for (var i = 0; i < masHora; i++) {
    await tester.tap(find.byKey(ClavesAgendarVisita.hojaMas));
    await tester.pump();
  }
  await tester.ensureVisible(find.byKey(ClavesAgendarVisita.hojaListo));
  await tester.tap(find.byKey(ClavesAgendarVisita.hojaListo));
  await asentar(tester);
}

/// Una venta de [n] productos sueltos, cada uno con su nombre, para las listas largas.
({VentaGuardada guardada, ProductosDeLaEntrega productos}) _ventaLarga(int n, {String? nombre}) => (
  guardada: VentaGuardada(
    venta: ventaDe('v-1', talonario: '0042', monto: 890000),
    items: [
      for (var i = 0; i < n; i++)
        itemDe('i-$i', 'v-1', productoId: 'p-$i', cantidad: 1, precio: 1000),
    ],
  ),
  productos: ProductosDeLaEntrega(
    nombres: {for (var i = 0; i < n; i++) 'p-$i': nombre ?? 'Libro número $i'},
  ),
);

EntornoDeEntrega _entorno() {
  final e = EntornoDeEntrega();
  e.entregas.respuestaDeDiferir = diferidaPara(DateTime(2026, 10, 29, 8, 30));
  return e;
}

void main() {
  group('27C·01 Entregar otro día', () {
    testWidgets('dice la venta, el cliente y qué se entrega; el día sin elegir no deja guardar', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(), () => _desdeLaVenta(ventaConColeccion()));

      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text('Entregar otro día'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('QUÉ ENTREGÁS'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('FECHA PREVISTA'), findsOneWidget);
      expect(find.text('Elegí el día y la hora'), findsOneWidget);
      expect(
        find.text('Agendamos una visita de entrega para ese día, con recordatorio.'),
        findsOneWidget,
      );
      expect(_textoDelBoton(tester), 'Guardar entrega');
      expect(_habilitado(tester), isFalse);
      expect(find.text('Elegí cuándo vas a entregar.'), findsOneWidget);
    });

    testWidgets('las filas son de solo lectura: no se tildan ni se destildan', (tester) async {
      await montarPantalla(tester, _entorno(), () => _desdeLaVenta(ventaConColeccion()));

      expect(find.byKey(const Key('otro_dia_fila')), findsNWidgets(3));
      await tester.tap(find.text('Nuestros Hijos × 1'));
      await tester.pump();
      expect(find.byIcon(Icons.check), findsNWidgets(3));
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('elegir el día y la hora los muestra en el campo y habilita «Guardar entrega»', (
      tester,
    ) async {
      await montarPantalla(tester, _entorno(), () => _desdeLaVenta(ventaConColeccion()));

      await _elegir(tester);

      expect(find.text('Mañana · 08:30'), findsOneWidget);
      expect(find.text('Elegí el día y la hora'), findsNothing);
      expect(_habilitado(tester), isTrue);
      expect(find.text('Elegí cuándo vas a entregar.'), findsNothing);
    });

    testWidgets('«Guardar entrega» guarda todo lo vendido para esa fecha, agenda y vuelve', (
      tester,
    ) async {
      final e = _entorno();
      final salida = await montarPantalla(
        tester,
        e,
        () => _desdeLaVenta(ventaConColeccion(conRevista: true)),
      );
      await _elegir(tester, masHora: 6); // 08:30 + 30 min = 09:00

      await tocar(tester, _cta);

      final llamada = e.entregas.diferidas.single;
      expect(llamada.ventaId, 'v-1');
      expect(llamada.fechaPrevista.isAtSameMomentAs(DateTime(2026, 10, 29, 9)), isTrue);
      expect(
        {for (final f in llamada.filasNuevas) f.productoId: (f.cantidad, f.pendiente)},
        {
          'p-camino': (1, true),
          'p-vida-feliz': (1, true),
          'p-deseado': (1, true),
          'p-salud': (1, true),
          'p-hijos': (1, true),
          'p-nuestra-salud': (2, true),
        },
      );
      expect(salida.cerrada, isTrue);
      expect(salida.valor, isNotNull);
      expect(find.text('Entregar otro día'), findsNothing);
      expect(find.textContaining('Entrega guardada para'), findsOneWidget);
      expect(find.textContaining('Te vamos a avisar antes'), findsOneWidget);
    });

    testWidgets('si el teléfono no deja avisar, la confirmación lo dice y qué pasa', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(
        tester,
        e,
        () => _desdeLaVenta(ventaConColeccion()),
        extra: [
          recordatoriosProvider.overrideWithValue(RecordatoriosEnMemoria(permisoConcedido: false)),
        ],
      );
      await _elegir(tester);

      await tocar(tester, _cta);

      expect(find.textContaining('Entrega guardada para'), findsOneWidget);
      expect(
        find.textContaining(
          'Las notificaciones están apagadas: no te va a llegar el recordatorio.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('el campo se lee en voz alta con su valor y que se puede cambiar', (tester) async {
      final handle = tester.ensureSemantics();
      await montarPantalla(tester, _entorno(), () => _desdeLaVenta(ventaConColeccion()));

      expect(
        find.bySemanticsLabel('Fecha prevista: Elegí el día y la hora. Tocá para cambiar'),
        findsOneWidget,
      );
      await _elegir(tester);
      expect(
        find.bySemanticsLabel('Fecha prevista: Mañana · 08:30. Tocá para cambiar'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });

  group('«Poner fecha» desde Entregas pendientes', () {
    testWidgets('muestra lo que falta con sus nombres y guarda sin volver a crear filas', (
      tester,
    ) async {
      final e = _entorno();
      final pendiente = pendienteDe('v-1');
      e.entregas.emitirPendientes([pendiente]);
      final salida = await montarPantalla(
        tester,
        e,
        () => EntregarOtroDiaPage.rutaPonerFecha(colportorId: 'col-1', pendiente: pendiente),
      );

      expect(find.text('VENTA 0042'), findsOneWidget);
      expect(find.text('María Fernández'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);

      await _elegir(tester);
      await tocar(tester, _cta);

      final llamada = e.entregas.diferidas.single;
      expect(llamada.ventaId, 'v-1');
      expect(llamada.filasNuevas, isEmpty);
      expect(salida.cerrada, isTrue);
    });

    testWidgets('si el catálogo no se puede leer, no inventa nombres: avisa y deja reintentar', (
      tester,
    ) async {
      final e = _entorno();
      final pendiente = pendienteDe('v-1');
      e.entregas.emitirPendientes([pendiente]);
      e.fuente.fallas = 1;
      await montarPantalla(
        tester,
        e,
        () => EntregarOtroDiaPage.rutaPonerFecha(colportorId: 'col-1', pendiente: pendiente),
      );

      expect(find.text('No pudimos leer qué se vendió. Probá de nuevo.'), findsOneWidget);
      expect(find.text('Producto sin nombre × 1'), findsNothing);

      await tocar(tester, find.text('Reintentar'));

      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });
  });

  group('estados que el canvas no dibuja', () {
    testWidgets('cargando lo vendido: el esqueleto dice qué pasa y no deja guardar', (
      tester,
    ) async {
      final e = _entorno();
      e.fuente.bloqueo = Completer<void>();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      expect(find.byKey(const Key('otro_dia_cargando')), findsOneWidget);
      expect(_cta, findsNothing);

      e.fuente.bloqueo!.complete();
      await asentar(tester);
      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('no se puede leer lo vendido: avisa y «Reintentar» lo vuelve a leer', (
      tester,
    ) async {
      final e = _entorno();
      e.fuente.fallas = 1;
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      expect(find.textContaining('No pudimos'), findsOneWidget);
      expect(_cta, findsNothing);

      await tocar(tester, find.text('Reintentar'));

      expect(find.text('Salud y Hogar × 1'), findsOneWidget);
    });

    testWidgets('una venta sin productos lo dice y no ofrece guardar', (tester) async {
      await montarPantalla(
        tester,
        _entorno(),
        () => _desdeLaVenta(
          VentaGuardada(
            venta: ventaDe('v-1', talonario: '0042'),
            items: const [],
          ),
        ),
      );

      expect(find.text('Esta venta no tiene productos para entregar.'), findsOneWidget);
      expect(_cta, findsNothing);
    });

    testWidgets('si ya se entregó todo, dice que no hay nada pendiente', (tester) async {
      final e = _entorno();
      e.entregas.guardadas['v-1'] = [entregaDe('e-1', 'p-camino'), entregaDe('e-2', 'p-hijos')];
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      expect(find.text('Esta venta no tiene nada pendiente de entregar.'), findsOneWidget);
      expect(_cta, findsNothing);
    });

    testWidgets('si la venta ya tiene filas, la fecha se pone solo a las que siguen pendientes', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.guardadas['v-1'] = [
        entregaDe('e-1', 'p-camino'),
        entregaDe('e-2', 'p-hijos', pendiente: true),
      ];
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Salud y Hogar × 1'), findsNothing);

      await _elegir(tester);
      await tocar(tester, _cta);

      expect(e.entregas.diferidas.single.filasNuevas, isEmpty);
    });

    testWidgets('sin conexión: guarda igual en el teléfono y no menciona la señal', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);

      await tocar(tester, _cta);

      expect(e.entregas.diferidas, hasLength(1));
      expect(find.textContaining('conexión'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en «Guardar entrega»: se guarda una sola vez', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);
      e.entregas.compuertaDeDiferida = Completer<void>();

      await tester.tap(_cta);
      await tester.pump();
      await tester.tap(_cta, warnIfMissed: false);
      await tester.pump();

      expect(e.entregas.diferidas, hasLength(1));

      e.entregas.compuertaDeDiferida!.complete();
      await asentar(tester);

      expect(e.entregas.diferidas, hasLength(1));
      expect(find.textContaining('Entrega guardada para'), findsOneWidget);
    });

    testWidgets('mientras se guarda: el botón no responde, no se sale y el campo no se abre', (
      tester,
    ) async {
      final e = _entorno();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);
      e.entregas.compuertaDeDiferida = Completer<void>();

      await tester.tap(_cta);
      await tester.pump();

      expect(_habilitado(tester), isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byKey(const Key('venta_atras')), findsNothing);
      await tester.tap(_campo, warnIfMissed: false);
      await tester.pump();
      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsNothing);

      e.entregas.compuertaDeDiferida!.complete();
      await asentar(tester);
    });

    testWidgets('falla al guardar: el aviso, la fecha sigue y el botón vuelve para reintentar', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.fallasAlDiferir.add(const FailureEntregaNoGuardada());
      final salida = await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);

      await tocar(tester, _cta);

      expect(
        find.text(
          'No pudimos guardar la entrega en tu teléfono. No se perdió nada de lo que marcaste: '
          'probá de nuevo.',
        ),
        findsOneWidget,
      );
      expect(_textoDelBoton(tester), 'Reintentar');
      expect(_habilitado(tester), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Mañana · 08:30'), findsOneWidget);
      expect(salida.cerrada, isFalse);

      await tocar(tester, _cta);

      expect(e.entregas.diferidas, hasLength(2));
      expect(salida.cerrada, isTrue);
    });

    testWidgets('una excepción que nadie previó también deja reintentar', (tester) async {
      final e = EntornoDeEntrega(entregas: _RepoQueExplota());
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);

      await tocar(tester, _cta);

      expect(find.textContaining('No pudimos guardar la entrega'), findsOneWidget);
      expect(_habilitado(tester), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('elegir otra fecha después de un error limpia el aviso y guarda la última', (
      tester,
    ) async {
      final e = _entorno();
      e.entregas.fallasAlDiferir.add(const FailureEntregaNoGuardada());
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);
      await tocar(tester, _cta);
      expect(find.textContaining('No pudimos guardar'), findsOneWidget);

      await _elegir(tester, dia: 2);

      expect(find.textContaining('No pudimos guardar'), findsNothing);
      expect(_textoDelBoton(tester), 'Guardar entrega');
      await tocar(tester, _cta);
      expect(e.entregas.diferidas.last.fechaPrevista.day, 30);
    });

    testWidgets('elegir dos veces seguidas deja la última elección', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      await _elegir(tester, dia: 1);
      await _elegir(tester, dia: 3, masHora: 12);

      expect(find.text('Mañana · 08:30'), findsNothing);
      await tocar(tester, _cta);
      final fecha = e.entregas.diferidas.single.fechaPrevista;
      expect(fecha.day, 31);
      expect(fecha.hour, 9);
      expect(fecha.minute, 30);
    });

    testWidgets('cerrar la hoja sin «Listo» no cambia nada', (tester) async {
      await montarPantalla(tester, _entorno(), () => _desdeLaVenta(ventaConColeccion()));

      await tocar(tester, _campo);
      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsOneWidget);
      await tester.tapAt(const Offset(195, 20));
      await asentar(tester);

      expect(find.byKey(ClavesAgendarVisita.hojaListo), findsNothing);
      expect(find.text('Elegí el día y la hora'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
    });

    testWidgets('volver sin guardar y reentrar: arranca de cero y no guardó nada', (tester) async {
      final e = _entorno();
      final salida = await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));
      await _elegir(tester);

      await tocar(tester, find.byKey(const Key('venta_atras')));

      expect(salida.cerrada, isTrue);
      expect(salida.valor, isNull);
      expect(e.entregas.diferidas, isEmpty);

      await abrirPantalla(tester);

      expect(find.text('Elegí el día y la hora'), findsOneWidget);
      expect(_habilitado(tester), isFalse);
      await _elegir(tester);
      await tocar(tester, _cta);
      expect(e.entregas.diferidas, hasLength(1));
    });

    testWidgets('un segundo toque en «volver» no cierra dos pantallas', (tester) async {
      final e = _entorno();
      await montarPantalla(tester, e, () => _desdeLaVenta(ventaConColeccion()));

      await tester.tap(find.byKey(const Key('venta_atras')));
      await tester.tap(find.byKey(const Key('venta_atras')), warnIfMissed: false);
      await asentar(tester);

      expect(find.byKey(const Key('abrir_pantalla')), findsOneWidget);
    });

    testWidgets('40 productos con nombres largos: la lista se recorre y se llega al botón', (
      tester,
    ) async {
      final e = _entorno();
      final larga = _ventaLarga(
        40,
        nombre: 'Un libro con un nombre larguísimo que no entra en una sola línea del teléfono',
      );
      e.fuente.productos = larga.productos;
      await montarPantalla(
        tester,
        e,
        () => _desdeLaVenta(larga.guardada),
        tamano: const Size(320, 568),
      );

      expect(tester.takeException(), isNull);
      await _elegir(tester);
      expect(tester.takeException(), isNull);
      await tocar(tester, _cta);
      expect(e.entregas.diferidas.single.filasNuevas, hasLength(40));
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets(
        'texto al ${(escala * 100).round()} % a 320 × 568: nada desborda y se alcanza todo',
        (tester) async {
          final e = _entorno();
          final venta = _ventaLarga(6);
          e.fuente.productos = venta.productos;
          await montarPantalla(
            tester,
            e,
            () => _desdeLaVenta(venta.guardada),
            escala: escala,
            tamano: const Size(320, 568),
          );

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_cta).height, greaterThanOrEqualTo(48));
          await tester.scrollUntilVisible(_campo, 100);
          expect(tester.getSize(_campo).height, greaterThanOrEqualTo(48));
          await _elegir(tester);
          expect(tester.takeException(), isNull);
          await tocar(tester, _cta);
          expect(tester.takeException(), isNull);
          expect(e.entregas.diferidas, hasLength(1));
        },
      );
    }
  });
}
