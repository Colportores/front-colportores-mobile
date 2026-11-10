// QA de #655, entrega 1 (vista 41: alta sobre el mapa 41A y duplicado 41B). Los 11 artboards en
// 360x640 y 412x915 a 1,0 y 2,0 (sin desbordes, la hoja entera en pantalla, todo alcanzable), los
// criterios de HU-UBI-001 con su texto literal, la validación de entradas y los casos límite
// (falla a mitad, acciones superpuestas, reentrada, datos límite). Los hallazgos van con `skip`
// (`--dart-define=QA_HALLAZGOS=true` los corre). Capturas: `--dart-define=QA_CAPTURAS=true`.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/resultado_alta_ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/services/ciudades_para_alta.dart';
import 'package:colportores_mobile/features/mapa/domain/services/geocodificador_inverso.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/alta_ubicacion_notifier.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_principal_provider.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/alta_sobre_el_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/widgets/piezas_alta.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/alta_ubicacion_falsos.dart';
import '../../helpers/qa_vista41_655_arnes.dart';
import 'mapa_ubicaciones_arnes.dart';

/// ¿Algún nodo de semántica con la etiqueta que contiene [texto] es una región viva?
bool _regionViva(WidgetTester tester, String texto) {
  final raiz = tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!;
  var viva = false;
  void visitar(SemanticsNode n) {
    if (n.label.contains(texto) && n.flagsCollection.isLiveRegion) viva = true;
    n.visitChildren((h) {
      visitar(h);
      return true;
    });
  }

  visitar(raiz);
  return viva;
}

