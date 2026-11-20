// QA de #722 (hojas inferiores y recortes de pantalla). Complementa los tests del implementador
// (`hojas_recortes_pantalla_722_test.dart`), que miden las 21 hojas envueltas en `HojaSegura`, con
// lo que el issue dejó como «ya están bien» y el PR no probó:
//
// - La hoja de filtros de la Lista (05B·01): su «Ver N ubicaciones» queda a 22 dp del borde, sin
//   `SafeArea` ni `HojaSegura`; con la barra de gestos (34 dp) o la de 3 botones (48 dp) queda pegado
//   o tapado. Hallazgo H1: arreglado, los tests corren siempre.
// - Las hojas que ya traían `SafeArea` propio, con la misma medición.
// - El teclado abierto sobre una hoja envuelta (la engine informa `padding.bottom` en 0 con el
//   teclado arriba): el campo y los botones quedan sobre el teclado, sin relleno de más.
// - Capturas (`QA_CAPTURAS=true`) con las barras del sistema dibujadas encima, en `.dart_tool/qa_capturas`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_entrevista_en_curso.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_estado_agenda.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart';
import 'package:colportores_mobile/features/catalogo/presentation/widgets/hoja_detalle_combo.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:colportores_mobile/features/depositos/presentation/widgets/piezas_deposito.dart';
import 'package:colportores_mobile/features/jornada/presentation/widgets/hoja_hora_inicio.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_empezar_sin_recuperar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../helpers/hojas_recortes_pantalla_722_arnes.dart';
import '../helpers/lista_ubicaciones_falsos.dart' show RepoListaFalso, filaLista;
import 'mapa/lista_ubicaciones_arnes.dart';

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

/// Los teléfonos del PR más uno chico (320×568 con barra de 3 botones y texto 2,0).
const _telefonos = <Recorte>[
  Recorte('iPhone con isla 360×640, texto 1,0', Size(360, 640), arriba: 59, abajo: 34, escala: 1),
  Recorte('Android 3 botones 412×915, texto 1,0', Size(412, 915), arriba: 24, abajo: 48, escala: 1),
  Recorte('iPhone con isla 360×640, texto 2,0', Size(360, 640), arriba: 59, abajo: 34, escala: 2),
  Recorte('Android 3 botones 412×915, texto 2,0', Size(412, 915), arriba: 59, abajo: 48, escala: 2),
  Recorte('Android 3 botones 320×568, texto 2,0', Size(320, 568), arriba: 24, abajo: 48, escala: 2),
];

String _archivo(String s) =>
    s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_').replaceAll(RegExp(r'^_+|_+$'), '').toLowerCase();

