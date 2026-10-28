import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/componente_vendido.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/linea_de_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_repository.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/nueva_venta_notifier.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/venta_falsos.dart';
import '../../../../helpers/venta_ui_falsos.dart' show argumentosDeMaria, maria;

const _camino = PrecioDeProducto(
  id: 'p-camino',
  nombre: 'El camino a Cristo',
  centavos: 15000,
  origen: OrigenDelPrecio.general,
  tipo: TipoDeProducto.misionero,
  esMisionero: true,
);
const _deseado = PrecioDeProducto(
  id: 'p-deseado',
  nombre: 'El Deseado de todas las gentes',
  centavos: 15000,
  origen: OrigenDelPrecio.general,
  tipo: TipoDeProducto.libro,
);
const _vidaFeliz = PrecioDeProducto(
  id: 'p-vf',
  nombre: 'Vida Feliz',
  centavos: 12000,
  origen: OrigenDelPrecio.general,
  tipo: TipoDeProducto.revista,
);
const _saludYHogar = PrecioDeProducto(
  id: 'p-l0',
  nombre: 'Salud y Hogar',
  centavos: 200000,
  origen: OrigenDelPrecio.general,
  tipo: TipoDeProducto.libro,
);
const _nuestrosHijos = PrecioDeProducto(
  id: 'p-l1',
  nombre: 'Nuestros Hijos',
  centavos: 200001,
  origen: OrigenDelPrecio.general,
  tipo: TipoDeProducto.libro,
);
const _combo2 = PrecioDeCombo(
  id: 'k-2',
  nombre: 'Colección de 2 libros',
  centavos: 890000,
  origen: OrigenDelPrecio.general,
  librosAElegir: 2,
);
const _base = [ComponenteVendido(productoId: 'p-camino'), ComponenteVendido(productoId: 'p-vf')];

