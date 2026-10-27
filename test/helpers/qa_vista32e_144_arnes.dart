// Arnés de los tests de QA de las notas de una persona (HU-UBI-012, vista 32E, #144): arma cada estado
// de las tres pantallas (notas, formulario y borradas) en una celda de la matriz de tamaños (360x640 y
// 412x915, texto 1,0 y 2,0), con las fuentes reales del proyecto si se piden (sin ellas `flutter_test`
// pinta cajas Ahem) y con capturas PNG a `.dart_tool/qa_capturas/` (gitignored: nunca se commitean).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_notas_persona.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/nota_persona.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/nota_persona_form_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/notas_borradas_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/notas_de_persona_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_notas.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../widget/mapa/notas_persona_arnes.dart';
import 'nota_persona_falsos.dart';

/// `--dart-define=QA_CAPTURAS=true` saca una captura PNG de cada estado.
const sacarCapturas144 = bool.fromEnvironment('QA_CAPTURAS');

/// `--dart-define=QA_HALLAZGOS=true` corre también los tests de hallazgos (los que llevan `skip`).
const verHallazgos144 = bool.fromEnvironment('QA_HALLAZGOS');

/// La raíz de la captura: envuelve la app entera (la hoja, el diálogo y el aviso viven dentro).
final raizCaptura144 = GlobalKey();

/// Una celda de la matriz de QA: el tamaño del teléfono y la escala del texto.
class Celda144 {
  const Celda144(this.tamano, this.escala);

  final Size tamano;
  final double escala;

  String get nombre =>
      '${tamano.width.toInt()}x${tamano.height.toInt()}_x${escala.toString().replaceAll('.', '_')}';

  @override
  String toString() => nombre;
}

const telefonoChico144 = Size(360, 640);
const telefonoGrande144 = Size(412, 915);

/// Las cuatro celdas de la matriz.
const celdas144 = [
  Celda144(telefonoChico144, 1),
  Celda144(telefonoChico144, 2),
  Celda144(telefonoGrande144, 1),
  Celda144(telefonoGrande144, 2),
];

/// Carga Inter, SourceSerif4 y JetBrainsMono de `assets/fonts/` y los íconos de Material.
Future<void> cargarFuentes144(WidgetTester tester) async {
  await tester.runAsync(() async {
    for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
      final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
      final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
      await cargador.load();
    }
    var dir = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 8; i++, dir = dir.parent) {
      final iconos = File('${dir.path}/artifacts/material_fonts/MaterialIcons-Regular.otf');
      if (iconos.existsSync()) {
        final bytes = iconos.readAsBytesSync();
        final cargador = FontLoader('MaterialIcons')
          ..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
        break;
      }
    }
  });
}

/// Una captura PNG de [raizCaptura144] en `.dart_tool/qa_capturas/144_<nombre>.png`.
Future<void> capturar144(WidgetTester tester, String nombre) async {
  if (!sacarCapturas144) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(raizCaptura144));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/144_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

/// Contraste WCAG entre dos colores opacos.
double contraste144(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final claro = la > lb ? la : lb;
  final oscuro = la > lb ? lb : la;
  return (claro + 0.05) / (oscuro + 0.05);
}

/// Ningún texto visible se sale de la pantalla por los costados.
void expectSinTextoFueraDeLosCostados144(WidgetTester tester, Size tamano) {
  for (final e in find.byType(RichText).evaluate()) {
    final render = e.renderObject;
    if (render is! RenderBox || !render.attached || !render.hasSize) continue;
    final r = render.localToGlobal(Offset.zero) & render.size;
    expect(
      r.left >= -0.5 && r.right <= tamano.width + 0.5,
      isTrue,
      reason: 'un texto se sale de la pantalla: ${(e.widget as RichText).text.toPlainText()} $r',
    );
  }
}

/// Las pantallas que se miran.
enum Pantalla144 { notas, formulario, borradas }

