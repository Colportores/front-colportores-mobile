// QA de #717 (PR #719) — las hojas inferiores quedan sobre la barra de navegación de Android.
//
// Matriz: hojas reales de la app × pantalla (360×640, 412×915) × texto (1,0 y 2,0) × barra (tres
// botones 48 dp, gestos 24 dp, sin barra). En cada celda: sin overflow, cada botón de la hoja se
// alcanza (con scroll si hace falta) y termina sobre la barra, y el fondo de la hoja sigue llegando al
// borde. Las hojas de una ubicación, de la casa y de filtros se abren con los arneses de sus vistas.
import 'dart:io';

import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/agenda/domain/entities/filtros_agenda.dart';
import 'package:colportores_mobile/features/agenda/presentation/widgets/hoja_estado_agenda.dart';
import 'package:colportores_mobile/features/configuracion/presentation/widgets/hoja_cerrar_sesion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_mapa_ubicaciones.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/widgets/hojas_centro_notificaciones.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_empezar_sin_recuperar.dart';
import 'package:colportores_mobile/features/respaldo/presentation/widgets/hoja_recuperar_respaldo.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_achicar_cobertura.dart';
import 'package:colportores_mobile/features/tiles/presentation/widgets/hoja_borrar_mapa.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show ByteData, FontLoader;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../mapa/hoja_espacios_arnes.dart';
import '../mapa/lista_ubicaciones_arnes.dart';

var _fuentesCargadas = false;

/// Las fuentes reales de la app y los íconos de Material: con la de prueba (Ahem) el ancho del texto
/// es falso y el overflow no se parece al del teléfono.
Future<void> _fuentes(WidgetTester tester) async {
  if (_fuentesCargadas) return;
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
  _fuentesCargadas = true;
}

const _tamanos = <String, Size>{'360x640': Size(360, 640), '412x915': Size(412, 915)};
const _escalas = <double>[1, 2];
const _barras = <String, double>{'tres botones': 48, 'gestos': 24, 'sin barra': 0};

/// La barra de navegación simulada: `viewPadding` es la barra; `padding` lo que de ella no tapa el
/// teclado (acá, todo).
void _barra(WidgetTester tester, double barra) {
  tester.view.viewPadding = FakeViewPadding(bottom: barra);
  tester.view.padding = FakeViewPadding(bottom: barra);
  addTearDown(tester.view.reset);
}

typedef _Abridor = Future<Object?> Function(BuildContext context);

