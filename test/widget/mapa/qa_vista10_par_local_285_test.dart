// QA de la vista 10 «Posibles duplicados», hoja 10·02 con un «Par local» (HU-UBI-006, #285): una de las
// dos ubicaciones todavía no está en el servidor. El canvas no dibuja este caso (los textos son los de
// P1, 04/11). Complementa `par_local_285_test.dart` (el del implementador) con lo que ese no mide:
//
// - la matriz 360×640 y 412×915 × texto 1,0 y 2,0 × cada estado del par local: sin overflow, toques de
//   48/44 dp, etiquetas y capturas PNG con las fuentes reales (`.dart_tool/qa_capturas/`, nunca se
//   commitean; se piden con `--dart-define=QA_CAPTURAS=true`);
// - lo que lee el lector de pantalla de cada opción (nombre, marcada, acción de toque);
// - contraste del aviso del par local;
// - casos límite: «Deshacer» en un par local, segundo toque, reentrada a la hoja, el alta que cambia
//   mientras corren los 8 s, las dos fallas nuevas con su salida, y el aviso con texto largo.
//
// Los tests con `skip` documentan un hallazgo de QA (`QA #285: …`): el implementador saca el `skip`
// cuando lo arregla; `--dart-define=QA_HALLAZGOS=true` los corre igual.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/posibles_duplicados_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_comparar_duplicado.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart'
    show ColoresAlta;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/duplicados_falsos.dart';
import '../../helpers/qa_vista10_arnes.dart';

const _verHallazgos = bool.fromEnvironment('QA_HALLAZGOS');
const _conCapturas = bool.fromEnvironment('QA_CAPTURAS');
const _ocho = Duration(seconds: 8);
const _clave = 'ub-a|ub-b';

/// Los textos de P1 (04/11), literales.
const _avisoParLocal =
    'Una de las dos todavía no está en el servidor, así que se conserva la que sí está. Lo que '
    'cargaste en la otra pasa a ella y se sube con el resto.';
const _textoSubiendo =
    'Una de las dos ubicaciones se está subiendo ahora. Esperá un momento y probá de nuevo.';
const _textoConservadaLocal =
    'La ubicación que ibas a conservar todavía no está en el servidor. Revisá el par de nuevo.';

/// A (la más vieja) y B, el mismo número de puerta a 12 m, con el estado de casa del canvas.
DuplicadosEnMemoria _datos({String calle = 'Av. Italia', String numero = '1234'}) =>
    DuplicadosEnMemoria()
      ..agregar(
        ubicacionDuplicable(
          'ub-a',
          calle: calle,
          numero: numero,
          creada: DateTime.utc(2026, 8, 1, 10),
        ),
        espacios: 2,
      )
      ..agregar(
        ubicacionDuplicable(
          'ub-b',
          calle: calle,
          numero: numero,
          metrosAlNorte: 12,
          creada: DateTime.utc(2026, 8, 5, 10),
        ),
      );

