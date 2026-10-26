// HU-UBI-001 · vista 39 (#451): N·02 «¿Qué hay acá?». El tipo (con la casa elegida), el número del mapa
// corregible, «Seguir» que registra con las reglas de las vistas 03 y 04 y «Volver». Con el estado real
// del alta (`AltaUbicacionNotifier`) y fakes del repositorio, la dirección, la ciudad y el GPS.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/salida_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_que_hay_aca.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/pin_nueva_casa.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';

const _parametros = ParametrosAlta(colportorId: 'col-1', puntoInicial: puntoItalia, apertura: 1);
const _grecia = DireccionDelPunto(calle: 'Grecia', numero: '3307');

/// Lo que dejó montado [_abrir].
final class _Montada {
  _Montada({required this.repo, required this.geo, required this.ciudades});

  final RepoAltaFalso repo;
  final GeocodificadorFalso geo;
  final CiudadesFalsas ciudades;

  /// Cómo terminó cada vez que se abrió la hoja (`null`: volvió sin registrar).
  final salidas = <SalidaAltaUbicacion?>[];
}

/// Monta una pantalla con un botón «abrir» que muestra N·02 sobre el alta de [_parametros], con el
/// estado vivo (como lo mantiene el mapa), y la abre.
Future<_Montada> _abrir(
  WidgetTester tester, {
  RepoAltaFalso? repo,
  GeocodificadorFalso? geocodificador,
  CiudadesFalsas? ciudades,
  Size tamano = const Size(390, 844),
  double escala = 1,
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final montada = _Montada(
    repo: repo ?? RepoAltaFalso(),
    geo: geocodificador ?? GeocodificadorFalso((_) => _grecia),
    ciudades: ciudades ?? CiudadesFalsas(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        geocodificador: montada.geo,
        ciudades: montada.ciudades,
        repo: montada.repo,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: Consumer(
          builder: (context, ref, _) {
            // Como el mapa: mantiene vivo el estado del alta mientras la hoja se abre y se cierra.
            ref.watch(altaUbicacionProvider(_parametros));
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    montada.salidas.add(
                      await mostrarHojaQueHayAca(context, parametros: _parametros),
                    );
                  },
                  child: const Text('abrir'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  if (abrir) await _abrirLaHoja(tester);
  return montada;
}

Future<void> _abrirLaHoja(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

/// Avanza un rato (sin `pumpAndSettle`: «Registrando…» tiene un indicador que no termina).
Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

final _hoja = find.byKey(ClavesPinNuevaCasa.queHayAca);
final _seguir = find.byKey(ClavesPinNuevaCasa.seguir);
final _volver = find.byKey(ClavesPinNuevaCasa.volver);
final _numero = find.byKey(ClavesPinNuevaCasa.campoNumero);
final _calle = find.byKey(ClavesPinNuevaCasa.campoCalle);
final _falla = find.byKey(ClavesPinNuevaCasa.falla);

Finder _tipo(String nombre) => find.byKey(ClavesPinNuevaCasa.tipo(nombre));

bool _seguirHabilitado(WidgetTester tester) =>
    tester.widget<FilledButton>(_seguir).onPressed != null;

/// Lo que vale el campo de texto [campo].
String _texto(WidgetTester tester, Finder campo) =>
    tester.widget<TextField>(campo).controller!.text;

void main() {
  group('N·02 · lo que se ve', () {
    testWidgets(
      '«¿Qué hay acá?» con la dirección, los tres tipos, el número del mapa y los botones',
      (tester) async {
        await _abrir(tester);

        expect(find.text('¿Qué hay acá?'), findsOneWidget);
        expect(find.text('Grecia 3307'), findsOneWidget);
        for (final (nombre, ayuda) in [
          ('Casa', 'Una o varias personas'),
          ('Edificio', 'Varios deptos'),
          ('Negocio', 'Un comercio'),
        ]) {
          expect(find.text(nombre), findsOneWidget);
          expect(find.text(ayuda), findsOneWidget);
        }
        expect(_texto(tester, _numero), '3307');
        expect(find.text('NÚMERO'), findsOneWidget);
        expect(find.text('Sacado del mapa. Corregilo si no coincide.'), findsOneWidget);
        expect(find.text('Seguir'), findsOneWidget);
        expect(find.text('Volver'), findsOneWidget);
        // La calle ya la tiene el mapa: no se pide.
        expect(_calle, findsNothing);
        // Entran sin desplazar en un teléfono normal.
        expect(tester.getRect(_seguir).bottom, lessThanOrEqualTo(844));
      },
    );

    testWidgets('la casa viene elegida, y el tipo se lee por el lector de pantalla', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      await _abrir(tester);

      expect(
        tester.getSemantics(_tipo('casa')),
        matchesSemantics(
          label: 'Casa. Una o varias personas',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      expect(
        tester.getSemantics(_tipo('edificio')),
        matchesSemantics(
          label: 'Edificio. Varios deptos',
          isButton: true,
          hasSelectedState: true,
          isInMutuallyExclusiveGroup: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      semantica.dispose();
    });

    testWidgets('cargando: sin la dirección todavía no la afirma, y avisa que busca el número', (
      tester,
    ) async {
      final geo = GeocodificadorFalso((_) => _grecia)..bloqueo = Completer<void>();
      await _abrir(tester, geocodificador: geo);

      expect(find.text('Buscando el número en el mapa…'), findsOneWidget);
      expect(find.text('Grecia 3307'), findsNothing);
      expect(_calle, findsNothing, reason: 'buscando no es que el mapa no la tenga');

      geo.bloqueo!.complete();
      await _asentar(tester);

      expect(find.text('Grecia 3307'), findsOneWidget);
      expect(_texto(tester, _numero), '3307');
      expect(find.text('Buscando el número en el mapa…'), findsNothing);
    });

    testWidgets(
      'si el mapa no conoce la dirección, pide la calle y dice que el número puede ir después',
      (tester) async {
        await _abrir(tester, geocodificador: GeocodificadorFalso());

        expect(_calle, findsOneWidget);
        expect(
          find.text('El mapa no tiene la calle de este lugar. Escribila si querés.'),
          findsOneWidget,
        );
        expect(
          find.text('El mapa no tiene el número de este lugar. Podés ponerlo ahora o después.'),
          findsOneWidget,
        );
        expect(find.text('Grecia 3307'), findsNothing);
        // Se puede seguir igual: calle y número son opcionales (R-UB02).
        expect(_seguirHabilitado(tester), isTrue);
      },
    );
  });

  group('N·02 · «Seguir» registra', () {
    testWidgets('una casa con la calle y el número del mapa, y su espacio default', (tester) async {
      final m = await _abrir(tester);

      await tester.tap(_seguir);
      await _asentar(tester);

      final llamada = m.repo.llamadas.single;
      expect(llamada.ubicacion.tipo, TipoUbicacion.casa);
      expect(llamada.ubicacion.calle, 'Grecia');
      expect(llamada.ubicacion.numero, '3307');
      expect(llamada.ubicacion.ciudadId, 'ciu-mvd');
      expect(llamada.espacio, isNotNull, reason: 'una casa nace con su espacio (S13)');
      expect(m.salidas.single, isA<UbicacionCreada>());
      expect((m.salidas.single! as UbicacionCreada).ubicacion.id, llamada.ubicacion.id);
      expect(_hoja, findsNothing);
    });

    for (final (nombre, tipo, conEspacio) in [
      ('edificio', TipoUbicacion.edificio, false),
      ('negocio', TipoUbicacion.negocio, false),
    ]) {
      testWidgets('un $nombre si se lo elige', (tester) async {
        final m = await _abrir(tester);

        await tester.tap(_tipo(nombre));
        await _asentar(tester);
        await tester.tap(_seguir);
        await _asentar(tester);

        final llamada = m.repo.llamadas.single;
        expect(llamada.ubicacion.tipo, tipo);
        expect(llamada.espacio != null, conEspacio);
        expect(m.salidas.single, isA<UbicacionCreada>());
      });
    }

    testWidgets('el número corregido, y la ayuda de «Sacado del mapa» se va', (tester) async {
      final m = await _abrir(tester);

      await tester.enterText(_numero, '3309');
      await _asentar(tester);

      expect(find.text('Sacado del mapa. Corregilo si no coincide.'), findsNothing);
      expect(find.text('Grecia 3309'), findsOneWidget);
      await tester.tap(_seguir);
      await _asentar(tester);

      expect(m.repo.llamadas.single.ubicacion.numero, '3309');
    });

    testWidgets('sin número se registra igual (es opcional)', (tester) async {
      final m = await _abrir(tester);

      await tester.enterText(_numero, '');
      await _asentar(tester);
      await tester.tap(_seguir);
      await _asentar(tester);

      expect(m.repo.llamadas.single.ubicacion.numero, isNull);
      expect(m.salidas.single, isA<UbicacionCreada>());
    });

    testWidgets('con la calle escrita a mano cuando el mapa no la tiene', (tester) async {
      final m = await _abrir(tester, geocodificador: GeocodificadorFalso());

      await tester.enterText(_calle, 'Rivera');
      await tester.enterText(_numero, '55');
      await _asentar(tester);
      expect(find.text('Rivera 55'), findsOneWidget);
      expect(_calle, findsOneWidget, reason: 'el campo no desaparece al escribir');
      await tester.tap(_seguir);
      await _asentar(tester);

      final ubicacion = m.repo.llamadas.single.ubicacion;
      expect(ubicacion.calle, 'Rivera');
      expect(ubicacion.numero, '55');
    });

    testWidgets(
      'mientras registra: «Registrando…», todo apagado, el atrás no sale; al terminar, sale',
      (tester) async {
        final repo = RepoAltaFalso()..bloqueo = Completer<void>();
        final m = await _abrir(tester, repo: repo);

        await tester.tap(_seguir);
        await _asentar(tester);

        expect(find.text('Registrando…'), findsOneWidget);
        expect(find.byKey(ClavesPinNuevaCasa.registrando), findsOneWidget);
        expect(_seguirHabilitado(tester), isFalse);
        expect(tester.widget<OutlinedButton>(_volver).onPressed, isNull);
        // Ni el atrás ni tocar afuera cierran lo que se está guardando.
        await tester.binding.handlePopRoute();
        await _asentar(tester);
        expect(_hoja, findsOneWidget);
        expect(tester.widget<TextField>(_numero).readOnly, isTrue);

        repo.bloqueo!.complete();
        await _asentar(tester);

        expect(_hoja, findsNothing);
        expect(m.salidas.single, isA<UbicacionCreada>());
        expect(repo.llamadas, hasLength(1));
      },
    );

    testWidgets('doble toque en «Seguir»: se registra una sola vez', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      await _abrir(tester, repo: repo);

      await tester.tap(_seguir);
      await tester.tap(_seguir, warnIfMissed: false);
      await _asentar(tester);
      repo.bloqueo!.complete();
      await _asentar(tester);

      expect(repo.llamadas, hasLength(1));
    });
  });

  group('N·02 · falla a mitad de la acción', () {
    for (final (nombre, comportamiento)
        in <(String, Future<Either<Failure, ResultadoAltaUbicacion>> Function(Ubicacion))>[
          ('devuelve una falla', (_) async => const Left(FailureInesperado())),
          ('lanza', (_) async => throw StateError('se cerró la base')),
        ]) {
      testWidgets('si el repositorio $nombre: el aviso dice qué hacer, nada queda trabado y el '
          'reintento guarda con el mismo id', (tester) async {
        final repo = RepoAltaFalso()..comportamiento = comportamiento;
        final m = await _abrir(tester, repo: repo);

        await tester.tap(_seguir);
        await _asentar(tester);

        expect(_falla, findsOneWidget);
        expect(
          find.text('No pudimos guardar la ubicación. Lo que cargaste sigue acá: probá de nuevo.'),
          findsOneWidget,
        );
        expect(find.text('Seguir'), findsOneWidget);
        expect(_seguirHabilitado(tester), isTrue);
        expect(tester.widget<OutlinedButton>(_volver).onPressed, isNotNull);
        expect(tester.widget<TextField>(_numero).readOnly, isFalse);
        expect(m.salidas, isEmpty);

        repo.comportamiento = null;
        await tester.tap(_seguir);
        await _asentar(tester);

        expect(repo.llamadas, hasLength(2));
        expect(repo.llamadas.last.ubicacion.id, repo.llamadas.first.ubicacion.id);
        expect(m.salidas.single, isA<UbicacionCreada>());
      });
    }

    testWidgets('cambiar algo después de la falla quita el aviso', (tester) async {
      final repo = RepoAltaFalso()..comportamiento = (_) async => const Left(FailureInesperado());
      await _abrir(tester, repo: repo);
      await tester.tap(_seguir);
      await _asentar(tester);
      expect(_falla, findsOneWidget);

      await tester.tap(_tipo('negocio'));
      await _asentar(tester);

      expect(_falla, findsNothing);
    });
  });

  group('N·02 · posible duplicado (vista 04)', () {
    RepoAltaFalso conDuplicado() =>
        RepoAltaFalso()
          ..comportamiento = (_) async =>
              Right(AltaConDuplicados(candidatas: [candidata('existente', metros: 3)]));

    testWidgets('«Reutilizar esta» sale con la ubicación que ya existía y no crea la nueva', (
      tester,
    ) async {
      final repo = conDuplicado();
      final m = await _abrir(tester, repo: repo);

      await tester.tap(_seguir);
      await _asentar(tester);
      expect(find.text('Reutilizar esta'), findsOneWidget);
      expect(
        _seguirHabilitado(tester),
        isTrue,
        reason: 'el botón no queda trabado detrás del aviso',
      );

      await tester.tap(find.text('Reutilizar esta'));
      await _asentar(tester);

      expect(m.salidas.single, isA<UbicacionReutilizada>());
      expect((m.salidas.single! as UbicacionReutilizada).ubicacionId, 'existente');
      expect(_hoja, findsNothing);
    });

    testWidgets('cerrar el aviso sin elegir deja N·02 como estaba, con todo lo escrito', (
      tester,
    ) async {
      final repo = conDuplicado();
      final m = await _abrir(tester, repo: repo);
      await tester.enterText(_numero, '3311');
      await _asentar(tester);

      await tester.tap(_seguir);
      await _asentar(tester);
      await tester.tap(find.text('Cancelar'));
      await _asentar(tester);

      expect(_hoja, findsOneWidget);
      expect(_texto(tester, _numero), '3311');
      expect(m.salidas, isEmpty);
      expect(_seguirHabilitado(tester), isTrue);
    });
  });

  group('N·02 · la ciudad', () {
    testWidgets('la propone la app y no se muestra mientras no haga falta', (tester) async {
      await _abrir(tester);

      expect(find.text('CIUDAD · OBLIGATORIA'), findsNothing);
      expect(_seguirHabilitado(tester), isTrue);
    });

    testWidgets('mientras la busca, «Seguir» espera y lo dice', (tester) async {
      final ciudades = CiudadesFalsas()..bloqueoPropuesta = Completer<void>();
      await _abrir(tester, ciudades: ciudades);

      expect(find.text('Buscando la ciudad…'), findsOneWidget);
      expect(_seguirHabilitado(tester), isFalse);

      ciudades.bloqueoPropuesta!.complete();
      await _asentar(tester);

      expect(find.text('Buscando la ciudad…'), findsNothing);
      expect(_seguirHabilitado(tester), isTrue);
    });

    testWidgets(
      'si no puede proponerla (varias ciudades y ninguna zona), se elige y se registra con esa',
      (tester) async {
        final ciudades = CiudadesFalsas(propone: (_) => const FaltaElPunto());
        final m = await _abrir(tester, ciudades: ciudades);

        expect(find.text('CIUDAD · OBLIGATORIA'), findsOneWidget);
        expect(find.text('Sin ciudad'), findsOneWidget);
        expect(find.text('Elegí la ciudad para registrar.'), findsOneWidget);
        expect(_seguirHabilitado(tester), isFalse);

        await tester.tap(find.text('Sin ciudad'));
        await _asentar(tester);
        await tester.tap(find.text('Canelones'));
        await _asentar(tester);

        expect(_seguirHabilitado(tester), isTrue);
        await tester.tap(_seguir);
        await _asentar(tester);

        expect(m.repo.llamadas.single.ubicacion.ciudadId, 'ciu-can');
      },
    );

    testWidgets('campaña sin ciudades: el aviso dice qué hacer y «Reintentar» vuelve a pedirla', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas(propone: (_) => const CampaniaSinCiudades());
      await _abrir(tester, ciudades: ciudades);

      expect(
        find.text('Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.'),
        findsOneWidget,
      );
      expect(_seguirHabilitado(tester), isFalse);

      ciudades.propone = CiudadesFalsas().propone;
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(
        find.text('Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.'),
        findsNothing,
      );
      expect(_seguirHabilitado(tester), isTrue);
    });

    testWidgets('no se pudo leer la campaña: lo dice y deja reintentar', (tester) async {
      final ciudades = CiudadesFalsas()..fallaPropuesta = const FailureInesperado();
      await _abrir(tester, ciudades: ciudades);

      expect(
        find.text('No pudimos leer las ciudades de tu campaña. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(_seguirHabilitado(tester), isFalse);

      ciudades.fallaPropuesta = null;
      await tester.tap(find.text('Reintentar'));
      await _asentar(tester);

      expect(_seguirHabilitado(tester), isTrue);
    });
  });

  group('N·02 · volver y reentrar', () {
    testWidgets('«Volver» cierra sin registrar y al reentrar sigue lo escrito', (tester) async {
      final m = await _abrir(tester);
      await tester.tap(_tipo('negocio'));
      await tester.enterText(_numero, '3315');
      await _asentar(tester);

      await tester.tap(_volver);
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(m.salidas, [null]);
      expect(m.repo.llamadas, isEmpty);

      await _abrirLaHoja(tester);

      expect(_texto(tester, _numero), '3315');
      await tester.tap(_seguir);
      await _asentar(tester);
      final ubicacion = m.repo.llamadas.single.ubicacion;
      expect(ubicacion.tipo, TipoUbicacion.negocio);
      expect(ubicacion.numero, '3315');
    });

    testWidgets('el atrás del sistema es «Volver»', (tester) async {
      final m = await _abrir(tester);

      await tester.binding.handlePopRoute();
      await _asentar(tester);

      expect(_hoja, findsNothing);
      expect(m.salidas, [null]);
    });

    testWidgets('«Volver» y «Seguir» seguidos no cierran dos veces', (tester) async {
      final m = await _abrir(tester);

      await tester.tap(_volver);
      await tester.tap(_seguir, warnIfMissed: false);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(m.salidas, hasLength(1));
    });
  });

  group('N·02 · datos límite y texto grande', () {
    for (final (tamano, escala) in [
      (const Size(360, 640), 2.0),
      (const Size(320, 568), 2.0),
      (const Size(320, 568), 3.0),
    ]) {
      testWidgets('${tamano.width.toInt()}×${tamano.height.toInt()} · texto $escala: no desborda y '
          '«Seguir» se alcanza desplazando', (tester) async {
        final m = await _abrir(
          tester,
          tamano: tamano,
          escala: escala,
          geocodificador: GeocodificadorFalso(
            (_) => const DireccionDelPunto(
              calle: 'Avenida de los Treinta y Tres Orientales y Doctor Luis Alberto de Herrera',
              numero: '12345678901234567890',
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.ensureVisible(_seguir);
        await _asentar(tester, 3);
        final seguir = tester.getRect(_seguir);
        expect(seguir.bottom, lessThanOrEqualTo(tamano.height + .5));
        expect(seguir.height, greaterThanOrEqualTo(56));
        await tester.tap(_seguir);
        await _asentar(tester);
        expect(m.repo.llamadas, hasLength(1));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('el número no pasa de 20 caracteres', (tester) async {
      await _abrir(tester);

      await tester.enterText(_numero, '1' * 40);
      await _asentar(tester);

      expect(_texto(tester, _numero).length, 20);
    });

    testWidgets('con el teclado abierto el campo y los botones siguen a la vista', (tester) async {
      await _abrir(tester, tamano: const Size(360, 640));
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      addTearDown(tester.view.resetViewInsets);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      await tester.ensureVisible(_numero);
      await _asentar(tester, 3);
      expect(tester.getRect(_numero).bottom, lessThanOrEqualTo(640 - 280 + .5));
    });
  });
}
