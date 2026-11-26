// Arnés de las pantallas de la vista 40 (HU-STK-005, #512): las transferencias en memoria, los compañeros
// de campaña falsos, el catálogo del canvas y la conexión a mano, con un inicio que abre cada pantalla.
import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart'
    show CategoriaDePrecios;
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:colportores_mobile/features/transferencias/domain/entities/material_de_transferencia.dart';
import 'package:colportores_mobile/features/transferencias/presentation/pages/detalle_de_transferencia_page.dart';
import 'package:colportores_mobile/features/transferencias/presentation/pages/pedir_transferencia_page.dart';
import 'package:colportores_mobile/features/transferencias/presentation/pages/transferencias_page.dart';
import 'package:colportores_mobile/features/transferencias/presentation/providers/transferencias_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agendar_visita_arnes.dart' show asentarAgendar;
import 'recuperacion_arnes.dart' show ConexionControlable;
import 'transferencias_en_memoria.dart';

/// El «ahora» del canvas: viernes 23/10/2026, 15:00 en Montevideo (18:00 UTC).
final ahoraDeLasTransferencias = DateTime.utc(2026, 10, 23, 18);

/// Los materiales del canvas: dos libros bonificables, otro, un misionero y una revista.
const materialesDelCanvas = [
  MaterialDeTransferencia(
    id: 'p-1',
    nombre: 'Salud y Hogar',
    categoria: CategoriaDePrecios.libros,
    tengo: 0,
    esBonificable: true,
  ),
  MaterialDeTransferencia(
    id: 'p-2',
    nombre: 'Nuestros Hijos',
    categoria: CategoriaDePrecios.libros,
    tengo: 3,
    esBonificable: true,
  ),
  MaterialDeTransferencia(
    id: 'p-3',
    nombre: 'Vida Feliz',
    categoria: CategoriaDePrecios.libros,
    tengo: 6,
  ),
  MaterialDeTransferencia(
    id: 'p-4',
    nombre: 'El Camino a Cristo',
    categoria: CategoriaDePrecios.misioneros,
    tengo: 12,
  ),
  MaterialDeTransferencia(
    id: 'p-5',
    nombre: 'Revista Señales',
    categoria: CategoriaDePrecios.revistas,
    tengo: 4,
  ),
];

class ArnesTransferencias {
  ArnesTransferencias({
    required this.repo,
    required this.companieros,
    required this.conexion,
    required this.ahora,
  });

  final TransferenciasEnMemoria repo;
  final CompanierosFalsos companieros;
  final ConexionControlable conexion;

  /// El reloj de las pantallas; se mueve cambiando este campo.
  DateTime ahora;

  /// Lo que devolvió cada vez que `PedirTransferenciaPage.abrir` terminó.
  final pedir = <bool?>[];

  /// Lo que devolvió cada vez que `DetalleDeTransferenciaPage.abrir` terminó.
  final detalle = <SalidaDelDetalle?>[];

  /// Cuántas veces se tocó «Hacer un pedido» de 40A·09.
  var hicieronUnPedido = 0;
}

