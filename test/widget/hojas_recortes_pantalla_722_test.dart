// #722 (pedido de Cristian, #717): las hojas inferiores respetan los recortes de pantalla. Con
// `useSafeArea: true` el modal protege solo el borde de arriba (la isla, el notch); el de abajo (la barra
// de gestos del iPhone de 34 dp, la de 3 botones de Android 15 de ~48 dp) lo tiene que resolver el
// contenido: `HojaSegura`. Cada hoja se abre por su función pública, con la pantalla recortada, y se mide
// que sus botones y campos queden entre la barra de arriba y la de abajo.
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/presentation/hoja_segura.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/visita.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/hoja_hora_inicio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/evento_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_detalle_de_visita.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_paso.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/hojas_centro_notificaciones.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_empezar_sin_recuperar.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_recuperar_respaldo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_achicar_cobertura.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_borrar_mapa.dart';
import 'package:colportores_mobile/features/ventas/domain/entities/venta_abierta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_a_que_venta.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/hoja_elegir_libro.dart';
import 'package:colportores_mobile/features/ventas/presentation/widgets/piezas_devolucion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/hojas_recortes_pantalla_722_arnes.dart';

/// Los teléfonos con recorte: tamaño en dp, barra de arriba (isla o barra de estado), barra de abajo
/// (gestos del iPhone o 3 botones de Android 15) y escala del texto.
const _telefonos = <Recorte>[
  Recorte('iPhone con isla 360×640, texto 1,0', Size(360, 640), arriba: 59, abajo: 34, escala: 1),
  Recorte('Android 3 botones 412×915, texto 1,0', Size(412, 915), arriba: 24, abajo: 48, escala: 1),
  Recorte('iPhone con isla 360×640, texto 2,0', Size(360, 640), arriba: 59, abajo: 34, escala: 2),
  Recorte('Android 3 botones 412×915, texto 2,0', Size(412, 915), arriba: 59, abajo: 48, escala: 2),
];

DateTime get _ahora => DateTime(2026, 11, 20, 10);

const _libro = PrecioDeProducto(
  id: 'lib-1',
  nombre: 'El Deseado de Todas las Gentes',
  centavos: 85000,
  origen: OrigenDelPrecio.ciudad,
  categoriaDelProducto: CategoriaDeProducto.bonificables,
  esBonificable: true,
);

/// Las hojas inferiores de #722 que no necesitan más que sus argumentos. Las que leen providers están
/// en `hojas_recortes_pantalla_722_providers_test.dart`.
final _hojas = <HojaAbrible>[
  HojaAbrible(
    'Cerrar sesión',
    (c) => mostrarHojaCerrarSesion(c, pendientes: 2, cerrar: () async => true),
  ),
  HojaAbrible(
    'Hora de inicio',
    (c) => mostrarHojaHoraInicio(c, ahora: _ahora, margenMinutos: 30, minutosAtras: 15),
  ),
  HojaAbrible(
    'Detalle de visita',
    (c) => mostrarHojaDetalleDeVisita(
      c,
      evento: VisitaDeLaCasa(
        id: 'v1',
        fecha: DateTime.utc(2026, 11, 19, 15),
        resultado: TipoResultadoVisita.entrevista,
        nota: 'Quiere el libro de la salud',
      ),
      direccion: 'Av. Italia 1234',
      ahora: _ahora,
    ),
  ),
  HojaAbrible(
    'Qué pasó',
    (c) => mostrarHojaQuePaso(
      c,
      direccion: 'Av. Italia 1234',
      ofrecidas: OpcionQuePaso.values.toSet(),
      cobro: (persona: 'Ana Gómez', saldoCentavos: 120000),
      venta: (persona: 'Ana Gómez'),
      alElegir: (_) async => const OpcionResuelta(),
    ),
  ),
  HojaAbrible('Acciones de nota', (c) => HojaOpcionesNota.mostrar(c, titulo: 'Nota de Ana')),
  HojaAbrible(
    'Menú del centro de notificaciones',
    (c) => mostrarMenuCentroNotificaciones(c, haySinLeer: true),
  ),
  HojaAbrible(
    'Borrar todas las notificaciones',
    (c) => mostrarHojaBorrarTodasLasNotificaciones(c, cantidad: 3, borrar: () async => true),
  ),
  const HojaAbrible('Empezar sin recuperar', mostrarHojaEmpezarSinRecuperar),
  HojaAbrible(
    'Recuperar respaldo',
    (c) => mostrarHojaRecuperarRespaldo(c, cuentaDrive: 'colportor@gmail.com'),
  ),
  HojaAbrible(
    'Achicar cobertura',
    (c) => mostrarHojaAchicarCobertura(
      c,
      nivel: NivelCobertura.ciudad,
      mayor: 'Ciudad',
      elegido: 'Zona',
      liberanMegabytes: 80,
    ),
  ),
  HojaAbrible('Borrar mapa', (c) => mostrarHojaBorrarMapa(c, nombre: 'Montevideo')),
  HojaAbrible(
    '¿A qué venta?',
    (c) => mostrarHojaAQueVenta(
      c,
      subtitulo: 'Ana Gómez',
      ventas: [
        VentaAbierta(
          ventaId: 'v-1',
          espacioPersonaId: 'ep-1',
          numeroTalonario: '0038',
          fecha: DateTime.utc(2026, 11, 10),
          montoTotalCentavos: 120000,
          cobradoCentavos: 40000,
          descripcion: 'Vida Feliz × 2',
        ),
        VentaAbierta(
          ventaId: 'v-2',
          espacioPersonaId: 'ep-1',
          numeroTalonario: '0041',
          fecha: DateTime.utc(2026, 11, 12),
          montoTotalCentavos: 85000,
          cobradoCentavos: 0,
          descripcion: 'Colección de 1 libro',
        ),
      ],
    ),
  ),
  HojaAbrible(
    'Elegir libro',
    (c) => mostrarHojaElegirLibro(c, titulo: 'Elegí el libro', libros: [_libro], actual: _libro),
  ),
  HojaAbrible(
    'Confirmar devolución',
    (c) => mostrarHojaConfirmarDevolucion(
      c,
      datos: const [
        DatoDeDevolucion('Se queda con', '1 libro'),
        DatoDeDevolucion('Ya pagó', r'$ 400'),
        DatoDeDevolucion('Saldo nuevo', r'$ 0', fuerte: true),
      ],
    ),
  ),
];