void main() {
  late VentasEnMemoria repo;
  late ProviderContainer c;
  var ids = 0;

  setUp(() {
    ids = 0;
    repo = VentasEnMemoria();
    c = ProviderContainer(
      overrides: [
        ventaRepositoryProvider.overrideWithValue(repo),
        generadorIdVentaProvider.overrideWithValue(() => 'id-${++ids}'),
        relojVentaProvider.overrideWithValue(() => DateTime.utc(2026, 10, 28, 13)),
      ],
    );
    addTearDown(c.dispose);
    c.listen(nuevaVentaProvider(argumentosDeMaria), (_, _) {});
  });

  NuevaVentaNotifier notifier() => c.read(nuevaVentaProvider(argumentosDeMaria).notifier);
  NuevaVentaState estado() => c.read(nuevaVentaProvider(argumentosDeMaria));

  void coleccion(List<PrecioDeProducto> libros, {String? reemplaza}) => notifier().ponerColeccion(
    combo: _combo2,
    base: _base,
    nombresBase: const ['El camino a Cristo', 'Vida Feliz'],
    elegidos: libros,
    reemplazaClave: reemplaza,
  );

  group('productos sueltos', () {
    test('agregar suma al total; cantidad 0 saca; otra cantidad reemplaza', () {
      notifier().fijarProductos(const [
        ProductoElegido(producto: _vidaFeliz, cantidad: 2),
        ProductoElegido(producto: _deseado, cantidad: 1),
      ]);
      expect(estado().totalCalculado, 39000);

      notifier().fijarProductos(const [ProductoElegido(producto: _vidaFeliz, cantidad: 3)]);
      expect(estado().renglones.length, 2);
      expect(estado().cantidadDe('p-vf'), 3);
      expect(estado().totalCalculado, 51000);

      notifier().fijarProductos(const [ProductoElegido(producto: _deseado, cantidad: 0)]);
      expect(estado().renglones.map((r) => r.titulo), ['Vida Feliz']);
    });

    test('un misionero va a \$ 0, sin el precio de lista, y queda en la venta', () {
      notifier().fijarProductos(const [ProductoElegido(producto: _camino, cantidad: 3)]);

      final linea = estado().renglones.single.linea as LineaDeProducto;
      expect(linea.precioCentavos, 0, reason: 'no lleva el precio de lista');
      expect(linea.sinCobrar, isTrue);
      expect(estado().totalCalculado, 0);
      expect(estado().cantidadDe('p-camino'), 3);
    });

    test('un misionero junto a lo que se cobra no suma al total', () {
      notifier().fijarProductos(const [
        ProductoElegido(producto: _camino, cantidad: 3),
        ProductoElegido(producto: _vidaFeliz, cantidad: 2),
      ]);

      expect(estado().totalCalculado, 24000);
      expect(estado().cobraAlgo, isTrue);
    });

    test('cambiar la cantidad de un misionero reemplaza el renglón, no lo duplica', () {
      notifier().fijarProductos(const [ProductoElegido(producto: _camino, cantidad: 3)]);
      notifier().fijarProductos(const [ProductoElegido(producto: _camino, cantidad: 5)]);

      expect(estado().renglones, hasLength(1));
      expect(estado().cantidadDe('p-camino'), 5);
    });
  });

  group('una venta solo de misioneros: no cuenta como venta', () {
    Future<void> soloMisioneros() async {
      notifier().fijarProductos(const [ProductoElegido(producto: _camino, cantidad: 2)]);
      await notifier().escribirTalonario('77');
    }

    test('no hay total que cambiar a mano: vale 0 aunque haya quedado abierto', () async {
      notifier()
        ..fijarProductos(const [
          ProductoElegido(producto: _camino, cantidad: 2),
          ProductoElegido(producto: _vidaFeliz, cantidad: 1),
        ])
        ..cambiarElMonto()
        ..escribirMonto('500')
        ..escribirMotivo('a voluntad');
      await notifier().escribirTalonario('77');
      notifier().quitar(estado().renglones.last.clave);

      expect(estado().cobraAlgo, isFalse);
      expect(estado().cambiandoElMonto, isFalse);
      expect(estado().puedeRegistrar, isTrue);

      await notifier().registrar();

      final r = repo.recibidas.single;
      expect(r.venta.montoTotalCentavos, 0);
      expect(r.venta.motivoMontoManual, isNull);
      expect(r.diferencia, isNull);
      expect(r.items.single.precioUnitarioCentavos, 0);
    });

    test('se guarda para bajar el stock, con precio 0 y subtotal 0', () async {
      await soloMisioneros();

      final guardada = await notifier().registrar();

      expect(guardada, isNotNull);
      final item = repo.recibidas.single.items.single;
      expect(
        [item.productoId, item.cantidad, item.precioUnitarioCentavos, item.subtotalCentavos],
        ['p-camino', 2, 0, 0],
      );
      expect(guardada!.totalCentavos, 0);
    });
  });

  group('colecciones', () {
    test('una colección lleva la base y los libros elegidos, ordenados', () {
      coleccion(const [_nuestrosHijos, _saludYHogar]);

      final linea = estado().renglones.single.linea as LineaDeCombo;
      expect(linea.comboId, 'k-2');
      expect(
        [for (final c in linea.componentes) c.productoId],
        ['p-camino', 'p-l0', 'p-l1', 'p-vf'],
      );
      expect(linea.precioCentavos, 890000);
      expect(estado().totalCalculado, 890000);
    });

    test('la misma colección con los libros en otro orden es una de cantidad 2', () {
      coleccion(const [_saludYHogar, _nuestrosHijos]);
      coleccion(const [_nuestrosHijos, _saludYHogar]);

      expect(estado().renglones, hasLength(1));
      expect(estado().renglones.single.linea.cantidad, 2);
      expect(estado().totalCalculado, 1780000);
    });

    test('con otros libros es otro ítem de cantidad 1', () {
      coleccion(const [_saludYHogar, _nuestrosHijos]);
      coleccion(const [_saludYHogar, _saludYHogar]);

      expect(estado().renglones.map((r) => r.linea.cantidad), [1, 1]);
      final repetido = estado().renglones.last.linea as LineaDeCombo;
      expect(repetido.componentes.firstWhere((c) => c.productoId == 'p-l0').cantidad, 2);
    });

    test('cambiar un libro de una colección reemplaza esa y no toca las demás', () {
      coleccion(const [_saludYHogar, _nuestrosHijos]);
      coleccion(const [_nuestrosHijos, _nuestrosHijos]);
      final primera = estado().renglones.first.clave;

      coleccion(const [_saludYHogar, _saludYHogar], reemplaza: primera);

      expect(estado().renglones, hasLength(2));
      expect(estado().renglones.first.idsElegidos, ['p-l1', 'p-l1']);
      expect(estado().renglones.last.idsElegidos, ['p-l0', 'p-l0']);
    });

    test('cambiar los libros de una de varias unidades cambia solo una', () {
      coleccion(const [_saludYHogar, _nuestrosHijos]);
      coleccion(const [_saludYHogar, _nuestrosHijos]);
      final clave = estado().renglones.single.clave;

      coleccion(const [_nuestrosHijos, _nuestrosHijos], reemplaza: clave);

      expect(estado().renglones.map((r) => r.linea.cantidad), [1, 1]);
      expect(estado().totalCalculado, 1780000);
    });
  });

  group('talonario', () {
    test('un número usado marca el repetido con el día de Montevideo; otro lo limpia', () async {
      repo.talonario = VentaDelTalonario(ventaId: 'v', fecha: DateTime.utc(2026, 3, 13, 1));

      await notifier().escribirTalonario(' 0042 ');
      expect(estado().talonarioRepetido!.mensaje, contains('0042'));
      expect(estado().talonarioRepetido!.mensaje, contains('(venta del 12/03)'));

      repo.talonario = null;
      await notifier().escribirTalonario('0043');
      expect(estado().talonarioRepetido, isNull);
    });

    test('una respuesta vieja no pisa al número que se está escribiendo ahora', () async {
      final primera = Completer<Either<Failure, VentaDelTalonario?>>();
      final repoLento = _TalonarioLento(primera.future);
      final c2 = ProviderContainer(
        overrides: [
          ventaRepositoryProvider.overrideWithValue(repoLento),
          generadorIdVentaProvider.overrideWithValue(() => 'x'),
        ],
      );
      addTearDown(c2.dispose);
      c2.listen(nuevaVentaProvider(argumentosDeMaria), (_, _) {});
      final n = c2.read(nuevaVentaProvider(argumentosDeMaria).notifier);

      final vieja = n.escribirTalonario('0042');
      await n.escribirTalonario('');
      primera.complete(
        Right(VentaDelTalonario(ventaId: 'v', fecha: DateTime.utc(2026, 3, 12, 15))),
      );
      await vieja;

      expect(c2.read(nuevaVentaProvider(argumentosDeMaria)).talonarioRepetido, isNull);
    });

    test('si no se puede mirar, no inventa un repetido', () async {
      final c2 = ProviderContainer(
        overrides: [
          ventaRepositoryProvider.overrideWith((ref) => throw StateError('sin base')),
          generadorIdVentaProvider.overrideWithValue(() => 'x'),
        ],
      );
      addTearDown(c2.dispose);
      c2.listen(nuevaVentaProvider(argumentosDeMaria), (_, _) {});

      await c2.read(nuevaVentaProvider(argumentosDeMaria).notifier).escribirTalonario('0042');

      expect(c2.read(nuevaVentaProvider(argumentosDeMaria)).talonarioRepetido, isNull);
    });
  });

  group('registrar', () {
    void completa() {
      notifier().fijarProductos(const [ProductoElegido(producto: _vidaFeliz, cantidad: 2)]);
    }

    test('sin talonario, sin ítems o con un monto inválido no hace nada', () async {
      expect(await notifier().registrar(), isNull);
      completa();
      expect(await notifier().registrar(), isNull);
      await notifier().escribirTalonario('1');
      notifier().cambiarElMonto();
      notifier().escribirMonto('abc');
      expect(await notifier().registrar(), isNull);

      expect(repo.recibidas, isEmpty);
    });

    test('dos llamadas juntas guardan una sola vez', () async {
      completa();
      await notifier().escribirTalonario('1');
      final espera = Completer<void>();
      repo.compuerta = espera.future;

      final a = notifier().registrar();
      final b = notifier().registrar();
      espera.complete();

      expect(await b, isNull);
      expect(await a, isNotNull);
      expect(repo.recibidas, hasLength(1));
    });

    test(
      'tras una falla todo sigue igual, el id de la venta también, y no queda «guardando»',
      () async {
        completa();
        await notifier().escribirTalonario('1');
        repo.respuesta = const FailureVentaNoGuardada();

        expect(await notifier().registrar(), isNull);
        expect(estado().guardando, isFalse);
        expect(estado().falla, isA<FailureVentaNoGuardada>());
        expect(estado().renglones, hasLength(1));
        expect(estado().talonario, '1');

        repo.respuesta = null;
        expect(await notifier().registrar(), isNotNull);
        expect(repo.recibidas, hasLength(2));
        expect(repo.recibidas[0].venta.id, repo.recibidas[1].venta.id);
      },
    );

    test('una excepción de la base (sin base abierta) es «no se guardó», no un cuelgue', () async {
      final c2 = ProviderContainer(
        overrides: [
          ventaRepositoryProvider.overrideWith((ref) => throw StateError('sin base')),
          generadorIdVentaProvider.overrideWithValue(() => 'x'),
        ],
      );
      addTearDown(c2.dispose);
      c2.listen(nuevaVentaProvider(argumentosDeMaria), (_, _) {});
      final n = c2.read(nuevaVentaProvider(argumentosDeMaria).notifier);
      n.fijarProductos(const [ProductoElegido(producto: _vidaFeliz, cantidad: 1)]);
      await n.escribirTalonario('1');

      expect(await n.registrar(), isNull);
      final s = c2.read(nuevaVentaProvider(argumentosDeMaria));
      expect(s.guardando, isFalse);
      expect(s.falla, isA<FailureVentaNoGuardada>());
    });

    test(
      'el motivo y el monto a mano viajan solo mientras «Cambiar el monto» está abierto',
      () async {
        completa();
        await notifier().escribirTalonario('1');
        notifier()
          ..cambiarElMonto()
          ..escribirMonto('100')
          ..escribirMotivo('  porque sí ')
          ..usarElMontoCalculado();

        await notifier().registrar();

        final r = repo.recibidas.single;
        expect(r.venta.montoTotalCentavos, 24000);
        expect(r.venta.motivoMontoManual, isNull);
      },
    );

    test('al ver el id de la visita de la entrevista lo ata a la venta', () async {
      final c2 = ProviderContainer(
        overrides: [
          ventaRepositoryProvider.overrideWithValue(repo),
          generadorIdVentaProvider.overrideWithValue(() => 'x'),
        ],
      );
      addTearDown(c2.dispose);
      const conVisita = ArgumentosDeVenta(colportorId: 'col-1', cliente: maria, visitaId: 'vis-9');
      c2.listen(nuevaVentaProvider(conVisita), (_, _) {});
      final n = c2.read(nuevaVentaProvider(conVisita).notifier);
      n.fijarProductos(const [ProductoElegido(producto: _vidaFeliz, cantidad: 1)]);
      await n.escribirTalonario('1');

      await n.registrar();

      expect(repo.recibidas.single.venta.visitaId, 'vis-9');
    });
  });

  test('los datos de la persona no aparecen en el toString de lo que se arma', () {
    final texto = '${argumentosDeMaria.cliente} ${estado()} $argumentosDeMaria';

    expect(texto, isNot(contains('María')));
    expect(texto, isNot(contains('Mataojo')));
  });

  test('los ítems guardados llevan el id de la venta', () async {
    notifier().fijarProductos(const [ProductoElegido(producto: _vidaFeliz, cantidad: 2)]);
    await notifier().escribirTalonario('1');

    final g = await notifier().registrar();

    expect(g!.items, isNotEmpty);
    expect(g.items.every((i) => i.ventaId == g.venta.id), isTrue);
  });
}

final class _TalonarioLento extends VentasEnMemoria {
  _TalonarioLento(this._respuesta);

  final Future<Either<Failure, VentaDelTalonario?>> _respuesta;
  var _llamadas = 0;

  @override
  Future<Either<Failure, VentaDelTalonario?>> talonarioUsado({
    required String colportorId,
    required String numero,
    required DateTime fecha,
  }) => _llamadas++ == 0 ? _respuesta : Future.value(const Right(null));
}
