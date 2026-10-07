// QA de la vista 07 «Modificar ubicación» (HU-UBI-004, #202), ronda 1. Complementa a
// `modificar_ubicacion_page_test.dart` con lo que el implementador no probó: que la escritura no pise
// la ubicación ni su historial, las fallas a mitad con confirmaciones, el doble toque en los
// diálogos, el teclado abierto en 360×640, las guías de accesibilidad de los estados que faltaban
// (cargando, no existe, error, guardando, aviso de falla) y los textos pegados con emoji.
//
// Los tests que documentan un hallazgo van con `skip: true` y, arriba, el comentario
// `// skip: QA #202 — <hallazgo>` (en `testWidgets` el `skip` es un bool).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_modificacion_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/modificar_ubicacion_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/hoja_modificar.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart' show Left, Right;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/mapa_base_falso.dart';
import '../../helpers/modificar_ubicacion_falsos.dart';

const _norte18m = 0.00016;

Coordenadas _alNorte(double grados) =>
    Coordenadas(lat: puntoItalia.lat + grados, lon: puntoItalia.lon);

class _Anfitrion extends StatelessWidget {
  const _Anfitrion({required this.salidas});

  final List<SalidaModificarUbicacion?> salidas;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          onPressed: () async => salidas.add(
            await ModificarUbicacionPage.abrir(
              context,
              colportorId: 'col-1',
              ubicacionId: 'ubi-1',
              alDarDeBaja: () {},
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
  }
}

final class _Escenario {
  _Escenario({required this.repo, required this.mapa});

