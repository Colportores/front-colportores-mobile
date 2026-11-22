// QA del aviso de zona de la pantalla principal (HU-CAM-006, #251, PR #329). La franja no tiene
// artboard propio (decisión de Cristian, 30/09): el texto es el de la HU. Acá va lo que el test del
// PR no cubre: las cuatro guías de accesibilidad en cada estado y en los dos tamaños de teléfono con
// el texto a 1.0 y a 2.0, el cierre que se pisa con un pull, el aviso que sobrevive a un cambio de
// la inscripción, la privacidad de lo guardado y el aviso con el teclado de la pestaña «Lista».
import 'dart:io';
import 'dart:ui' as ui;

import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/inscripciones_con_zona_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/repositories/zonas_avisadas_repository_impl.dart';
import 'package:colportores_mobile/features/auth/domain/entities/inscripcion_con_zona.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/avisos_zona_providers.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:colportores_mobile/features/jornada/data/datasources/fakes/jornada_local_data_source_en_memoria.dart';
import 'package:colportores_mobile/features/jornada/domain/services/disparador_backup.dart';
import 'package:colportores_mobile/features/jornada/presentation/providers/jornada_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/lista_ubicaciones_falsos.dart';
import '../helpers/logger_mudo.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;

const _capturas = bool.fromEnvironment('QA_CAPTURAS');

final _ahora = DateTime(2026, 10, 9, 9, 30);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);
final _raiz = GlobalKey();

const _telefonoChico = Size(360, 640);
const _telefonoGrande = Size(412, 915);

final class _BackupFalso implements DisparadorBackup {
  @override
  Future<void> solicitar(String colportorId) async {}
}

InscripcionConZona _inscripcion({
  String id = 'insc-1',
  String campania = 'Campaña Primavera 2026',
  String? zonaId,
  String? zonaNombre,
  bool dadaDeBaja = false,
}) => InscripcionConZona(
  id: id,
  campaniaId: 'camp-$id',
  campaniaNombre: campania,
  zonaId: zonaId,
  zonaNombre: zonaNombre,
  dadaDeBaja: dadaDeBaja,
);

final _centro = _inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro');
final _norte = _inscripcion(zonaId: 'z-norte', zonaNombre: 'Norte');

const _textoCentro = 'Te asignaron la zona Centro en Campaña Primavera 2026.';
const _textoNorte = 'Te asignaron la zona Norte en Campaña Primavera 2026.';
const _textoSinZona = 'Ya no tenés zona en Campaña Primavera 2026.';

final class _Telefono {
  final fuente = InscripcionesConZonaEnMemoria();
  final almacen = AlmacenSeguroEnMemoria();

  ZonasAvisadasRepositoryImpl get avisadas =>
      ZonasAvisadasRepositoryImpl(almacen, logger: loggerMudo());

  String? get guardado => almacen.contenido[ClaveSegura.zonasAvisadas];
}

/// Los estados del aviso que se ven en la franja.
enum _Estado {
  asignada('asignada'),
  quitada('quitada'),
  dosAvisos('dos avisos (asignada y quitada)'),
  nombresLargos('nombres larguísimos'),
  veinteAvisos('20 avisos');

  const _Estado(this.nombre);
  final String nombre;

  Future<void> armar(_Telefono t) async {
    switch (this) {
      case asignada:
        t.fuente.publicar([_centro]);
      case quitada:
        await t.avisadas.anotar({'insc-1': 'z-centro'});
        t.fuente.publicar([_inscripcion()]);
      case dosAvisos:
        await t.avisadas.anotar({'insc-2': 'z-sur'});
        t.fuente.publicar([_centro, _inscripcion(id: 'insc-2', campania: 'Campaña Verano')]);
      case nombresLargos:
        t.fuente.publicar([
          _inscripcion(
            campania: 'Campaña ${'extensa ' * 12}',
            zonaId: 'z',
            zonaNombre: 'Zona ${'muy larga ' * 12}',
          ),
        ]);
      case veinteAvisos:
        t.fuente.publicar([
          for (var i = 0; i < 20; i++)
            _inscripcion(
              id: 'insc-$i',
              campania: 'Campaña $i',
              zonaId: 'z-$i',
              zonaNombre: 'Zona $i',
            ),
        ]);
    }
  }
}

