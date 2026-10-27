// HU-CAT-006 (vista 26, «Precios»): un test por artboard (26·01 a 26·11), por los estados que el
// canvas no dibuja (elegir una ciudad, pestaña vacía, sin campaña) y por cada caso límite: doble
// toque, falla a mitad de la acción, acciones seguidas, volver y reentrar, datos límite y texto al 200 %.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/catalogo/presentation/pages/precios_page.dart';
import 'package:colportores_mobile/features/catalogo/presentation/providers/precios_providers.dart';
import 'package:colportores_mobile/features/catalogo/presentation/widgets/hoja_detalle_combo.dart';
import 'package:colportores_mobile/features/catalogo/presentation/widgets/hoja_otra_ciudad.dart';
import 'package:colportores_mobile/features/inicio/presentation/widgets/barra_pestanas_inicio.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/precios_falsos.dart';

/// Miércoles 28/10/2026, 10:00 (hora local).
final _ahora = DateTime(2026, 10, 28, 10);

/// Todo lo que el test controla de la pantalla.
final class _Entorno {
  _Entorno({
    ConsultaDePreciosFalsa? repo,
    FuenteDeCiudadesFalsa? ciudades,
    GpsFalso? gps,
    CiudadesFalsas? alta,
    DateTime? bajada,
    this.conexion = TipoConexion.wifi,
    this.dias = 15,
  }) : repo = repo ?? ConsultaDePreciosFalsa(),
       ciudades = ciudades ?? FuenteDeCiudadesFalsa(),
       gps = gps ?? GpsFalso(),
       alta = alta ?? CiudadesFalsas(),
       fecha = FechaDeLosPreciosFalsa(bajada ?? DateTime(2026, 10, 22, 18));

  final ConsultaDePreciosFalsa repo;
  final FuenteDeCiudadesFalsa ciudades;
  final GpsFalso gps;
  final CiudadesFalsas alta;
  final FechaDeLosPreciosFalsa fecha;
  TipoConexion conexion;
  int dias;
  DateTime ahora = _ahora;

  List<Override> get overrides => [
    consultaDePreciosRepositoryProvider.overrideWithValue(repo),
    fuenteDeCiudadesParaPreciosProvider.overrideWithValue(ciudades),
    fechaDeLosPreciosProvider.overrideWithValue(fecha),
    diasDeAntiguedadDePreciosProvider.overrideWithValue(DiasFalsos(dias)),
    relojPreciosProvider.overrideWithValue(() => ahora),
    esperaDelGpsPreciosProvider.overrideWithValue(const Duration(milliseconds: 200)),
    proveedorGpsProvider.overrideWithValue(gps),
    ciudadesParaAltaProvider.overrideWithValue(alta),
    conexionProvider.overrideWith((ref) => Stream.value(conexion)),
  ];
}

/// Monta la pantalla de Precios sola.
Future<void> _montar(
  WidgetTester tester,
  _Entorno e, {
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool asentar = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: e.overrides,
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const PreciosPage(colportorId: 'col-1'),
      ),
    ),
  );
  if (asentar) await _asentar(tester);
}

Future<void> _asentar(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
}

/// Vuelve al principio de la lista (lo de arriba se desarma al salir de la pantalla).
Future<void> _alInicio(WidgetTester tester) async {
  for (var i = 0; i < 100; i++) {
    await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, 2000));
    await tester.pump();
  }
}

/// Desliza la lista hasta que [f] se construya: las filas se arman a medida que se ven.
Future<void> _desplazarHasta(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 100 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byKey(const Key('precios_scroll')), const Offset(0, -600));
    await tester.pump();
  }
  expect(f, findsOneWidget, reason: 'la lista no llegó a construirlo');
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) await _alInicio(tester);
  if (f.evaluate().isEmpty) await _desplazarHasta(tester, f);
  // El alto de lo que falta construir se estima: a veces hace falta acercarse en más de un paso.
  final alto = tester.view.physicalSize.height;
  for (var i = 0; i < 6; i++) {
    await tester.ensureVisible(f);
    await tester.pump();
    if (tester.getCenter(f).dy < alto - 80) break;
  }
  // Una fila más alta que media pantalla (texto al 200 %) se toca cerca de su borde de arriba.
  final r = tester.getRect(f);
  await tester.tapAt(r.height > alto / 2 ? r.topCenter + const Offset(0, 30) : r.center);
  await _asentar(tester);
}

