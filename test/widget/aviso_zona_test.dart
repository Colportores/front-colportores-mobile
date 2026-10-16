// El aviso de zona de la pantalla principal (HU-CAM-006, #251): «Te asignaron la zona <zona> en
// <campaña>.» y «Ya no tenés zona en <campaña>.» arriba de la pestaña, con «Entendido» para
// cerrarlo. Sin artboard propio (decisión de Cristian: el texto es el de la HU); acá se prueban
// todos sus estados y los casos límite de cada flujo.
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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/logger_mudo.dart';
import '../helpers/mapa_base_falso.dart' show overridesPestanaMapa;

final _ahora = DateTime(2026, 10, 9, 9, 30);
final _sesion = Sesion(
  usuarioId: 'u-1',
  email: 'lucia.silva@correo.com',
  accessToken: 'token-secreto',
  expiraEn: DateTime.utc(2030),
);

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

const _textoCentro = 'Te asignaron la zona Centro en Campaña Primavera 2026.';
const _textoSinZona = 'Ya no tenés zona en Campaña Primavera 2026.';

/// El teléfono: el pull (la fuente) y el almacén seguro donde queda lo ya avisado. Sobreviven a
/// «cerrar y volver a abrir la app» (un [_montar] nuevo con el mismo [_Telefono]).
final class _Telefono {
  final fuente = InscripcionesConZonaEnMemoria();
  final almacen = AlmacenSeguroEnMemoria();

  ZonasAvisadasRepositoryImpl get avisadas =>
      ZonasAvisadasRepositoryImpl(almacen, logger: loggerMudo());

  String? get guardado => almacen.contenido[ClaveSegura.zonasAvisadas];
}