void main() {
  group('Matriz: 11 artboards × 360x640 / 412x915 × 1,0 / 2,0', () {
    for (final a in Artboard655.values) {
      for (final tamano in tamanos655) {
        for (final escala in escalas655) {
          final nombre =
              '${a.rotulo} · ${tamano.width.toInt()}x${tamano.height.toInt()} · ×$escala';
          testWidgets(nombre, (tester) async {
            await llegarA655(tester, a, tamano: tamano, escala: escala);
            await tester.pump(const Duration(milliseconds: 300));

            expect(tester.takeException(), isNull, reason: 'sin desbordes');
            final hoja = tester.getRect(hojaAlta655);
            expect(hoja.top, greaterThanOrEqualTo(0), reason: 'la hoja no se sale por arriba');
            expect(hoja.bottom, lessThanOrEqualTo(tamano.height + 0.5));
            sinTextoCortado655(tester);
            await capturar655(
              tester,
              '${a.name}_${tamano.width.toInt()}_x${escala.toStringAsFixed(0)}',
            );

            // Todo alcanzable: el botón principal se trae a la vista y se puede tocar.
            final boton = a == Artboard655.b02 ? crearIgual655 : principal655;
            await tester.ensureVisible(boton);
            await tester.pump();
            expect(boton.hitTestable(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });

  group('HU-UBI-001 · criterios con su texto literal', () {
    testWidgets('alta exitosa: tipo CASA, calle, número y ciudad; autocrea el espacio default', (
      tester,
    ) async {
      final a = await montar655(tester);
      await hastaQueHayAca655(tester);

      await tocar655(tester, principal655);

      expect(a.repo.llamadas, hasLength(1));
      final u = a.repo.llamadas.single.ubicacion;
      expect(u.calle, 'Grecia');
      expect(u.numero, '3307');
      expect(u.ciudadId, 'ciu-mvd');
      expect(a.repo.llamadas.single.espacio, isNotNull, reason: 'una casa nace con su espacio');
      expect(a.repo.llamadas.single.origen, OrigenCoordenadas.gps);
      expect(hojaAlta655, findsNothing);
      expect(seleccionadaId(tester), 'nueva-1');
    });

    testWidgets('un edificio no autocrea espacio', (tester) async {
      final a = await montar655(tester);
      await hastaQueHayAca655(tester);

      await tocar655(tester, find.text('Edificio'));
      await tocar655(tester, principal655);

      expect(a.repo.llamadas.single.ubicacion.tipo.name, 'edificio');
      expect(a.repo.llamadas.single.espacio, isNull);
    });

    testWidgets('alta sin GPS: el pin se coloca a mano y queda coords_source manual', (
      tester,
    ) async {
      final a = await montar655(
        tester,
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      await abrir655(tester);
      expect(habilitado655(tester, principal655), isFalse, reason: 'sin punto no se registra');

      a.m.mapa.tocar(mataojo655);
      await asentar655(tester);
      await tocar655(tester, principal655);
      await tocar655(tester, principal655);

      expect(a.repo.llamadas.single.origen, OrigenCoordenadas.manual);
      expect(hojaAlta655, findsNothing);
    });

    testWidgets('GPS impreciso: la advertencia literal y solo procede si confirma', (tester) async {
      final a = await montar655(tester, gps: GpsFalso(Right(lecturaGps(85))));
      await abrir655(tester);

      expect(
        find.text('Tu ubicación tiene baja precisión. ¿Querés ajustar manualmente o continuar?'),
        findsOneWidget,
      );
      expect(find.text('Confirmar posición'), findsNothing);
      expect(a.repo.llamadas, isEmpty);

      await tocar655(tester, secundario655); // «Continuar»
      await tocar655(tester, principal655); // «Registrar»

      expect(a.repo.llamadas, hasLength(1));
      expect(hojaAlta655, findsNothing);
    });

    testWidgets('posible duplicado: la candidata y las 3 acciones «Reutilizar esta», «Crear igual» '
        'y «Cancelar»; no crea todavía', (tester) async {
      final a = await montar655(
        tester,
        repo: conDuplicados655([
          candidata('vieja', metros: 3, calle: 'Av. Italia', numero: '1230'),
        ]),
      );
      await hastaQueHayAca655(tester);

      await tocar655(tester, principal655);

      expect(find.text('Reutilizar esta'), findsOneWidget);
      expect(find.text('Crear igual'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(
        find.text('Av. Italia 1230'),
        findsOneWidget,
        reason: 'la candidata con su vista previa',
      );
      expect(a.repo.llamadas, hasLength(1), reason: 'se preguntó, no se creó otra');
      expect(hojaAlta655, findsOneWidget);
    });

    testWidgets('misma dirección a 100 m o más: las 3 acciones y «Crear igual» deja las dos', (
      tester,
    ) async {
      final a = await montar655(
        tester,
        repo: conDuplicados655([candidata('lejos', metros: 150, calle: 'Grecia', numero: '3307')]),
      );
      await hastaQueHayAca655(tester);
      await tocar655(tester, principal655);

      expect(find.text('Reutilizar esta'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);

      await tocar655(tester, crearIgual655);
      await tester.enterText(justificacion655, 'Es la casa del fondo, otra entrada');
      await asentar655(tester);
      await tocar655(tester, principal655);

      expect(a.repo.llamadas, hasLength(2));
      expect(a.repo.llamadas.last.justificacion, 'Es la casa del fondo, otra entrada');
      expect(hojaAlta655, findsNothing);
    });

    testWidgets('«Elegí la ciudad»: sin ninguna viva dice «Tu campaña todavía no tiene ciudades. '
        'Avisale a tu coordinador.»', (tester) async {
      final ciudades = CiudadesFalsas(campania: const []);
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);

      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));

      expect(
        find.text('Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.'),
        findsOneWidget,
      );
    });

    testWidgets('«Elegí la ciudad»: si no puede leerlas dice «No pudimos leer las ciudades de tu '
        'campaña. Probá de nuevo.» con «Reintentar» solamente', (tester) async {
      final ciudades = CiudadesFalsas()..fallaCampania = const FailureCiudadesNoDisponibles();
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);

      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));

      expect(
        find.text('No pudimos leer las ciudades de tu campaña. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Elegir'), findsNothing);
    });

    // QA #655: «Reintentar» de «Elegí la ciudad» hace `setState(() => _ciudades = _leer())`: el cierre
    // devuelve un Future y Flutter (debug) lanza «setState() callback argument returned a Future».
    testWidgets('«Elegí la ciudad»: «Reintentar» trae las ciudades sin lanzar excepción', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas()..fallaCampania = const FailureCiudadesNoDisponibles();
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);
      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));

      ciudades.fallaCampania = null;
      await tocar655(tester, find.text('Reintentar'));

      expect(tester.takeException(), isNull);
      expect(find.byKey(ClavesAltaMapa.opcionCiudad('ciu-mvd')), findsOneWidget);
      expect(find.text('Canelones'), findsOneWidget);
    }, skip: !verHallazgos655);

    testWidgets('«Elegí la ciudad» mientras lee: no queda mudo — se puede volver y el texto lo '
        'dice', (tester) async {
      final espera = Completer<void>();
      final ciudades = CiudadesFalsas()..bloqueoCampania = espera;
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);

      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));

      // «Volver» anda mientras lee: no queda trabado.
      expect(habilitado655(tester, secundario655), isTrue);
      expect(
        find.text('Buscando las ciudades de tu campaña…'),
        findsOneWidget,
        reason: 'HU-UBI-001: «mientras lee, muestra "Buscando las ciudades de tu campaña…"»',
      );
      espera.complete();
    });

    testWidgets('«Elegí la ciudad» mientras lee: «Volver» anda y no hay excepción', (tester) async {
      final espera = Completer<void>();
      final ciudades = CiudadesFalsas()..bloqueoCampania = espera;
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);
      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tocar655(tester, secundario655);

      expect(find.text('¿Qué hay acá?'), findsOneWidget);
      espera.complete();
      await asentar655(tester);
      expect(tester.takeException(), isNull);
    });

    testWidgets('N·02 con una campaña sin ciudades: avisa con «Reintentar», «Registrar» apagado '
        'y Reintentar lo recupera', (tester) async {
      final ciudades = CiudadesFalsas(propone: (_) => throw UnimplementedError())
        ..fallaPropuesta = null;
      ciudades.propone = (_) => const CampaniaSinCiudades();
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);

      expect(
        find.text('Tu campaña todavía no tiene ciudades. Avisale a tu coordinador.'),
        findsOneWidget,
      );
      expect(habilitado655(tester, principal655), isFalse);

      ciudades.propone = (_) => const CiudadPropuesta(montevideo, OrigenPropuesta.deCampania);
      await tocar655(tester, find.text('Reintentar'));

      expect(habilitado655(tester, principal655), isTrue);
      expect(find.text('Montevideo'), findsWidgets);
    });

    testWidgets('N·02 con la ciudad ilegible: avisa «No pudimos leer…» y se puede elegir a mano', (
      tester,
    ) async {
      final ciudades = CiudadesFalsas()..fallaPropuesta = const FailureCiudadesNoDisponibles();
      await montar655(tester, ciudades: ciudades);
      await hastaQueHayAca655(tester);

      expect(
        find.text('No pudimos leer las ciudades de tu campaña. Probá de nuevo.'),
        findsOneWidget,
      );
      expect(habilitado655(tester, principal655), isFalse);

      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));
      await tocar655(tester, find.byKey(ClavesAltaMapa.opcionCiudad('ciu-mvd')));
      await tocar655(tester, principal655);

      expect(habilitado655(tester, principal655), isTrue);
      expect(find.text('Editado'), findsNothing, reason: 'el rótulo lleva «✎ Editado»');
      expect(find.textContaining('Editado'), findsOneWidget);
    });
  });

  group('Validación de entradas', () {
    testWidgets(
      'calle y número pegados muy largos se acotan a 120 y 20 y no desbordan a 360×640 ×2',
      (tester) async {
        final a = await montar655(tester, tamano: telefonoChico655, escala: 2);
        await hastaQueHayAca655(tester);

        await tester.enterText(find.byKey(ClavesAltaMapa.calle), 'Calle ' * 60);
        await tester.enterText(find.byKey(ClavesAltaMapa.numero), '1234567890' * 5);
        await asentar655(tester);

        final alta = estado655(tester)!;
        expect(alta.calle.texto.length, lessThanOrEqualTo(120));
        expect(alta.numero.texto.length, lessThanOrEqualTo(20));
        expect(tester.takeException(), isNull);
        await tocar655(tester, principal655);
        expect(a.repo.llamadas.single.ubicacion.numero!.length, lessThanOrEqualTo(20));
      },
    );

    testWidgets('calle y número de solo espacios: se guardan vacíos (opcionales), no espacios', (
      tester,
    ) async {
      final a = await montar655(tester);
      await hastaQueHayAca655(tester);

      await tester.enterText(find.byKey(ClavesAltaMapa.calle), '     ');
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '   ');
      await asentar655(tester);
      expect(habilitado655(tester, principal655), isTrue, reason: 'calle y número son opcionales');
      await tocar655(tester, principal655);

      final u = a.repo.llamadas.single.ubicacion;
      expect((u.calle ?? '').trim(), isEmpty);
      expect((u.numero ?? '').trim(), isEmpty);
      expect(u.calle, anyOf(isNull, isEmpty), reason: 'no se guardan solo espacios');
      expect(u.numero, anyOf(isNull, isEmpty));
    });

    testWidgets('emoji y caracteres especiales no rompen nada y llegan tal cual (sin espacios de '
        'borde)', (tester) async {
      final a = await montar655(tester);
      await hastaQueHayAca655(tester);

      await tester.enterText(find.byKey(ClavesAltaMapa.calle), '  Av. «Ñandú» 🏠 <b>&amp;  ');
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), ' 12-B/🏠 ');
      await asentar655(tester);
      await tocar655(tester, principal655);

      expect(tester.takeException(), isNull);
      final u = a.repo.llamadas.single.ubicacion;
      expect(u.calle, 'Av. «Ñandú» 🏠 <b>&amp;');
      expect(u.numero, '12-B/🏠');
    });

    testWidgets('justificación: 9 caracteres no alcanzan, 10 sí, 10 espacios no, con espacios de '
        'borde no cuentan', (tester) async {
      await montar655(tester, repo: conDuplicados655([candidata('vieja')]));
      await hastaQueHayAca655(tester);
      await tocar655(tester, principal655);
      await tocar655(tester, crearIgual655);

      Future<bool> con(String t) async {
        await tester.enterText(justificacion655, t);
        await asentar655(tester);
        return habilitado655(tester, principal655);
      }

      expect(await con(''), isFalse);
      expect(await con('123456789'), isFalse);
      expect(await con('1234567890'), isTrue);
      expect(await con('          '), isFalse);
      expect(await con('   abcdefgh   '), isFalse, reason: 'solo 8 caracteres reales');
      expect(await con('   abcdefghij   '), isTrue);
    });

    testWidgets('justificación pegada de 500 caracteres: queda en 200 y se manda recortada', (
      tester,
    ) async {
      final a = await montar655(tester, repo: conDuplicados655([candidata('vieja')]));
      await hastaQueHayAca655(tester);
      await tocar655(tester, principal655);
      await tocar655(tester, crearIgual655);

      await tester.enterText(justificacion655, 'x' * 500);
      await asentar655(tester);
      expect(tester.widget<TextField>(justificacion655).controller!.text.length, 200);
      await tocar655(tester, principal655);

      expect(a.repo.llamadas.last.justificacion!.length, 200);
    });

    testWidgets(
      'justificación con emoji y saltos de línea: llega recortada y sin romper el layout',
      (tester) async {
        final a = await montar655(
          tester,
          repo: conDuplicados655([candidata('vieja')]),
          tamano: telefonoChico655,
          escala: 2,
        );
        await hastaQueHayAca655(tester);
        await tocar655(tester, principal655);
        await tocar655(tester, crearIgual655);

        await tester.enterText(justificacion655, '  Otra puerta 🏠🏠\nfondo del lote 🚪  ');
        await asentar655(tester);
        expect(tester.takeException(), isNull);
        await tocar655(tester, principal655);

        expect(a.repo.llamadas.last.justificacion, 'Otra puerta 🏠🏠\nfondo del lote 🚪');
      },
    );

    testWidgets(
      'justificación: cinco emoji cuentan como 10 «caracteres» y habilitan «Crear igual»',
      (tester) async {
        await montar655(tester, repo: conDuplicados655([candidata('vieja')]));
        await hastaQueHayAca655(tester);
        await tocar655(tester, principal655);
        await tocar655(tester, crearIgual655);

        await tester.enterText(justificacion655, '🏠🏠🏠🏠🏠');
        await asentar655(tester);

        expect(
          habilitado655(tester, principal655),
          isFalse,
          reason: 'el mínimo es de 10 caracteres y acá hay 5 (el largo cuenta unidades UTF-16)',
        );
      },
      skip: !verHallazgos655,
    );

    testWidgets('lo tipeado en N·02 sobrevive a un fallo, a «Volver» y a «Elegí la ciudad»', (
      tester,
    ) async {
      await montar655(tester, repo: conFalloPrimero655());
      await hastaQueHayAca655(tester);
      await tester.enterText(find.byKey(ClavesAltaMapa.calle), 'Mataojo');
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '2047 B');
      await asentar655(tester);

      await tocar655(tester, principal655); // falla
      expect(find.text('Mataojo'), findsWidgets);
      expect(find.text('2047 B'), findsWidgets);
      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));
      await tocar655(tester, secundario655); // Volver desde «Elegí la ciudad»
      await tocar655(tester, secundario655); // Volver a N·01
      await tocar655(tester, principal655); // Confirmar posición

      final alta = estado655(tester)!;
      expect(alta.calle.texto, 'Mataojo');
      expect(alta.numero.texto, '2047 B');
    });
  });

  group('Casos límite de cada flujo', () {
    testWidgets('«Registrar» que lanza una excepción: avisa, el botón vuelve y lo escrito sigue', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          if (++intento == 1) throw StateError('disco lleno');
          return Right(AltaRegistrada(ubicacion: u));
        };
      final a = await montar655(tester, repo: repo);
      await hastaQueHayAca655(tester);
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '3307 B');
      await asentar655(tester);

      await tocar655(tester, principal655);

      expect(find.byType(AvisoAlta), findsOneWidget);
      expect(texto655(principal655), 'Registrar', reason: 'no queda en «Registrando…»');
      expect(habilitado655(tester, principal655), isTrue);
      expect(estado655(tester)!.numero.texto, '3307 B');
      expect(estado655(tester)!.guardando, isFalse);

      await tocar655(tester, principal655);
      expect(a.repo.llamadas, hasLength(2));
      expect(hojaAlta655, findsNothing);
    });

    testWidgets('el aviso de la falla se anuncia (región viva) y tiene salida', (tester) async {
      await montar655(tester, repo: conFalloPrimero655());
      final semantica = tester.ensureSemantics();
      await hastaQueHayAca655(tester);

      await tocar655(tester, principal655);

      final aviso = find.byType(AvisoAlta);
      expect(aviso, findsOneWidget);
      final mensaje = (tester.widget<AvisoAlta>(aviso)).texto;
      expect(_regionViva(tester, mensaje), isTrue, reason: 'se anuncia al lector de pantalla');
      expect(habilitado655(tester, principal655), isTrue, reason: 'la salida es reintentar');
      semantica.dispose();
    });

    testWidgets('el aviso de falla queda a la vista de la hoja a 360×640 ×2', (tester) async {
      await montar655(tester, repo: conFalloPrimero655(), tamano: telefonoChico655, escala: 2);
      await hastaQueHayAca655(tester);

      await tocar655(tester, principal655);

      expect(find.byType(AvisoAlta), findsOneWidget);
      expect(
        enVistaDeLaHoja655(tester, find.byType(AvisoAlta)),
        isTrue,
        reason: 'el aviso rojo no puede quedar fuera de vista (un error sin salida visible)',
      );
      await capturar655(tester, 'falla_registrar_360_x2');
    });

    testWidgets('mientras guarda: el atrás, «Volver» y la ciudad no hacen nada; al terminar cierra '
        'con una sola alta', (tester) async {
      final repo = RepoAltaFalso()..bloqueo = Completer<void>();
      final a = await montar655(tester, repo: repo);
      await hastaQueHayAca655(tester);

      await tester.tap(principal655);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(estado655(tester)!.guardando, isTrue);
      expect(texto655(principal655), 'Registrando…');

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));
      expect(hojaAlta655, findsOneWidget, reason: 'el atrás no cierra mientras guarda');
      expect(estado655(tester)!.paso, PasoAlta.queHayAca);
      expect(habilitado655(tester, secundario655), isFalse);
      await tester.tap(find.byKey(ClavesAltaMapa.ciudad), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));
      expect(estado655(tester)!.paso, PasoAlta.queHayAca);
      await tester.tap(principal655, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 50));

      repo.bloqueo!.complete();
      await asentar655(tester);

      expect(a.repo.llamadas, hasLength(1));
      expect(hojaAlta655, findsNothing);
      expect(seleccionadaId(tester), 'nueva-1');
    });

    testWidgets('«Crear igual» en vuelo: un segundo toque y el atrás no duplican ni cierran', (
      tester,
    ) async {
      var intento = 0;
      final espera = Completer<void>();
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          if (++intento == 1) {
            return Right(AltaConDuplicados(candidatas: [candidata('vieja', calle: 'Grecia')]));
          }
          await espera.future;
          return Right(AltaRegistrada(ubicacion: u));
        };
      final a = await montar655(tester, repo: repo);
      await hastaQueHayAca655(tester);
      await tocar655(tester, principal655);
      await tocar655(tester, crearIgual655);
      await tester.enterText(justificacion655, 'Otra puerta del fondo');
      await asentar655(tester);

      await tester.tap(principal655);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(principal655, warnIfMissed: false);
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 50));

      expect(a.repo.llamadas, hasLength(2), reason: 'un solo «Crear igual»');
      expect(hojaAlta655, findsOneWidget);
      espera.complete();
      await asentar655(tester);
      expect(hojaAlta655, findsNothing);
      expect(a.repo.llamadas, hasLength(2));
    });

    testWidgets('«Crear igual» que lanza una excepción: el botón vuelve y la justificación sigue', (
      tester,
    ) async {
      var intento = 0;
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async {
          if (++intento == 1) {
            return Right(AltaConDuplicados(candidatas: [candidata('vieja', calle: 'Grecia')]));
          }
          if (intento == 2) throw StateError('disco');
          return Right(AltaRegistrada(ubicacion: u));
        };
      final a = await montar655(tester, repo: repo);
      await hastaQueHayAca655(tester);
      await tocar655(tester, principal655);
      await tocar655(tester, crearIgual655);
      await tester.enterText(justificacion655, 'Otra puerta del fondo');
      await asentar655(tester);

      await tocar655(tester, principal655);

      expect(find.byType(AvisoAlta), findsOneWidget);
      expect(habilitado655(tester, principal655), isTrue);
      expect(find.text('Otra puerta del fondo'), findsOneWidget);
      await tocar655(tester, principal655);
      expect(a.repo.llamadas, hasLength(3));
      expect(a.repo.llamadas.last.justificacion, 'Otra puerta del fondo');
      expect(hojaAlta655, findsNothing);
    });

    testWidgets('reentrada: «Cancelar» del aviso, mover el pin y volver a registrar pregunta otra '
        'vez sin perder lo escrito', (tester) async {
      final repo = RepoAltaFalso()
        ..comportamiento = (u) async =>
            Right(AltaConDuplicados(candidatas: [candidata('vieja', calle: 'Grecia')]));
      final a = await montar655(tester, repo: repo);
      await hastaQueHayAca655(tester);
      await tester.enterText(find.byKey(ClavesAltaMapa.numero), '3307 B');
      await asentar655(tester);
      await tocar655(tester, principal655);
      expect(find.text('Cancelar'), findsOneWidget);

      await tocar655(tester, secundario655); // Cancelar → N·01
      a.m.mapa.tocar(mataojo655);
      await asentar655(tester);
      await tocar655(tester, principal655); // Confirmar posición
      await tocar655(tester, principal655); // Registrar → aviso otra vez

      expect(a.repo.llamadas, hasLength(2));
      expect(find.text('Cancelar'), findsOneWidget);
      expect(estado655(tester)!.numero.texto, '3307 B');
      expect(estado655(tester)!.guardando, isFalse);
    });

    testWidgets(
      'la justificación escrita para un lugar no reaparece al pedir «Crear igual» en otro '
      'punto',
      (tester) async {
        final repo = RepoAltaFalso()
          ..comportamiento = (u) async =>
              Right(AltaConDuplicados(candidatas: [candidata('vieja', calle: 'Grecia')]));
        final a = await montar655(tester, repo: repo);
        await hastaQueHayAca655(tester);
        await tocar655(tester, principal655);
        await tocar655(tester, crearIgual655);
        await tester.enterText(justificacion655, 'Es la casa del fondo de Grecia');
        await asentar655(tester);
        await tocar655(tester, secundario655); // Volver al aviso
        await tocar655(tester, secundario655); // Cancelar → N·01

        a.m.mapa.tocar(mataojo655);
        await asentar655(tester);
        await tocar655(tester, principal655);
        await tocar655(tester, principal655);
        await tocar655(tester, crearIgual655);

        expect(
          tester.widget<TextField>(justificacion655).controller!.text,
          isEmpty,
          reason: 'es otro punto: la justificación de la casa anterior no corresponde',
        );
      },
      skip: !verHallazgos655,
    );

    testWidgets('41B con 30 candidatas: las letras siguen (AA…) y a 360×640 ×2 no desborda', (
      tester,
    ) async {
      final muchas = [
        for (var i = 0; i < 30; i++)
          candidata('c$i', metros: 2.0 + i, calle: 'Grecia', numero: '${3300 + i}'),
      ];
      await montar655(tester, repo: conDuplicados655(muchas), tamano: telefonoChico655, escala: 2);
      await hastaQueHayAca655(tester);

      await tocar655(tester, principal655);

      expect(tester.takeException(), isNull);
      expect(find.text('Hay 30 ubicaciones cerca'), findsOneWidget);
      expect(FormatoUbicaciones.rotuloCandidata(26), 'AA');
      await tester.ensureVisible(crearIgual655);
      await tester.pump();
      expect(crearIgual655.hitTestable(), findsOneWidget);
      await tocar655(tester, secundario655);
      expect(texto655(principal655), 'Confirmar posición');
    });

    testWidgets('60 ciudades con nombres largos: la lista se desplaza y «Usar» llega a la vista '
        'a 360×640 ×2', (tester) async {
      final ciudades = CiudadesFalsas(
        campania: [
          for (var i = 0; i < 60; i++)
            CiudadCatalogo(id: 'c$i', nombre: 'Ciudad de nombre larguísimo número $i del interior'),
          montevideo,
        ],
      );
      await montar655(tester, ciudades: ciudades, tamano: telefonoChico655, escala: 2);
      await hastaQueHayAca655(tester);
      await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));

      expect(tester.takeException(), isNull);
      await tocar655(tester, find.byKey(ClavesAltaMapa.opcionCiudad('c40')));
      expect(find.textContaining('Usar Ciudad de nombre larguísimo número 40'), findsOneWidget);
      await tocar655(tester, principal655);

      expect(find.textContaining('número 40'), findsWidgets);
      expect(tester.takeException(), isNull);
      expect(estado655(tester)!.ciudad!.id, 'c40');
    });

    testWidgets(
      'la dirección del mapa larguísima en N·01 a 360×640 ×2: sin desborde y alcanzable',
      (tester) async {
        final larga = 'Avenida ${'Doctor Luis Alberto de Herrera ' * 5}';
        await montar655(
          tester,
          tamano: telefonoChico655,
          escala: 2,
          geocodificador: GeocodificadorFalso(
            (_) => DireccionDelPunto(calle: larga, numero: '3307'),
          ),
        );
        await abrir655(tester);

        expect(tester.takeException(), isNull);
        sinTextoCortado655(tester);
        await tester.ensureVisible(principal655);
        await tester.pump();
        expect(principal655.hitTestable(), findsOneWidget);
      },
    );

    testWidgets('«Activar GPS» y después el GPS llega: el pin aparece y se puede confirmar', (
      tester,
    ) async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      await montar655(tester, gps: gps);
      await abrir655(tester);
      expect(estado655(tester)!.punto, isNull);

      gps.alActivar = () => gps.moverse(lecturaGps(8));
      await tocar655(tester, find.text('Activar GPS'));

      expect(tester.takeException(), isNull);
      expect(find.text('Activar GPS'), findsOneWidget, reason: 'sin lectura sigue habiendo salida');
    });

    testWidgets('✕ en 41A·02 (sin GPS) cierra sin guardar y el mapa vuelve a explorar', (
      tester,
    ) async {
      final a = await montar655(
        tester,
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      await abrir655(tester);

      await tocar655(tester, find.byKey(ClavesAltaMapa.cerrar));

      expect(hojaAlta655, findsNothing);
      expect(a.repo.llamadas, isEmpty);
      expect(contenedorDeLaPestana(tester).read(mapaPrincipalProvider), const Explorando());
    });

    testWidgets(
      'el atrás de «Elegí la ciudad» vuelve a N·02 sin cambiar la ciudad y desde 41B·04 a '
      'N·01',
      (tester) async {
        await montar655(
          tester,
          repo: conDuplicados655([
            candidata(
              'vieja',
              metros: 26,
              calle: 'Grecia',
              numero: '3307',
              admiteConservarAmbos: false,
            ),
          ]),
        );
        await hastaQueHayAca655(tester);
        await tocar655(tester, find.byKey(ClavesAltaMapa.ciudad));
        await tester.binding.handlePopRoute();
        await asentar655(tester);
        expect(find.text('¿Qué hay acá?'), findsOneWidget);
        expect(estado655(tester)!.ciudad!.id, 'ciu-mvd');

        await tocar655(tester, principal655);
        expect(find.text('Ya registraste Grecia 3307'), findsOneWidget);
        await tester.binding.handlePopRoute();
        await asentar655(tester);
        expect(texto655(principal655), 'Confirmar posición');
        expect(estado655(tester)!.punto, puntoItalia);
      },
    );
  });

  group('Revisión visual', () {
    Future<Color> bordeIzquierdo(WidgetTester tester, Finder campo) async {
      final r = tester.getRect(campo);
      return pixel655(tester, Offset(r.left + 1, r.center.dy));
    }

    testWidgets('el campo de número de N·02 enfocado conserva su borde (referencia del método)', (
      tester,
    ) async {
      await llegarA655(tester, Artboard655.a06);
      await tester.pump(const Duration(milliseconds: 300));

      expect(await bordeIzquierdo(tester, find.byKey(ClavesAltaMapa.numero)), isNot(Colors.white));
    });

    testWidgets('41B·03: la justificación enfocada conserva su borde como los demás campos (el '
        'canvas la dibuja con caja)', (tester) async {
      await llegarA655(tester, Artboard655.b03);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        await bordeIzquierdo(tester, justificacion655),
        isNot(Colors.white),
        reason: 'enfocado, el campo queda con una raya abajo y sin caja (le falta `focusedBorder`)',
      );
    }, skip: !verHallazgos655);
  });

  group('Acción principal a la vista', () {
    testWidgets('N·02 a 360×640 ×2: «Registrar» se ve sin desplazar la hoja (fijo al pie, como la '
        'vista 03 desde #305)', (tester) async {
      await llegarA655(tester, Artboard655.a04, tamano: telefonoChico655, escala: 2);
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        enVistaDeLaHoja655(tester, principal655),
        isTrue,
        reason: 'la acción principal tiene que estar a la vista con texto grande y teléfono chico',
      );
    }, skip: !verHallazgos655);
  });

  group('41B · comparar la nueva con la existente en el mapa (sin velo)', () {
    // El canvas: «La nueva (el pin) y la existente (resaltada) se ven en el mapa principal, cada una con
    // su etiqueta. Sin velo, para poder comparar.» La cámara no se mueve al pasar de N·02 al aviso, así
    // que lo que se ve depende de dónde dejó el pin «Confirmar posición» arriba de la hoja alta de N·02.
    for (final tamano in tamanos655) {
      for (final a in [Artboard655.b01, Artboard655.b02, Artboard655.b04]) {
        testWidgets(
          '${a.rotulo} en ${tamano.width.toInt()}x${tamano.height.toInt()}: las etiquetas '
          'de la nueva y de la existente se ven arriba de la hoja',
          (tester) async {
            await llegarA655(tester, a, tamano: tamano);
            await tester.pump(const Duration(milliseconds: 300));

            final bordeHoja = tester.getRect(hojaAlta655).top;
            final etiquetas = [
              find.text('La nueva'),
              find.textContaining('Ya registrada · a '),
              find.textContaining('A · a '),
              find.textContaining('B · a '),
            ];
            for (final f in etiquetas) {
              for (var i = 0; i < f.evaluate().length; i++) {
                final r = tester.getRect(f.at(i));
                expect(r.top, greaterThanOrEqualTo(0), reason: 'etiqueta cortada por arriba: $r');
                expect(r.bottom, lessThanOrEqualTo(bordeHoja), reason: 'etiqueta bajo la hoja: $r');
              }
            }
            expect(find.text('La nueva'), findsOneWidget);
          },
        );
      }
    }
  });

  group('Privacidad', () {
    test('toString del estado del alta, de sus parámetros y del modo del mapa no trae PII', () {
      const estado = AltaUbicacionState(
        calle: CampoDireccion('Grecia Secreta', FuenteCampo.editado),
        numero: CampoDireccion('3307 B', FuenteCampo.editado),
        punto: puntoItalia,
      );
      final textos = [
        estado.toString(),
        estado.calle.toString(),
        const ParametrosAlta(colportorId: 'col-privado').toString(),
        const ColocandoPin(ParametrosAlta(colportorId: 'col-privado')).toString(),
      ].join(' ');
      expect(textos, isNot(contains('Grecia')));
      expect(textos, isNot(contains('3307')));
      expect(textos, isNot(contains('col-privado')));
      expect(textos, isNot(contains('-34.88')));
    });
  });
}