/// Monta la [pantalla] directo como pantalla de inicio (en una celda de la matriz).
Future<void> montarPantalla144(
  WidgetTester tester,
  Celda144 celda, {
  required NotaPersonaRepositorioFalso repo,
  Pantalla144 pantalla = Pantalla144.notas,
  NotaPersona? nota,
  bool lector = false,
}) async {
  fijarTamano(tester, celda.tamano);
  final Widget home = switch (pantalla) {
    Pantalla144.notas => const NotasDePersonaPage(personaId: 'per-1', colportorId: 'col-1'),
    Pantalla144.formulario => NotaPersonaFormPage(
      personaId: 'per-1',
      colportorId: 'col-1',
      nota: nota,
    ),
    Pantalla144.borradas => const NotasBorradasPage(personaId: 'per-1', colportorId: 'col-1'),
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesNotas(repo),
      child: RepaintBoundary(
        key: raizCaptura144,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(celda.escala), accessibleNavigation: lector),
            child: child!,
          ),
          home: home,
        ),
      ),
    ),
  );
  await asentar(tester);
}

/// Una nota con un texto largo.
NotaPersona notaLarga144(String id, int caracteres, {DateTime? creada}) =>
    notaDePrueba(id, List.filled(caracteres ~/ 5, 'ñand ').join().trim(), creada: creada);

/// Un estado de la matriz: lo arma en una [Celda144].
typedef Armar144 = Future<void> Function(WidgetTester tester, Celda144 celda);

/// Abre la hoja de la nota [id] (con la lista perezosa la nota puede estar bajo el pliegue).
Future<void> abrirOpciones144(WidgetTester tester, String id) async {
  final nota = find.byKey(ValueKey('nota_$id'));
  await tester.scrollUntilVisible(nota, 120, scrollable: find.byType(Scrollable).first);
  await tester.pump();
  await tester.tapAt(tester.getTopLeft(nota) + const Offset(30, 14));
  await asentar(tester);
}

Future<void> _escribir(WidgetTester tester, String texto) async {
  await tester.enterText(find.byKey(ClavesNotas.campo), texto);
  await tester.pump();
}