Future<void> _montar(WidgetTester tester, _Telefono telefono, {double escala = 1}) async {
  // Un ProviderScope nuevo en cada montaje: la app «se abre de nuevo».
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
      ],
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(escala), alwaysUse24HourFormat: true),
          child: child!,
        ),
        home: InicioPage(sesion: _sesion),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _pantalla(WidgetTester tester, Size tamanio) {
  tester.view.physicalSize = tamanio;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

final _avisos = find.byKey(const Key('avisos_zona'));
Finder _cerrar([String inscripcion = 'insc-1']) =>
    find.byKey(Key('aviso_zona_cerrar_$inscripcion'));

/// Lleva «Entendido» al área visible de la franja (si el aviso es más alto que el 40 % reservado se
/// desplaza), lo toca y espera a que termine la animación.
Future<void> _tocarCerrar(WidgetTester tester, [String inscripcion = 'insc-1']) async {
  await tester.ensureVisible(_cerrar(inscripcion));
  await tester.pump();
  await tester.tap(_cerrar(inscripcion));
  await tester.pumpAndSettle();
}

void main() {
  late _Telefono telefono;

  setUp(() => telefono = _Telefono());

  group('estados del aviso', () {
    testWidgets('dado que no hay inscripciones, la pantalla principal no muestra ningún aviso', (
      tester,
    ) async {
      await _montar(tester, telefono);

      expect(_avisos, findsNothing);
      expect(find.text('Entendido'), findsNothing);
    });

    testWidgets('dado que le asignaron una zona, al abrir la app dice «Te asignaron la zona <zona> '
        'en <campaña>.»', (tester) async {
      telefono.fuente.publicar([_centro]);

      await _montar(tester, telefono);

      expect(find.text(_textoCentro), findsOneWidget);
      expect(find.text('Entendido'), findsOneWidget);
    });

    testWidgets('dado que le quitaron la zona y sigue inscripto, dice «Ya no tenés zona en '
        '<campaña>.»', (tester) async {
      await telefono.avisadas.anotar({'insc-1': 'z-centro'});
      telefono.fuente.publicar([_inscripcion()]);

      await _montar(tester, telefono);

      expect(find.text(_textoSinZona), findsOneWidget);
    });

    testWidgets('dado que lo sacaron de la campaña (inscripción con baja), no hay aviso de zona', (
      tester,
    ) async {
      await telefono.avisadas.anotar({'insc-1': 'z-centro'});
      telefono.fuente.publicar([_inscripcion(dadaDeBaja: true)]);

      await _montar(tester, telefono);

      expect(_avisos, findsNothing);
      expect(find.textContaining('zona'), findsNothing);
    });

    testWidgets('dado que la app está abierta, cuando termina un pull con una zona nueva, el aviso '
        'aparece sin que la persona haga nada', (tester) async {
      await _montar(tester, telefono);
      expect(_avisos, findsNothing);

      telefono.fuente.publicar([_centro]);
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsOneWidget);
    });

    testWidgets('dado un aviso sin cerrar, cuando otro pull cambia la zona, el aviso se reemplaza '
        'por el último', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      telefono.fuente.publicar([_inscripcion(zonaId: 'z-norte', zonaNombre: 'Norte')]);
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsNothing);
      expect(find.text('Te asignaron la zona Norte en Campaña Primavera 2026.'), findsOneWidget);
    });

    testWidgets('dado que está en dos campañas, hay un aviso por campaña, cada uno con su botón', (
      tester,
    ) async {
      telefono.fuente.publicar([
        _centro,
        _inscripcion(id: 'insc-2', campania: 'Campaña Verano', zonaId: 'z-sur', zonaNombre: 'Sur'),
      ]);

      await _montar(tester, telefono);

      expect(find.text(_textoCentro), findsOneWidget);
      expect(find.text('Te asignaron la zona Sur en Campaña Verano.'), findsOneWidget);
      expect(find.text('Entendido'), findsNWidgets(2));
    });

    testWidgets('dado que el nombre de la zona todavía no llegó, no hay aviso hasta que llegue', (
      tester,
    ) async {
      telefono.fuente.publicar([_inscripcion(zonaId: 'z-centro')]);
      await _montar(tester, telefono);
      expect(_avisos, findsNothing);

      telefono.fuente.publicar([_centro]);
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsOneWidget);
    });

    testWidgets('dado un aviso, la pantalla principal sigue ahí: pestañas, engranaje y contenido', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);

      await _montar(tester, telefono);

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(find.byKey(const Key('inicio_barra')), findsOneWidget);
      expect(find.byKey(const Key('inicio_configuracion')), findsOneWidget);
    });
  });

  group('cerrar el aviso', () {
    testWidgets('dado un aviso, cuando toca «Entendido», desaparece y la zona queda como avisada', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await tester.tap(_cerrar());
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsNothing);
      expect(_avisos, findsNothing);
      expect(telefono.guardado, '{"insc-1":"z-centro"}');
    });

    testWidgets('dado un aviso cerrado, cuando la app se abre de nuevo, no vuelve a salir', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);
      await tester.tap(_cerrar());
      await tester.pumpAndSettle();

      await _montar(tester, telefono);

      expect(_avisos, findsNothing);
    });

    testWidgets('dado un aviso sin cerrar, cuando la app se abre de nuevo, vuelve a salir', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await _montar(tester, telefono);

      expect(find.text(_textoCentro), findsOneWidget);
    });

    testWidgets('dado un aviso cerrado, cuando el coordinador cambia la zona otra vez, el aviso '
        'nuevo sale', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);
      await tester.tap(_cerrar());
      await tester.pumpAndSettle();

      telefono.fuente.publicar([_inscripcion(zonaId: 'z-norte', zonaNombre: 'Norte')]);
      await tester.pumpAndSettle();

      expect(find.text('Te asignaron la zona Norte en Campaña Primavera 2026.'), findsOneWidget);
    });

    testWidgets('dado el doble toque en «Entendido», se cierra una vez y no pasa nada raro', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await tester.tap(_cerrar());
      await tester.tap(_cerrar(), warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(_avisos, findsNothing);
      expect(tester.takeException(), isNull);
      expect(telefono.guardado, '{"insc-1":"z-centro"}');
    });

    testWidgets('dado que cierra uno de dos avisos, el otro se queda', (tester) async {
      telefono.fuente.publicar([
        _centro,
        _inscripcion(id: 'insc-2', campania: 'Campaña Verano', zonaId: 'z-sur', zonaNombre: 'Sur'),
      ]);
      await _montar(tester, telefono);

      await tester.tap(_cerrar('insc-1'));
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsNothing);
      expect(find.text('Te asignaron la zona Sur en Campaña Verano.'), findsOneWidget);
    });

    testWidgets('dado que el almacén seguro falla al anotar, el aviso igual se cierra y no se '
        'traba nada', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);
      telefono.almacen.simularFalla = true;

      await tester.tap(_cerrar());
      await tester.pumpAndSettle();

      expect(_avisos, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('volver atrás y reentrar', () {
    testWidgets('dado un aviso, cuando cambia de pestaña y vuelve, el aviso sigue visible', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await tester.tap(find.byKey(const Key('inicio_pestana_agenda')));
      await tester.pumpAndSettle();
      expect(find.text(_textoCentro), findsOneWidget);
      await tester.tap(find.byKey(const Key('inicio_pestana_hoy')));
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsOneWidget);
    });

    testWidgets('dado un aviso, cuando abre Configuración y vuelve, el aviso sigue ahí', (
      tester,
    ) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      await tester.tap(find.byKey(const Key('inicio_configuracion')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(_textoCentro), findsOneWidget);
    });
  });

  group('datos límite y texto grande', () {
    const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

    for (final MapEntry(key: nombre, value: tam) in tamanios.entries) {
      for (final escala in [1.0, 2.0]) {
        testWidgets('un aviso con nombres larguísimos en $nombre, texto $escala: sin overflow y el '
            'botón se puede tocar', (tester) async {
          _pantalla(tester, tam);
          final largo = 'Zona ${'muy larga ' * 12}';
          telefono.fuente.publicar([
            _inscripcion(campania: 'Campaña ${'extensa ' * 12}', zonaId: 'z', zonaNombre: largo),
          ]);

          await _montar(tester, telefono, escala: escala);

          expect(find.textContaining('Te asignaron la zona Zona muy larga'), findsOneWidget);
          expect(tester.takeException(), isNull);
          // Con 12 repeticiones el aviso es más alto que el 40 % reservado: «Entendido» queda a un
          // desplazamiento, siempre al alcance.
          await _tocarCerrar(tester);
          expect(_avisos, findsNothing);
        });

        testWidgets('20 avisos a la vez en $nombre, texto $escala: no tapan toda la pantalla, se '
            'desplazan y los de abajo se pueden cerrar', (tester) async {
          _pantalla(tester, tam);
          telefono.fuente.publicar([
            for (var i = 0; i < 20; i++)
              _inscripcion(
                id: 'insc-$i',
                campania: 'Campaña $i',
                zonaId: 'z-$i',
                zonaNombre: 'Zona $i',
              ),
          ]);

          await _montar(tester, telefono, escala: escala);

          expect(tester.takeException(), isNull);
          expect(tester.getSize(_avisos).height, lessThanOrEqualTo(tam.height * 0.4 + 0.01));
          expect(find.byKey(const Key('inicio_barra')), findsOneWidget);
          // Los de abajo se arman al desplazar la franja (lista perezosa).
          await tester.scrollUntilVisible(
            _cerrar('insc-19'),
            120,
            maxScrolls: 400,
            scrollable: find.descendant(of: _avisos, matching: find.byType(Scrollable)),
          );
          await _tocarCerrar(tester, 'insc-19');
          expect(find.text('Te asignaron la zona Zona 19 en Campaña 19.'), findsNothing);
        });
      }
    }
  });

  group('texto al 200 % con datos comunes', () {
    testWidgets('dado un aviso común en 412x915 con texto 2.0, «Entendido» se ve y se toca sin '
        'desplazar nada', (tester) async {
      _pantalla(tester, const Size(412, 915));
      telefono.fuente.publicar([_centro]);

      await _montar(tester, telefono, escala: 2);

      expect(tester.takeException(), isNull);
      expect(_cerrar().hitTestable(), findsOneWidget);
      await tester.tap(_cerrar());
      await tester.pumpAndSettle();
      expect(_avisos, findsNothing);
    });

    testWidgets('dado un aviso común en 360x640 con texto 2.0, el aviso se desplaza dentro de su '
        'franja y «Entendido» queda al alcance sin tapar la barra de abajo', (tester) async {
      _pantalla(tester, const Size(360, 640));
      telefono.fuente.publicar([_centro]);

      await _montar(tester, telefono, escala: 2);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_avisos).height, lessThanOrEqualTo(640 * 0.4 + 0.01));
      expect(find.byKey(const Key('inicio_barra')), findsOneWidget);
      await _tocarCerrar(tester);
      expect(_avisos, findsNothing);
    });
  });

  group('accesibilidad', () {
    testWidgets('el aviso se anuncia al aparecer (región viva) y su botón cumple los tamaños de '
        'toque y el contraste', (tester) async {
      final semantica = tester.ensureSemantics();
      _pantalla(tester, const Size(360, 640));
      telefono.fuente.publicar([_centro]);

      await _montar(tester, telefono);

      final nodo = tester.getSemantics(find.text(_textoCentro));
      expect(nodo.label, contains(_textoCentro));
      expect(
        find.ancestor(
          of: find.text(_textoCentro),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      semantica.dispose();
    });

    testWidgets('el botón «Entendido» mide al menos 48 dp de alto', (tester) async {
      telefono.fuente.publicar([_centro]);
      await _montar(tester, telefono);

      expect(tester.getSize(_cerrar()).height, greaterThanOrEqualTo(48));
    });
  });

  group('sin fuente de datos (producción hasta que llegue el pull, #274)', () {
    testWidgets('dado el aviso de zona sin fuente, la pantalla principal funciona igual y sin '
        'avisos', (tester) async {
      final sinFuente = InscripcionesConZonaEnMemoria()..falla = StateError('sin fuente');
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            jornadaLocalDataSourceProvider.overrideWithValue(JornadaLocalDataSourceEnMemoria()),
            disparadorBackupProvider.overrideWithValue(_BackupFalso()),
            relojJornadaProvider.overrideWithValue(() => _ahora),
            inscripcionesConZonaDataSourceProvider.overrideWithValue(sinFuente),
            ...overridesPestanaMapa(),
          ],
          child: MaterialApp(
            theme: temaClaro(),
            home: InicioPage(sesion: _sesion),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('inicio_principal')), findsOneWidget);
      expect(_avisos, findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