Finder _chip(String nombre) => find.byKey(Key('precios_chip_$nombre'));
final _verOtra = find.byKey(const Key('precios_ver_otra'));
final _busqueda = find.byKey(const Key('precios_busqueda'));

Future<void> _irA(WidgetTester tester, String chip) => _tocar(tester, _chip(chip));

void main() {
  group('26·01 Colecciones', () {
    testWidgets('abre con donde está: la ciudad, los chips y las colecciones con su precio', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      expect(find.text('VENTAS'), findsOneWidget);
      expect(find.text('Precios'), findsOneWidget);
      expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(_verOtra, findsOneWidget);
      for (final c in ['Colecciones', 'Libros', 'Misioneros', 'Revistas']) {
        expect(find.text(c), findsOneWidget);
      }
      // Los combos van de menos a más libros a elegir; el precio es el de la excepción de la ciudad.
      expect(find.text('Pack Familia'), findsOneWidget);
      expect(find.text('Colección de 2 libros'), findsOneWidget);
      expect(find.text(r'$ 8.900'), findsOneWidget);
      expect(find.text(r'$ 3.000'), findsOneWidget);
      expect(
        find.textContaining('Misionero Esperanza, Revista Vida y Salud + 2 a elegir'),
        findsOneWidget,
      );
      expect(find.text(r'$ 4.450 por libro'), findsOneWidget);
      // Las colecciones no se buscan.
      expect(_busqueda, findsNothing);
      expect(find.text('El Deseado de Todas las Gentes'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('la barra de abajo tiene Ventas seleccionada', (tester) async {
      await _montar(tester, _Entorno());
      final barra = tester.widget<BarraPestanasInicio>(find.byType(BarraPestanasInicio));
      expect(barra.seleccionada, PestanaInicio.ventas);
    });
  });

  group('26·02 Libros', () {
    testWidgets(
      'lista los libros con su código, su etiqueta y el precio de la ciudad o el general',
      (tester) async {
        await _montar(tester, _Entorno());
        await _irA(tester, 'libros');
        expect(find.text('El Deseado de Todas las Gentes'), findsOneWidget);
        expect(find.text('ACES-0214'), findsOneWidget);
        expect(find.text(r'$ 4.800'), findsOneWidget, reason: 'la excepción de Montevideo');
        expect(find.text('El Camino a Cristo'), findsOneWidget);
        expect(find.text(r'$ 1.200'), findsOneWidget, reason: 'el precio general');
        expect(find.text('◆ Bonificable'), findsNWidgets(2));
        // Sin precio vigente, el material y las colecciones no aparecen.
        expect(find.text('Libro sin precio'), findsNothing);
        expect(find.text('Folleto de la casa'), findsNothing);
        expect(find.text('Pack Familia'), findsNothing);
        expect(_busqueda, findsOneWidget);
        expect(find.text('Buscar por nombre o código'), findsOneWidget);
      },
    );

    testWidgets('Misioneros lleva ✦ Misionero y Revistas la etiqueta Revista', (tester) async {
      await _montar(tester, _Entorno());
      await _irA(tester, 'misioneros');
      expect(find.text('Misionero Esperanza'), findsOneWidget);
      expect(find.text('✦ Misionero'), findsOneWidget);
      expect(find.text(r'$ 450'), findsOneWidget);
      await _irA(tester, 'revistas');
      expect(find.text('Revista Vida y Salud'), findsOneWidget);
      expect(find.text('Revista'), findsOneWidget, reason: 'la etiqueta');
      expect(find.text(r'$ 250'), findsOneWidget);
    });

    testWidgets('busca por nombre, sin tildes, y por código; el ✕ borra la búsqueda', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await _irA(tester, 'libros');
      await tester.enterText(_busqueda, 'DESEADÓ');
      await _asentar(tester);
      expect(find.text('El Deseado de Todas las Gentes'), findsOneWidget);
      expect(find.text('El Camino a Cristo'), findsNothing);

      await tester.enterText(_busqueda, 'camino');
      await _asentar(tester);
      expect(find.text('El Camino a Cristo'), findsOneWidget);
      expect(find.text('El Deseado de Todas las Gentes'), findsNothing);

      await tester.enterText(_busqueda, 'aces-02');
      await _asentar(tester);
      expect(find.text('El Deseado de Todas las Gentes'), findsOneWidget);

      await _tocar(tester, find.byKey(const Key('precios_borrar_busqueda')));
      expect(find.text('El Camino a Cristo'), findsOneWidget);
      expect(find.byKey(const Key('precios_borrar_busqueda')), findsNothing);
    });
  });

  group('26·03 Detalle de una colección', () {
    testWidgets('abre la hoja con lo que lleva, los libros a elegir y el precio en la ciudad', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, find.byKey(const ValueKey('k-2')));
      expect(find.byType(HojaDetalleDelCombo), findsOneWidget);
      expect(find.textContaining('Se vende como un solo ítem.'), findsOneWidget);
      expect(find.text('Siempre van'), findsOneWidget);
      expect(find.text('Misionero Esperanza, Revista Vida y Salud'), findsOneWidget);
      expect(find.text('Libros a elegir'), findsOneWidget);
      expect(find.text('Precio en Montevideo'), findsOneWidget);
      expect(find.byKey(const Key('precios_detalle_precio')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('precios_detalle_precio'))).data, r'$ 8.900');
      await _tocar(tester, find.byKey(const Key('precios_cerrar_detalle')));
      expect(find.byType(HojaDetalleDelCombo), findsNothing);
    });

    testWidgets('un combo fijo no tiene «Libros a elegir»', (tester) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, find.byKey(const ValueKey('k-fijo')));
      expect(find.text('Libros a elegir'), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HojaDetalleDelCombo),
          matching: find.text('2 × El Camino a Cristo'),
        ),
        findsOneWidget,
      );
    });
  });

  group('26·04 Ver otra ciudad', () {
    testWidgets('la hoja lista las ciudades de sus campañas con la de donde está marcada', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, _verOtra);
      expect(find.byType(HojaOtraCiudad), findsOneWidget);
      expect(find.text('Ver precios de'), findsOneWidget);
      expect(find.text('Donde estás · Primavera 2026'), findsOneWidget);
      expect(find.text('Primavera 2026'), findsOneWidget);
      expect(
        find.text('Solo campañas en curso o por empezar: las terminadas no se muestran.'),
        findsOneWidget,
      );
      expect(find.text('Ver precios'), findsOneWidget);
    });

    testWidgets('con una sola ciudad no hay «Ver otra»', (tester) async {
      final e = _Entorno(
        ciudades: FuenteDeCiudadesFalsa(
          const ContextoDeCiudades(ciudades: [cMontevideo], ciudadDeMiZonaId: 'ciu-mvd'),
        ),
      );
      await _montar(tester, e);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(_verOtra, findsNothing);
    });

    testWidgets('cerrar la hoja sin aplicar deja la ciudad como estaba', (tester) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await tester.tapAt(const Offset(195, 20));
      await _asentar(tester);
      expect(find.byType(HojaOtraCiudad), findsNothing);
      expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
    });
  });

  group('26·05 Viendo otra ciudad', () {
    Future<_Entorno> verCanelones(WidgetTester tester) async {
      final e = _Entorno();
      e.repo.porCiudad['cc-can'] = const CatalogoLocal(
        productos: [
          ProductoDelCatalogo(
            id: 'p-camino',
            nombre: 'El Camino a Cristo',
            tipo: TipoDeProducto.libro,
          ),
        ],
        excepciones: [
          PrecioDelCatalogo(
            id: 'e-c',
            productoId: 'p-camino',
            centavos: 99900,
            validoDesde: '2026-01-01',
          ),
        ],
      );
      await _montar(tester, e);
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      return e;
    }

    testWidgets('dice que mira otra ciudad y con qué precios se vende, sin cambiar la venta', (
      tester,
    ) async {
      await verCanelones(tester);
      expect(find.text('ESTÁS VIENDO OTRA CIUDAD'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
      expect(
        find.text(
          'Estos son los precios de Canelones. Si vendés en Montevideo, se usan los de Montevideo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Volver a donde estoy'), findsOneWidget);
    });

    testWidgets('los precios son los de la ciudad elegida y «Volver a donde estoy» regresa', (
      tester,
    ) async {
      final e = await verCanelones(tester);
      await _irA(tester, 'libros');
      expect(find.text(r'$ 999'), findsOneWidget);
      expect(e.repo.pedidos, containsAll(['cc-mvd', 'cc-can']));
      await _tocar(tester, find.text('Volver a donde estoy'));
      expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(find.text('Volver a donde estoy'), findsNothing);
    });

    testWidgets('elegir de nuevo la ciudad de entrada es volver a ella', (tester) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-mvd')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
      expect(find.text('ESTÁS VIENDO OTRA CIUDAD'), findsNothing);
    });
  });

  group('26·06 Sin ubicación', () {
    testWidgets('sin GPS abre con la ciudad de su zona y se lo dice', (tester) async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado)),
      );
      await _montar(tester, _Entorno(gps: gps));
      expect(find.text('CIUDAD DE TU ZONA · SIN GPS'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
      expect(
        find.text('No sabemos dónde estás. Te mostramos Montevideo, la ciudad de tu zona.'),
        findsOneWidget,
      );
      expect(_verOtra, findsOneWidget);
    });

    testWidgets('un GPS que no contesta no cuelga la pantalla', (tester) async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      await _montar(tester, _Entorno(gps: gps), asentar: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await _asentar(tester);
      expect(find.text('CIUDAD DE TU ZONA · SIN GPS'), findsOneWidget);
      gps.bloqueo!.complete();
      await tester.pump();
    });

    testWidgets('un GPS fuera de todas sus ciudades también abre con la de su zona', (
      tester,
    ) async {
      final alta = CiudadesFalsas(
        propone: (_) => const CiudadPropuesta(
          CiudadCatalogo(id: 'ciu-otra', nombre: 'Otra'),
          OrigenPropuesta.detectada,
        ),
      );
      await _montar(tester, _Entorno(alta: alta));
      expect(find.text('CIUDAD DE TU ZONA · SIN GPS'), findsOneWidget);
    });

    testWidgets('con GPS en otra de sus ciudades abre en esa', (tester) async {
      final alta = CiudadesFalsas(
        propone: (_) => const CiudadPropuesta(canelones, OrigenPropuesta.detectada),
      );
      await _montar(tester, _Entorno(alta: alta));
      expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
    });

    testWidgets('sin zona ni GPS elige ella la ciudad y los precios aparecen', (tester) async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      final e = _Entorno(
        gps: gps,
        ciudades: FuenteDeCiudadesFalsa(
          const ContextoDeCiudades(ciudades: [cMontevideo, cCanelones]),
        ),
      );
      await _montar(tester, e);
      expect(find.text('Elegí una ciudad'), findsOneWidget);
      expect(find.text('Pack Familia'), findsNothing);
      await _tocar(tester, find.text('Ver otra ciudad'));
      expect(find.byType(HojaOtraCiudad), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-mvd')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      expect(find.text('Pack Familia'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
    });
  });

  group('26·07 Búsqueda sin resultados', () {
    testWidgets('dice qué no encontró y por qué puede ser', (tester) async {
      await _montar(tester, _Entorno());
      await _irA(tester, 'libros');
      await tester.enterText(_busqueda, 'zzzz');
      await _asentar(tester);
      expect(find.text('Ningún libro con precio en Montevideo coincide'), findsOneWidget);
      expect(
        find.text('Si esperabas verlo, puede que no tenga precio en esta ciudad.'),
        findsOneWidget,
      );
      expect(find.text('El Camino a Cristo'), findsNothing);
    });
  });

  group('26·08 Cargando', () {
    testWidgets('muestra tres bloques de carga mientras llegan los precios', (tester) async {
      final repo = ConsultaDePreciosFalsa()..bloqueo = Completer<void>();
      await _montar(tester, _Entorno(repo: repo));
      expect(find.byKey(const Key('precios_esqueleto')), findsOneWidget);
      final bloques = find.descendant(
        of: find.byKey(const Key('precios_esqueleto')),
        matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxHeight == 66),
      );
      expect(bloques, findsNWidgets(3));
      repo.bloqueo!.complete();
      await _asentar(tester);
      expect(find.byKey(const Key('precios_esqueleto')), findsNothing);
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('mientras lee las ciudades también muestra la carga', (tester) async {
      final ciudades = FuenteDeCiudadesFalsa()..bloqueo = Completer<void>();
      await _montar(tester, _Entorno(ciudades: ciudades));
      expect(find.byKey(const Key('precios_esqueleto')), findsOneWidget);
      ciudades.bloqueo!.complete();
      await _asentar(tester);
      expect(find.text('Pack Familia'), findsOneWidget);
    });
  });

  group('26·09 Sin conexión', () {
    testWidgets('los precios son los guardados y dice de cuándo', (tester) async {
      await _montar(tester, _Entorno(conexion: TipoConexion.sinConexion));
      expect(
        find.text('Sin conexión. Son los precios que recibiste el 22/10 a las 18:00.'),
        findsOneWidget,
      );
      expect(find.text('Pack Familia'), findsOneWidget);
      expect(find.text('Montevideo'), findsOneWidget);
    });

    testWidgets('sin saber cuándo bajaron no inventa una fecha', (tester) async {
      final e = _Entorno(conexion: TipoConexion.sinConexion);
      e.fecha.fecha = null;
      await _montar(tester, e);
      expect(find.text('Sin conexión. Son los precios guardados en tu teléfono.'), findsOneWidget);
    });

    testWidgets('a los 15 días el aviso se pone fuerte, pero se sigue pudiendo consultar', (
      tester,
    ) async {
      final e = _Entorno(conexion: TipoConexion.sinConexion, bajada: DateTime(2026, 10, 10, 9));
      await _montar(tester, e);
      expect(find.textContaining('tienen 18 días'), findsOneWidget);
      expect(find.textContaining('podés seguir vendiendo'), findsOneWidget);
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('con conexión no hay aviso de conexión', (tester) async {
      await _montar(tester, _Entorno());
      expect(find.textContaining('Sin conexión'), findsNothing);
    });

    testWidgets('el umbral lo fija el parámetro global', (tester) async {
      final e = _Entorno(
        conexion: TipoConexion.sinConexion,
        bajada: DateTime(2026, 10, 22, 18),
        dias: 5,
      );
      await _montar(tester, e);
      expect(find.textContaining('tienen 5 días'), findsOneWidget);
    });
  });

  group('26·10 Error al leer', () {
    testWidgets('si no se puede leer el catálogo lo dice y deja reintentar', (tester) async {
      final repo = ConsultaDePreciosFalsa()..fallas = 1;
      await _montar(tester, _Entorno(repo: repo));
      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
      expect(find.text('Pack Familia'), findsNothing);
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsNothing);
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('si no se pueden leer las ciudades también', (tester) async {
      final ciudades = FuenteDeCiudadesFalsa()..fallas = 1;
      await _montar(tester, _Entorno(ciudades: ciudades));
      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('sin ninguna réplica (las fuentes reales) muestra el error y no se cuelga', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            fechaDeLosPreciosProvider.overrideWithValue(FechaDeLosPreciosFalsa(null)),
            esperaDelGpsPreciosProvider.overrideWithValue(const Duration(milliseconds: 50)),
            conexionProvider.overrideWith((ref) => Stream.value(TipoConexion.wifi)),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: const PreciosPage(colportorId: 'col-1'),
          ),
        ),
      );
      await _asentar(tester);
      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
    });
  });

  group('26·11 Solo una campaña terminada', () {
    testWidgets('dice cuál terminó y que sus precios ya no se usan', (tester) async {
      final e = _Entorno(
        ciudades: FuenteDeCiudadesFalsa(
          ContextoDeCiudades(
            campaniaTerminada: CampaniaTerminada(
              nombre: 'Primavera 2026',
              terminoEl: DateTime(2026, 12, 15),
            ),
          ),
        ),
      );
      await _montar(tester, e);
      expect(find.text('No tenés precios vigentes'), findsOneWidget);
      expect(
        find.text(
          'Primavera 2026 terminó el 15/12 y sus precios ya no se usan. Cuando te inscriban en otra campaña, vas a ver sus precios acá.',
        ),
        findsOneWidget,
      );
      expect(_verOtra, findsNothing);
    });

    testWidgets('sin campaña alguna lo dice sin inventar una', (tester) async {
      final e = _Entorno(ciudades: FuenteDeCiudadesFalsa(const ContextoDeCiudades()));
      await _montar(tester, e);
      expect(find.text('No tenés precios vigentes'), findsOneWidget);
      expect(
        find.text('Cuando te inscriban en una campaña, vas a ver sus precios acá.'),
        findsOneWidget,
      );
    });
  });

  group('pestaña vacía (el canvas no la dibuja)', () {
    testWidgets('una pestaña sin ítems con precio lo dice', (tester) async {
      final repo = ConsultaDePreciosFalsa(const CatalogoLocal());
      await _montar(tester, _Entorno(repo: repo));
      expect(find.text('No hay colecciones con precio en Montevideo'), findsOneWidget);
      await _irA(tester, 'revistas');
      expect(find.text('No hay revistas con precio en Montevideo'), findsOneWidget);
      expect(
        find.text('Si esperabas verlos, puede que no tengan precio en esta ciudad.'),
        findsOneWidget,
      );
    });
  });

  group('casos límite', () {
    testWidgets('doble toque en una colección abre una sola hoja', (tester) async {
      await _montar(tester, _Entorno());
      final fila = find.byKey(const ValueKey('k-2'));
      await tester.tap(fila);
      await tester.tap(fila);
      await _asentar(tester);
      expect(find.byType(HojaDetalleDelCombo), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('precios_cerrar_detalle')));
      expect(find.byType(HojaDetalleDelCombo), findsNothing);
      // Cerrada la primera, se puede abrir otra.
      await _tocar(tester, fila);
      expect(find.byType(HojaDetalleDelCombo), findsOneWidget);
    });

    testWidgets('doble toque en «Ver otra» y en «Ver precios» no apila hojas ni cambia dos veces', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await tester.tap(_verOtra);
      await tester.tap(_verOtra);
      await _asentar(tester);
      expect(find.byType(HojaOtraCiudad), findsOneWidget);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      final aplicar = find.byKey(const Key('precios_aplicar_ciudad'));
      await tester.tap(aplicar);
      await tester.tap(aplicar, warnIfMissed: false);
      await _asentar(tester);
      expect(find.byType(HojaOtraCiudad), findsNothing);
      expect(find.text('ESTÁS VIENDO OTRA CIUDAD'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('si la lectura falla varias veces el botón sigue habilitado hasta que sale', (
      tester,
    ) async {
      final repo = ConsultaDePreciosFalsa()..fallas = 2;
      await _montar(tester, _Entorno(repo: repo));
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text('Reintentar'), findsOneWidget, reason: 'falló otra vez: sigue el botón');
      await _tocar(tester, find.text('Reintentar'));
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('si la ciudad elegida falla, volver a la de entrada recupera los precios', (
      tester,
    ) async {
      final e = _Entorno();
      await _montar(tester, e);
      e.repo.fallas = 1;
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      expect(find.text('No pudimos leer los precios guardados en tu teléfono.'), findsOneWidget);
      await _tocar(tester, find.text('Volver a donde estoy'));
      expect(find.text('Pack Familia'), findsOneWidget);
    });

    testWidgets('dos pestañas seguidas sin esperar quedan en la última, con su búsqueda limpia', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await _irA(tester, 'libros');
      await tester.enterText(_busqueda, 'camino');
      await _asentar(tester);
      await tester.tap(_chip('misioneros'));
      await tester.tap(_chip('revistas'));
      await _asentar(tester);
      expect(find.text('Revista Vida y Salud'), findsOneWidget);
      expect(find.text('Misionero Esperanza'), findsNothing);
      expect((tester.widget<TextField>(_busqueda)).controller!.text, isEmpty);
      await _irA(tester, 'libros');
      expect(
        find.text('El Deseado de Todas las Gentes'),
        findsOneWidget,
        reason: 'no quedó filtrada',
      );
    });

    testWidgets('abrir un combo y cambiar de ciudad seguidos no pisa ni pierde ninguna acción', (
      tester,
    ) async {
      await _montar(tester, _Entorno());
      await _tocar(tester, find.byKey(const ValueKey('k-2')));
      await _tocar(tester, find.byKey(const Key('precios_cerrar_detalle')));
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      await _tocar(tester, find.byKey(const ValueKey('k-2')));
      expect(find.text('Precio en Canelones'), findsOneWidget);
    });

    testWidgets('un precio que empieza mañana no se muestra hoy', (tester) async {
      final e = _Entorno();
      e.repo.catalogo = const CatalogoLocal(
        productos: [
          ProductoDelCatalogo(id: 'a', nombre: 'Libro nuevo', tipo: TipoDeProducto.libro),
        ],
        generales: [
          PrecioDelCatalogo(id: 'g', productoId: 'a', centavos: 1000, validoDesde: '2026-10-29'),
        ],
      );
      await _montar(tester, e);
      await _irA(tester, 'libros');
      expect(find.text('Libro nuevo'), findsNothing);
    });

    testWidgets(
      'volver atrás y reentrar vuelve a abrir en la ciudad de entrada y las colecciones',
      (tester) async {
        final e = _Entorno();
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          ProviderScope(
            overrides: e.overrides,
            child: MaterialApp(
              theme: temaClaro(),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      key: const Key('abrir'),
                      onPressed: () =>
                          Navigator.of(context).push(PreciosPage.ruta(colportorId: 'col-1')),
                      child: const Text('abrir'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _tocar(tester, find.byKey(const Key('abrir')));
        await _irA(tester, 'libros');
        await _tocar(tester, _verOtra);
        await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
        await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
        expect(find.text('Canelones'), findsOneWidget);

        await _tocar(tester, find.byKey(const Key('precios_atras')));
        expect(find.byType(PreciosPage), findsNothing);

        await _tocar(tester, find.byKey(const Key('abrir')));
        expect(find.text('SEGÚN DÓNDE ESTÁS'), findsOneWidget);
        expect(find.text('Montevideo'), findsOneWidget);
        expect(find.text('Pack Familia'), findsOneWidget, reason: 'abre en Colecciones');
      },
    );

    testWidgets('un tap en una pestaña de la barra de abajo devuelve esa pestaña', (tester) async {
      final e = _Entorno();
      PestanaInicio? devuelta;
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: e.overrides,
          child: MaterialApp(
            theme: temaClaro(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  key: const Key('abrir'),
                  onPressed: () async => devuelta = await Navigator.of(
                    context,
                  ).push(PreciosPage.ruta(colportorId: 'col-1')),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      );
      await _tocar(tester, find.byKey(const Key('abrir')));
      await tester.tap(
        find.descendant(of: find.byType(NavigationBar), matching: find.text('Agenda')),
      );
      await _asentar(tester);
      expect(devuelta, PestanaInicio.agenda);
    });
  });

  group('datos límite', () {
    testWidgets('200 libros: la lista se desliza y la búsqueda encuentra uno', (tester) async {
      await _montar(tester, _Entorno(repo: ConsultaDePreciosFalsa(catalogoLargo(200))));
      await _irA(tester, 'libros');
      expect(find.text('Libro 0000'), findsOneWidget);
      await _desplazarHasta(tester, find.text('Libro 0199'));
      await _alInicio(tester);
      await tester.enterText(_busqueda, '0150');
      await _asentar(tester);
      expect(find.text('Libro 0150'), findsOneWidget);
      expect(find.text('Libro 0199'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un nombre larguísimo se ajusta sin desbordar', (tester) async {
      final nombre = List.filled(30, 'Palabra').join(' ');
      final repo = ConsultaDePreciosFalsa(catalogoLargo(1, prefijo: nombre));
      await _montar(tester, _Entorno(repo: repo));
      await _irA(tester, 'libros');
      expect(find.textContaining('Palabra Palabra'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con texto al 200 % no desborda en ninguna pestaña ni en las hojas', (
      tester,
    ) async {
      await _montar(tester, _Entorno(), escala: 2);
      expect(tester.takeException(), isNull);
      await _tocar(tester, find.byKey(const ValueKey('k-2')));
      expect(find.byType(HojaDetalleDelCombo), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _tocar(tester, find.byKey(const Key('precios_cerrar_detalle')));
      for (final c in ['libros', 'misioneros', 'revistas']) {
        await _irA(tester, c);
        expect(tester.takeException(), isNull, reason: c);
      }
      await _tocar(tester, _verOtra);
      expect(find.byType(HojaOtraCiudad), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('con texto al 200 % también el aviso fuerte, la otra ciudad y el error', (
      tester,
    ) async {
      final e = _Entorno(conexion: TipoConexion.sinConexion, bajada: DateTime(2026, 9, 1));
      await _montar(tester, e, escala: 2);
      expect(tester.takeException(), isNull);
      await _tocar(tester, _verOtra);
      await _tocar(tester, find.byKey(const Key('precios_opcion_cc-can')));
      await _tocar(tester, find.byKey(const Key('precios_aplicar_ciudad')));
      expect(tester.takeException(), isNull);
    });

    testWidgets('en una pantalla chica (320 × 568) tampoco desborda', (tester) async {
      await _montar(tester, _Entorno(), tamano: const Size(320, 568));
      await _irA(tester, 'libros');
      expect(tester.takeException(), isNull);
    });
  });

  group('accesibilidad', () {
    testWidgets('las filas se leen enteras y los controles miden al menos 48', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montar(tester, _Entorno());
      await _irA(tester, 'libros');
      expect(
        find.bySemanticsLabel(
          RegExp(r'El Deseado de Todas las Gentes, código ACES-0214, bonificable, \$ 4\.800'),
        ),
        findsOneWidget,
      );
      for (final k in ['precios_ver_otra', 'precios_atras']) {
        final tam = tester.getSize(find.byKey(Key(k)));
        expect(tam.height, greaterThanOrEqualTo(48), reason: k);
        expect(tam.width, greaterThanOrEqualTo(48), reason: k);
      }
      await tester.enterText(_busqueda, 'x');
      await _asentar(tester);
      final borrar = tester.getSize(find.byKey(const Key('precios_borrar_busqueda')));
      expect(borrar.height, greaterThanOrEqualTo(48));
      semantica.dispose();
    });
  });
}