Future<void> _asentar(WidgetTester tester, [int veces = 8]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<void> _transicion(WidgetTester tester) async {
  await _asentar(tester);
  await tester.pump(const Duration(seconds: 1));
  await _asentar(tester);
}

Future<void> _montar(
  WidgetTester tester,
  DuplicadosEnMemoria datos,
  ConsultorAltaUbicacionFalso altas, {
  double escala = 1,
  Size tamano = telefonoChico208,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(datos.cerrar);
  await cargarFuentes208(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesDuplicados(datos, conMapa: true, altas: altas),
      child: RepaintBoundary(
        key: raizCaptura208,
        child: MaterialApp(
          theme: temaClaro(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('abrir'),
                  onPressed: () =>
                      unawaited(PosiblesDuplicadosPage.abrir(context, colportorId: 'col-1')),
                  child: const Text('abrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.byKey(const Key('abrir')));
  await _transicion(tester);
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  if (f.evaluate().isEmpty) {
    await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
  }
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
  await _asentar(tester);
}

Future<void> _desmontar(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 10));
}

void _prueba(String descripcion, Future<void> Function(WidgetTester tester) cuerpo, {bool? skip}) {
  testWidgets(descripcion, (tester) async {
    final semantica = tester.ensureSemantics();
    await cuerpo(tester);
    await _desmontar(tester);
    semantica.dispose();
  }, skip: skip);
}

final _revisar = find.byKey(const Key('revisar_$_clave'));
final _conservarYUnir = find.byKey(const Key('comparar_conservar_y_unir'));
final _despues = find.byKey(const Key('comparar_despues'));
final _primera = find.byKey(const Key('comparar_opcion_primera'));
final _segunda = find.byKey(const Key('comparar_opcion_segunda'));
final _avisoDeLaHoja = find.byKey(const Key('comparar_par_local'));
final _falla = find.byKey(const Key('duplicados_falla_union'));
final _reintentar = find.byKey(const Key('duplicados_reintentar_union'));
final _hoja = find.byType(HojaCompararDuplicado);

Future<void> _abrirHoja(WidgetTester tester) => _tocar(tester, _revisar);

Future<void> _unirYEsperar(WidgetTester tester) async {
  await _tocar(tester, _conservarYUnir);
  await tester.pump(_ocho);
  await _asentar(tester);
}

// ------------------------------------------------------------------------------------------------
// Los estados de la matriz.
// ------------------------------------------------------------------------------------------------
class _Estado {
  const _Estado(this.nombre, this.altas, this.llegar, {this.falla});

  final String nombre;
  final Map<String, EstadoAltaUbicacion> altas;
  final Failure? falla;
  final Future<void> Function(WidgetTester tester) llegar;
}

Future<void> _soloLaHoja(WidgetTester tester) => _abrirHoja(tester);

Future<void> _hastaLaFalla(WidgetTester tester) async {
  await _abrirHoja(tester);
  await _unirYEsperar(tester);
}

Future<void> _hastaElAvisoDeshacer(WidgetTester tester) async {
  await _abrirHoja(tester);
  await _tocar(tester, _conservarYUnir);
}

final _estados = <_Estado>[
  const _Estado('02-hoja-B-solo-en-telefono', {
    'ub-b': EstadoAltaUbicacion.soloEnTelefono,
  }, _soloLaHoja),
  const _Estado('02-hoja-A-solo-en-telefono', {
    'ub-a': EstadoAltaUbicacion.soloEnTelefono,
  }, _soloLaHoja),
  const _Estado('02-hoja-las-dos-solo-en-telefono', {
    'ub-a': EstadoAltaUbicacion.soloEnTelefono,
    'ub-b': EstadoAltaUbicacion.soloEnTelefono,
  }, _soloLaHoja),
  const _Estado('02-hoja-B-subiendo', {'ub-b': EstadoAltaUbicacion.subiendo}, _soloLaHoja),
  const _Estado('02-hoja-par-comun', {}, _soloLaHoja),
  const _Estado('03-par-resuelto-par-local', {
    'ub-b': EstadoAltaUbicacion.soloEnTelefono,
  }, _hastaElAvisoDeshacer),
  const _Estado(
    '03-falla-alta-subiendo',
    {'ub-b': EstadoAltaUbicacion.subiendo},
    _hastaLaFalla,
    falla: FailureAltaSubiendo(),
  ),
  const _Estado(
    '03-falla-conservada-solo-en-telefono',
    {'ub-b': EstadoAltaUbicacion.soloEnTelefono},
    _hastaLaFalla,
    falla: FailureConservadaSoloEnTelefono(),
  ),
];

/// Las tres guías de accesibilidad de Flutter menos el contraste (con las fuentes reales da falsos
/// negativos: el contraste se mide aparte, par de colores por par de colores).
Future<List<String>> _guias(WidgetTester tester) async {
  final fallas = <String>[];
  Future<void> probar(String nombre, AccessibilityGuideline guia) async {
    try {
      await expectLater(tester, meetsGuideline(guia));
    } on TestFailure catch (e) {
      fallas.add('$nombre: ${e.message}');
    }
  }

  await probar('android 48dp', androidTapTargetGuideline);
  await probar('ios 44dp', iOSTapTargetGuideline);
  await probar('etiquetas', labeledTapTargetGuideline);
  return fallas;
}

void main() {
  group('10·02 · textos literales (P1, 04/11) y lo que lee el lector', () {
    _prueba('dado B solo en el teléfono, el aviso y las etiquetas dicen lo decidido', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);

      expect(find.text(_avisoParLocal), findsOneWidget);
      final a = tester.getSemantics(_primera);
      final b = tester.getSemantics(_segunda);
      expect(a.label, startsWith('Ubicación A, la que se conserva: Av. Italia 1234'));
      expect(b.label, startsWith('Ubicación B, solo en tu teléfono: queda como baja: Av. Italia'));
      expect(a, isSemantics(isButton: true, hasTapAction: true, isChecked: true));
      expect(b, isSemantics(isButton: true, hasTapAction: false, isChecked: false));
    });

    _prueba('dado B solo en el teléfono, la hoja ofrece "Conservar A y unir" habilitado y no pide '
        'nada más para seguir', (tester) async {
      await _montar(
        tester,
        _datos(),
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);

      expect(_conservarYUnir, findsOneWidget);
      expect(
        tester.getSemantics(_conservarYUnir),
        isSemantics(isEnabled: true, hasTapAction: true),
      );
      // Con la misma dirección a menos de 100 m (D1) «Son distintos» no se ofrece; «Después» sí.
      expect(find.byKey(const Key('comparar_son_distintos')), findsNothing);
      expect(_despues, findsOneWidget);
    });

    _prueba('dado B solo en el teléfono, la opción que no se puede elegir se anuncia como no '
        'disponible', (tester) async {
      await _montar(
        tester,
        _datos(),
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);

      // Un botón sin acción y sin estado «deshabilitado»: TalkBack/VoiceOver lo leen como un botón más.
      expect(tester.getSemantics(_segunda), isSemantics(hasEnabledState: true, isEnabled: false));
    }, skip: !_verHallazgos); // skip: QA #285 — la opción de la que solo está en el teléfono no se
    // anuncia como desactivada (es un `button` sin `onTap` y sin `enabled: false`).

    _prueba('el aviso del par local usa el color de tinta del resto de la hoja con contraste AA', (
      tester,
    ) async {
      await _montar(
        tester,
        _datos(),
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);

      final texto = tester.widget<Text>(_avisoDeLaHoja);
      final color = texto.style?.color ?? ColoresAlta.tinta;
      // La hoja es blanca.
      expect(contraste208(color, Colors.white), greaterThanOrEqualTo(4.5));
    });

    _prueba(
      'dado B subiendo (IN_FLIGHT), la etiqueta no dice "solo en tu teléfono" y el aviso es el de «subiendo»',
      (tester) async {
        await _montar(
          tester,
          _datos(),
          ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.subiendo}),
        );
        await _abrirHoja(tester);

        // El alta de B ya está viajando: decir que está «solo en tu teléfono» es lo que no se sabe.
        expect(tester.getSemantics(_segunda).label, isNot(contains('solo en tu teléfono')));
        expect(
          tester.getSemantics(_segunda).label,
          contains('Ubicación B, se está subiendo: queda como baja'),
        );
        expect(find.text(_textoSubiendo), findsOneWidget);
        expect(find.textContaining('todavía no está en el servidor'), findsNothing);
      },
    );

    _prueba(
      'par local con B solo en el teléfono: el texto de dirección única no pide marcar cuál es '
      'el duplicado',
      (tester) async {
        await _montar(
          tester,
          _datos(),
          ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
        );
        await _abrirHoja(tester);

        final unica = find.byKey(const Key('comparar_direccion_unica'));
        expect(
          tester.widget<Text>(unica).data,
          'Si son dos lugares distintos, corregí la dirección de una con «Editar uno».',
        );
        expect(find.textContaining('Marcá cuál es el duplicado'), findsNothing);
      },
    );
  });

  group('Matriz 360×640 y 412×915 × texto 1.0 y 2.0', () {
    for (final tamano in [telefonoChico208, telefonoGrande208]) {
      for (final escala in [1.0, 2.0]) {
        for (final estado in _estados) {
          final etiqueta = '${tamano.width.toInt()}x${tamano.height.toInt()}-x$escala';
          testWidgets('${estado.nombre} · $etiqueta: sin overflow, toques 48/44 dp y etiquetas', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            final datos = _datos()..falloAlUnir = estado.falla;
            await _montar(
              tester,
              datos,
              ConsultorAltaUbicacionFalso(estado.altas),
              tamano: tamano,
              escala: escala,
            );
            await estado.llegar(tester);

            expect(tester.takeException(), isNull, reason: 'overflow o excepción de layout');
            expectSinTextoFueraDeLosCostados208(tester, tamano);
            final fallas = await _guias(tester);
            if (_conCapturas) {
              await capturar208(tester, '285_${estado.nombre}_$etiqueta');
              if (_hoja.evaluate().isNotEmpty && _despues.evaluate().isNotEmpty) {
                await tester.ensureVisible(_despues);
                await tester.pump(const Duration(milliseconds: 200));
                await capturar208(tester, '285_${estado.nombre}_${etiqueta}_pie');
              }
            }
            expect(fallas, isEmpty);
            await _desmontar(tester);
            semantica.dispose();
          });
        }
      }
    }
  });

  group('Casos límite del par local', () {
    _prueba('«Deshacer» dentro de los 8 s cancela: el par sigue en la lista y no se une nada', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);
      await _tocar(tester, _conservarYUnir);
      await tester.pump(const Duration(seconds: 3));
      await _tocar(tester, find.text('Deshacer'));
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, isEmpty);
      expect(find.byKey(const Key('par_$_clave')), findsOneWidget);
    });

    _prueba('un segundo toque en «Conservar A y unir» no suma una segunda unión', (tester) async {
      final datos = _datos();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);
      await tester.ensureVisible(_conservarYUnir);
      await tester.pump();
      await tester.tap(_conservarYUnir);
      await tester.tap(_conservarYUnir, warnIfMissed: false);
      await tester.pump(_ocho);
      await _asentar(tester);

      expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
    });

    _prueba('reentrada: cerrar con «Después» y volver a abrir deja la misma hoja con su aviso', (
      tester,
    ) async {
      final datos = _datos();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);
      await _tocar(tester, _despues);
      expect(_hoja, findsNothing);
      await _abrirHoja(tester);

      expect(find.text(_avisoParLocal), findsOneWidget);
      expect(tester.getSemantics(_primera).label, startsWith('Ubicación A, la que se conserva'));
      expect(datos.uniones, isEmpty);
    });

    _prueba(
      'el alta de B sube mientras corren los 8 s: la unión se hace igual y no queda trabada',
      (tester) async {
        final datos = _datos();
        final altas = ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono});
        await _montar(tester, datos, altas);
        await _abrirHoja(tester);
        await _tocar(tester, _conservarYUnir);
        altas.poner('ub-b', EstadoAltaUbicacion.enServidor);
        await tester.pump(_ocho);
        await _asentar(tester);

        expect(datos.uniones, [(conservadaId: 'ub-a', duplicadaId: 'ub-b')]);
        expect(_falla, findsNothing);
      },
    );

    _prueba('falla «alta subiendo»: el aviso rojo dice qué hacer, «Reintentar» y la lista siguen '
        'a mano y nada queda trabado', (tester) async {
      final datos = _datos()..falloAlUnir = const FailureAltaSubiendo();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.subiendo}),
      );
      await _abrirHoja(tester);
      await _unirYEsperar(tester);

      expect(find.text(_textoSubiendo), findsOneWidget);
      expect(_reintentar, findsOneWidget);
      expect(find.byKey(const Key('par_$_clave')), findsOneWidget);
      // Se puede volver a abrir el par: la pantalla no quedó ocupada.
      await _tocar(tester, _revisar);
      expect(_hoja, findsOneWidget);
      expect(tester.getSemantics(_conservarYUnir), isSemantics(isEnabled: true));
    });

    _prueba('falla «alta subiendo» a 360×640 y texto al 200 %: el aviso se lee entero, sin '
        'desplazarlo por dentro', (tester) async {
      final datos = _datos()..falloAlUnir = const FailureAltaSubiendo();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.subiendo}),
        escala: 2,
      );
      await _abrirHoja(tester);
      await _unirYEsperar(tester);

      final texto = tester.getRect(find.text(_textoSubiendo));
      final acciones = tester.getRect(_reintentar);
      // El texto lleva la instrucción («Esperá un momento y probá de nuevo»): si su final queda bajo
      // las acciones, hay que arrastrar el aviso por dentro para leerla.
      expect(texto.bottom, lessThanOrEqualTo(acciones.top));
    }, skip: !_verHallazgos); // skip: QA #285 — a 360×640 con texto al 200 % el aviso rojo de «alta
    // subiendo» (más largo que los de antes) se corta a la mitad de la frase y la instrucción queda
    // dentro de un scroll.

    _prueba('falla «la que ibas a conservar todavía no está en el servidor»: no ofrece Reintentar '
        '(no cambia nada) y el par se puede revisar', (tester) async {
      final datos = _datos()..falloAlUnir = const FailureConservadaSoloEnTelefono();
      await _montar(
        tester,
        datos,
        ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
      );
      await _abrirHoja(tester);
      await _unirYEsperar(tester);

      expect(find.text(_textoConservadaLocal), findsOneWidget);
      expect(_reintentar, findsNothing);
      // La salida: el aviso se puede cerrar y el par sigue ahí para revisarlo de nuevo.
      expect(find.byKey(const Key('par_$_clave')), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
      await _tocar(tester, find.text('Entendido'));
      expect(_falla, findsNothing);
      await _tocar(tester, _revisar);
      expect(_hoja, findsOneWidget);
    });

    _prueba(
      'direcciones largas y con emoji: el par local no desborda a 360×640 con texto al 200 %',
      (tester) async {
        final datos = _datos(
          calle: 'Avenida Doctor José Gervasio Artigas y Presidente Tomás Berreta 🙂',
          numero: '12345 bis apto 1204',
        );
        await _montar(
          tester,
          datos,
          ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
          escala: 2,
        );
        await _abrirHoja(tester);
        await tester.ensureVisible(_avisoDeLaHoja);
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.text(_avisoParLocal), findsOneWidget);
        expectSinTextoFueraDeLosCostados208(tester, telefonoChico208);
      },
    );

    _prueba(
      'dado que se toca la opción que no se puede elegir, el aviso del par local sigue a la '
      'vista sin tener que bajar',
      (tester) async {
        await _montar(
          tester,
          _datos(),
          ConsultorAltaUbicacionFalso({'ub-b': EstadoAltaUbicacion.soloEnTelefono}),
          escala: 2,
        );
        await _abrirHoja(tester);
        await tester.tap(_segunda, warnIfMissed: false);
        await _asentar(tester);

        // El toque en la opción apagada no hace nada: si el motivo está bajo el pliegue, la persona no
        // ve por qué. A 360×640 y 200 % el aviso debería estar a la vista junto a las opciones.
        final pantalla = tester.view.physicalSize / tester.view.devicePixelRatio;
        final aviso = tester.getRect(_avisoDeLaHoja);
        expect(aviso.bottom, lessThanOrEqualTo(pantalla.height));
      },
      skip: !_verHallazgos,
    ); // skip: QA #285 — a 360×640 con texto al 200 % el motivo por el que no se
    // puede elegir una opción queda bajo el pliegue y tocar la opción no da ninguna respuesta.
  });
}
