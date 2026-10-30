// Vista 31 «Devolución» (HU-VEN-004, #161): los 10 artboards (31-01 a 31-10), los estados que la HU pide
// y el canvas no dibuja (cargando, venta ausente, error de lectura, ya devuelta) y los casos límite
// (doble toque, falla a mitad, reintento con el mismo id, volver y reentrar, listas largas, letra
// grande). El repositorio es un falso: lo que se prueba es la pantalla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/personas_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/devolucion.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_para_devolver.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/devolucion_repository.dart';
import 'package:colportores_mobile/features/ventas/domain/services/reglas_de_devolucion.dart';
import 'package:colportores_mobile/features/ventas/presentation/formato_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/devolucion_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/devolucion_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/persona_falsos.dart';
import '../../helpers/venta_ui_falsos.dart';

final _fechaDeLaVenta = DateTime.utc(2026, 10, 13, 18, 20);
final _ahora = _fechaDeLaVenta.add(const Duration(hours: 24));

/// La venta del canvas 31: «Salud y Hogar» $ 2.600 y «Nuestros Hijos» $ 1.900, $ 4.500 en total.
VentaParaDevolver _ventaDelCanvas({
  int cobrado = 450000,
  int salud = 0,
  int hijos = 0,
  int reembolsado = 0,
  List<RenglonDeLaVenta>? renglones,
}) {
  final lista =
      renglones ??
      [
        RenglonDeLaVenta(
          ventaItemId: 'i-salud',
          titulo: 'Salud y Hogar',
          productoId: 'p-salud',
          cantidad: 1,
          precioUnitarioCentavos: 260000,
          unidadesDevueltas: salud,
        ),
        RenglonDeLaVenta(
          ventaItemId: 'i-hijos',
          titulo: 'Nuestros Hijos',
          productoId: 'p-hijos',
          cantidad: 1,
          precioUnitarioCentavos: 190000,
          unidadesDevueltas: hijos,
        ),
      ];
  return VentaParaDevolver(
    ventaId: 'v-1',
    numeroTalonario: '0042',
    fecha: _fechaDeLaVenta,
    montoTotalCentavos: lista.fold(0, (s, r) => s + r.cantidad * r.precioUnitarioCentavos),
    cobradoCentavos: cobrado,
    reembolsadoCentavos: reembolsado,
    renglones: lista,
  );
}

class _RepoFalso implements DevolucionRepository {
  _RepoFalso(this.venta);

  VentaParaDevolver? venta;

  /// Si no es `null`, leer la venta falla con esto.
  Failure? fallaAlLeer;

  /// Las respuestas de [registrar], en orden; cuando se acaban, se registra bien.
  final respuestas = <Future<Either<Failure, DevolucionRegistrada>> Function()>[];

  final pedidos = <PedidoDeDevolucion>[];
  var lecturas = 0;
  Completer<void>? lecturaDetenida;

  @override
  Future<Either<Failure, VentaParaDevolver?>> ventaParaDevolver(String ventaId) async {
    lecturas++;
    await lecturaDetenida?.future;
    final falla = fallaAlLeer;
    return falla != null ? Left(falla) : Right(venta);
  }

  @override
  Future<Either<Failure, DevolucionRegistrada>> registrar(PedidoDeDevolucion pedido) async {
    pedidos.add(pedido);
    if (respuestas.isNotEmpty) return respuestas.removeAt(0)();
    return Right(_registrada(pedido));
  }

  DevolucionRegistrada _registrada(PedidoDeDevolucion pedido) {
    final v = venta!;
    final cuenta = ReglasDeDevolucion.cuenta(v, pedido.unidadesPorRenglon);
    final debo = pedido.queHacer == QueHacerConLaDiferencia.devolverDespues
        ? cuenta.pagoDeMasCentavos
        : 0;
    return DevolucionRegistrada(
      devolucion: Devolucion(
        id: pedido.id,
        ventaId: pedido.ventaId,
        productos: const [],
        fechaDevolucion: pedido.ahora,
        auditoria: auditoriaPersonas(),
      ),
      totalCentavos: cuenta.seQuedaConCentavos,
      saldoCentavos: cuenta.saldoNuevoCentavos,
      deboAlClienteCentavos: debo,
      eraTotal: cuenta.esTotal,
    );
  }
}

