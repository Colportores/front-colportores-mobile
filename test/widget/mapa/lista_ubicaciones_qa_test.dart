// QA de la vista 05 «Lista Ubicaciones» (HU-UBI-002, #196, PR #292): lo que no cubren los tests de
// la implementación. Monta la pestaña **como la ve el colportor hoy** (sin estado de la casa: no hay
// `house_status` local hasta #151) con las fuentes reales y comprueba, en cada estado y en las
// hojas, las guías de accesibilidad de Flutter (toque 48 dp, etiquetas, contraste) a 360×640 y
// 412×915 con texto 1.0 y 2.0; y los casos límite de los flujos (falla a mitad de la acción,
// reintentos, lo tipeado que no se pierde).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/data/services/fuentes_sin_adaptador_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/presentation/pages/lista_ubicaciones_page.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_lista_ubicaciones.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/alta_ubicacion_qa_arnes.dart' show cargarFuentesReales;
import '../../helpers/lista_ubicaciones_falsos.dart';
import 'lista_ubicaciones_arnes.dart';

const _calleLarga = 'Avenida Doctor Luis Alberto de Herrera y Presidente General Flores';

/// Lo que ve el colportor hoy: ninguna fila trae el estado de la casa (`estado == null`).
List<UbicacionConResumen> _hoy() => [
  filaLista('a', calle: 'Av. Italia', numero: '1234', hace: const Duration(hours: 2), espacios: 2),
  filaLista(
    'b',
    tipo: TipoUbicacion.negocio,
    calle: 'Michigan',
    numero: '1540',
    hace: const Duration(days: 1),
    espacios: 1,
  ),
  filaLista(
    'c',
    tipo: TipoUbicacion.edificio,
    calle: _calleLarga,
    numero: 'Km 12 bis apto 1203',
    hace: const Duration(days: 40),
    espacios: 120,
  ),
  filaLista('d', calle: 'Orinoco', numero: '5031', espacios: 0),
  filaLista(
    'e',
    calle: 'Rivera',
    numero: '3920',
    hace: const Duration(days: 20),
    baja: ahoraLista.subtract(const Duration(days: 20)),
  ),
];

List<UbicacionConResumen> _muchas(int n) => [
  for (var i = 0; i < n; i++)
    filaLista(
      'u-${i.toString().padLeft(3, '0')}',
      calle: 'Calle $i',
      numero: '${i + 1}',
      hace: Duration(minutes: i + 1),
    ),
];

