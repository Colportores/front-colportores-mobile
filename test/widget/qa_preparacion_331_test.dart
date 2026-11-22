// QA de #331 (PR #337, HU-AUTH-009): los textos de «No pudimos abrir tus datos» y del diálogo de
// «Empezar de nuevo». Complementa `preparacion_db_local_page_test.dart` sin repetirlo: los literales
// se vuelven a escribir acá a mano desde la HU y la decisión del 09/10 (front-colportores-mobile#283),
// no se importan de la página, para que un cambio de la constante falle el test; sumá la navegación
// (atrás, barrera, Tab), las acciones superpuestas del diálogo, la falla después del descarte, la
// matriz de accesibilidad en 360x640 y 412x915 con texto 1.0 y 2.0, y la geometría del diálogo con
// las fuentes reales. El canvas de la vista 13 no dibuja estos dos estados: no hay artboard.
import 'dart:io';

import 'package:colportores_mobile/app.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_ajustes_sistema.dart';
import 'package:colportores_mobile/core/dispositivo/abridor_enlace_externo.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/auth_data_sources_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/estado_db_local.dart';
import 'package:colportores_mobile/features/auth/presentation/pages/preparacion_db_local_page.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/auth_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/db_local_providers.dart';
import 'package:colportores_mobile/features/auth/presentation/providers/sesion_notifier.dart';
import 'package:colportores_mobile/features/inicio/presentation/pages/inicio_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/db_local_repository_en_memoria.dart';

const _email = 'ana@example.com';
const _password = 'Secreto123';

// HU-AUTH-009, escenario «Edge -el envoltorio por contraseña falta o está dañado».
const _literalHu =
    'No pudimos abrir los datos guardados en este teléfono: se perdieron la llave que los protege '
    'y la copia que se abre con tu contraseña. No se borró nada.';
const _tituloPantalla = 'No pudimos abrir tus datos';
const _ofertaEmpezar = 'Si sigue sin funcionar, podés empezar de nuevo con este teléfono.';
const _tituloDialogo = '¿Empezar de nuevo?';
// Decisión del orquestador (09/10) en front-colportores-mobile#283, P2, y en #337 (jornadas,
// ubicaciones y ventas).
const _detalleDialogo =
    'Los datos guardados en este teléfono no se pueden abrir sin la llave que los protege. Si '
    'empezás de nuevo, se borran: se pierden las personas y las notas (que nunca se suben) y todo '
    'lo que todavía no se subió, como jornadas, ubicaciones y ventas. Lo que ya se subió no se '
    'pierde. No se puede deshacer.';

/// Lo que un usuario nunca debe leer: el texto viejo, el del `Failure`, el código o jerga técnica.
const _prohibidoEnPantalla = [
  'pasajero',
  'reintentá.',
  'DB_ALMACEN',
  'Failure',
  'Exception',
  'DEK',
  'SQLCipher',
  'Keystore',
  'Argon',
  'No pudimos preparar el almacenamiento seguro',
  'Consultá a soporte antes de reinstalar',
];

/// Lo que el diálogo no debe prometer ni decir (texto viejo, Drive, «se vuelve a bajar»).
const _prohibidoEnDialogo = [
  'sincroniz',
  'bajar',
  'Drive',
  'nube',
  'servidor',
  'sin su clave',
  ..._prohibidoEnPantalla,
];

late DbLocalRepositoryEnMemoria _db;
late _EnlaceFalso _soporte;

final class _Ajustes implements AbridorAjustesSistema {
  @override
  Future<bool> abrirSeguridad() async => true;
  @override
  Future<bool> abrirAlmacenamiento() async => true;
  @override
  Future<bool> abrirRed() async => true;
}

final class _EnlaceFalso implements AbridorEnlaceExterno {
  final abiertos = <Uri>[];

  @override
  Future<bool> abrir(Uri enlace) async {
    abiertos.add(enlace);
    return true;
  }
}

Finder _k(String key) => find.byKey(Key(key));
Finder get _principal => find.byType(InicioPage);
Finder get _dialogo => find.byType(AlertDialog);