/// La pantalla como PNG con las barras del sistema (arriba y abajo) dibujadas encima en rojo
/// translúcido: lo que queda bajo el rojo es lo que tapa el sistema. Solo con `QA_CAPTURAS`.
Future<void> _capturar(WidgetTester tester, Recorte r, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final vista = tester.binding.renderViews.first;
    final capa = vista.debugLayer! as OffsetLayer;
    final img = await capa.toImage(Offset.zero & vista.size, pixelRatio: 1);
    final grabador = ui.PictureRecorder();
    final lienzo = Canvas(grabador);
    lienzo.drawImage(img, Offset.zero, Paint());
    final rojo = Paint()..color = const Color(0x66FF0000);
    lienzo.drawRect(Rect.fromLTWH(0, 0, vista.size.width, r.arriba), rojo);
    lienzo.drawRect(Rect.fromLTWH(0, vista.size.height - r.abajo, vista.size.width, r.abajo), rojo);
    final salida = await grabador.endRecording().toImage(
      vista.size.width.round(),
      vista.size.height.round(),
    );
    final bytes = (await salida.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File(
      '${dir.path}/722_${_archivo(nombre)}_${_archivo(r.nombre)}.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Carga los íconos de Material (sin ellos las capturas salen con cajas).
Future<void> _cargarIconos() async {
  final raiz = Platform.environment['FLUTTER_ROOT'] ?? '/sdks/flutter';
  final f = File('$raiz/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final cargador = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(f.readAsBytesSync().buffer)));
  await cargador.load();
}

const _combo = PrecioDeCombo(
  id: 'c-1',
  nombre: 'Colección Familia',
  centavos: 350000,
  origen: OrigenDelPrecio.ciudad,
  librosAElegir: 2,
  componentes: [
    ComponenteDeCombo(nombre: 'El Camino a Cristo'),
    ComponenteDeCombo(nombre: 'Vida Feliz', cantidad: 2),
  ],
);

void main() {
  setUpAll(() async {
    await cargarFuentesReales();
    await _cargarIconos();
  });

  // H1 (arreglado): `mostrarHojaFiltrosLista` envuelve la hoja en `HojaSegura`.
  group('H1 · filtros de la Lista (05B·01): «Ver N ubicaciones» arriba de la barra', () {
    for (final t in _telefonos) {
      testWidgets(t.nombre, (tester) async {
        ponerRecorte(tester, t);
        await montarLista(tester, escala: t.escala, tamano: t.tamano);
        await abrirHojaFiltros(tester);
        await _capturar(tester, t, 'filtros');
        expect(
          await controlesFueraDelAreaSegura(tester, t),
          isEmpty,
          reason: 'la hoja de filtros no usa HojaSegura ni SafeArea (hoja_filtros_lista.dart)',
        );
      });
    }
  });

  group('la hoja «Ordenar» de la Lista (con SafeArea propio) queda entre las barras', () {
    for (final t in _telefonos) {
      testWidgets(t.nombre, (tester) async {
        ponerRecorte(tester, t);
        await montarLista(
          tester,
          repo: RepoListaFalso([filaLista('u1'), filaLista('u2')]),
          escala: t.escala,
          tamano: t.tamano,
        );
        await tester.ensureVisible(botonOrden);
        await tester.tap(botonOrden);
        await asentarLista(tester);
        await _capturar(tester, t, 'ordenar');
        expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
      });
    }
  });

  group('hojas que ya traían SafeArea propio: siguen entre las barras', () {
    final hojas = <HojaAbrible>[
      HojaAbrible(
        'Estado de la agenda',
        (c) => mostrarHojaEstadoAgenda(c, actual: EstadoFiltroAgenda.values.first),
      ),
      HojaAbrible(
        'Entrevista en curso',
        (c) => mostrarHojaEntrevistaEnCurso(
          c,
          direccion: 'Av. Italia 1234',
          persona: 'Ana Gómez',
          inicio: DateTime(2026, 11, 20, 9),
          notaInicial: '',
          alEscribirNota: (_) {},
          reloj: () => DateTime(2026, 11, 20, 9, 20),
        ),
      ),
      HojaAbrible(
        'Detalle de una colección',
        (c) => mostrarHojaDetalleDelCombo(c, combo: _combo, ciudad: 'Montevideo'),
      ),
      const HojaAbrible('Origen de la foto del ticket', mostrarHojaOrigenDeLaFoto),
    ];
    for (final t in _telefonos) {
      group(t.nombre, () {
        for (final h in hojas) {
          testWidgets(h.nombre, (tester) async {
            await montarHojaRecortada(tester, t, h);
            await _capturar(tester, t, h.nombre);
            expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
          });
        }
      });
    }
  });

  group('con el teclado arriba la hoja envuelta no suma la barra de más', () {
    // La engine informa `padding.bottom` en 0 cuando el teclado cubre la barra (el `viewPadding` queda en
    // 34): el relleno de `HojaSegura` baja a 0 y lo único que corre la hoja es el `viewInsets` que ya
    // maneja. El campo y los botones quedan arriba del teclado.
    const teclado = 280.0;
    for (final t in _telefonos.take(2)) {
      testWidgets('Otra hora (hora de inicio) — ${t.nombre}', (tester) async {
        await montarHojaRecortada(
          tester,
          t,
          HojaAbrible(
            'Hora de inicio',
            (c) => mostrarHojaHoraInicio(
              c,
              ahora: DateTime(2026, 11, 20, 10),
              margenMinutos: 30,
              minutosAtras: 15,
            ),
          ),
        );
        await tester.tap(find.byKey(const Key('hoja_hora_valor')));
        await tester.pump();
        tester.view.padding = FakeViewPadding(top: t.arriba);
        tester.view.viewInsets = const FakeViewPadding(bottom: teclado);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await _capturar(tester, t, 'hora de inicio con teclado');
        final limite = t.tamano.height - teclado;
        final campo = tester.getRect(find.byKey(const Key('hoja_hora_campo')));
        expect(campo.bottom, lessThanOrEqualTo(limite), reason: 'el campo queda bajo el teclado');
        expect(campo.top, greaterThanOrEqualTo(t.arriba));
        final botones = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.bySubtype<ButtonStyleButton>(),
        );
        for (var i = 0; i < botones.evaluate().length; i++) {
          await tester.ensureVisible(botones.at(i));
          await tester.pump();
          final r = tester.getRect(botones.at(i));
          expect(r.bottom, lessThanOrEqualTo(limite), reason: 'botón $i bajo el teclado: $r');
        }
      });
    }
  });

  group('capturas de las hojas envueltas (con las barras dibujadas)', () {
    final hojas = <HojaAbrible>[
      const HojaAbrible('Empezar sin recuperar', mostrarHojaEmpezarSinRecuperar),
      HojaAbrible(
        'Cerrar sesión',
        (c) => mostrarHojaCerrarSesion(c, pendientes: 2, cerrar: () async => true),
      ),
    ];
    for (final t in _telefonos) {
      for (final h in hojas) {
        testWidgets('${h.nombre} — ${t.nombre}', (tester) async {
          await montarHojaRecortada(tester, t, h);
          await _capturar(tester, t, h.nombre);
          expect(await controlesFueraDelAreaSegura(tester, t), isEmpty);
        }, skip: !_capturas);
      }
    }
  });
}