Future<void> _montarAbridor(
  WidgetTester tester, {
  required Size tamano,
  required double escala,
  required double barra,
  required _Abridor abrir,
}) async {
  await _fuentes(tester);
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  _barra(tester, barra);
  await tester.pumpWidget(
    MaterialApp(
      theme: temaClaro(),
      builder: (context, hijo) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
        child: hijo!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              key: const Key('abrir'),
              onPressed: () => abrir(context),
              child: const Text('Abrir'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await tester.pumpAndSettle();
}

/// Cada botón de [dentro] se alcanza y termina sobre la barra; el fondo de la hoja llega al borde.
Future<void> _verificar(
  WidgetTester tester, {
  required Size tamano,
  required double barra,
  required Finder dentro,
  bool fondoAlBorde = true,
}) async {
  expect(tester.takeException(), isNull, reason: 'overflow o excepción al abrir la hoja');
  final todos = find.descendant(of: dentro, matching: find.bySubtype<ButtonStyleButton>());
  final cantidad = todos.evaluate().length;
  expect(cantidad, greaterThan(0), reason: 'la hoja no tiene botones');
  for (var i = 0; i < cantidad; i++) {
    final boton = todos.at(i);
    await tester.ensureVisible(boton);
    await tester.pumpAndSettle();
    final pie = tester.getBottomLeft(boton).dy;
    expect(
      pie,
      lessThanOrEqualTo(tamano.height - barra + 0.5),
      reason: 'el botón #$i termina en $pie y la barra empieza en ${tamano.height - barra}',
    );
  }
  expect(tester.takeException(), isNull, reason: 'excepción al desplazar la hoja');
  if (fondoAlBorde) {
    expect(
      tester.getBottomLeft(find.byType(BottomSheet)).dy,
      closeTo(tamano.height, 0.5),
      reason: 'el fondo de la hoja no llega al borde',
    );
  }
}

/// Las hojas que se abren con una función suelta (sin proveedores).
final _hojasSimples = <String, _Abridor>{
  'cerrar sesión sin pendientes': (c) =>
      mostrarHojaCerrarSesion(c, pendientes: 0, cerrar: () async => true),
  'cerrar sesión con pendientes': (c) =>
      mostrarHojaCerrarSesion(c, pendientes: 4, cerrar: () async => true),
  'empezar sin recuperar': mostrarHojaEmpezarSinRecuperar,
  'recuperar mi respaldo': (c) => mostrarHojaRecuperarRespaldo(c, cuentaDrive: 'ana@example.com'),
  'borrar mapa': (c) => mostrarHojaBorrarMapa(c, nombre: 'Montevideo'),
  'achicar cobertura': (c) => mostrarHojaAchicarCobertura(
    c,
    nivel: NivelCobertura.zona,
    mayor: 'Montevideo',
    elegido: 'Tu zona',
    liberanMegabytes: 64,
  ),
  'menú del centro con avisos sin leer': (c) =>
      mostrarMenuCentroNotificaciones(c, haySinLeer: true),
  'menú del centro sin avisos sin leer': (c) =>
      mostrarMenuCentroNotificaciones(c, haySinLeer: false),
  'borrar todas las notificaciones': (c) =>
      mostrarHojaBorrarTodasLasNotificaciones(c, cantidad: 12, borrar: () async => true),
  'estado de la agenda': (c) => mostrarHojaEstadoAgenda(c, actual: EstadoFiltroAgenda.pendientes),
  'referencias del mapa': mostrarReferenciasMapa,
};

void main() {
  group('QA #717 · hojas sueltas de la app sobre la barra de navegación', () {
    for (final hoja in _hojasSimples.entries) {
      for (final tam in _tamanos.entries) {
        for (final escala in _escalas) {
          for (final barra in _barras.entries) {
            testWidgets(
              'dado ${hoja.key} a ${tam.key} con texto ×$escala y ${barra.key}, cuando se abre, '
              'entonces cada botón queda sobre la barra y no hay overflow',
              (tester) async {
                await _montarAbridor(
                  tester,
                  tamano: tam.value,
                  escala: escala,
                  barra: barra.value,
                  abrir: hoja.value,
                );
                await _verificar(
                  tester,
                  tamano: tam.value,
                  barra: barra.value,
                  dentro: find.byType(BottomSheet),
                );
              },
            );
          }
        }
      }
    }
  });

  group('QA #717 · guías de accesibilidad de las hojas con la barra de navegación', () {
    for (final hoja in _hojasSimples.entries) {
      testWidgets('dado ${hoja.key} con la barra de tres botones, cuando se abre, entonces los '
          'botones cumplen tamaño de toque y etiqueta', (tester) async {
        final semantica = tester.ensureSemantics();
        await _montarAbridor(
          tester,
          tamano: const Size(412, 915),
          escala: 1,
          barra: 48,
          abrir: hoja.value,
        );
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        semantica.dispose();
      });
    }
  });

  group('QA #717 · hoja de una ubicación (fondo propio, `conBarraInferior: false`)', () {
    for (final tam in _tamanos.entries) {
      for (final escala in _escalas) {
        for (final barra in _barras.entries) {
          testWidgets(
            'dado el edificio con deptos a ${tam.key} con texto ×$escala y ${barra.key}, cuando se '
            'abre, entonces «Editar» y «+ Departamento» quedan sobre la barra',
            (tester) async {
              await _fuentes(tester);
              tester.view.viewPadding = FakeViewPadding(bottom: barra.value);
              tester.view.padding = FakeViewPadding(bottom: barra.value);
              await montarHoja(
                tester,
                tamano: tam.value,
                escala: escala,
                espacios: [
                  for (var i = 1; i <= 12; i++)
                    espacioDe('e$i', '${100 + i}', piso: '${1 + i ~/ 4}', orden: i),
                ],
                personas: {'e1': 2, 'e2': 1},
              );
              expect(tester.takeException(), isNull);
              for (final clave in [ClavesHojaUbicacion.agregarDepto, ClavesHojaUbicacion.editar]) {
                final boton = find.byKey(clave);
                await tester.ensureVisible(boton);
                await tester.pump(const Duration(milliseconds: 300));
                expect(
                  tester.getBottomLeft(boton).dy,
                  lessThanOrEqualTo(tam.value.height - barra.value + 0.5),
                  reason: '$clave queda bajo la barra',
                );
              }
              expect(tester.takeException(), isNull);
            },
          );
        }
      }
    }
  });

  group('QA #717 · hoja de la casa en la Lista', () {
    for (final tam in _tamanos.entries) {
      for (final escala in _escalas) {
        for (final barra in _barras.entries) {
          testWidgets(
            'dado una casa a ${tam.key} con texto ×$escala y ${barra.key}, cuando se abre su hoja, '
            'entonces sus botones quedan sobre la barra y el fondo llega al borde',
            (tester) async {
              await _fuentes(tester);
              _barra(tester, barra.value);
              await montarLista(
                tester,
                repo: RepoListaFalso([
                  filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
                ]),
                casaAbreSuHoja: true,
                tamano: tam.value,
                escala: escala,
              );
              await tester.tap(find.textContaining('Av. Italia'));
              await asentarLista(tester, 14);
              expect(find.byType(HojaCasa), findsOneWidget);
              await _verificar(
                tester,
                tamano: tam.value,
                barra: barra.value,
                dentro: find.byType(HojaCasa),
              );
            },
          );
        }
      }
    }
  });

  group('QA #717 · hoja de filtros de la Lista', () {
    for (final tam in _tamanos.entries) {
      for (final escala in _escalas) {
        for (final barra in _barras.entries) {
          testWidgets(
            'dado la Lista a ${tam.key} con texto ×$escala y ${barra.key}, cuando se abren los '
            'filtros, entonces «Ver N ubicaciones» queda sobre la barra',
            (tester) async {
              await _fuentes(tester);
              _barra(tester, barra.value);
              await montarLista(
                tester,
                repo: RepoListaFalso([
                  filaLista('a', calle: 'Av. Italia', numero: '1234', metrosAlNorte: 40),
                ]),
                tamano: tam.value,
                escala: escala,
              );
              await abrirHojaFiltros(tester);
              await _verificar(
                tester,
                tamano: tam.value,
                barra: barra.value,
                dentro: find.byType(BottomSheet),
              );
            },
          );
        }
      }
    }
  });
}