/// Una base que no abre: el archivo está, el almacén perdió la llave y no hay copia por contraseña.
void _baseCerrada() {
  final dek = Uint8List.fromList(List<int>.filled(32, 9));
  _db
    ..marca = MarcaDbLocal.puesta
    ..archivo = true
    ..claveDelArchivo = dek
    ..dekEnAlmacen = null
    ..envoltorio = null;
}

Future<ProviderContainer> _entrar(WidgetTester tester) async {
  final container = ProviderContainer(
    overrides: [
      authRemoteDataSourceProvider.overrideWithValue(
        AuthRemoteDataSourceEnMemoria(credenciales: const {_email: _password}),
      ),
      authLocalDataSourceProvider.overrideWithValue(AuthLocalDataSourceEnMemoria()),
      dbLocalRepositoryProvider.overrideWithValue(_db),
      abridorAjustesSistemaProvider.overrideWithValue(_Ajustes()),
      abridorEnlaceExternoProvider.overrideWithValue(_soporte),
    ],
  );
  addTearDown(container.dispose);
  await container.read(sesionProvider.future);
  await container.read(sesionProvider.notifier).iniciarSesion(email: _email, password: _password);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const ColportoresApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> _tocar(WidgetTester tester, String key) async {
  await tester.ensureVisible(_k(key));
  await tester.tap(_k(key));
  await tester.pumpAndSettle();
}

/// La pantalla de la base cerrada: con [reintentos] fallidos ya se ofrece «Empezar de nuevo».
Future<ProviderContainer> _pantalla(WidgetTester tester, {int reintentos = 0}) async {
  _baseCerrada();
  final c = await _entrar(tester);
  for (var i = 0; i < reintentos; i++) {
    await _tocar(tester, 'preparacion_db_reintentar');
  }
  return c;
}

Future<void> _abrirDialogo(WidgetTester tester) async {
  await _pantalla(tester, reintentos: 1);
  await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
}

void _tamano(WidgetTester tester, Size tam, double escala) {
  tester.view.physicalSize = tam;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Todo texto visible: los `Text` del árbol (con su `data`).
List<String> _textos(WidgetTester tester) => [
  for (final t in tester.widgetList<Text>(find.byType(Text)))
    if (t.data != null) t.data!,
];

/// Todas las etiquetas del árbol de semántica (lo que leería un lector de pantalla).
List<String> _etiquetas(WidgetTester tester) {
  final etiquetas = <String>[];
  void visitar(SemanticsNode nodo) {
    final data = nodo.getSemanticsData();
    if (data.label.isNotEmpty) etiquetas.add(data.label);
    if (data.tooltip.isNotEmpty) etiquetas.add(data.tooltip);
    nodo.visitChildren((hijo) {
      visitar(hijo);
      return true;
    });
  }

  visitar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
  return etiquetas;
}

int _descartes() => _db.llamadas.where((l) => l == 'descartar').length;

void main() {
  setUp(() {
    _db = DbLocalRepositoryEnMemoria();
    _soporte = _EnlaceFalso();
  });

  group('QA #331 — textos literales de HU-AUTH-009 y de la decisión del 09/10', () {
    testWidgets('«No pudimos abrir tus datos» la primera vez: el literal de la HU, los botones '
        'que guían y nada técnico', (tester) async {
      final handle = tester.ensureSemantics();
      await _pantalla(tester);

      expect(find.text(_tituloPantalla), findsOneWidget);
      expect(find.text(_literalHu), findsOneWidget);
      expect(_k('preparacion_db_reintentar'), findsOneWidget);
      expect(_k('preparacion_db_contactar_soporte'), findsOneWidget);
      expect(_k('preparacion_db_cerrar_sesion'), findsOneWidget);
      // «Empezar de nuevo» recién después de un reintento que vuelve a fallar.
      expect(_k('preparacion_db_empezar_de_nuevo'), findsNothing);
      expect(find.text(_ofertaEmpezar), findsNothing);
      for (final prohibido in _prohibidoEnPantalla) {
        expect(
          [..._textos(tester), ..._etiquetas(tester)].where((t) => t.contains(prohibido)),
          isEmpty,
          reason: 'la pantalla no debe decir «$prohibido»',
        );
      }
      expect(_db.archivo, isTrue, reason: 'no se borró nada');
      expect(_descartes(), 0);
      handle.dispose();
    });

    testWidgets('tras 1, 2 y 3 reintentos fallidos el literal es uno solo, no se pierde ni se '
        'duplica, y la oferta de empezar de nuevo no pisa nada', (tester) async {
      await _pantalla(tester);
      for (var n = 1; n <= 3; n++) {
        await _tocar(tester, 'preparacion_db_reintentar');

        expect(find.text(_literalHu), findsOneWidget, reason: 'reintento $n');
        expect(find.text(_ofertaEmpezar), findsOneWidget, reason: 'reintento $n');
        expect(_k('preparacion_db_empezar_de_nuevo'), findsOneWidget);
        expect(_textos(tester).any((t) => t.contains('pasajero')), isFalse);
      }
      expect(_db.archivo, isTrue);
    });

    testWidgets('el diálogo dice qué se pierde (personas, notas y ventas sin subir) con el texto '
        'de la decisión, y nada de lo viejo', (tester) async {
      final handle = tester.ensureSemantics();
      await _abrirDialogo(tester);

      expect(find.descendant(of: _dialogo, matching: find.text(_tituloDialogo)), findsOneWidget);
      expect(find.descendant(of: _dialogo, matching: find.text(_detalleDialogo)), findsOneWidget);
      expect(find.descendant(of: _dialogo, matching: find.text('Cancelar')), findsOneWidget);
      expect(
        find.descendant(of: _dialogo, matching: find.text('Borrar y empezar de nuevo')),
        findsOneWidget,
      );
      for (final palabra in ['personas', 'notas', 'ventas', 'No se puede deshacer']) {
        expect(_detalleDialogo, contains(palabra));
        expect(
          find.descendant(of: _dialogo, matching: find.textContaining(palabra)),
          findsOneWidget,
        );
      }
      final enElDialogo = [
        for (final t in tester.widgetList<Text>(
          find.descendant(of: _dialogo, matching: find.byType(Text)),
        ))
          t.data ?? '',
        ..._etiquetas(tester),
      ];
      for (final prohibido in _prohibidoEnDialogo) {
        expect(
          enElDialogo.where((t) => t.contains(prohibido)),
          isEmpty,
          reason: 'el diálogo no debe decir «$prohibido»',
        );
      }
      expect(_descartes(), 0, reason: 'preguntar no borra');
      handle.dispose();
    });

    testWidgets('«Contactar a soporte» lleva el código de la falla y ningún dato personal', (
      tester,
    ) async {
      await _pantalla(tester);
      await _tocar(tester, 'preparacion_db_contactar_soporte');

      expect(_soporte.abiertos, hasLength(1));
      final enlace = Uri.decodeFull(_soporte.abiertos.single.toString());
      expect(enlace, contains('DB_ALMACEN_SIN_RECUPERACION'));
      expect(enlace, isNot(contains(_email)));
      expect(enlace, isNot(contains('ana')));
      expect(enlace, isNot(contains(_password)));
    });
  });

  group('QA #331 — navegación: atrás, barrera, Tab y reentrada', () {
    testWidgets('atrás con el diálogo abierto lo cierra sin borrar, y se puede volver a abrir '
        '(uno solo)', (tester) async {
      await _abrirDialogo(tester);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(_dialogo, findsNothing);
      expect(find.text(_literalHu), findsOneWidget);
      expect(_descartes(), 0);
      expect(_db.archivo, isTrue);

      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
      expect(_dialogo, findsOneWidget);
      expect(find.text(_detalleDialogo), findsOneWidget);
    });

    testWidgets('un toque fuera del diálogo (la barrera) lo cierra sin borrar y deja reabrirlo', (
      tester,
    ) async {
      await _abrirDialogo(tester);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();

      expect(_dialogo, findsNothing);
      expect(_descartes(), 0);
      expect(_db.archivo, isTrue);
      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
      expect(_dialogo, findsOneWidget);
    });

    testWidgets('cinco veces abrir y cancelar: ningún borrado, ninguna ruta colgada, la pantalla '
        'sigue en su lugar', (tester) async {
      await _pantalla(tester, reintentos: 1);
      for (var i = 0; i < 5; i++) {
        await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
        expect(_dialogo, findsOneWidget, reason: 'vuelta $i');
        await _tocar(tester, 'preparacion_db_cancelar_empezar');
        expect(_dialogo, findsNothing, reason: 'vuelta $i');
      }
      expect(_descartes(), 0);
      expect(find.byType(PreparacionDbLocalPage), findsOneWidget);
      expect(tester.state<NavigatorState>(find.byType(Navigator).first).canPop(), isFalse);
      expect(find.text(_literalHu), findsOneWidget);
    });

    testWidgets('atrás en la pantalla (sin diálogo) no borra nada ni cambia lo que dice', (
      tester,
    ) async {
      await _pantalla(tester, reintentos: 1);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byType(PreparacionDbLocalPage), findsOneWidget);
      expect(find.text(_literalHu), findsOneWidget);
      expect(_descartes(), 0);
      expect(_db.archivo, isTrue);
    });

    testWidgets('con el teclado, el foco queda dentro del diálogo y no se escapa a la pantalla de '
        'abajo; Enter en «Cancelar» lo cierra sin borrar', (tester) async {
      await _abrirDialogo(tester);

      final dentro = <bool>[];
      for (var i = 0; i < 6; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final foco = FocusManager.instance.primaryFocus;
        dentro.add(foco?.context?.findAncestorWidgetOfExactType<AlertDialog>() != null);
      }
      expect(dentro, everyElement(isTrue), reason: 'Tab no sale del diálogo');

      // Llega a «Cancelar» (el primero de las acciones) y lo activa con Enter.
      for (var i = 0; i < 4; i++) {
        final foco = FocusManager.instance.primaryFocus;
        if (foco?.context?.findAncestorWidgetOfExactType<TextButton>() != null) break;
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(_dialogo, findsNothing);
      expect(_descartes(), 0);
      expect(_db.archivo, isTrue);
    });
  });

  group('QA #331 — acciones superpuestas y fallas a mitad', () {
    testWidgets('«Cancelar» y enseguida «Borrar» en el mismo instante: gana el primero, no se '
        'borra nada', (tester) async {
      await _abrirDialogo(tester);

      await tester.tap(_k('preparacion_db_cancelar_empezar'));
      await tester.tap(_k('preparacion_db_confirmar_empezar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_descartes(), 0);
      expect(_db.archivo, isTrue);
      expect(_dialogo, findsNothing);
      expect(find.byType(PreparacionDbLocalPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('«Borrar» y enseguida «Cancelar»: se borra una sola vez y la app llega a Inicio', (
      tester,
    ) async {
      await _abrirDialogo(tester);

      await tester.tap(_k('preparacion_db_confirmar_empezar'));
      await tester.tap(_k('preparacion_db_cancelar_empezar'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // `descartar` también lo llama la preparación al tratar el teléfono como nuevo: se cuenta
      // la preparación (`crearDek`), que tiene que ser una sola.
      expect(_db.llamadas.where((l) => l == 'crearDek'), hasLength(1));
      expect(_db.archivo, isTrue, reason: 'la base nueva ya está creada');
      expect(_principal, findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('el descarte anda pero preparar de nuevo falla: la pantalla ya no dice «No se '
        'borró nada» (sí se borró), no queda «ocupada» y «Reintentar» termina el trabajo', (
      tester,
    ) async {
      await _abrirDialogo(tester);
      _db.fallas['crearDek'] = const FailureAlmacenSeguro();

      await _tocar(tester, 'preparacion_db_confirmar_empezar');

      expect(_descartes(), greaterThanOrEqualTo(1));
      expect(find.text(_literalHu), findsNothing, reason: 'ya se borró: decir lo contrario miente');
      expect(find.textContaining('No se borró nada'), findsNothing);
      expect(find.text('Preparando tu espacio seguro… 1/3'), findsNothing);
      expect(_dialogo, findsNothing);
      expect(
        tester.widget<ButtonStyleButton>(_k('preparacion_db_reintentar')).onPressed,
        isNotNull,
      );
      expect(_k('preparacion_db_contactar_soporte'), findsOneWidget);

      _db.fallas.remove('crearDek');
      await _tocar(tester, 'preparacion_db_reintentar');
      expect(_principal, findsOneWidget);
    });

    testWidgets('con el diálogo abierto la sesión se cierra (revocada): «Borrar y empezar de '
        'nuevo» no borra nada porque la pantalla ya no está', (tester) async {
      await _pantalla(tester, reintentos: 1);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PreparacionDbLocalPage)),
      );
      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
      expect(_dialogo, findsOneWidget);

      await container.read(sesionProvider.notifier).cerrarSesion();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      if (_dialogo.evaluate().isNotEmpty) {
        await tester.tap(_k('preparacion_db_confirmar_empezar'));
        await tester.pumpAndSettle();
      }

      expect(_descartes(), 0, reason: 'sin pantalla que lo pida no se borra');
      expect(_db.archivo, isTrue);
      expect(_dialogo, findsNothing, reason: 'el diálogo no queda flotando sobre otra pantalla');
      expect(tester.takeException(), isNull);
    });
  });

  group('QA #331 — accesibilidad: matriz de tamaños y escalas', () {
    final estados = <String, Future<void> Function(WidgetTester)>{
      'primera vez (sin empezar de nuevo)': (tester) async {
        await _pantalla(tester);
      },
      'tras un reintento (con empezar de nuevo)': (tester) async {
        await _pantalla(tester, reintentos: 1);
      },
      'diálogo de empezar de nuevo': _abrirDialogo,
    };

    for (final MapEntry(key: nombre, value: preparar) in estados.entries) {
      for (final (tam, escala) in [
        (const Size(360, 640), 1.0),
        (const Size(360, 640), 2.0),
        (const Size(412, 915), 1.0),
        (const Size(412, 915), 2.0),
      ]) {
        testWidgets('$nombre en ${tam.width.toInt()}x${tam.height.toInt()} con texto $escala: sin '
            'overflow, toque ≥ 48 dp, etiquetas y contraste', (tester) async {
          final handle = tester.ensureSemantics();
          _tamano(tester, tam, escala);
          await preparar(tester);

          expect(tester.takeException(), isNull);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }

    testWidgets('el literal se anuncia (región viva) y el título es un encabezado; el diálogo '
        'tiene nombre y alcance de ruta', (tester) async {
      final handle = tester.ensureSemantics();
      await _pantalla(tester, reintentos: 1);

      final literal = tester.getSemantics(find.text(_literalHu));
      expect(literal.flagsCollection.isLiveRegion, isTrue);
      final titulo = tester.getSemantics(find.text(_tituloPantalla));
      expect(titulo.flagsCollection.isHeader, isTrue);

      await _tocar(tester, 'preparacion_db_empezar_de_nuevo');
      // El diálogo es una ruta con nombre y alcance propios, y el título está en su árbol.
      var conAlcance = 0;
      void contar(SemanticsNode nodo) {
        final d = nodo.getSemanticsData();
        if (d.flagsCollection.scopesRoute && d.flagsCollection.namesRoute) {
          conAlcance++;
        }
        nodo.visitChildren((h) {
          contar(h);
          return true;
        });
      }

      contar(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      expect(conAlcance, 1);
      expect(_etiquetas(tester), contains(_tituloDialogo));
      handle.dispose();
    });

    test('contraste AA de los colores nuevos del diálogo y de «Empezar de nuevo» (tema claro, el '
        'único de la app)', () {
      final tema = temaClaro();
      final esquema = tema.colorScheme;
      double razon(Color a, Color b) {
        final la = a.computeLuminance();
        final lb = b.computeLuminance();
        final (claro, oscuro) = la > lb ? (la, lb) : (lb, la);
        return (claro + 0.05) / (oscuro + 0.05);
      }

      // «Borrar y empezar de nuevo»: texto onError sobre fondo error.
      expect(razon(esquema.onError, esquema.error), greaterThanOrEqualTo(4.5));
      // «Empezar de nuevo» (outlined): texto error sobre el fondo de la pantalla.
      expect(razon(esquema.error, tema.scaffoldBackgroundColor), greaterThanOrEqualTo(4.5));
    });
  });

  group('QA #331 — el diálogo con el texto al 200 % en una pantalla chica', () {
    // Con el texto al 200 % en 360x640 el detalle que dice qué se pierde queda detrás de un
    // desplazamiento: el diálogo muestra un `Scrollbar` con `thumbVisibility` para que se note.
    testWidgets(
      'con el texto al 200 % en 360x640 el desplazamiento del detalle se ve (barra visible)',
      (tester) async {
        _tamano(tester, const Size(360, 640), 2.0);
        await _abrirDialogo(tester);

        final barra = find.descendant(of: _dialogo, matching: find.byType(Scrollbar));
        expect(barra, findsOneWidget);
        expect(tester.widget<Scrollbar>(barra).thumbVisibility, isTrue);
      },
    );
  });

  group('QA #331 — geometría del diálogo con las fuentes reales', () {
    setUpAll(() async {
      for (final f in ['Inter', 'SourceSerif4', 'JetBrainsMono']) {
        final bytes = File('assets/fonts/$f.ttf').readAsBytesSync();
        final cargador = FontLoader(f)..addFont(Future.value(ByteData.view(bytes.buffer)));
        await cargador.load();
      }
    });

    for (final (tam, escala) in [
      (const Size(360, 640), 1.0),
      (const Size(360, 640), 2.0),
      (const Size(412, 915), 2.0),
    ]) {
      testWidgets('en ${tam.width.toInt()}x${tam.height.toInt()} con texto $escala los dos '
          'botones quedan enteros en pantalla, miden ≥ 48 dp y la última frase se alcanza', (
        tester,
      ) async {
        _tamano(tester, tam, escala);
        await _abrirDialogo(tester);
        final pantalla = Offset.zero & tam;

        for (final key in ['preparacion_db_cancelar_empezar', 'preparacion_db_confirmar_empezar']) {
          final r = tester.getRect(_k(key));
          expect(
            pantalla.contains(r.topLeft) && pantalla.contains(r.bottomRight),
            isTrue,
            reason: '$key $r fuera de $pantalla',
          );
          expect(r.height, greaterThanOrEqualTo(48), reason: key);
          expect(r.width, greaterThanOrEqualTo(48), reason: key);
        }

        // El detalle se desplaza dentro del diálogo; al final se ve «No se puede deshacer.».
        final desplazable = find.descendant(
          of: _dialogo,
          matching: find.byType(SingleChildScrollView),
        );
        expect(desplazable, findsOneWidget);
        await tester.drag(desplazable, const Offset(0, -3000));
        await tester.pumpAndSettle();
        final texto = tester.getRect(find.text(_detalleDialogo));
        final vista = tester.getRect(desplazable);
        expect(
          texto.bottom,
          lessThanOrEqualTo(vista.bottom + 0.5),
          reason: 'la última línea del detalle queda cortada',
        );
        expect(tester.takeException(), isNull);

        // Y el botón destructivo sigue tocable sin desplazarse.
        await tester.tap(_k('preparacion_db_cancelar_empezar'));
        await tester.pumpAndSettle();
        expect(_dialogo, findsNothing);
        expect(_descartes(), 0);
      });
    }
  });
}