  final RepoEdicionFalso repo;
  final FabricaMapaFalsa mapa;
  final salidas = <SalidaModificarUbicacion?>[];
}

Future<void> _asentar(WidgetTester tester, [int veces = 10]) async {
  for (var i = 0; i < veces; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

Future<_Escenario> _montar(
  WidgetTester tester, {
  RepoEdicionFalso? repo,
  int espacios = 2,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool abrir = true,
}) async {
  tester.view.physicalSize = tamano;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final e = _Escenario(
    repo: repo ?? RepoEdicionFalso(ubicacionGuardada(), espacios: espacios),
    mapa: FabricaMapaFalsa(),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overridesAlta(
        gps: GpsFalso(),
        geocodificador: GeocodificadorFalso(
          (_) => const DireccionDelPunto(calle: 'Av. Italia', numero: '1250'),
        ),
        ciudades: CiudadesFalsas(),
        repo: e.repo,
        ahora: DateTime.utc(2026, 10, 2, 12),
        mapa: e.mapa,
      ),
      child: MaterialApp(
        theme: temaClaro(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: _Anfitrion(salidas: e.salidas),
      ),
    ),
  );
  if (abrir) await _abrir(tester);
  return e;
}

Future<void> _abrir(WidgetTester tester) async {
  await tester.tap(find.text('abrir'));
  await _asentar(tester);
}

Future<void> _traer(WidgetTester tester, Finder f) async {
  await tester.pump();
  if (f.hitTestable().evaluate().isEmpty) {
    await Scrollable.ensureVisible(tester.element(f), alignment: .5);
    await tester.pump();
  }
}

Future<void> _tocar(WidgetTester tester, Finder f) async {
  await _traer(tester, f);
  await tester.tap(f);
  await _asentar(tester);
}

Finder get _guardar => find.widgetWithText(FilledButton, TextosModificar.guardarCambios);
Finder get _campoCalle => find.byType(TextField).at(0);
Finder get _campoNumero => find.byType(TextField).at(1);
Finder get _cerrar => find.byTooltip('Cerrar');

bool _habilitado(WidgetTester tester, Finder boton) =>
    tester.widget<FilledButton>(boton).onPressed != null;

Future<void> _escribirNumero(WidgetTester tester, String texto) async {
  await _traer(tester, _campoNumero);
  await tester.enterText(_campoNumero, texto);
  await tester.pump();
}

/// Una cadena sin sustitutos sueltos: lo que se guarda tiene que poder codificarse en UTF-8.
bool _utf16Valido(String s) {
  final u = s.codeUnits;
  for (var i = 0; i < u.length; i++) {
    final c = u[i];
    if (c >= 0xD800 && c <= 0xDBFF) {
      if (i + 1 >= u.length || u[i + 1] < 0xDC00 || u[i + 1] > 0xDFFF) return false;
      i++;
    } else if (c >= 0xDC00 && c <= 0xDFFF) {
      return false;
    }
  }
  return true;
}

/// Dispara «Guardar cambios» sin desplazar la hoja (un `ensureVisible` recorta nodos y rompe las guías).
Future<void> _guardarSinDesplazar(WidgetTester tester) async {
  tester.widget<FilledButton>(_guardar).onPressed!();
  await _asentar(tester);
}

Future<void> _guias(WidgetTester tester, {bool contraste = true}) async {
  expect(tester.takeException(), isNull);
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
  if (contraste) await expectLater(tester, meetsGuideline(textContrastGuideline));
}

void main() {
  group('QA #202 · la escritura no pisa la ubicación ni su historial', () {
    testWidgets(
      'editar el número cambia solo el número: id, alta, autor, zona, ciudad y punto quedan',
      (tester) async {
        final original = ubicacionGuardada(zonaId: 'zona-7');
        final e = await _montar(tester, repo: RepoEdicionFalso(original));
        await _escribirNumero(tester, '1238');

        await _tocar(tester, _guardar);

        final escritura = e.repo.escrituras.single;
        final nueva = escritura.nueva;
        expect(nueva.numero, '1238');
        expect(nueva.id, original.id);
        expect(nueva.tipo, original.tipo);
        expect(nueva.calle, original.calle);
        expect(nueva.ciudadId, original.ciudadId);
        expect(nueva.zonaId, 'zona-7');
        expect(nueva.lat, original.lat);
        expect(nueva.lon, original.lon);
        expect(nueva.auditoria.createdAt, creadaEl12DeAgosto);
        expect(nueva.auditoria.createdBy, 'col-1');
        expect(nueva.auditoria.deletedAt, isNull);
        expect(escritura.baseUpdatedAt, tocadaElUltimoDia, reason: 'la base del CAS es la leída');
      },
    );

    testWidgets(
      'en baja, tras confirmar, si la escritura falla sigue en baja y reintentar vuelve a preguntar',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada(deBajaDesde: DateTime.utc(2026, 9, 1, 12)))
          ..comportamiento = (u, n, _) async => n == 1
              ? const Left(FailureInesperado())
              : Right(UbicacionModificada(ubicacion: u, reactivada: true));
        final e = await _montar(tester, repo: repo);
        await _escribirNumero(tester, '1238');

        await _tocar(tester, _guardar);
        await _tocar(tester, find.text('Confirmar'));

        expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
        expect(repo.actual!.estaBorrada, isTrue, reason: 'no quedó reactivada a medias');
        expect(_habilitado(tester, _guardar), isTrue);
        expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
        expect(e.salidas, isEmpty);

        await _tocar(tester, _guardar);
        expect(
          find.text('Esta ubicación está en baja. ¿Reactivarla al guardar?'),
          findsOneWidget,
          reason: 'la confirmación no se arrastra de un intento fallido',
        );
        await _tocar(tester, find.text('Confirmar'));

        expect(repo.escrituras, hasLength(2));
        expect((e.salidas.single! as UbicacionEditada).reactivada, isTrue);
      },
    );

    testWidgets('cambiar la ciudad y cancelar la pregunta no escribe y deja lo tipeado', (
      tester,
    ) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Cambiar'));
      await _tocar(tester, find.text('Canelones'));
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);

      await _tocar(tester, find.text('Cancelar'));

      expect(e.repo.escrituras, isEmpty);
      expect(e.repo.actual!.ciudadId, 'ciu-mvd');
      expect(find.widgetWithText(TextField, '1238'), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
      expect(_habilitado(tester, _guardar), isTrue);
    });

    testWidgets(
      'de edificio con 3 espacios: volver a «Edificio» quita el aviso y deja guardar otro cambio',
      (tester) async {
        final repo = RepoEdicionFalso(ubicacionGuardada(tipo: TipoUbicacion.edificio), espacios: 3);
        final e = await _montar(tester, repo: repo);
        await _tocar(tester, find.text('Negocio'));
        expect(
          find.text('Esta ubicación tiene 3 espacios. Borralos o reubicalos primero.'),
          findsOneWidget,
        );
        await _escribirNumero(tester, '1238');
        expect(
          _habilitado(tester, _guardar),
          isFalse,
          reason: 'bloqueada aunque tenga otro cambio',
        );

        await _tocar(tester, find.text('Edificio'));

        expect(find.textContaining('Borralos o reubicalos primero.'), findsNothing);
        expect(_habilitado(tester, _guardar), isTrue);
        await _tocar(tester, _guardar);
        expect(e.repo.escrituras.single.nueva.tipo, TipoUbicacion.edificio);
        expect(e.repo.escrituras.single.nueva.numero, '1238');
      },
    );

    testWidgets('la falla de una escritura no queda pegada al volver a abrir', (tester) async {
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => const Left(FailureInesperado());
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);
      expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);

      await _tocar(tester, _cerrar);
      await _tocar(tester, find.text('Descartar'));
      await _abrir(tester);

      expect(find.text(TextosModificar.noPudimosGuardar), findsNothing);
      expect(_habilitado(tester, _guardar), isFalse);
      expect(find.widgetWithText(TextField, '1234'), findsOneWidget);
    });
  });

  group('QA #202 · acciones superpuestas en los diálogos', () {
    testWidgets(
      'doble toque en «Confirmar» del cambio de ciudad: una escritura y no se cierra otra pantalla',
      (tester) async {
        final e = await _montar(tester);
        await _tocar(tester, find.text('Cambiar'));
        await _tocar(tester, find.text('Canelones'));
        await _tocar(tester, _guardar);

        await tester.tap(find.text('Confirmar'));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.tap(find.text('Confirmar'), warnIfMissed: false);
        await _asentar(tester);

        expect(tester.takeException(), isNull);
        expect(e.repo.escrituras, hasLength(1));
        expect(e.salidas, hasLength(1));
        expect(
          find.text('abrir'),
          findsOneWidget,
          reason: 'quedó la pantalla de atrás, una sola vez',
        );
      },
    );

    testWidgets('doble toque en «Descartar»: cierra una sola vez', (tester) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _cerrar);

      await tester.tap(find.text('Descartar'));
      await tester.pump(const Duration(milliseconds: 20));
      await tester.tap(find.text('Descartar'), warnIfMissed: false);
      await _asentar(tester);

      expect(tester.takeException(), isNull);
      expect(e.salidas, hasLength(1));
      expect(find.text('abrir'), findsOneWidget);
    });
  });

  group('QA #202 · teclado abierto y texto grande', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets(
        '360×640 con teclado y texto ${escala}x: el número que se escribe queda a la vista',
        (tester) async {
          await _montar(tester, tamano: const Size(360, 640), escala: escala);
          tester.view.viewInsets = const FakeViewPadding(bottom: 300);
          addTearDown(tester.view.resetViewInsets);
          await _asentar(tester);

          await _traer(tester, _campoNumero);
          await tester.tap(_campoNumero);
          await _asentar(tester);
          await tester.enterText(_campoNumero, '1238');
          await _asentar(tester);

          expect(tester.takeException(), isNull);
          final r = tester.getRect(_campoNumero);
          expect(r.top, greaterThanOrEqualTo(0), reason: 'el campo no se sale por arriba');
          expect(
            r.bottom,
            lessThanOrEqualTo(640 - 300),
            reason: 'el campo no queda tapado por el teclado',
          );
        },
      );

      testWidgets(
        '360×640 con texto ${escala}x: «Guardar cambios» se alcanza desplazando y guarda',
        (tester) async {
          final e = await _montar(tester, tamano: const Size(360, 640), escala: escala);
          await tester.enterText(_campoNumero, '1238');
          await _asentar(tester);

          await _tocar(tester, _guardar);

          expect(tester.takeException(), isNull);
          expect(e.repo.escrituras.single.nueva.numero, '1238');
        },
      );
    }
  });

  group('QA #202 · accesibilidad de los estados que faltaban', () {
    for (final (nombre, tamano, escala) in <(String, Size, double)>[
      ('360×640', const Size(360, 640), 1.0),
      ('412×915', const Size(412, 915), 1.0),
      ('360×640 a 200 %', const Size(360, 640), 2.0),
    ]) {
      testWidgets('cargando cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoLectura = Completer<void>();
        await _montar(tester, repo: repo, tamano: tamano, escala: escala);

        expect(find.text(TextosModificar.cargando), findsOneWidget);
        await _guias(tester);
        repo.bloqueoLectura!.complete();
        await _asentar(tester);
        handle.dispose();
      });

      testWidgets('no existe cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoEdicionFalso(null);
        await _montar(tester, repo: repo, tamano: tamano, escala: escala);

        expect(find.text('Volver'), findsOneWidget);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('error de lectura con «Reintentar» cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoEdicionFalso(ubicacionGuardada())..fallaAlLeer = const FailureInesperado();
        await _montar(tester, repo: repo, tamano: tamano, escala: escala);

        expect(find.text('Reintentar'), findsOneWidget);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('el estado inicial (guardar deshabilitado) cumple las guías en $nombre', (
        tester,
      ) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, tamano: tamano, escala: escala);

        await _guias(tester);
        handle.dispose();
      });

      testWidgets('guardando («Guardando…») cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoEdicionFalso(ubicacionGuardada())..bloqueoEscritura = Completer<void>();
        await _montar(tester, repo: repo, tamano: tamano, escala: escala);
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);
        await _guardarSinDesplazar(tester);

        expect(find.text(TextosModificar.guardando), findsOneWidget);
        await _guias(tester);
        repo.bloqueoEscritura!.complete();
        await _asentar(tester);
        handle.dispose();
      });

      testWidgets('el aviso de falla al guardar cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        final repo = RepoEdicionFalso(ubicacionGuardada())
          ..comportamiento = (u, n, _) async => const Left(FailureInesperado());
        await _montar(tester, repo: repo, tamano: tamano, escala: escala);
        await tester.enterText(_campoNumero, '1238');
        await _asentar(tester);
        await _guardarSinDesplazar(tester);

        expect(find.text(TextosModificar.noPudimosGuardar), findsOneWidget);
        await _guias(tester);
        handle.dispose();
      });

      testWidgets('la pregunta «Confirmar / Cancelar» cumple las guías en $nombre', (tester) async {
        final handle = tester.ensureSemantics();
        await _montar(tester, tamano: tamano, escala: escala);
        await _tocar(tester, find.text('Cambiar'));
        await _tocar(tester, find.text('Canelones'));
        await _guardarSinDesplazar(tester);

        expect(find.text('Confirmar'), findsOneWidget);
        await _guias(tester);
        handle.dispose();
      });
    }

    testWidgets('el aviso de falla al guardar se anuncia (liveRegion)', (tester) async {
      final handle = tester.ensureSemantics();
      final repo = RepoEdicionFalso(ubicacionGuardada())
        ..comportamiento = (u, n, _) async => const Left(FailureInesperado());
      await _montar(tester, repo: repo);
      await _escribirNumero(tester, '1238');
      await _tocar(tester, _guardar);

      final aviso = find.ancestor(
        of: find.text(TextosModificar.noPudimosGuardar),
        matching: find.byType(AvisoAlta),
      );
      expect(aviso, findsOneWidget);
      final anunciado = find.ancestor(
        of: find.text(TextosModificar.noPudimosGuardar),
        matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.liveRegion == true),
      );
      expect(anunciado, findsWidgets);
      handle.dispose();
    });

    testWidgets('el fantasma «Antes» tiene nombre para el lector de pantalla', (tester) async {
      final handle = tester.ensureSemantics();
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      e.mapa.moverPorGesto(e.mapa.camara!.conCentro(_alNorte(_norte18m)));
      await _asentar(tester);

      expect(find.text('Antes'), findsOneWidget);
      expect(find.bySemanticsLabel('Dónde estaba la ubicación antes de moverla'), findsOneWidget);
      expect(find.bySemanticsLabel('Punto de la ubicación'), findsOneWidget);
      handle.dispose();
    });
  });

  group('QA #202 · hallazgos documentados', () {
    // skip: QA #202 — si la ubicación cambió mientras se editaba, el aviso dice «Abrila de nuevo» pero no
    // trae ninguna acción: «Guardar cambios» queda apagado y solo queda la ✕ → «¿Descartar los cambios?».
    testWidgets('el aviso de «cambió mientras la editabas» trae una acción a mano', (tester) async {
      final e = await _montar(tester);
      await _escribirNumero(tester, '1238');
      e.repo.actual = ubicacionGuardada(actualizada: DateTime.utc(2026, 10, 1, 9));
      await _tocar(tester, _guardar);

      final aviso = find.ancestor(
        of: find.textContaining('Esta ubicación cambió mientras la editabas.'),
        matching: find.byType(AvisoAlta),
      );
      expect(aviso, findsOneWidget);
      expect(
        find.descendant(of: aviso, matching: find.byType(TextButton)),
        findsOneWidget,
        reason: 'un botón dentro del aviso (por ejemplo, volver a leer la ubicación)',
      );
    }, skip: true);

    // skip: QA #202 — «Mover el punto» + «Guardar posición» sin mover (menos de 1 m) deja «Guardar cambios»
    // habilitado y la ✕ pregunta «¿Descartar los cambios? Cambiaste la posición» sin que se vea ningún cambio
    // (el revisor lo reportó como menor: `puntoCambiado` compara coordenadas exactas, no 1 m).
    testWidgets('un ajuste de menos de 1 m no cuenta como cambio de posición', (tester) async {
      final e = await _montar(tester);
      await _tocar(tester, find.text('Mover el punto'));
      e.mapa.moverPorGesto(e.mapa.camara!.conCentro(_alNorte(0.000002)));
      await _asentar(tester);
      await _tocar(tester, find.text('Guardar posición'));

      expect(_habilitado(tester, _guardar), isFalse);
    }, skip: true);

    // skip: QA #202 — en 360×640 «Guardar cambios» no está fijo: con un campo «Editado» (o un aviso) queda
    // cortado al pie de la hoja que se desplaza y hay que arrastrar para ver la acción principal.
    testWidgets('en 360×640 con un campo editado, «Guardar cambios» queda entero a la vista', (
      tester,
    ) async {
      await _montar(tester, tamano: const Size(360, 640));
      await tester.enterText(_campoNumero, '1238');
      await _asentar(tester);

      final r = tester.getRect(_guardar);
      expect(r.bottom, lessThanOrEqualTo(640), reason: 'el botón no queda cortado');
      expect(r.top, greaterThanOrEqualTo(0));
    }, skip: true);
  });

  group('QA #202 · textos pegados', () {
    testWidgets(
      '300 emoji pegados en la calle: se corta en 120 y sin sustitutos sueltos al guardar',
      (tester) async {
        final e = await _montar(tester);
        await _traer(tester, _campoCalle);

        await tester.enterText(_campoCalle, '😀' * 300);
        await _asentar(tester);
        await _tocar(tester, _guardar);

        final calle = e.repo.escrituras.single.nueva.calle!;
        expect(_utf16Valido(calle), isTrue, reason: 'no se corta un emoji por la mitad');
        expect(calle.runes.length, lessThanOrEqualTo(120));
      },
    );

    testWidgets(
      'texto pegado con saltos de línea y caracteres especiales en el número queda en una línea',
      (tester) async {
        final e = await _montar(tester);

        await _escribirNumero(tester, "12\n34 <b>&\"'");
        await _tocar(tester, _guardar);

        final numero = e.repo.escrituras.single.nueva.numero!;
        expect(numero.contains('\n'), isFalse);
        expect(numero.contains('\r'), isFalse);
      },
    );

    testWidgets(
      'borrar la calle y el número guarda «sin dirección» sin perder el punto ni el tipo',
      (tester) async {
        final e = await _montar(tester);
        await tester.enterText(_campoCalle, '   ');
        await tester.enterText(_campoNumero, '');
        await _asentar(tester);

        await _tocar(tester, _guardar);

        final nueva = e.repo.escrituras.single.nueva;
        expect(nueva.calle, isNull);
        expect(nueva.numero, isNull);
        expect(nueva.lat, puntoItalia.lat);
        expect(nueva.tipo, TipoUbicacion.casa);
      },
    );
  });
}