/// Monta un inicio con tres botones («abrir pedir», «abrir lista», «abrir detalle») y, si [abrir] es uno
/// de ellos, lo toca.
Future<ArnesTransferencias> montarTransferencias(
  WidgetTester tester, {
  TransferenciasEnMemoria? repo,
  CompanierosFalsos? companieros,
  List<MaterialDeTransferencia>? materiales,
  Map<String, String>? nombres,
  String colportor = 'juan',
  String transferenciaId = 't-1',
  DateTime? ahora,
  DateTime? ultimaBajada,
  bool sinConexion = false,
  bool conHacerUnPedido = false,
  double escala = 1,
  Size tamano = const Size(390, 844),
  String? abrir,
}) async {
  final arnes = ArnesTransferencias(
    repo: repo ?? TransferenciasEnMemoria(),
    companieros: companieros ?? CompanierosFalsos(resultado: companierosDelCanvas),
    conexion: ConexionControlable()
      ..tipo = sinConexion ? TipoConexion.sinConexion : TipoConexion.wifi,
    ahora: ahora ?? ahoraDeLasTransferencias,
  );
  final catalogo = materiales ?? materialesDelCanvas;
  var siguiente = 0;
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        transferenciaRepositoryProvider.overrideWithValue(arnes.repo),
        transferenciasProvider.overrideWith((ref, id) => arnes.repo.observar(id)),
        materialesDeTransferenciaProvider.overrideWith((ref, id) => Stream.value(catalogo)),
        nombresDeProductosProvider.overrideWith(
          (ref) => Stream.value(nombres ?? {for (final m in catalogo) m.id: m.nombre}),
        ),
        ultimaBajadaDeTransferenciasProvider.overrideWith((ref) async => ultimaBajada),
        companierosDeCampaniaRepositoryProvider.overrideWithValue(arnes.companieros),
        monitorConectividadProvider.overrideWithValue(arnes.conexion),
        relojTransferenciaProvider.overrideWithValue(() => arnes.ahora),
        generadorIdTransferenciaProvider.overrideWithValue(() => 'id-${++siguiente}'),
        if (conHacerUnPedido)
          hacerUnPedidoDesdeTransferenciaProvider.overrideWithValue(
            (_) => arnes.hicieronUnPedido++,
          ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      arnes.pedir.add(
                        await PedirTransferenciaPage.abrir(context, colportorId: colportor),
                      );
                    },
                    child: const Text('abrir pedir'),
                  ),
                  TextButton(
                    onPressed: () => TransferenciasPage.abrir(context, colportorId: colportor),
                    child: const Text('abrir lista'),
                  ),
                  TextButton(
                    onPressed: () async {
                      arnes.detalle.add(
                        await DetalleDeTransferenciaPage.abrir(
                          context,
                          colportorId: colportor,
                          transferenciaId: transferenciaId,
                        ),
                      );
                    },
                    child: const Text('abrir detalle'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  if (abrir != null) await abrirPantalla(tester, abrir);
  return arnes;
}

/// Toca el botón de arranque [cual] («pedir», «lista» o «detalle») y deja correr la apertura.
Future<void> abrirPantalla(WidgetTester tester, String cual) async {
  await tester.tap(find.text('abrir $cual'));
  await asentarAgendar(tester);
}

final paginaPedir = find.byKey(const Key('pedir_transferencia_pagina'));
final paginaLista = find.byKey(const Key('transferencias_pagina'));
final paginaDetalle = find.byKey(const Key('detalle_transferencia_pagina'));
final botonPrincipal = find.byKey(const Key('venta_cta'));
final tarjetaDeColportor = find.byKey(const Key('pedir_transferencia_colportor'));
final listoDelSelector = find.byKey(const Key('transferencia_colportores_listo'));
final botonCancelar = find.byKey(const Key('detalle_transferencia_cancelar'));
final cancelarSi = find.byKey(const Key('transferencia_cancelar_si'));
final cancelarNo = find.byKey(const Key('transferencia_cancelar_no'));

FilledButton elBoton(WidgetTester tester) => tester.widget<FilledButton>(botonPrincipal);

/// Trae [f] a la vista: la lista es perezosa y con letra grande el widget puede no estar armado.
Future<void> traerAlAlcance(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    final listas = find.byType(Scrollable);
    await tester.scrollUntilVisible(f, 300, scrollable: listas.first, maxScrolls: 400);
  }
  await tester.ensureVisible(f.first);
  await tester.pump();
}

Future<void> tocar(WidgetTester tester, Finder f) async {
  await traerAlAlcance(tester, f);
  await tester.tap(f.first);
  await asentarAgendar(tester);
}

/// Sube la cantidad de [productoId] en [veces] con el «+» de su fila.
Future<void> sumar(WidgetTester tester, String productoId, [int veces = 1]) async {
  final fila = find.byKey(Key('pedir_transferencia_material_$productoId'));
  await traerAlAlcance(tester, fila);
  final mas = find.descendant(of: fila, matching: find.byIcon(Icons.add_circle_outline));
  await tester.ensureVisible(mas);
  await tester.pump();
  for (var i = 0; i < veces; i++) {
    await tester.tap(mas);
    await tester.pump();
  }
}

/// Abre la hoja de colportores y elige a [nombre] con «Listo».
Future<void> elegirColportor(WidgetTester tester, String nombre) async {
  await tocar(tester, tarjetaDeColportor);
  await tocar(tester, find.text(nombre));
  await tocar(tester, listoDelSelector);
}
