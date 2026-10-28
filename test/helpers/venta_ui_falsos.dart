// El entorno de la vista 27 (Registrar venta) para los tests de pantalla: el catálogo, la fuente de
// precios, la base en memoria y cómo se monta la pantalla.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/presentation/providers/precios_providers.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/cliente_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/nueva_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/precios_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/fuente_de_precios_de_la_venta.dart';
import 'package:colportores_mobile/features/ventas/domain/repositories/venta_repository.dart';
import 'package:colportores_mobile/features/ventas/presentation/pages/nueva_venta_page.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/nueva_venta_notifier.dart';
import 'package:colportores_mobile/features/ventas/presentation/providers/ventas_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'precios_falsos.dart';
import 'venta_falsos.dart';

const maria = ClienteDeLaVenta(
  espacioPersonaId: 'ep-1',
  nombre: 'María Fernández',
  direccion: 'Mataojo 2044 · Depto 3B',
);

const argumentosDeMaria = ArgumentosDeVenta(colportorId: 'col-1', cliente: maria);

/// Un catálogo parecido al de la vista 27: tres que siempre van, libros para elegir, revistas y
/// misioneros, y colecciones de 1 y 2 libros más un pack fijo.
CatalogoLocal catalogoDeVentas({int libros = 5}) {
  const nombres = [
    'Salud y Hogar',
    'Nuestros Hijos',
    'Vida sin estrés',
    'Cocina vegetariana',
    'El hogar feliz',
  ];
  return CatalogoLocal(
    productos: [
      const ProductoDelCatalogo(
        id: 'p-camino',
        nombre: 'El camino a Cristo',
        tipo: TipoDeProducto.misionero,
        esMisionero: true,
      ),
      const ProductoDelCatalogo(
        id: 'p-vida-feliz',
        nombre: 'Vida Feliz',
        tipo: TipoDeProducto.revista,
      ),
      const ProductoDelCatalogo(
        id: 'p-deseado',
        nombre: 'El Deseado de todas las gentes',
        tipo: TipoDeProducto.libro,
      ),
      const ProductoDelCatalogo(
        id: 'p-gran-esperanza',
        nombre: 'La gran esperanza',
        tipo: TipoDeProducto.misionero,
        esMisionero: true,
      ),
      const ProductoDelCatalogo(
        id: 'p-nuestra-salud',
        nombre: 'Nuestra Salud',
        tipo: TipoDeProducto.revista,
      ),
      for (var i = 0; i < libros; i++)
        ProductoDelCatalogo(
          id: 'p-libro-$i',
          nombre: i < nombres.length ? nombres[i] : 'Libro ${i.toString().padLeft(4, '0')}',
          tipo: TipoDeProducto.libro,
          esBonificable: i.isEven,
        ),
    ],
    combos: const [
      ComboDelCatalogo(
        id: 'k-1',
        nombre: 'Colección de 1 libro',
        librosAElegir: 1,
        componentes: [
          ComponenteDelCombo(productoId: 'p-camino'),
          ComponenteDelCombo(productoId: 'p-vida-feliz'),
          ComponenteDelCombo(productoId: 'p-deseado'),
        ],
      ),
      ComboDelCatalogo(
        id: 'k-2',
        nombre: 'Colección de 2 libros',
        librosAElegir: 2,
        componentes: [
          ComponenteDelCombo(productoId: 'p-camino'),
          ComponenteDelCombo(productoId: 'p-vida-feliz'),
          ComponenteDelCombo(productoId: 'p-deseado'),
        ],
      ),
      ComboDelCatalogo(
        id: 'k-fijo',
        nombre: 'Pack Familia',
        componentes: [ComponenteDelCombo(productoId: 'p-camino', cantidad: 2)],
      ),
    ],
    generales: [
      const PrecioDelCatalogo(
        id: 'g-k1',
        comboId: 'k-1',
        centavos: 480000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-k2',
        comboId: 'k-2',
        centavos: 890000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-kf',
        comboId: 'k-fijo',
        centavos: 300000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-camino',
        productoId: 'p-camino',
        centavos: 15000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-gran',
        productoId: 'p-gran-esperanza',
        centavos: 15000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-vf',
        productoId: 'p-vida-feliz',
        centavos: 12000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-ns',
        productoId: 'p-nuestra-salud',
        centavos: 12000,
        validoDesde: '2026-01-01',
      ),
      const PrecioDelCatalogo(
        id: 'g-des',
        productoId: 'p-deseado',
        centavos: 250000,
        validoDesde: '2026-01-01',
      ),
      for (var i = 0; i < libros; i++)
        PrecioDelCatalogo(
          id: 'g-l$i',
          productoId: 'p-libro-$i',
          centavos: 200000 + i,
          validoDesde: '2026-01-01',
        ),
    ],
  );
}