void main() {
  setUpAll(cargarFuentesReales);

  const tamanios = {'360x640': Size(360, 640), '412x915': Size(412, 915)};

  /// Las guías de accesibilidad y que nada reviente el layout.
  Future<void> accesible(WidgetTester tester, {bool contraste = true}) async {
    expect(tester.takeException(), isNull);
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    if (contraste) await expectLater(tester, meetsGuideline(textContrastGuideline));
  }

  // Cada estado de la vista, armado como en producción. Devuelve si hay que saltear el contraste
  // (el indicador de carga gira sin parar).
  final estados = <String, Future<bool> Function(WidgetTester, Size, double)>{
    'cargando': (tester, tam, escala) async {
      final bloqueo = Completer<void>();
      addTearDown(() {
        if (!bloqueo.isCompleted) bloqueo.complete();
      });
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy())..bloqueo = bloqueo,
        tamano: tam,
        escala: escala,
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      return true;
    },
    'vacío': (tester, tam, escala) async {
      await montarLista(tester, tamano: tam, escala: escala);
      expect(find.text(TextosListaUbicaciones.registrarPrimera), findsOneWidget);
      return false;
    },
    'lista sin estado de la casa': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: tam,
        escala: escala,
      );
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      return false;
    },
    'lista por cercanía con bajas': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: tam,
        escala: escala,
      );
      await abrirHojaFiltros(tester);
      await tester.ensureVisible(find.byKey(const Key('hoja_filtros_bajas')));
      await tester.tap(find.byKey(const Key('hoja_filtros_bajas')));
      await asentarLista(tester);
      await verUbicaciones(tester);
      await tester.tap(botonOrden);
      await asentarLista(tester);
      await tester.tap(find.text('Por cercanía').last);
      await asentarLista(tester);
      await tester.scrollUntilVisible(
        find.text('BAJA'),
        200,
        scrollable: find.descendant(
          of: find.byKey(const Key('lista_filas')),
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('BAJA'), findsOneWidget);
      return false;
    },
    'sin resultados': (tester, tam, escala) async {
      await montarLista(tester, repo: RepoListaFalso(_hoy()), tamano: tam, escala: escala);
      await buscarEnLista(tester, 'zzz');
      expect(find.text(TextosListaUbicaciones.limpiarFiltros), findsOneWidget);
      return false;
    },
    'error de lectura sin lista': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy())..fallaAlSuscribir = true,
        tamano: tam,
        escala: escala,
      );
      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
      return false;
    },
    'error de lectura con la lista a la vista': (tester, tam, escala) async {
      final repo = RepoListaFalso(_hoy());
      await montarLista(tester, repo: repo, tamano: tam, escala: escala);
      repo.fallar(StateError('base cerrada'));
      await asentarLista(tester);
      expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);
      expect(find.text('Av. Italia 1234'), findsOneWidget);
      return false;
    },
    'sin GPS': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
        tamano: tam,
        escala: escala,
      );
      expect(find.text('◎ Sin GPS'), findsOneWidget);
      return false;
    },
    'hoja de filtros': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: tam,
        escala: escala,
      );
      await abrirHojaFiltros(tester);
      expect(find.text('Ver 4 ubicaciones'), findsOneWidget);
      return false;
    },
    'hoja de filtros sin GPS': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
        tamano: tam,
        escala: escala,
      );
      await abrirHojaFiltros(tester);
      expect(find.text('Necesita GPS'), findsOneWidget);
      return false;
    },
    'hoja de ciudades (sin adaptador real)': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        ciudades: CiudadesParaAltaSinFuente(),
        tamano: tam,
        escala: escala,
      );
      await abrirHojaFiltros(tester);
      await tester.ensureVisible(find.text('Todas'));
      await tester.tap(find.text('Todas'));
      await asentarLista(tester);
      expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);
      return false;
    },
    'hoja de orden': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(Right(lecturaGps(8))),
        tamano: tam,
        escala: escala,
      );
      await tester.tap(botonOrden);
      await asentarLista(tester);
      expect(find.text('Ordenar'), findsOneWidget);
      return false;
    },
    'hoja de orden sin GPS': (tester, tam, escala) async {
      await montarLista(
        tester,
        repo: RepoListaFalso(_hoy()),
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
        tamano: tam,
        escala: escala,
      );
      await tester.tap(botonOrden);
      await asentarLista(tester);
      expect(find.text('Necesita GPS'), findsOneWidget);
      return false;
    },
  };

  for (final MapEntry(key: nombreTam, value: tam) in tamanios.entries) {
    for (final escala in [1.0, 2.0]) {
      group('QA #196 · accesibilidad · $nombreTam, texto $escala', () {
        for (final MapEntry(key: nombre, value: armar) in estados.entries) {
          testWidgets('$nombre: toque de 48 dp, etiquetas, contraste y sin overflow', (
            tester,
          ) async {
            final semantica = tester.ensureSemantics();
            final sinContraste = await armar(tester, tam, escala);
            // La guía de contraste de Flutter mide el borde suavizado de las letras: a 10–13 px da
            // 1,4–1,9 aunque el color cumpla (precedente: QA #247). Por eso corre al 200 % y con
            // texto 1.0 los pares de color se miden aparte, en «pares de color».
            await accesible(tester, contraste: !sinContraste && escala >= 2);
            semantica.dispose();
          });
        }
      });
    }
  }

  group('QA #196 · pares de color (texto 1.0, WCAG AA 4,5:1 para texto)', () {
    double contraste(Color a, Color b) {
      final la = a.computeLuminance();
      final lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    final pares = <String, (Color, Color)>{
      'texto atenuado sobre la fila': (ColoresLista.grisTexto, Colors.white),
      'meta gris sobre la fila blanca': (const Color(0xFF5B6B82), Colors.white),
      'meta gris sobre la fila de baja': (const Color(0xFF5B6B82), ColoresLista.filaBaja),
      '«BAJA» blanco sobre su etiqueta': (Colors.white, const Color(0xFF5B6B82)),
      'glifo de «No contestó»': (Colors.white, ColoresLista.grisEstado),
      'glifo de «Entrevista agendada»': (ColoresLista.tinta, ColoresLista.ambar),
      'glifo de «Entrevista hecha» y «Venta completa»': (Colors.white, ColoresLista.verde),
      'glifo de «Cobranza pendiente»': (Colors.white, ColoresLista.azul),
      'glifo de «Rechazó»': (Colors.white, ColoresLista.rojo),
      'chip de filtro': (ColoresLista.azul, ColoresLista.azulFondo),
      '«Por cercanía ▾» y «Sin GPS»': (ColoresLista.azul, const Color(0xFFFAFAF7)),
    };
    for (final MapEntry(key: nombre, value: (fg, bg)) in pares.entries) {
      test('$nombre llega a 4,5:1', () {
        expect(contraste(fg, bg), greaterThanOrEqualTo(4.5));
      });
    }
  });

  group('QA #196 · casos límite de los flujos', () {
    testWidgets('dado que falla al pedir la página siguiente, entonces la lista queda, avisa con '
        '«Reintentar» y al reintentar sigue cargando de a 50 (nada queda trabado)', (tester) async {
      final repo = RepoListaFalso(_muchas(120));
      await montarLista(tester, repo: repo);
      // Llega al pie: pide la segunda página y esa lectura falla.
      repo.fallaAlSuscribir = true;
      await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -6000));
      await asentarLista(tester);

      expect(find.text(TextosListaUbicaciones.errorLectura), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.reintentar), findsOneWidget);
      expect(
        find.textContaining('Calle 49 '),
        findsOneWidget,
        reason: 'la lista que ya tenía se conserva',
      );

      repo.fallaAlSuscribir = false;
      await tester.tap(find.text(TextosListaUbicaciones.reintentar));
      await asentarLista(tester);
      expect(find.text(TextosListaUbicaciones.errorLectura), findsNothing);
      expect(repo.activas, 1, reason: 'nunca dos lecturas vivas');
      // La segunda página llegó: se puede seguir bajando hasta el final de las 120.
      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -6000));
        await asentarLista(tester);
      }
      expect(find.textContaining('Calle 119 '), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.cargandoMas), findsNothing);
    });

    testWidgets(
      'dado que ya escribió una búsqueda, cuando falla la lectura, entonces lo tipeado no se '
      'pierde y «Reintentar» vuelve a la misma búsqueda',
      (tester) async {
        final repo = RepoListaFalso(_hoy());
        await montarLista(tester, repo: repo);
        await buscarEnLista(tester, 'italia');
        repo.fallar(StateError('base cerrada'));
        await asentarLista(tester);

        expect(tester.widget<TextField>(campoBusqueda).controller!.text, 'italia');
        await tester.tap(find.text(TextosListaUbicaciones.reintentar));
        await asentarLista(tester);
        expect(find.text('Av. Italia 1234'), findsOneWidget);
        expect(find.text('Michigan 1540'), findsNothing);
        expect(tester.widget<TextField>(campoBusqueda).controller!.text, 'italia');
      },
    );

    testWidgets(
      'dado una búsqueda de solo espacios, entonces no filtra nada ni cuenta como filtro',
      (tester) async {
        await montarLista(tester, repo: RepoListaFalso(_hoy()));
        await buscarEnLista(tester, '     ');

        expect(find.text('Av. Italia 1234'), findsOneWidget);
        expect(find.text('Michigan 1540'), findsOneWidget);
        expect(find.text(TextosListaUbicaciones.sinResultadosTitulo), findsNothing);
        expect(find.text('☷ Filtros'), findsOneWidget);
      },
    );

    for (final raro in [
      '%',
      '_',
      "'",
      r'\',
      '(',
      '[a-z]',
      '.*',
      '🏠',
      'ñandú 🏠 <b>',
      'a' * 5000,
    ]) {
      testWidgets('dado «${raro.length > 12 ? '${raro.substring(0, 12)}…' : raro}» en el buscador, '
          'entonces no rompe, dice «Sin resultados» y «Limpiar filtros» vuelve a la lista entera', (
        tester,
      ) async {
        await montarLista(tester, repo: RepoListaFalso(_hoy()));
        await buscarEnLista(tester, raro);

        expect(tester.takeException(), isNull);
        expect(find.text(TextosListaUbicaciones.sinResultadosTitulo), findsOneWidget);
        await tester.tap(find.byKey(const Key('lista_limpiar_filtros')));
        await asentarLista(tester);
        expect(find.text('Av. Italia 1234'), findsOneWidget);
        expect(tester.widget<TextField>(campoBusqueda).controller!.text, isEmpty);
      });
    }

    testWidgets(
      'dado que la lista es larga, cuando llega al final con el texto al 200 %, entonces la '
      'última fila queda entera y el botón «Nueva» no la tapa',
      (tester) async {
        await montarLista(
          tester,
          repo: RepoListaFalso(_hoy()),
          tamano: const Size(360, 640),
          escala: 2,
        );
        await tester.drag(find.byKey(const Key('lista_filas')), const Offset(0, -3000));
        await asentarLista(tester);

        final ultima = tester.getRect(find.byType(FilaUbicacionLista).last);
        final nueva = tester.getRect(botonNueva);
        expect(ultima.overlaps(nueva), isFalse, reason: 'la última fila no queda bajo «Nueva»');
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'dado que toca «Nueva» y el alta tarda, cuando vuelve a tocar, entonces el alta se abre '
      'una sola vez y al volver el botón sigue disponible',
      (tester) async {
        final alta = Completer<void>();
        var aperturas = 0;
        await montarLista(
          tester,
          repo: RepoListaFalso(_hoy()),
          alRegistrar: () {
            aperturas++;
            return alta.future;
          },
        );
        await tester.tap(botonNueva);
        await tester.pump();
        await tester.tap(botonNueva, warnIfMissed: false);
        await tester.pump();
        expect(aperturas, 1);

        alta.complete();
        await asentarLista(tester);
        await tester.tap(botonNueva);
        await tester.pump();
        expect(aperturas, 2, reason: 'terminada la primera, se puede abrir otra vez');
      },
    );

    testWidgets(
      'dado que la lista cambia de filtros mientras llega una emisión, entonces nunca quedan dos '
      'lecturas vivas',
      (tester) async {
        final repo = RepoListaFalso(_hoy());
        await montarLista(tester, repo: repo);
        await abrirHojaFiltros(tester);
        await tester.tap(find.text('Negocio'));
        await asentarLista(tester);
        await verUbicaciones(tester);
        repo.emitir([..._hoy(), filaLista('z', calle: 'Nueva', numero: '1')]);
        await tester.tap(chipFiltro('Negocio'));
        await asentarLista(tester);

        expect(repo.activas, 1);
        expect(find.text('Nueva 1'), findsOneWidget);
      },
    );
  });

  // Hallazgos menores de la revisión visual y del §8.3: cada test dice qué debería pasar; el
  // implementador le saca el `skip` cuando lo arregla.
  group('QA #196 · hallazgos menores (con skip)', () {
    // skip: QA #196 — §8.3: el cargando es un spinner sin texto visible (solo una etiqueta de
    // Semantics); debería decir «Cargando ubicaciones» debajo.
    testWidgets('mientras carga se ve un texto que lo dice, no solo el círculo', (tester) async {
      final repo = RepoListaFalso(_hoy())..bloqueo = Completer<void>();
      await montarLista(tester, repo: repo);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(TextosListaUbicaciones.cargando), findsOneWidget);

      repo.bloqueo!.complete();
      await asentarLista(tester);
    }, skip: true);

    // skip: QA #196 — convenciones §10: el error de lectura sin lista no se anuncia (el aviso con la
    // lista a la vista sí es liveRegion); un lector de pantalla no se entera de que falló.
    testWidgets('el error de lectura sin lista se anuncia (liveRegion)', (tester) async {
      final repo = RepoListaFalso(_hoy())..fallaAlSuscribir = true;
      await montarLista(tester, repo: repo);

      expect(
        find.ancestor(
          of: find.text(TextosListaUbicaciones.errorLectura),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsWidgets,
      );
    }, skip: true);

    // skip: QA #196 — visual (canvas 05B, hoja de filtros): el texto de las casillas de TIPO queda
    // pegado arriba; el canvas lo centra (`align-items:center`).
    testWidgets('las casillas de TIPO centran su texto en vertical', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_hoy()));
      await abrirHojaFiltros(tester);

      final casilla = find.ancestor(of: find.text('Casa'), matching: find.byType(InkWell)).first;
      expect(
        (tester.getCenter(find.text('Casa')).dy - tester.getCenter(casilla).dy).abs(),
        lessThan(3),
      );
    }, skip: true);

    // skip: QA #196 — visual: «Limpiar filtros» no tiene margen horizontal (el tema del
    // OutlinedButton solo fija el vertical) y el texto toca el borde de la píldora.
    testWidgets('«Limpiar filtros» deja aire entre el texto y el borde', (tester) async {
      await montarLista(tester, repo: RepoListaFalso(_hoy()));
      await buscarEnLista(tester, 'zzz');

      final boton = tester.getRect(find.byKey(const Key('lista_limpiar_filtros')));
      final texto = tester.getRect(find.text(TextosListaUbicaciones.limpiarFiltros));
      expect(texto.left - boton.left, greaterThanOrEqualTo(12));
      expect(boton.right - texto.right, greaterThanOrEqualTo(12));
    }, skip: true);
  });
}
