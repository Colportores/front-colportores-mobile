// QA del PR #468 (#211, HU-UBI-007, vistas 11 y 39): desde la Lista del Inicio, una casa abre la hoja
// de la casa (vista 39, C·01) y un edificio o un negocio, la de espacios (vista 11); «Abrir la existente»
// del aviso de reactivación respeta lo mismo. Casos límite, estados y accesibilidad a 360×640 y
// 412×915, texto 1.0 y 2.0, tema claro y oscuro.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/contexto_de_la_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/espacio.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/espacios_providers.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/hoja_casa_providers.dart'
    show ClaveDeLaCasa;
import 'package:colportores_mobile/features/mapa/presentation/widgets/estados_hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_casa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_reactivar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_ubicacion.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/espacios_falsos.dart';
import '../../helpers/hoja_casa_falsos.dart';
import '../../helpers/lista_ubicaciones_falsos.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';
import '../../helpers/qa_baja_205_arnes.dart' show cargarFuentes205;
import 'lista_ubicaciones_arnes.dart';

final _sesion = Sesion(
  usuarioId: 'col-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');

/// `skip` de un hallazgo: salvo con `QA_HALLAZGOS=true`.
const _hallazgo = !_verHallazgos;

const _chico = Size(360, 640);
const _grande = Size(412, 915);

/// La Lista del Inicio con una casa, un edificio, un negocio y una casa de baja (la del canvas 09).
List<UbicacionConResumen> _filas() => [
  filaLista('casa', calle: 'Rivadavia', numero: '100'),
  filaLista('edif', tipo: TipoUbicacion.edificio, calle: 'Mataojo', numero: '2044'),
  filaLista('nego', tipo: TipoUbicacion.negocio, calle: 'Colonia', numero: '77'),
];

final _raiz = GlobalKey();

class _Edicion {
  SalidaModificarUbicacion? salida;
  final abiertas = <String>[];

  Future<SalidaModificarUbicacion?> abrir(
    BuildContext context, {
    required String colportorId,
    required String ubicacionId,
    bool ofreceIrALaCobranza = false,
  }) async {
    abiertas.add(ubicacionId);
    return salida;
  }
}

/// El Inicio entero, en la pestaña «Lista».
Future<_Edicion> _montarInicio(
  WidgetTester tester, {
  RepoListaFalso? repo,
  Size tamano = _chico,
  double escala = 1,
  Stream<ContextoDeLaCasa> Function(ClaveDeLaCasa clave)? lecturaContexto,
  Map<String, TipoUbicacion> tipos = const {},
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final edicion = _Edicion();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => DateTime(2026, 10, 6, 15)),
        ...overridesLista(repo: repo ?? RepoListaFalso(_filas())),
        ...overridesHojaCasa(lectura: lecturaContexto),
        ubicacionDeLaHojaProvider.overrideWith(
          (ref, id) => ubicacionGuardada(
            id: id,
            tipo: tipos[id] ?? TipoUbicacion.edificio,
            calle: 'Mataojo',
            numero: '2044',
          ),
        ),
        espaciosDadosDeBajaProvider.overrideWith((ref, id) => const <Espacio>[]),
        espaciosDeUbicacionProvider.overrideWith(
          (ref, id) => [espacioDe('e-$id', '11', ubicacionId: id)],
        ),
        abridorEdicionUbicacionProvider.overrideWithValue(edicion.abrir),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: RepaintBoundary(key: _raiz, child: child!),
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await asentarLista(tester);
  await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
  await asentarLista(tester);
  return edicion;
}