final class FuenteDePreciosDeLaVentaFalsa implements FuenteDePreciosDeLaVenta {
  FuenteDePreciosDeLaVentaFalsa([PreciosDeLaVenta? precios])
    : respuesta = Right(precios ?? const PreciosVigentes(cMontevideo));

  Either<Failure, PreciosDeLaVenta> respuesta;
  var lecturas = 0;
  var fallas = 0;
  Completer<void>? bloqueo;

  @override
  Future<Either<Failure, PreciosDeLaVenta>> leer(String espacioPersonaId) async {
    lecturas++;
    final espera = bloqueo;
    if (espera != null) await espera.future;
    if (fallas > 0) {
      fallas--;
      return const Left(FailurePreciosNoDisponibles());
    }
    return respuesta;
  }
}

/// Todo lo que el test controla de la pantalla de la venta.
final class EntornoDeVenta {
  EntornoDeVenta({CatalogoLocal? catalogo, PreciosDeLaVenta? precios, VentasEnMemoria? ventas})
    : repo = ConsultaDePreciosFalsa(catalogo ?? catalogoDeVentas()),
      fuente = FuenteDePreciosDeLaVentaFalsa(precios),
      ventas = ventas ?? VentasEnMemoria();

  final ConsultaDePreciosFalsa repo;
  final FuenteDePreciosDeLaVentaFalsa fuente;
  final VentasEnMemoria ventas;
  DateTime ahora = DateTime.utc(2026, 10, 28, 13);
  var _ids = 0;

  /// Los ids de las ventas que se generaron, en orden.
  final idsDeVenta = <String>[];

  List<Override> get overrides => [
    consultaDePreciosRepositoryProvider.overrideWithValue(repo),
    fuenteDePreciosDeLaVentaProvider.overrideWithValue(fuente),
    ventaRepositoryProvider.overrideWithValue(ventas),
    relojVentaProvider.overrideWithValue(() => ahora),
    generadorIdVentaProvider.overrideWithValue(() {
      final id = 'id-${++_ids}';
      idsDeVenta.add(id);
      return id;
    }),
  ];
}

/// El resultado con el que se cerró la pantalla, para los tests.
final class Salida {
  VentaGuardada? guardada;
  var cerrada = false;
}

/// Monta la pantalla de la venta sobre una pantalla de inicio desde la que se abre (así se puede
/// probar volver y reentrar).
Future<Salida> montarNuevaVenta(
  WidgetTester tester,
  EntornoDeVenta e, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  ClienteDeLaVenta cliente = maria,
  AntesDeGuardarLaVenta? antesDeGuardar,
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final salida = Salida();
  await tester.pumpWidget(
    ProviderScope(
      overrides: e.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                key: const Key('abrir_venta'),
                onPressed: () async {
                  final g = await Navigator.of(context).push(
                    NuevaVentaPage.ruta(
                      argumentos: ArgumentosDeVenta(colportorId: 'col-1', cliente: cliente),
                      antesDeGuardar: antesDeGuardar,
                    ),
                  );
                  salida.guardada = g;
                  salida.cerrada = true;
                },
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir) {
    await tester.tap(find.byKey(const Key('abrir_venta')));
    await asentar(tester);
  }
  return salida;
}

Future<void> asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Trae [f] a la vista: si la lista todavía no armó ese widget (es perezosa), baja hasta él.
Future<void> verVisible(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final pagina = find.descendant(
      of: find.byType(Scaffold).last,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(f, 200, scrollable: pagina.first);
  }
  await tester.ensureVisible(f.first);
}

/// Toca [f] (lo desplaza a la vista si hace falta) y deja asentar.
Future<void> tocar(WidgetTester tester, Finder f) async {
  await verVisible(tester, f);
  await tester.pump();
  await tester.tap(f.first);
  await asentar(tester);
}

Future<void> escribir(WidgetTester tester, Finder f, String texto) async {
  await verVisible(tester, f);
  await tester.enterText(f.first, texto);
  await asentar(tester);
}