/// Todos los estados de la vista 32E (artboards y estados de la lista), por nombre.
final Map<String, Armar144> estados144 = {
  'e01_notas': (t, c) =>
      montarPantalla144(t, c, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas())),
  'e01_muchas_y_larga': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: [
        for (var i = 0; i < 30; i++)
          notaDePrueba(
            'n$i',
            'Nota número $i del barrio',
            creada: DateTime(2026, 9, 1 + i % 28, 9),
          ),
        notaLarga144('larga', 6000, creada: DateTime(2026, 10, 22, 14, 21)),
      ],
    ),
  ),
  'e02_nueva': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(),
    pantalla: Pantalla144.formulario,
  ),
  'e02_nueva_con_texto': (t, c) async {
    await montarPantalla144(
      t,
      c,
      repo: NotaPersonaRepositorioFalso(),
      pantalla: Pantalla144.formulario,
    );
    await _escribir(t, 'Prefiere que la llamen antes de pasar.');
  },
  'e02_en_blanco_intentado': (t, c) async {
    await montarPantalla144(
      t,
      c,
      repo: NotaPersonaRepositorioFalso(),
      pantalla: Pantalla144.formulario,
    );
    await t.tap(find.text('Guardar nota'));
    await asentar(t);
  },
  'e02_mas_de_5000': (t, c) async {
    await montarPantalla144(
      t,
      c,
      repo: NotaPersonaRepositorioFalso(),
      pantalla: Pantalla144.formulario,
    );
    await _escribir(t, List.filled(1020, 'abcde').join());
  },
  'e07_error_al_guardar': (t, c) async {
    final repo = NotaPersonaRepositorioFalso()..resultados['agregar'] = [const FailureInesperado()];
    await montarPantalla144(t, c, repo: repo, pantalla: Pantalla144.formulario);
    await _escribir(t, 'Prefiere que la llamen antes de pasar.');
    await t.tap(find.text('Guardar nota'));
    await asentar(t);
    // El aviso de privacidad lleva «No volver a mostrar»: al enfocar el campo la lista se desplaza y el
    // enlace queda recortado por el borde; la guía de tamaño de toque lo mide recortado. Se vuelve arriba.
    await t.drag(find.byType(SingleChildScrollView), const Offset(0, 800));
    await asentar(t);
  },
  'editar_nota': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(),
    pantalla: Pantalla144.formulario,
    nota: notasDelCanvas().first,
  ),
  'descartar_lo_escrito': (t, c) async {
    await montarPantalla144(
      t,
      c,
      repo: NotaPersonaRepositorioFalso(),
      pantalla: Pantalla144.formulario,
    );
    await _escribir(t, 'Una nota larga que no quiero perder');
    await t.tap(find.byTooltip('Cerrar'));
    await asentar(t);
  },
  'e03_menu': (t, c) async {
    await montarPantalla144(t, c, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));
    await abrirOpciones144(t, 'hoy');
  },
  'e04_borrada': (t, c) async {
    await montarPantalla144(t, c, repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()));
    await abrirOpciones144(t, 'hoy');
    await elegirOpcion(t, ClavesNotas.botonBorrar);
  },
  'e05_borradas': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: [
        notaDePrueba(
          'b1',
          'Pidió volver el sábado con el esposo. Le interesa Nuestros Hijos.',
          borrada: DateTime(2026, 10, 22, 14, 30),
        ),
        notaDePrueba(
          'b2',
          'Trabaja en la farmacia de Av. Italia de 9 a 13.',
          creada: DateTime(2026, 10, 5, 9),
          borrada: DateTime(2026, 10, 6, 9),
        ),
      ],
    ),
    pantalla: Pantalla144.borradas,
  ),
  'e05_sin_borradas': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(notas: notasDelCanvas()),
    pantalla: Pantalla144.borradas,
  ),
  'e06_sin_notas': (t, c) => montarPantalla144(t, c, repo: NotaPersonaRepositorioFalso()),
  'cargando': (t, c) async {
    fijarTamano(t, c.tamano);
    await montarPantalla144(t, c, repo: NotaPersonaRepositorioCargando());
  },
  'error_de_lectura': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso()..fallaDeContexto = const FailureInesperado(),
  ),
  'persona_que_ya_no_esta': (t, c) =>
      montarPantalla144(t, c, repo: NotaPersonaRepositorioFalso()..contexto = null),
  'solo_lectura_persona_de_baja': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: notasDelCanvas(),
      contexto: ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.personaDeBaja,
        bajaDesde: DateTime(2026, 10, 22),
      ),
    ),
  ),
  'solo_lectura_espacio_de_baja': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: notasDelCanvas(),
      contexto: const ContextoNotasPersona(
        nombre: 'María',
        causa: CausaSoloLectura.espacioDeBaja,
        numeroDepto: '3B',
        direccion: 'Mataojo 2044',
      ),
    ),
  ),
  'solo_lectura_nombres_largos': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: notasDelCanvas(),
      contexto: const ContextoNotasPersona(
        nombre: 'Mariadelosangelesfernandezdelarosa',
        causa: CausaSoloLectura.espacioDeBaja,
        numeroDepto: 'PH-12-A',
        direccion: 'Avenida Doctor Luis Alberto de Herrera 1248 bis',
      ),
    ),
  ),
  'borradas_solo_lectura': (t, c) => montarPantalla144(
    t,
    c,
    repo: NotaPersonaRepositorioFalso(
      notas: [notaDePrueba('b1', 'Una borrada', borrada: DateTime(2026, 10, 22, 14, 30))],
      contexto: const ContextoNotasPersona(nombre: 'María', causa: CausaSoloLectura.personaDeBaja),
    ),
    pantalla: Pantalla144.borradas,
  ),
};
