// QA de «Transferencia de materiales» (HU-STK-005, vista 40, #512): los 20 estados del canvas en 360×640
// y 412×915 con letra 1.0 y 2.0 (sin desbordes ni texto cortado), tamaño de toque y nombre de cada botón,
// el aviso de error anunciado, el texto literal de la HU y los casos límite que las pruebas del PR no tocan.
// Capturas: `--dart-define=QA_CAPTURAS=true` (van a `.dart_tool/qa_capturas`, nunca al repo).
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/qa_vista40_512_arnes.dart';
import '../../helpers/transferencias_arnes.dart';
import '../../helpers/transferencias_en_memoria.dart';

void main() {
  group('Matriz: los 20 estados del canvas en cada tamaño y escala', () {
    for (final estado in estados512) {
      for (final tamano in [chico512, grande512]) {
        for (final escala in [1.0, 2.0]) {
          final nombre =
              '${estado.id} ${estado.rotulo} · ${rotuloDeTamano512(tamano)} · x$escala: '
              'sin desbordes ni texto cortado';
          testWidgets(nombre, (tester) async {
            await cargarFuentes512(tester);
            await estado.armar(tester, tamano, escala);
            expect(tester.takeException(), isNull, reason: 'sin overflow');
            sinTextoCortado512(tester);
            await capturar512(
              tester,
              '${estado.id.replaceAll('·', '_')}_${rotuloDeTamano512(tamano)}_x$escala',
            );
          });
        }
      }
    }
  });

  group('Hallazgos de QA (corren con --dart-define=QA_HALLAZGOS=true)', () {
    for (final estado in estados512) {
      testWidgets(
        '${estado.id} ${estado.rotulo} · 360x640 · x2.0: ninguna palabra se parte en dos renglones',
        (tester) async {
          await cargarFuentes512(tester);
          await estado.armar(tester, chico512, 2);
          expect(palabrasPartidas512(tester), isEmpty);
        },
        // QA #512: «Transferencias» (40B·01) se parte en «Transferen/cias» con letra 2.0 en 360×640.
        skip: !conHallazgos512,
      );
    }
  });

  group('Accesibilidad: toque de 48 dp, ícono con nombre', () {
    for (final estado in estados512) {
      for (final tamano in [chico512, grande512]) {
        testWidgets('${estado.id} ${estado.rotulo} · ${rotuloDeTamano512(tamano)}', (tester) async {
          await cargarFuentes512(tester);
          final semantica = tester.ensureSemantics();
          await estado.armar(tester, tamano, 1);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          semantica.dispose();
        });
      }
    }
  });

  group('Los avisos se anuncian y dicen qué hacer', () {
    testWidgets('40A·08: el aviso de error es una región viva y trae la acción a mano', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
      await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);

      final aviso = find.byKey(const Key('pedir_transferencia_error'));
      expect(aviso, findsOneWidget);
      expect(
        tester.getSemantics(find.descendant(of: aviso, matching: find.byType(Text)).first),
        isSemantics(isLiveRegion: true),
      );
      expect(find.text('Reintentar'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('40A·07: el aviso de sin conexión es una región viva', (tester) async {
      final semantica = tester.ensureSemantics();
      await montarTransferencias(tester, sinConexion: true, abrir: 'pedir');
      final aviso = find.byKey(const Key('pedir_transferencia_sin_conexion'));
      expect(
        tester.getSemantics(find.descendant(of: aviso, matching: find.byType(Text)).first),
        isSemantics(isLiveRegion: true),
      );
      semantica.dispose();
    });

    testWidgets('40B·10: el error de la lista es una región viva y «Reintentar» tiene nombre', (
      tester,
    ) async {
      final semantica = tester.ensureSemantics();
      final repo = TransferenciasEnMemoria()
        ..errorDeLectura = const FailureTransferenciasNoDisponibles();
      await montarTransferencias(tester, repo: repo, abrir: 'lista');
      final aviso = find.byKey(const Key('transferencias_error'));
      expect(
        tester.getSemantics(find.descendant(of: aviso, matching: find.byType(Text)).first),
        isSemantics(isLiveRegion: true),
      );
      expect(find.bySemanticsLabel('Reintentar'), findsOneWidget);
      semantica.dispose();
    });

    testWidgets('40B·03: si cancelar falla, el aviso del detalle dice qué hacer', (tester) async {
      final repo = repoDelCanvas512()..fallas.add(const FailureTransferenciaNoCancelada());
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');
      await tocar(tester, botonCancelar);
      await tocar(tester, cancelarSi);

      expect(find.byKey(const Key('detalle_transferencia_falla')), findsOneWidget);
      expect(
        find.text('No pudimos cancelar la transferencia. Sigue por autorizar: probá de nuevo.'),
        findsOneWidget,
      );
      expect(botonCancelar, findsOneWidget, reason: 'el botón vuelve a estar a mano');
    });
  });

  group('HU-STK-005 · «Solicitud» (texto literal)', () {
    testWidgets(
      'Dado que necesito 5 libros del compañero, cuando creo la solicitud con cantidades, queda por autorizar',
      (tester) async {
        final arnes = await montarTransferencias(tester, abrir: 'pedir');
        await sumar(tester, 'p-3', 5);
        await elegirColportor(tester, 'Bruno Techera');
        await tocar(tester, botonPrincipal);

        final t = arnes.repo.pedidos.single;
        expect(t.estado, EstadoDeTransferencia.porAutorizar);
        expect(t.origenId, 'bruno', reason: 'el compañero es quien entrega');
        expect(t.destinoId, 'juan', reason: 'quien pide es quien recibe');
        expect(t.lineas.single.productoId, 'p-3');
        expect(t.lineas.single.cantidad, 5);
        expect(find.text('Tu coordinadora la tiene que autorizar'), findsOneWidget);
      },
    );

    testWidgets('pedir de dos categorías a la vez guarda las dos líneas, sin mezclar cantidades', (
      tester,
    ) async {
      final arnes = await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await tocar(tester, find.byKey(const Key('pedir_transferencia_chip_misioneros')));
      await sumar(tester, 'p-4', 7);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);

      final lineas = arnes.repo.pedidos.single.lineas;
      expect({for (final l in lineas) l.productoId: l.cantidad}, {'p-1': 2, 'p-4': 7});
      expect(find.text('El Camino a Cristo'), findsOneWidget);
      expect(find.text('× 7'), findsOneWidget);
    });
  });

  group('Casos límite del envío', () {
    testWidgets('mientras envía, los «+», los chips y la tarjeta no cambian lo que se pidió', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..compuerta = Completer<void>();
      final arnes = await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      expect(find.text('Enviando…'), findsOneWidget);

      await sumar(tester, 'p-1', 3);
      await tocar(tester, find.byKey(const Key('pedir_transferencia_chip_misioneros')));
      await tocar(tester, tarjetaDeColportor);
      expect(
        find.text('¿A quién le pedís?'),
        findsNothing,
        reason: 'no abre la hoja a mitad de envío',
      );

      repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(arnes.repo.pedidos.single.lineas.single.cantidad, 2);
    });

    testWidgets('falla, se cambia la cantidad y se reintenta: pide una sola vez con lo nuevo', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
      final arnes = await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      expect(find.byKey(const Key('pedir_transferencia_error')), findsOneWidget);

      await sumar(tester, 'p-1', 1);
      expect(find.byKey(const Key('pedir_transferencia_error')), findsNothing);
      await tocar(tester, botonPrincipal);

      expect(arnes.repo.pedidos, hasLength(1));
      expect(arnes.repo.pedidos.single.lineas.single.cantidad, 3);
    });

    testWidgets('falla, se cambia a otro colportor y se reintenta: pide al nuevo, no al anterior', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
      final arnes = await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      await elegirColportor(tester, 'Bruno Techera');
      await tocar(tester, botonPrincipal);

      expect(arnes.repo.pedidos.single.origenId, 'bruno');
    });

    testWidgets('el atrás del sistema con la hoja de colportores abierta solo cierra la hoja', (
      tester,
    ) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 1);
      await tocar(tester, tarjetaDeColportor);
      expect(find.text('¿A quién le pedís?'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('¿A quién le pedís?'), findsNothing);
      expect(paginaPedir, findsOneWidget);
      expect(find.text('Libros · 1'), findsOneWidget, reason: 'lo elegido sigue ahí');
    });
  });

  group('La hoja de colportores con muchos y con nombres largos', () {
    CompanierosDeCampania muchos(int n, {String? largo}) => CompanierosDeCampania(
      campania: 'Primavera 2026 de un nombre bastante largo para la campaña',
      companieros: [
        for (var i = 0; i < n; i++)
          CompanieroDeCampania(
            id: 'c-$i',
            nombre: largo == null ? 'Colportor Número $i' : '$largo$i',
            lugar: largo == null ? 'Rivera' : 'Un departamento con un nombre larguísimo $i',
          ),
      ],
    );

    for (final escala in [1.0, 2.0]) {
      testWidgets('60 colportores y letra $escala en 360×640: se desplaza sin desbordar', (
        tester,
      ) async {
        await cargarFuentes512(tester);
        await montarTransferencias(
          tester,
          companieros: CompanierosFalsos(resultado: muchos(60)),
          tamano: chico512,
          escala: escala,
          abrir: 'pedir',
        );
        await tocar(tester, tarjetaDeColportor);
        expect(tester.takeException(), isNull);

        await tester.drag(find.byType(SingleChildScrollView).last, const Offset(0, -3000));
        await asentarAgendar(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const Key('transferencia_colportores_listo')), findsOneWidget);
        await capturar512(tester, 'hoja60_x$escala');
      });

      testWidgets('un nombre larguísimo y letra $escala en 360×640: no se corta ni desborda', (
        tester,
      ) async {
        await cargarFuentes512(tester);
        final largo = 'Maria de los Angeles Fernandez Gutierrez de la Concepcion ' * 2;
        await montarTransferencias(
          tester,
          companieros: CompanierosFalsos(resultado: muchos(3, largo: largo)),
          tamano: chico512,
          escala: escala,
          abrir: 'pedir',
        );
        await sumar(tester, 'p-1', 1);
        await tocar(tester, tarjetaDeColportor);
        await tocar(tester, find.byKey(const Key('transferencia_colportor_c-0')));
        await tocar(tester, listoDelSelector);
        expect(tester.takeException(), isNull);
        sinTextoCortado512(tester);
        await capturar512(tester, 'nombre_largo_x$escala');
      });
    }

    testWidgets('elegir, volver a abrir y elegir a otro cambia solo al final con «Listo»', (
      tester,
    ) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 1);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, tarjetaDeColportor);
      await tocar(tester, find.text('Valentina Silva'));
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(find.text('Valentina Silva'), findsNothing);
    });
  });

  group('Datos límite de la lista', () {
    testWidgets('una sola transferencia y los filtros no dejan la pantalla en blanco', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo());
      await montarTransferencias(tester, repo: repo, abrir: 'lista');
      expect(find.byKey(const Key('transferencia_t-1')), findsOneWidget);
      for (final f in ['autorizadas', 'cerradas']) {
        await tocar(tester, find.byKey(Key('transferencias_filtro_$f')));
        expect(find.byKey(const Key('transferencias_filtro_vacio')), findsOneWidget);
      }
    });

    testWidgets('una transferencia con 40 líneas en el detalle se lee entera a 2.0 en 360×640', (
      tester,
    ) async {
      await cargarFuentes512(tester);
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(
            lineas: [
              for (var i = 0; i < 40; i++)
                LineaDeTransferencia(id: 'l-$i', productoId: 'p-${1 + i % 5}', cantidad: i + 1),
            ],
          ),
        );
      await montarTransferencias(tester, repo: repo, tamano: chico512, escala: 2, abrir: 'detalle');
      expect(tester.takeException(), isNull);
      await traerAlAlcance(tester, botonCancelar);
      expect(botonCancelar, findsOneWidget, reason: 'el botón de cancelar se alcanza al final');
    });
  });

  group('Privacidad', () {
    test(
      'el toString de la transferencia y de sus fallas no deja salir ids, nombres ni motivos',
      () {
        final t = transferenciaDeEjemplo(
          id: 'secreto-id',
          origen: 'ana-uuid',
          destino: 'juan-uuid',
          estado: EstadoDeTransferencia.rechazada,
          motivoRechazo: 'motivo privado de la coordinadora',
        );
        final texto =
            '$t ${const FailureTransferenciaNoGuardada(causa: 'StateError')} '
            '${const CompanieroDeCampania(id: 'ana-uuid', nombre: 'Ana Pereira', lugar: 'Rivera')}';
        for (final dato in [
          'secreto-id',
          'ana-uuid',
          'juan-uuid',
          'motivo privado',
          'Ana Pereira',
        ]) {
          expect(texto.contains(dato), isFalse, reason: 'el toString dejó salir «$dato»');
        }
      },
    );
  });
}