class _Montaje {
  _Montaje(this.repo, this.ids, this.resultados);
  final _RepoFalso repo;
  final List<String> ids;
  final List<bool?> resultados;
}

Future<_Montaje> _montar(
  WidgetTester tester,
  _RepoFalso repo, {
  DateTime? ahora,
  double escala = 1,
  Size tamano = const Size(390, 844),
  String? personaId,
  bool asentarLaLectura = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final ids = <String>[];
  final resultados = <bool?>[];
  var n = 0;
  await tester.pumpWidget(
    ProviderScope(
      // ignore: always_specify_types
      overrides: [
        devolucionRepositoryProvider.overrideWithValue(repo),
        generadorIdDevolucionProvider.overrideWithValue(() {
          final id = 'd-${++n}';
          ids.add(id);
          return id;
        }),
        relojDevolucionProvider.overrideWithValue(() => ahora ?? _ahora),
        personasDelEspacioProvider.overrideWith(
          (ref, espacioId) =>
              Stream.value([clienteDePersonas('per-1', 'María', apellido: 'Fernández')]),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir'),
                onPressed: () async {
                  final r = await DevolucionPage.abrir(
                    context,
                    ventaId: 'v-1',
                    colportorId: 'col-1',
                    espacioId: 'esp-1',
                    personaId: personaId,
                  );
                  resultados.add(r);
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  if (asentarLaLectura) await asentar(tester);
  return _Montaje(repo, ids, resultados);
}

Finder _mas(String titulo) => find.byTooltip('Uno más de $titulo');
Finder _menos(String titulo) => find.byTooltip('Uno menos de $titulo');

/// El `IconButton` que lleva el tooltip [t] (el finder por tooltip da el `Tooltip`).
IconButton _icono(WidgetTester tester, Finder t) =>
    tester.widget<IconButton>(find.ancestor(of: t, matching: find.byType(IconButton)));

/// Sube la lista al principio: tras bajar a un campo, lo de arriba queda sin armar.
Future<void> _alPrincipio(WidgetTester tester) async {
  final lista = find.descendant(of: find.byType(Scaffold).last, matching: find.byType(Scrollable));
  tester.state<ScrollableState>(lista.first).position.jumpTo(0);
  await tester.pump();
}

Finder get _cta => find.byKey(const Key('venta_cta'));

FilledButton _boton(WidgetTester tester) => tester.widget<FilledButton>(_cta);

Future<void> _seguir(WidgetTester tester) async {
  await tocar(tester, _cta);
}

Future<void> _confirmarEnLaHoja(WidgetTester tester) async {
  await tocar(tester, _cta);
  await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
}

String _m(int centavos) => FormatoVenta.monto(centavos);

void main() {
  group('31-01 elegir qué devuelve', () {
    testWidgets('dice el título, el subtítulo, cada renglón y el plazo de 72 h', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()), personaId: 'per-1');

      expect(find.text('DEVOLUCIÓN · VENTA 0042'), findsOneWidget);
      expect(find.text('¿Qué te devuelve?'), findsOneWidget);
      expect(find.text('María Fernández · pagó ${_m(450000)} de ${_m(450000)}'), findsOneWidget);
      expect(find.text('EN LA VENTA'), findsOneWidget);
      expect(find.text('Salud y Hogar'), findsOneWidget);
      expect(find.text('Nuestros Hijos'), findsOneWidget);
      expect(find.text('Vendidos 1 · ${_m(260000)}'), findsOneWidget);
      expect(find.text('Vendidos 1 · ${_m(190000)}'), findsOneWidget);
      expect(find.textContaining('(72 h desde la venta)'), findsOneWidget);
      expect(find.text('Seguir'), findsOneWidget);
    });

    testWidgets('31-09 sin nada elegido «Seguir» está apagado y dice por qué', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));

      expect(find.text('Elegí al menos un producto.'), findsOneWidget);
      expect(_boton(tester).onPressed, isNull);
    });

    testWidgets('elegir un producto enciende «Seguir» y sacarlo lo apaga', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));

      await tocar(tester, _mas('Nuestros Hijos'));
      expect(_boton(tester).onPressed, isNotNull);
      expect(find.text('Elegí al menos un producto.'), findsNothing);

      await tocar(tester, _menos('Nuestros Hijos'));
      expect(_boton(tester).onPressed, isNull);
    });

    testWidgets('no deja elegir más unidades de las que quedan', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));

      await tocar(tester, _mas('Nuestros Hijos'));

      expect(_icono(tester, _mas('Nuestros Hijos')).onPressed, isNull);
    });

    testWidgets('un renglón que ya volvió entero no se puede elegir y lo dice', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas(hijos: 1)));

      expect(find.text('Vendidos 1 · ya devolvió 1 · ${_m(190000)}'), findsOneWidget);
      expect(_icono(tester, _mas('Nuestros Hijos')).onPressed, isNull);
      expect(_icono(tester, _mas('Salud y Hogar')).onPressed, isNotNull);
    });
  });

  group('31-02 a 31-04 y 31-05, pagó de más', () {
    testWidgets('31-02 «Seguir» muestra las cuentas y obliga a elegir qué hace con la diferencia', (
      tester,
    ) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));
      await tocar(tester, _mas('Nuestros Hijos'));

      await _seguir(tester);

      expect(find.text('Devuelve Nuestros Hijos'), findsOneWidget);
      expect(find.text('Se queda con'), findsOneWidget);
      expect(find.text(_m(260000)), findsOneWidget);
      expect(find.text('Ya pagó'), findsOneWidget);
      expect(find.text('Pagó de más'), findsOneWidget);
      expect(find.text(_m(190000)), findsWidgets);
      expect(find.text('¿QUÉ HACÉS CON ${_m(190000)}?'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_opcion_devolverAhora')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_opcion_retener')), findsOneWidget);
      expect(find.byKey(const Key('devolucion_opcion_devolverDespues')), findsOneWidget);
      expect(find.text('Registrar devolución'), findsOneWidget);
      expect(find.text('Elegí qué hacés con la diferencia.'), findsOneWidget);
      expect(_boton(tester).onPressed, isNull);
    });

    testWidgets(
      '31-02 el motivo avisa que lo lee el coordinador y que no se pongan datos del cliente',
      (tester) async {
        await _montar(tester, _RepoFalso(_ventaDelCanvas()));
        await tocar(tester, _mas('Nuestros Hijos'));

        await _seguir(tester);

        await verVisible(tester, find.byKey(const Key('devolucion_motivo')));
        expect(find.byKey(const Key('devolucion_motivo')), findsOneWidget);
        expect(
          find.text('Tu coordinador va a leer este motivo. No pongas datos del cliente.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('31-03 elegir «Se lo devuelvo ahora» enciende «Registrar devolución»', (
      tester,
    ) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);

      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));

      expect(_boton(tester).onPressed, isNotNull);
      expect(find.text('Elegí qué hacés con la diferencia.'), findsNothing);
    });

    testWidgets('31-04 la hoja pide confirmar y «Volver» no registra nada', (tester) async {
      final repo = _RepoFalso(_ventaDelCanvas());
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));

      await tocar(tester, _cta);

      expect(find.text('¿Registrar la devolución?'), findsOneWidget);
      expect(
        find.text('La venta original no se borra: queda con la devolución anotada.'),
        findsOneWidget,
      );
      expect(find.text('Le devolvés ahora'), findsOneWidget);

      await tocar(tester, find.byKey(const Key('devolucion_hoja_volver')));

      expect(find.text('¿Registrar la devolución?'), findsNothing);
      expect(repo.pedidos, isEmpty);
      expect(find.text('Registrar devolución'), findsOneWidget);
    });

    testWidgets('31-05 al confirmar registra con lo elegido y muestra la devolución registrada', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas());
      final m = await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));
      await escribir(tester, find.byKey(const Key('devolucion_motivo')), '  No le gustó  ');

      await _confirmarEnLaHoja(tester);

      final pedido = repo.pedidos.single;
      expect(pedido.id, 'd-1');
      expect(pedido.ventaId, 'v-1');
      expect(pedido.colportorId, 'col-1');
      expect(pedido.unidadesPorRenglon, {'i-hijos': 1});
      expect(pedido.queHacer, QueHacerConLaDiferencia.devolverAhora);
      expect(pedido.motivo, 'No le gustó');
      expect(pedido.ahora, _ahora);
      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(find.text('Total de la venta'), findsOneWidget);
      expect(find.text('Saldo'), findsOneWidget);
      expect(find.text('Debo al cliente'), findsNothing);
      expect(find.text('Registramos la devolución de Nuestros Hijos.'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_agendar')), findsNothing);

      await tocar(tester, find.byKey(const Key('devolucion_listo')));
      expect(m.resultados, [true]);
    });

    testWidgets('31-05 con «Se lo devuelvo después» queda «Debo al cliente» y ofrece agendarlo', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas());
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverDespues')));

      await _confirmarEnLaHoja(tester);

      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.devolverDespues);
      expect(find.text('Debo al cliente'), findsOneWidget);
      expect(find.text('Agendar la devolución del dinero'), findsOneWidget);
      expect(find.text('Listo'), findsOneWidget);
    });

    testWidgets('«Lo retengo» registra con la elección retener', (tester) async {
      final repo = _RepoFalso(_ventaDelCanvas());
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

      await _confirmarEnLaHoja(tester);

      expect(repo.pedidos.single.queHacer, QueHacerConLaDiferencia.retener);
      expect(find.text('Devolución registrada'), findsOneWidget);
    });
  });

  group('31-06 y 31-07', () {
    testWidgets('31-06 si no pagó de más no hay nada que elegir: el saldo baja solo', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas(cobrado: 100000));
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));

      await _seguir(tester);

      expect(find.text('Se queda con'), findsOneWidget);
      expect(find.text('Ya pagó'), findsOneWidget);
      expect(find.text('Saldo nuevo'), findsOneWidget);
      expect(find.text(_m(160000)), findsWidgets);
      expect(find.text('Pagó de más'), findsNothing);
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      expect(_boton(tester).onPressed, isNotNull);

      await _confirmarEnLaHoja(tester);

      expect(repo.pedidos.single.queHacer, isNull);
      expect(find.text('Devolución registrada'), findsOneWidget);
    });

    testWidgets(
      '31-07 devolver todo dice «Devuelve todo», se queda con \$ 0 y pregunta por la plata',
      (tester) async {
        final repo = _RepoFalso(_ventaDelCanvas());
        await _montar(tester, repo);
        await tocar(tester, _mas('Salud y Hogar'));
        await tocar(tester, _mas('Nuestros Hijos'));

        await _seguir(tester);

        expect(find.text('Devuelve todo'), findsOneWidget);
        expect(find.text(_m(0)), findsOneWidget);
        expect(find.text('Pagó de más'), findsOneWidget);
        expect(find.text(_m(450000)), findsWidgets);
        expect(find.byKey(const Key('devolucion_opciones')), findsOneWidget);

        await tocar(tester, find.byKey(const Key('devolucion_opcion_devolverAhora')));
        await _confirmarEnLaHoja(tester);

        expect(repo.pedidos.single.unidadesPorRenglon, {'i-salud': 1, 'i-hijos': 1});
        expect(find.text('Registramos la devolución de toda la venta.'), findsOneWidget);
      },
    );

    testWidgets('con varios productos el título cuenta cuántos', (tester) async {
      final venta = _ventaDelCanvas(
        renglones: const [
          RenglonDeLaVenta(
            ventaItemId: 'i-a',
            titulo: 'Libro A',
            productoId: 'p-a',
            cantidad: 3,
            precioUnitarioCentavos: 100000,
          ),
          RenglonDeLaVenta(
            ventaItemId: 'i-b',
            titulo: 'Libro B',
            productoId: 'p-b',
            cantidad: 1,
            precioUnitarioCentavos: 100000,
          ),
        ],
      );
      await _montar(tester, _RepoFalso(venta));
      await tocar(tester, _mas('Libro A'));
      await tocar(tester, _mas('Libro A'));
      await tocar(tester, _mas('Libro B'));

      await _seguir(tester);

      expect(find.text('Devuelve 3 productos'), findsOneWidget);
    });

    testWidgets('en la segunda etapa las filas siguen editables: vaciarlas vuelve a elegir', (
      tester,
    ) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

      await tocar(tester, _menos('Nuestros Hijos'));

      expect(find.text('¿Qué te devuelve?'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_opciones')), findsNothing);
      expect(find.text('Seguir'), findsOneWidget);
      expect(find.text('Elegí al menos un producto.'), findsOneWidget);
    });
  });

  group('31-08 fuera de plazo y otros estados', () {
    testWidgets(
      '31-08 pasadas las 72 h solo ofrece «Volver» y dice que lo registra el coordinador',
      (tester) async {
        final m = await _montar(
          tester,
          _RepoFalso(_ventaDelCanvas()),
          ahora: _fechaDeLaVenta.add(const Duration(hours: 73)),
        );

        expect(find.text('VENTA 0042'), findsOneWidget);
        expect(find.text('Devolución'), findsOneWidget);
        expect(
          find.text(
            'Pasaron más de 72 h desde la venta. La devolución la registra tu coordinador.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsOneWidget);
        expect(find.text('Seguir'), findsNothing);
        expect(_mas('Nuestros Hijos'), findsNothing);

        await tocar(tester, find.byKey(const Key('devolucion_volver')));
        expect(m.resultados, [false]);
      },
    );

    testWidgets('a las 72 h justas todavía se puede', (tester) async {
      await _montar(
        tester,
        _RepoFalso(_ventaDelCanvas()),
        ahora: _fechaDeLaVenta.add(const Duration(hours: 72)),
      );

      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsNothing);
      expect(find.text('Seguir'), findsOneWidget);
    });

    testWidgets('mientras lee la venta muestra el esqueleto y no deja registrar', (tester) async {
      final repo = _RepoFalso(_ventaDelCanvas())..lecturaDetenida = Completer<void>();
      await _montar(tester, repo);

      expect(find.byKey(const Key('devolucion_cargando')), findsOneWidget);
      expect(_cta, findsNothing);

      repo.lecturaDetenida!.complete();
      await asentar(tester);

      expect(find.byKey(const Key('devolucion_cargando')), findsNothing);
      expect(find.text('Seguir'), findsOneWidget);
    });

    testWidgets('si la venta ya no está lo dice y deja volver', (tester) async {
      final m = await _montar(tester, _RepoFalso(null));

      expect(find.byKey(const Key('devolucion_sin_venta')), findsOneWidget);
      expect(
        find.text('Esta venta ya no está en tu teléfono. Volvé atrás y elegí otra.'),
        findsOneWidget,
      );

      await tocar(tester, find.byKey(const Key('devolucion_volver')));
      expect(m.resultados, [false]);
    });

    testWidgets('si no puede leer la venta ofrece «Reintentar» y al reintentar la muestra', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas())
        ..fallaAlLeer = const FailureDevolucionNoDisponible();
      await _montar(tester, repo);

      expect(find.byKey(const Key('devolucion_error_lectura')), findsOneWidget);
      expect(find.text('No pudimos leer la venta guardada en tu teléfono.'), findsOneWidget);

      repo.fallaAlLeer = null;
      await tocar(tester, find.text('Reintentar'));

      expect(find.byKey(const Key('devolucion_error_lectura')), findsNothing);
      expect(find.text('Seguir'), findsOneWidget);
      expect(repo.lecturas, 2);
    });

    testWidgets('una venta ya devuelta por completo no deja devolver otra vez', (tester) async {
      await _montar(tester, _RepoFalso(_ventaDelCanvas(salud: 1, hijos: 1)));

      expect(find.byKey(const Key('devolucion_ya_devuelta')), findsOneWidget);
      expect(_mas('Nuestros Hijos'), findsNothing);
      expect(find.byKey(const Key('devolucion_volver')), findsOneWidget);
    });
  });

  group('31-10 errores al guardar', () {
    testWidgets(
      '31-10 si falla muestra el aviso, conserva lo elegido y el botón pasa a «Reintentar»',
      (tester) async {
        final repo = _RepoFalso(_ventaDelCanvas())
          ..respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'x')));
        await _montar(tester, repo);
        await tocar(tester, _mas('Nuestros Hijos'));
        await _seguir(tester);
        await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

        await _confirmarEnLaHoja(tester);

        expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
        expect(find.text('No pudimos registrar la devolución. No cambió nada.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(_boton(tester).onPressed, isNotNull);
        expect(find.text('Registrando…'), findsNothing);
        expect(find.text('Devuelve Nuestros Hijos'), findsOneWidget);
      },
    );

    testWidgets('«Reintentar» repite el mismo id: un reintento no devuelve dos veces', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas())
        ..respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'x')));
      final m = await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await _confirmarEnLaHoja(tester);

      await tocar(tester, _cta);

      expect(repo.pedidos.map((p) => p.id), ['d-1', 'd-1']);
      expect(m.ids, ['d-1']);
      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(find.byKey(const Key('devolucion_error')), findsNothing);
    });

    testWidgets('si cambia lo elegido después de fallar, es otra devolución con otro id', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas(cobrado: 0))
        ..respuestas.add(() async => const Left(FailureDevolucionNoGuardada(causa: 'x')));
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, _cta);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));
      expect(find.byKey(const Key('devolucion_error')), findsOneWidget);

      await tocar(tester, _mas('Salud y Hogar'));
      await tocar(tester, _cta);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));

      expect(repo.pedidos.map((p) => p.id), ['d-1', 'd-2']);
    });

    testWidgets(
      'si el repositorio lanza, no queda trabado en «Registrando…» y se puede reintentar',
      (tester) async {
        final repo = _RepoFalso(_ventaDelCanvas())
          ..respuestas.add(() => Future.error(StateError('se cayó')));
        await _montar(tester, repo);
        await tocar(tester, _mas('Nuestros Hijos'));
        await _seguir(tester);
        await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

        await _confirmarEnLaHoja(tester);

        expect(find.byKey(const Key('devolucion_error')), findsOneWidget);
        expect(find.text('Registrando…'), findsNothing);
        expect(_boton(tester).onPressed, isNotNull);

        await tocar(tester, _cta);
        expect(find.text('Devolución registrada'), findsOneWidget);
      },
    );

    testWidgets('si pasaron las 72 h mientras tanto, pasa a 31-08', (tester) async {
      final repo = _RepoFalso(_ventaDelCanvas())
        ..respuestas.add(() async => const Left(FailureDevolucionFueraDePlazo()));
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

      await _confirmarEnLaHoja(tester);

      expect(find.byKey(const Key('devolucion_fuera_de_plazo')), findsOneWidget);
    });

    testWidgets('si otra devolución se coló, vuelve a leer la venta y las filas lo dicen', (
      tester,
    ) async {
      final repo = _RepoFalso(_ventaDelCanvas(cobrado: 0))
        ..respuestas.add(() async {
          // Mientras tanto otra devolución se llevó el libro.
          // ignore: cascade_invocations
          return const Left(FailureDevolucionInvalida(causa: 'de_mas'));
        });
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      repo.venta = _ventaDelCanvas(cobrado: 0, hijos: 1);

      await tocar(tester, _cta);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));

      expect(repo.lecturas, 2);
      expect(find.text('Vendidos 1 · ya devolvió 1 · ${_m(190000)}'), findsOneWidget);
      expect(find.text('Registrando…'), findsNothing);
    });

    testWidgets('si la venta se dio de baja mientras tanto, dice que ya no está', (tester) async {
      final repo = _RepoFalso(_ventaDelCanvas())
        ..respuestas.add(() async => const Left(FailureDevolucionSinVenta()));
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));

      await _confirmarEnLaHoja(tester);

      expect(find.byKey(const Key('devolucion_sin_venta')), findsOneWidget);
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en «Registrar devolución» de la hoja registra una sola vez', (
      tester,
    ) async {
      final espera = Completer<Either<Failure, DevolucionRegistrada>>();
      final repo = _RepoFalso(_ventaDelCanvas())..respuestas.add(() => espera.future);
      await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await tocar(tester, _cta);

      final registrar = find.byKey(const Key('devolucion_hoja_registrar'));
      await tester.tap(registrar);
      await tester.tap(registrar, warnIfMissed: false);
      await tester.pump();

      expect(repo.pedidos, hasLength(1));
      expect(find.text('Registrando…'), findsOneWidget);
      // Mientras guarda, el botón no responde y las filas no cambian.
      expect(_boton(tester).onPressed, isNull);
      await tester.tap(_menos('Nuestros Hijos'), warnIfMissed: false);
      await tester.pump();
      expect(repo.pedidos, hasLength(1));

      espera.complete(Right(repo._registrada(repo.pedidos.single)));
      await asentar(tester);

      expect(repo.pedidos, hasLength(1));
      expect(find.text('Devolución registrada'), findsOneWidget);
    });

    testWidgets('mientras guarda, «atrás» no cierra la pantalla', (tester) async {
      final espera = Completer<Either<Failure, DevolucionRegistrada>>();
      final repo = _RepoFalso(_ventaDelCanvas())..respuestas.add(() => espera.future);
      final m = await _montar(tester, repo);
      await tocar(tester, _mas('Nuestros Hijos'));
      await _seguir(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await _confirmarEnLaHoja(tester);

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.byKey(const Key('devolucion_pagina')), findsOneWidget);
      expect(m.resultados, isEmpty);

      espera.complete(Right(repo._registrada(repo.pedidos.single)));
      await asentar(tester);
      expect(find.text('Devolución registrada'), findsOneWidget);
    });

    testWidgets(
      'dos devoluciones seguidas de la misma venta: la segunda ve lo que dejó la primera',
      (tester) async {
        final repo = _RepoFalso(_ventaDelCanvas(cobrado: 0));
        final m = await _montar(tester, repo);
        await tocar(tester, _mas('Nuestros Hijos'));
        await _seguir(tester);
        await _confirmarEnLaHoja(tester);
        await tocar(tester, find.byKey(const Key('devolucion_listo')));
        expect(m.resultados, [true]);

        repo.venta = _ventaDelCanvas(cobrado: 0, hijos: 1);
        await tocar(tester, find.byKey(const Key('abrir')));
        await asentar(tester);

        expect(find.text('Vendidos 1 · ya devolvió 1 · ${_m(190000)}'), findsOneWidget);
        expect(find.text('Seguir'), findsOneWidget);
        expect(_boton(tester).onPressed, isNull);

        await tocar(tester, _mas('Salud y Hogar'));
        await _seguir(tester);
        await _confirmarEnLaHoja(tester);

        expect(repo.pedidos.map((p) => p.id), ['d-1', 'd-2']);
        expect(repo.pedidos.last.unidadesPorRenglon, {'i-salud': 1});
      },
    );

    testWidgets(
      'volver atrás con algo elegido pregunta, y al descartar y reentrar empieza limpio',
      (tester) async {
        final repo = _RepoFalso(_ventaDelCanvas());
        final m = await _montar(tester, repo);
        await tocar(tester, _mas('Nuestros Hijos'));

        await tester.binding.handlePopRoute();
        await asentar(tester);

        expect(find.text('¿Descartar lo que escribiste?'), findsOneWidget);
        // «Seguir escribiendo» no cierra.
        await tocar(tester, find.text('Seguir escribiendo'));
        expect(find.byKey(const Key('devolucion_pagina')), findsOneWidget);
        expect(m.resultados, isEmpty);

        await tester.binding.handlePopRoute();
        await asentar(tester);
        await tocar(tester, find.text('Descartar'));

        expect(find.byKey(const Key('devolucion_pagina')), findsNothing);
        expect(m.resultados, [false]);
        expect(repo.pedidos, isEmpty);

        await tocar(tester, find.byKey(const Key('abrir')));
        await asentar(tester);

        expect(find.text('¿Qué te devuelve?'), findsOneWidget);
        expect(_boton(tester).onPressed, isNull);
        expect(find.text('Elegí al menos un producto.'), findsOneWidget);
      },
    );

    testWidgets('volver atrás sin nada elegido cierra sin preguntar', (tester) async {
      final m = await _montar(tester, _RepoFalso(_ventaDelCanvas()));

      await tester.binding.handlePopRoute();
      await asentar(tester);

      expect(find.text('¿Descartar lo que escribiste?'), findsNothing);
      expect(m.resultados, [false]);
    });

    testWidgets('una lista larga de renglones se recorre y cada uno se elige', (tester) async {
      final renglones = [
        for (var i = 0; i < 40; i++)
          RenglonDeLaVenta(
            ventaItemId: 'i-$i',
            titulo: 'Libro número $i',
            productoId: 'p-$i',
            cantidad: 2,
            precioUnitarioCentavos: 10000,
          ),
      ];
      final repo = _RepoFalso(_ventaDelCanvas(renglones: renglones, cobrado: 0));
      await _montar(tester, repo);

      await tocar(tester, _mas('Libro número 39'));
      await _seguir(tester);
      await _confirmarEnLaHoja(tester);

      expect(repo.pedidos.single.unidadesPorRenglon, {'i-39': 1});
      expect(tester.takeException(), isNull);
    });

    testWidgets('textos largos y letra al doble, en una pantalla chica, no desbordan', (
      tester,
    ) async {
      const largo =
          'Una colección con un nombre larguísimo que no entra en una sola línea de la pantalla';
      final venta = _ventaDelCanvas(
        cobrado: 3 * 123456789,
        renglones: const [
          RenglonDeLaVenta(
            ventaItemId: 'i-a',
            titulo: largo,
            productoId: 'p-a',
            cantidad: 3,
            precioUnitarioCentavos: 123456789,
          ),
        ],
      );
      final repo = _RepoFalso(venta);
      await _montar(tester, repo, escala: 2, tamano: const Size(320, 568), personaId: 'per-1');

      expect(tester.takeException(), isNull);
      await tocar(tester, _mas(largo));
      await _seguir(tester);
      expect(tester.takeException(), isNull);

      await _alPrincipio(tester);
      await tocar(tester, find.byKey(const Key('devolucion_opcion_retener')));
      await escribir(tester, find.byKey(const Key('devolucion_motivo')), 'x' * 600);
      expect(tester.takeException(), isNull);

      await tocar(tester, _cta);
      expect(find.text('¿Registrar la devolución?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tocar(tester, find.byKey(const Key('devolucion_hoja_registrar')));

      expect(repo.pedidos.single.motivo!.length, lessThanOrEqualTo(500));
      expect(find.text('Devolución registrada'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('sin conexión se registra igual: no hay estado propio', (tester) async {
      // Todo es local: el repositorio no sabe de la red. La pantalla no tiene aviso de conexión.
      await _montar(tester, _RepoFalso(_ventaDelCanvas()));

      expect(find.textContaining('conexión'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
    });
  });
}
