// #722: las hojas inferiores que leen providers, con la pantalla recortada. Las que no necesitan más que
// sus argumentos están en `hojas_recortes_pantalla_722_test.dart`. Cada hoja se abre con el arnés que ya
// la prueba (los dobles de sus repositorios) después de poner la isla y la barra de abajo de la
// pantalla; el arnés propio pone el tamaño y el texto.
import 'dart:async';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_providers.dart'
    show ciudadesParaAltaProvider;
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_state.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_filtros_lista.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/mostrar_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_hoja_casa.dart'
    show ClavesHojaCasa;
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hojas_drive.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:colportores_mobile/features/tiles/presentation/providers/sugerencia_mapa_providers.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_sugerencia_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_falsos.dart' show CiudadesFalsas;
import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/cobrar_desde_la_casa_arnes.dart';
import '../helpers/cobro_arnes.dart' show ventaDelCobro;
import '../helpers/espacios_falsos.dart';
import '../helpers/hoja_casa_falsos.dart';
import '../helpers/hojas_recortes_pantalla_722_arnes.dart';
import '../helpers/lista_ubicaciones_falsos.dart';
import '../helpers/persona_falsos.dart';
import 'mapa/hoja_con_quien_arnes.dart';
import 'mapa/hoja_espacios_arnes.dart';

const _telefonos = <Recorte>[
  Recorte('iPhone con isla 360×640, texto 1,0', Size(360, 640), arriba: 59, abajo: 34, escala: 1),
  Recorte('Android 3 botones 412×915, texto 1,0', Size(412, 915), arriba: 24, abajo: 48, escala: 1),
  Recorte('iPhone con isla 360×640, texto 2,0', Size(360, 640), arriba: 59, abajo: 34, escala: 2),
  Recorte('Android 3 botones 412×915, texto 2,0', Size(412, 915), arriba: 59, abajo: 48, escala: 2),
];

/// La sugerencia de mapa que el notifier real arma con el pull de la zona, ya resuelta.
final _sugerencia = SugerenciaMapa(
  paquete: PaqueteTiles(
    id: 'zona-centro',
    nivel: NivelCobertura.zona,
    ambitoId: 'z-1',
    version: '1',
    partes: [
      ParteTiles(
        origen: Uri.parse('https://ejemplo.uy/zona.pmtiles'),
        tamanoBytes: 12 << 20,
        sha256: 'a' * 64,
      ),
    ],
  ),
  zonaNombre: 'Zona Centro',
  ciudadNombre: 'Montevideo',
);

/// El notifier de la sugerencia con la sugerencia ya lista (sin Wi-Fi, catálogo ni disco).
final class _SugerenciaLista extends SugerenciaMapaNotifier {
  _SugerenciaLista(super.colportorId);

  @override
  SugerenciaMapa? build() {
    unawaited(Future<void>.microtask(() => state = _sugerencia));
    return null;
  }
}

/// Una casa con ocho clientes que deben: más de lo que entra en la hoja, así que se desplaza.
final _contextoConMuchaGente = ContextoDeLaCasa(
  espacioId: 'esp-1',
  personas: [
    for (var i = 0; i < 8; i++)
      clienteDePersonas('p$i', 'Cliente$i', apellido: 'Gómez', minutos: i),
  ],
  saldosCentavos: {for (var i = 0; i < 8; i++) 'p$i': 120000 + i},
  nota: notaDelCanvas,
);

void main() {
  setUpAll(cargarFuentesReales);

  for (final t in _telefonos) {
    group(t.nombre, () {
      testWidgets('¿A qué venta? (cobro)', (tester) async {
        ponerRecorte(tester, t);
        await montarQueVenta(
          tester,
          repo: cobranzasConVentas([ventaDelCobro(), ventaDelCobro(id: 'v-43', talonario: '0043')]),
          escala: t.escala,
          tamano: t.tamano,
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Con quién', (tester) async {
        ponerRecorte(tester, t);
        await montarConQuien(
          tester,
          repo: PersonaRepositorioFalso()..sembrar(personasDeLaCasa(3)),
          escala: t.escala,
          tamano: t.tamano,
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Hoja de una ubicación (Modificar ubicación)', (tester) async {
        ponerRecorte(tester, t);
        await montarHoja(
          tester,
          espacios: [
            espacioDe('e-1', '101', piso: '1'),
            espacioDe('e-2', '102', piso: '1', orden: 1),
          ],
          escala: t.escala,
          tamano: t.tamano,
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Hoja de la casa (Lista)', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          HojaAbrible(
            'Hoja de la casa',
            (c) => mostrarHojaCasa(c, colportorId: 'col-1', item: itemDeLaHoja()),
            overrides: [
              ...overridesLista(repo: RepoListaFalso()),
              // Ocho clientes: la hoja se desplaza y el último renglón queda al fondo de la lista.
              ...overridesHojaCasa(lectura: (_) => Stream.value(_contextoConMuchaGente)),
            ],
          ),
        );
        // Las dos alturas de la hoja: el resumen (un tercio) y arriba (con las pestañas y los botones).
        final resumen = await controlesFueraDelAreaSegura(tester, t);
        await tester.tap(find.byKey(ClavesHojaCasa.asaDeLaLista));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        final arriba = await controlesFueraDelAreaSegura(tester, t);
        expect([...resumen, ...arriba], isEmpty);
      });

      testWidgets('Filtros de la Lista (Ver N ubicaciones)', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          HojaAbrible(
            'Filtros de la Lista',
            (c) => mostrarHojaFiltrosLista(
              c,
              colportorId: 'col-1',
              actuales: const FiltrosLista(orden: OrdenListaUbicaciones.recientes),
              posicion: null,
            ),
            overrides: [ciudadesParaAltaProvider.overrideWithValue(CiudadesFalsas())],
          ),
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Conectar Google Drive', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          HojaAbrible(
            'Conectar Drive',
            mostrarHojaConectarDrive,
            overrides: [conexionProvider.overrideWith((ref) => Stream.value(TipoConexion.wifi))],
          ),
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Desconectar Google Drive', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          const HojaAbrible('Desconectar Drive', mostrarHojaDesconectarDrive),
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });

      testWidgets('Sugerencia de mapa', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          HojaAbrible(
            'Sugerencia de mapa',
            null,
            cuerpo: const SugerenciaMapaZona(colportorId: 'col-1'),
            overrides: [
              sugerenciaMapaProvider.overrideWith2((colportorId) => _SugerenciaLista(colportorId)),
            ],
          ),
        );
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });
    });
  }
}