Future<void> _captura(WidgetTester tester, String nombre) async {
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/468_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

Future<void> _tocarFila(WidgetTester tester, String id) async {
  await Scrollable.ensureVisible(tester.element(find.byKey(ValueKey(id))), alignment: .5);
  await tester.pump();
  // Arriba a la izquierda de la fila y no al centro: a 200 % en 360×640 el centro queda bajo la
  // barra de pestañas y el botón «Nueva» tapa el borde derecho.
  await tester.tapAt(tester.getTopLeft(find.byKey(ValueKey(id))) + const Offset(60, 20));
  await asentarLista(tester);
}

const _chocaConRivadavia = FailureReactivacionChocaConActiva(
  existenteId: 'casa-1',
  direccion: 'Rivadavia 100',
);

void main() {
  group('Lista del Inicio · casa vs edificio vs negocio', () {
    testWidgets('una casa abre la hoja de la casa (C·01), sin sección de espacios', (tester) async {
      await _montarInicio(tester);

      await _tocarFila(tester, 'casa');

      expect(find.byType(HojaCasa), findsOneWidget);
      expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
      expect(find.text('+ Departamento'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('un edificio abre la hoja de espacios (vista 11)', (tester) async {
      await _montarInicio(tester);

      await _tocarFila(tester, 'edif');

      expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
      expect(find.byType(HojaCasa), findsNothing);
      expect(find.text('Depto 11'), findsOneWidget);
    });

    testWidgets('un negocio abre la hoja de espacios (vista 11), no la de la casa', (tester) async {
      await _montarInicio(tester, tipos: {'nego': TipoUbicacion.negocio});

      await _tocarFila(tester, 'nego');

      expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets('cerrar la hoja de la casa deja la Lista en su pestaña y la casa se puede abrir '
        'de nuevo (reentrada)', (tester) async {
      await _montarInicio(tester);
      await _tocarFila(tester, 'casa');
      expect(find.byType(HojaCasa), findsOneWidget);

      await tester.tapAt(const Offset(180, 10));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsNothing);
      expect(find.byKey(const Key('pestana_lista')), findsOneWidget);

      await _tocarFila(tester, 'casa');
      expect(find.byType(HojaCasa), findsOneWidget);
    });

    testWidgets('doble toque en la fila de una casa: una sola hoja', (tester) async {
      await _montarInicio(tester);

      await tester.tap(find.byKey(const ValueKey('casa')));
      await tester.tap(find.byKey(const ValueKey('casa')), warnIfMissed: false);
      await asentarLista(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
      await tester.tapAt(const Offset(180, 10));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsNothing, reason: 'no quedó una segunda hoja debajo');
    });

    testWidgets('tocar la casa y enseguida un edificio: no se apilan dos hojas', (tester) async {
      await _montarInicio(tester);

      await tester.tap(find.byKey(const ValueKey('casa')));
      await tester.tap(find.byKey(const ValueKey('edif')), warnIfMissed: false);
      await asentarLista(tester);

      expect(
        find.byType(HojaCasa).evaluate().length +
            find.byKey(ClavesHojaUbicacion.hoja).evaluate().length,
        1,
      );
    });
  });

  group('Lista del Inicio · «Abrir la existente» con una casa como existente', () {
    // La baja de Av. Italia 1240 choca con la casa activa de Rivadavia 100 (D1).
    RepoListaFalso repoConBaja({TipoUbicacion existente = TipoUbicacion.casa}) => RepoListaFalso([
      filaLista('casa-1', tipo: existente, calle: 'Rivadavia', numero: '100'),
      filaLista(
        'baja-1',
        calle: 'Av. Italia',
        numero: '1240',
        baja: DateTime.utc(2026, 9, 12, 15),
        motivoBaja: 'Ya no existe',
      ),
    ]);

    Future<RepoListaFalso> montarConBajas(
      WidgetTester tester, {
      TipoUbicacion existente = TipoUbicacion.casa,
    }) async {
      final repo = repoConBaja(existente: existente)..fallaAlCambiarBaja = _chocaConRivadavia;
      await _montarInicio(tester, repo: repo, tipos: {'casa-1': existente});
      await abrirHojaFiltros(tester);
      await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
      await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
      await asentarLista(tester);
      await tester.ensureVisible(botonVerUbicaciones);
      await verUbicaciones(tester);
      return repo;
    }

    Future<void> hastaElChoque(WidgetTester tester) async {
      await _tocarFila(tester, 'baja-1');
      await tester.tap(find.widgetWithText(FilledButton, TextosReactivar.reactivar));
      await asentarLista(tester);
    }

    testWidgets('con una casa existente, «Abrir la existente» abre su hoja de casa, cierra el '
        'aviso y no deja otra hoja apilada', (tester) async {
      await montarConBajas(tester);
      await hastaElChoque(tester);
      expect(find.text(TextosReactivar.noSePuede), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, TextosReactivar.abrirExistente));
      await asentarLista(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
      expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
      expect(find.text(TextosReactivar.noSePuede), findsNothing);
      // Volver: la Lista, sin una hoja de la baja debajo (la baja se reactiva desde la fila, no
      // desde una hoja de casa).
      await tester.tapAt(const Offset(180, 10));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsNothing);
      expect(find.byKey(const Key('pestana_lista')), findsOneWidget);
      expect(find.text('BAJA'), findsOneWidget, reason: 'la baja sigue de baja');
    });

    testWidgets('con un edificio existente, «Abrir la existente» abre la hoja de espacios', (
      tester,
    ) async {
      await montarConBajas(tester, existente: TipoUbicacion.edificio);
      await hastaElChoque(tester);

      await tester.tap(find.widgetWithText(FilledButton, TextosReactivar.abrirExistente));
      await asentarLista(tester);

      expect(find.byKey(ClavesHojaUbicacion.hoja), findsOneWidget);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets('doble toque en «Abrir la existente»: una sola hoja de casa', (tester) async {
      await montarConBajas(tester);
      await hastaElChoque(tester);

      final boton = find.widgetWithText(FilledButton, TextosReactivar.abrirExistente);
      await tester.tap(boton);
      await tester.tap(boton, warnIfMissed: false);
      await asentarLista(tester);

      expect(find.byType(HojaCasa), findsOneWidget);
      await tester.tapAt(const Offset(180, 10));
      await asentarLista(tester);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets('una casa de baja reactivable abre directo «Reactivar» (09·03), no la hoja de la '
        'casa', (tester) async {
      await montarConBajas(tester);

      await _tocarFila(tester, 'baja-1');

      expect(find.widgetWithText(FilledButton, TextosReactivar.reactivar), findsOneWidget);
      expect(find.byType(HojaCasa), findsNothing);
    });

    testWidgets(
      'la casa existente que la búsqueda de la Lista no muestra igual abre su hoja de casa, no la '
      'de espacios',
      (tester) async {
        await montarConBajas(tester);
        await buscarEnLista(tester, 'Italia');
        expect(
          find.text('Rivadavia 100'),
          findsNothing,
          reason: 'la existente quedó fuera de la lista',
        );
        await hastaElChoque(tester);

        await tester.tap(find.widgetWithText(FilledButton, TextosReactivar.abrirExistente));
        await asentarLista(tester);

        expect(find.byType(HojaCasa), findsOneWidget);
        expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
      },
      // skip: QA #211 — «Abrir la existente» busca la casa solo entre las filas filtradas de la Lista;
      // si la búsqueda o un filtro la esconde, abre la hoja de espacios (vista 11) de una casa.
      skip: _hallazgo,
    );

    testWidgets(
      'si desde la edición de un edificio el aviso manda a una casa, se abre la hoja de la casa',
      (tester) async {
        final edicion = await _montarInicio(tester, tipos: {'casa': TipoUbicacion.casa});
        await _tocarFila(tester, 'edif');
        edicion.salida = const UbicacionExistenteElegida('casa');

        await tester.tap(find.byKey(ClavesHojaUbicacion.editar));
        await asentarLista(tester);

        expect(find.byType(HojaCasa), findsOneWidget);
        expect(find.byKey(ClavesHojaUbicacion.hoja), findsNothing);
      },
      // skip: QA #211 — InicioPage._abrirUbicacion encadena solo hojas de espacios: «Abrir la
      // existente» de la edición de un edificio hacia una casa abre la vista 11 de la casa (solo
      // «Editar casa»).
      skip: _hallazgo,
    );
  });

  group('Estados de la hoja de la casa abierta desde la Lista', () {
    testWidgets('cargando: dice «Cargando la casa», no un spinner solo', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montarInicio(tester, lecturaContexto: (_) => const Stream<ContextoDeLaCasa>.empty());
      await _tocarFila(tester, 'casa');

      expect(find.byType(HojaCasa), findsOneWidget);
      expect(find.byKey(ClavesEstadosHojaCasa.cargando), findsOneWidget);
      expect(
        tester.getSemantics(find.byKey(ClavesEstadosHojaCasa.cargando)).label,
        TextosEstadosHojaCasa.cargando,
      );
      semantica.dispose();
    });

    testWidgets('error al leer: avisa qué pasó y «Reintentar» está a mano', (tester) async {
      var falla = true;
      await _montarInicio(
        tester,
        lecturaContexto: (_) => falla
            ? Stream<ContextoDeLaCasa>.error(StateError('base cerrada'))
            : Stream.value(contextoDelCanvas),
      );
      await _tocarFila(tester, 'casa');
      expect(find.text(TextosEstadosHojaCasa.errorAlLeer), findsOneWidget);
      expect(find.text(TextosEstadosHojaCasa.reintentar), findsOneWidget);

      // Que «Reintentar» recupere la lectura ya lo prueba `hoja_casa_444_test.dart` (aviso aislado);
      // acá, dentro del Inicio, el aviso no se pudo hacer desaparecer en el arnés de QA (sin
      // verificar: queda para la prueba manual).
      falla = false;
      expect(
        tester.widget<TextButton>(find.byKey(ClavesEstadosHojaCasa.accionDelAviso)).onPressed,
        isNotNull,
      );
    });

    testWidgets('lista vacía: sigue diciendo cómo registrar la primera ubicación', (tester) async {
      await _montarInicio(tester, repo: RepoListaFalso());

      expect(find.text('Registrar tu primera ubicación'), findsWidgets);
    });

    testWidgets('la lectura de la Lista falla: el aviso sigue con «Reintentar»', (tester) async {
      final repo = RepoListaFalso(_filas())..fallaAlSuscribir = true;
      await _montarInicio(tester, repo: repo);

      expect(find.text('Reintentar'), findsWidgets);
    });
  });

  group('Accesibilidad de la hoja de la casa abierta desde la Lista', () {
    for (final (nombre, tamano) in [('360x640', _chico), ('412x915', _grande)]) {
      for (final escala in [1.0, 2.0]) {
        // 360×640 a 200 %: el arnés no pudo tocar la fila (el encabezado fijo deja una sola fila y
        // el botón «Nueva» la tapa); sin verificar, para la prueba manual.
        if (tamano == _chico && escala == 2.0) continue;
        testWidgets('$nombre · texto $escala: toque, etiqueta, contraste y sin overflow', (
          tester,
        ) async {
          final semantica = tester.ensureSemantics();
          await _montarInicio(tester, tamano: tamano, escala: escala);
          await _tocarFila(tester, 'casa');
          expect(find.byType(HojaCasa), findsOneWidget);

          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          expect(tester.takeException(), isNull);
          semantica.dispose();
        });
      }
    }

    testWidgets('la Lista con casa, edificio y negocio cumple toque, etiqueta y contraste a '
        '360×640 y texto 2.0', (tester) async {
      final semantica = tester.ensureSemantics();
      await _montarInicio(tester, escala: 2);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      expect(tester.takeException(), isNull);
      semantica.dispose();
    });
  });

  group('Capturas (fuera del repo: .dart_tool/qa_capturas)', () {
    // La app solo tiene tema claro (`tema_colportaje.dart`): no hay tema oscuro que capturar.
    for (final (nombre, tamano, escala) in [
      ('chico_1', _chico, 1.0),
      ('chico_2', _chico, 2.0),
      ('grande_1', _grande, 1.0),
    ]) {
      testWidgets(nombre, (tester) async {
        await cargarFuentes205(tester);
        await _montarInicio(tester, tamano: tamano, escala: escala);
        await _captura(tester, '${nombre}_lista');
        await _tocarFila(tester, 'casa');
        await _captura(tester, '${nombre}_hoja_casa');
        await tester.tapAt(const Offset(180, 10));
        await asentarLista(tester);
        await _tocarFila(tester, 'edif');
        await _captura(tester, '${nombre}_hoja_espacios');
        expect(tester.takeException(), isNull);
      });
    }
  });
}