void main() {
  setUpAll(cargarFuentesReales);

  group('la hoja de abajo queda entre la barra de arriba y la de abajo (#722)', () {
    for (final t in _telefonos) {
      group(t.nombre, () {
        for (final h in _hojas) {
          testWidgets(h.nombre, (tester) async {
            await montarHojaRecortada(tester, t, h);
            expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
          });
        }
      });
    }
  });

  group('el arnés mide de verdad', () {
    // La misma hoja con un botón en el último renglón: sin `HojaSegura` el botón cae bajo la barra de
    // gestos (el caso de #717, «¿Empezar sin recuperar?» tapada por la barra de Android); con ella, no.
    HojaAbrible conBotonAlFondo({required bool segura}) => HojaAbrible('botón al fondo', (c) {
      Widget hoja = Padding(
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('¿Empezar sin recuperar?'),
            FilledButton(onPressed: () {}, child: const Text('Empezar')),
          ],
        ),
      );
      if (segura) hoja = HojaSegura(child: hoja);
      return showModalBottomSheet<void>(
        context: c,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => hoja,
      );
    });

    for (final t in _telefonos) {
      testWidgets('sin HojaSegura el botón queda bajo la barra, con ella no — ${t.nombre}', (
        tester,
      ) async {
        await montarHojaRecortada(tester, t, conBotonAlFondo(segura: false));
        expect(await controlesFueraDelAreaSegura(tester, t), isNotEmpty);
      });
      testWidgets('con HojaSegura el botón queda arriba de la barra — ${t.nombre}', (tester) async {
        await montarHojaRecortada(tester, t, conBotonAlFondo(segura: true));
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });
    }
  });

  testWidgets('HojaSegura no toca el borde de arriba: ya lo protege useSafeArea', (tester) async {
    tester.view.physicalSize = const ui.Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 59, bottom: 34);
    tester.view.viewPadding = const FakeViewPadding(top: 59, bottom: 34);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: temaClaro(),
        home: const Align(
          alignment: Alignment.topLeft,
          child: HojaSegura(child: SizedBox(key: Key('contenido'), width: 100, height: 100)),
        ),
      ),
    );
    final rect = tester.getRect(find.byKey(const Key('contenido')));
    expect(rect.top, 0, reason: 'el relleno de arriba lo pone useSafeArea, no la hoja');
  });
}