Future<void> _montar(
  WidgetTester tester,
  _Telefono telefono, {
  Size tamano = _telefonoChico,
  double escala = 1,
  double teclado = 0,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  if (teclado > 0) tester.view.viewInsets = FakeViewPadding(bottom: teclado);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
        disparadorBackupProvider.overrideWithValue(_BackupFalso()),
        relojJornadaProvider.overrideWithValue(() => _ahora),
        inscripcionesConZonaDataSourceProvider.overrideWithValue(telefono.fuente),
        zonasAvisadasRepositoryProvider.overrideWithValue(telefono.avisadas),
        ...overridesPestanaMapa(),
        ...overridesLista(
          repo: RepoListaFalso([
            for (var i = 0; i < 6; i++) filaLista('ubi-$i', calle: 'Calle $i', numero: '${i + 1}'),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => RepaintBoundary(
          key: _raiz,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
            child: child!,
          ),
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

final _avisos = find.byKey(const Key('avisos_zona'));
Finder _cerrar([String inscripcion = 'insc-1']) =>
    find.byKey(Key('aviso_zona_cerrar_$inscripcion'));

Future<void> _tocarCerrar(WidgetTester tester, [String inscripcion = 'insc-1']) async {
  await tester.ensureVisible(_cerrar(inscripcion));
  await tester.pump();
  await tester.tap(_cerrar(inscripcion));
  await tester.pumpAndSettle();
}

Future<void> _guias(WidgetTester tester) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  await expectLater(tester, meetsGuideline(textContrastGuideline));
}

Future<void> _cargarFuentesEIconos(WidgetTester tester) async {
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

Future<void> _capturar(WidgetTester tester, String nombre) async {
  if (!_capturas) return;
  await tester.runAsync(() async {
    final render = tester.renderObject<RenderRepaintBoundary>(find.byKey(_raiz));
    final img = await render.toImage();
    final bytes = (await img.toByteData(format: ui.ImageByteFormat.png))!;
    final dir = Directory('.dart_tool/qa_capturas')..createSync(recursive: true);
    File('${dir.path}/329_$nombre.png').writeAsBytesSync(bytes.buffer.asUint8List());
  });
}

String _combo(Size t, double e) => '${t.width.toInt()}×${t.height.toInt()} · texto ${e}x';

void main() {
  late _Telefono telefono;

  setUp(() => telefono = _Telefono());

  final matriz = <(Size, double)>[
    (_telefonoChico, 1),
    (_telefonoChico, 2),
    (_telefonoGrande, 1),
    (_telefonoGrande, 2),
  ];

  group('QA #329 · las cuatro guías de accesibilidad en cada estado de la franja', () {
    for (final estado in _Estado.values) {
      for (final (tamano, escala) in matriz) {
        testWidgets('${estado.nombre} · ${_combo(tamano, escala)}', (tester) async {
          final semantica = tester.ensureSemantics();
          await estado.armar(telefono);

          await _montar(tester, telefono, tamano: tamano, escala: escala);

          expect(_avisos, findsOneWidget);
          expect(tester.takeException(), isNull);
          await _guias(tester);
          semantica.dispose();
        });
      }
    }
  });

  group('QA #329 · textos literales y semántica', () {
    testWidgets('los dos textos son los de la HU y «Entendido» es un botón con nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _Estado.dosAvisos.armar(telefono);
      await _montar(tester, telefono);

      expect(find.text(_textoCentro), findsOneWidget);
      expect(find.text('Ya no tenés zona en Campaña Verano.'), findsOneWidget);
      final boton = tester.getSemantics(_cerrar('insc-1'));
      expect(boton.label, 'Entendido');
      expect(boton.flagsCollection.isButton, isTrue);
      semantica.dispose();
    });

    testWidgets('«Entendido» mide al menos 48×48 dp a texto 1.0 y 2.0', (tester) async {
      await _Estado.asignada.armar(telefono);
      for (final escala in [1.0, 2.0]) {
        await _montar(tester, telefono, escala: escala);
        final tam = tester.getSize(_cerrar());
        expect(tam.height, greaterThanOrEqualTo(48), reason: 'alto con texto $escala: $tam');
        expect(tam.width, greaterThanOrEqualTo(48), reason: 'ancho con texto $escala: $tam');
      }
    });

    testWidgets('el aviso de zona quitada se anuncia como región viva con su texto', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _Estado.quitada.armar(telefono);
      await _montar(tester, telefono);

      expect(tester.getSemantics(find.text(_textoSinZona)).label, contains(_textoSinZona));
      expect(
        find.ancestor(
          of: find.text(_textoSinZona),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      semantica.dispose();
    });
  });

  group('QA #329 · acciones superpuestas', () {
    testWidgets('cierra «Centro» y en el mismo instante llega un pull con «Norte»: el nuevo se '
        've, el cerrado queda anotado y el nuevo no', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await tester.tap(_cerrar());
      telefono.fuente.publicar([_norte]);
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsNothing);
      expect(find.text(_textoNorte), findsOneWidget);
      expect(telefono.guardado, '{"insc-1":"z-centro"}');
      await _tocarCerrar(tester);
      expect(_avisos, findsNothing);
      expect(telefono.guardado, '{"insc-1":"z-norte"}');
    });

    testWidgets('llega un pull con «Norte» y justo después toca «Entendido» del aviso viejo: el '
        'aviso nuevo no se pierde sin haberlo visto', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      telefono.fuente.publicar([_norte]);
      await tester.tap(_cerrar(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text(_textoCentro), findsNothing);
      // Si se alcanzó a cerrar el viejo, el nuevo sigue ahí; si el pull llegó antes, el toque cerró
      // el nuevo, que sí estaba a la vista: en los dos casos el guardado dice lo que se cerró.
      final cerrado = _avisos.evaluate().isEmpty;
      expect(telefono.guardado, cerrado ? '{"insc-1":"z-norte"}' : '{"insc-1":"z-centro"}');
      if (!cerrado) expect(find.text(_textoNorte), findsOneWidget);
    });

    testWidgets(
      'cierra uno de dos avisos y cierra la app: al abrirla vuelve solo el que no cerró',
      (tester) async {
        await _Estado.dosAvisos.armar(telefono);
        await telefono.avisadas.anotar({'insc-2': 'z-sur'});
        telefono.fuente.publicar([
          _centro,
          _inscripcion(
            id: 'insc-2',
            campania: 'Campaña Verano',
            zonaId: 'z-sur2',
            zonaNombre: 'Sur',
          ),
        ]);
        await _montar(tester, telefono);
        await _tocarCerrar(tester, 'insc-2');

        await _montar(tester, telefono);

        expect(find.text(_textoCentro), findsOneWidget);
        expect(find.textContaining('Campaña Verano'), findsNothing);
      },
    );
  });

  group('QA #329 · el aviso sigue a la inscripción', () {
    testWidgets('con el aviso a la vista, el pull trae la inscripción dada de baja: desaparece', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      telefono.fuente.publicar([
        _inscripcion(zonaId: 'z-centro', zonaNombre: 'Centro', dadaDeBaja: true),
      ]);
      await tester.pumpAndSettle();

      expect(_avisos, findsNothing);
      expect(find.textContaining('zona'), findsNothing);
    });

    testWidgets('con el aviso a la vista, la inscripción deja de estar: el aviso se va', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      telefono.fuente.publicar(const []);
      await tester.pumpAndSettle();

      expect(_avisos, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #329 · el almacén seguro falla', () {
    testWidgets('al leer lo ya avisado: igual avisa, se puede cerrar y no vuelve en la sesión', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      telefono.almacen.simularFalla = true;
      await _montar(tester, telefono);

      expect(find.text(_textoCentro), findsOneWidget);
      await _tocarCerrar(tester);
      expect(_avisos, findsNothing);

      telefono.fuente.publicar([_centro]);
      await tester.pumpAndSettle();

      expect(_avisos, findsNothing, reason: 'cerrado en esta sesión, aunque no se pudo guardar');
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #329 · privacidad', () {
    testWidgets('lo guardado son solo ids: ni zona, ni campaña, ni correo, ni token', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);
      await _tocarCerrar(tester);

      final guardado = telefono.guardado!;
      expect(guardado, '{"insc-1":"z-centro"}');
      for (final dato in ['Centro', 'Campaña', _sesion.email, _sesion.accessToken]) {
        expect(guardado.contains(dato), isFalse, reason: 'el guardado lleva «$dato»');
      }
    });
  });

  group('QA #329 · aviso con el teclado de la pestaña «Lista»', () {
    // Sin el aviso la pestaña no desborda con el teclado (control). Con aviso, la franja se oculta
    // mientras el teclado está abierto (decisión del orquestador, 09/10: gana el campo que se
    // escribe; precedente #322), así que el campo queda a la vista aun con texto 2.0.
    for (final conAviso in [false, true]) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('360×640 con teclado de 300 dp, texto ${escala}x, '
            '${conAviso ? 'con' : 'sin'} aviso: sin overflow y el campo de búsqueda a la vista', (
          tester,
        ) async {
          // Con las fuentes de la app: la de prueba (cuadrados) parte el texto distinto y mide de más.
          await _cargarFuentesEIconos(tester);
          if (conAviso) telefono.fuente.publicar([_centro]);
          await _montar(tester, telefono, escala: escala);
          await tester.tap(find.byKey(const Key('inicio_pestana_lista')));
          await tester.pumpAndSettle();
          final campo = find
              .descendant(
                of: find.byKey(const Key('pestana_lista')),
                matching: find.byType(TextField),
              )
              .first;
          await tester.tap(campo);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          await tester.pumpAndSettle();
          await _capturar(tester, 'lista_teclado_${conAviso ? 'con' : 'sin'}_aviso_${escala}x');

          expect(tester.takeException(), isNull);
          expect(_avisos, findsNothing, reason: 'con el teclado abierto la franja se oculta');
          final rect = tester.getRect(campo);
          expect(
            rect.height >= 48 && rect.bottom <= 640 - 300,
            isTrue,
            reason: 'campo $rect, teclado desde y=340',
          );
        });
      }
    }

    testWidgets('el aviso vuelve al cerrar el teclado y no se anota mientras estuvo oculto', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono, escala: 2);
      expect(find.text(_textoCentro), findsOneWidget);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(_avisos, findsNothing);
      expect(find.text(_textoCentro), findsNothing);
      expect(telefono.guardado, isNull, reason: 'oculto no es lo mismo que avisado');

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();
      expect(find.text(_textoCentro), findsOneWidget);
      expect(telefono.guardado, isNull);

      await _tocarCerrar(tester);
      expect(_avisos, findsNothing);
      expect(telefono.guardado, '{"insc-1":"z-centro"}');
    });

    testWidgets('con el teclado abierto llega un pull con otra zona: al cerrarlo sale el último '
        'aviso, uno solo', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      telefono.fuente.publicar([_norte]);
      await tester.pumpAndSettle();
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsNothing);
      expect(find.text(_textoNorte), findsOneWidget);
    });
  });

  group('QA #329 · capturas de cada estado (solo con QA_CAPTURAS=true)', () {
    for (final (tamano, escala) in matriz) {
      testWidgets('capturas ${tamano.width.toInt()}x${tamano.height.toInt()}_${escala}x', (
        tester,
      ) async {
        if (!_capturas) return;
        await _cargarFuentesEIconos(tester);
        for (final estado in _Estado.values) {
          final t = _Telefono();
          await estado.armar(t);
          await _montar(tester, t, tamano: tamano, escala: escala);
          await _capturar(
            tester,
            '${tamano.width.toInt()}x${tamano.height.toInt()}_${escala}x_${estado.name}',
          );
        }
      });
    }
  });
}
