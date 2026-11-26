// «Pedir transferencia de materiales» (vista 40 A, HU-STK-005, #512): los nueve artboards (40A·01 a
// 40A·09) y los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart'
    show TipoConexion;
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/material_de_transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/transferencias_arnes.dart';
import '../../helpers/transferencias_en_memoria.dart';

void main() {
  group('40A·01 · Qué pedís', () {
    testWidgets('sin nada elegido el botón está apagado y dice qué falta', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');

      expect(find.text('Pedir materiales a otro colportor'), findsOneWidget);
      expect(find.text('QUÉ PEDÍS'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Sumá al menos un material.'), findsOneWidget);
    });

    testWidgets('las categorías son chips y las filas no llevan precio, solo «Tenés N»', (
      tester,
    ) async {
      await montarTransferencias(tester, abrir: 'pedir');

      expect(find.text('Libros'), findsOneWidget);
      expect(find.text('Misioneros'), findsOneWidget);
      expect(find.text('Revistas'), findsOneWidget);
      expect(find.text('Salud y Hogar'), findsOneWidget);
      expect(find.text('Tenés 0'), findsOneWidget);
      expect(find.text('Tenés 3'), findsOneWidget);
      expect(find.text('◆ Bonificable'), findsNWidgets(2));
      expect(
        find.textContaining(r'$'),
        findsNothing,
        reason: 'la transferencia mueve materiales, no plata',
      );
    });

    testWidgets('con materiales y sin colportor: «Elegí a quién se lo pedís.»', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await asentarAgendar(tester);

      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Elegí a quién se lo pedís.'), findsOneWidget);
      expect(find.text('Libros · 2'), findsOneWidget);
    });

    testWidgets('cada chip cuenta lo elegido en su categoría y cambia de lista', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await sumar(tester, 'p-3');
      await tocar(tester, find.byKey(const Key('pedir_transferencia_chip_misioneros')));

      expect(find.text('Libros · 3'), findsOneWidget);
      expect(find.text('El Camino a Cristo'), findsOneWidget);
      expect(find.text('Salud y Hogar'), findsNothing);
      await sumar(tester, 'p-4');
      expect(find.text('Misioneros · 1'), findsOneWidget);
    });

    testWidgets('el «−» baja a cero y el material deja de contar', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');
      expect(find.text('Libros · 1'), findsOneWidget);

      final fila = find.byKey(const Key('pedir_transferencia_material_p-1'));
      await tester.tap(
        find.descendant(of: fila, matching: find.byIcon(Icons.remove_circle_outline)),
      );
      await tester.pump();

      expect(find.text('Libros'), findsOneWidget);
    });

    testWidgets('no se pasa de 999 por línea', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');
      final fila = find.byKey(const Key('pedir_transferencia_material_p-1'));
      final mas = find.descendant(of: fila, matching: find.byIcon(Icons.add_circle_outline));
      for (var i = 0; i < 1100; i++) {
        final boton = tester.widget<IconButton>(
          find.ancestor(of: mas, matching: find.byType(IconButton)),
        );
        if (boton.onPressed == null) break;
        boton.onPressed!();
        await tester.pump();
      }

      expect(find.text('999'), findsOneWidget);
      expect(
        tester
            .widget<IconButton>(find.ancestor(of: mas, matching: find.byType(IconButton)))
            .onPressed,
        isNull,
      );
    });

    testWidgets('un catálogo vacío lo dice y deja el botón apagado', (tester) async {
      await montarTransferencias(tester, materiales: const [], abrir: 'pedir');

      expect(find.byKey(const Key('pedir_transferencia_sin_catalogo')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);
    });

    testWidgets('una categoría sin materiales dice que no hay', (tester) async {
      await montarTransferencias(tester, materiales: [materialesDelCanvas.first], abrir: 'pedir');
      await tocar(tester, find.byKey(const Key('pedir_transferencia_chip_revistas')));

      expect(find.byKey(const Key('pedir_transferencia_categoria_vacia')), findsOneWidget);
    });
  });

  group('40A·02 · Elegir a la otra colportora', () {
    testWidgets('la hoja lista a los colportores de la campaña, sin nada elegido', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await tocar(tester, tarjetaDeColportor);

      expect(find.text('¿A quién le pedís?'), findsOneWidget);
      expect(find.text('Colportores de Primavera 2026.'), findsOneWidget);
      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(find.text('Bruno Techera'), findsOneWidget);
      expect(find.text('Valentina Silva'), findsOneWidget);
      expect(find.text('Rivera'), findsNWidgets(2));
      expect(
        tester.widget<FilledButton>(listoDelSelector).onPressed,
        isNull,
        reason: 'sin elegir no hay «Listo»',
      );
    });

    testWidgets('elegir a Ana deja su nombre, «SE LO PEDÍS A» y «Cambiar»', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await elegirColportor(tester, 'Ana Pereira');

      expect(find.text('SE LO PEDÍS A'), findsOneWidget);
      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(find.text('Cambiar'), findsOneWidget);
      expect(find.text('Elegir colportor'), findsNothing);
    });

    testWidgets(
      'cambiar de colportora: la hoja abre con la anterior marcada y se puede elegir otra',
      (tester) async {
        await montarTransferencias(tester, abrir: 'pedir');
        await elegirColportor(tester, 'Ana Pereira');
        await elegirColportor(tester, 'Bruno Techera');

        expect(find.text('Bruno Techera'), findsOneWidget);
        expect(find.text('Ana Pereira'), findsNothing);
      },
    );

    testWidgets('cerrar la hoja sin «Listo» no cambia nada', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await tocar(tester, tarjetaDeColportor);
      await tocar(tester, find.text('Ana Pereira'));
      await tester.tapAt(const Offset(10, 10));
      await asentarAgendar(tester);

      expect(find.text('Elegir colportor'), findsOneWidget);
    });

    testWidgets('sin la lista del servidor, la hoja lo dice y deja reintentar', (tester) async {
      final falsos = CompanierosFalsos();
      await montarTransferencias(tester, companieros: falsos, abrir: 'pedir');
      await tocar(tester, tarjetaDeColportor);

      expect(find.byKey(const Key('transferencia_colportores_error')), findsOneWidget);
      expect(
        find.textContaining('No pudimos traer a los colportores de tu campaña'),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(listoDelSelector).onPressed, isNull);

      falsos.resultado = companierosDelCanvas;
      await tocar(tester, find.text('Reintentar'));

      expect(find.byKey(const Key('transferencia_colportores_error')), findsNothing);
      expect(find.text('Ana Pereira'), findsOneWidget);
    });

    testWidgets('mientras la lista llega, la hoja muestra que está buscando', (tester) async {
      final falsos = CompanierosFalsos(resultado: companierosDelCanvas)
        ..compuerta = Completer<void>();
      await montarTransferencias(tester, companieros: falsos, abrir: 'pedir');
      await tocar(tester, tarjetaDeColportor);

      expect(find.byKey(const Key('transferencia_colportores_cargando')), findsOneWidget);

      falsos.compuerta!.complete();
      await asentarAgendar(tester);
      expect(find.text('Ana Pereira'), findsOneWidget);
    });

    testWidgets('un doble toque en la tarjeta no abre dos hojas', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await traerAlAlcance(tester, tarjetaDeColportor);
      await tester.tap(tarjetaDeColportor);
      await tester.tap(tarjetaDeColportor, warnIfMissed: false);
      await asentarAgendar(tester);

      expect(find.text('¿A quién le pedís?'), findsOneWidget);
    });
  });

  group('40A·03 · Lista para enviar', () {
    testWidgets('con materiales y colportora el botón se enciende y dice qué pasa', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');

      expect(elBoton(tester).onPressed, isNotNull);
      expect(find.text('Pedir transferencia'), findsOneWidget);
      expect(
        find.text('Tu coordinadora la tiene que autorizar. Ana Pereira la ve desde que la enviás.'),
        findsOneWidget,
      );
    });
  });

  group('40A·04 · Sin materiales elegidos', () {
    testWidgets('con la colportora pero sin materiales: «Sumá al menos un material.»', (
      tester,
    ) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await elegirColportor(tester, 'Ana Pereira');

      expect(elBoton(tester).onPressed, isNull);
      expect(find.text('Sumá al menos un material.'), findsOneWidget);
    });

    testWidgets('quitar el último material apaga el botón otra vez', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      expect(elBoton(tester).onPressed, isNotNull);

      final fila = find.byKey(const Key('pedir_transferencia_material_p-1'));
      await tocar(
        tester,
        find.descendant(of: fila, matching: find.byIcon(Icons.remove_circle_outline)),
      );

      expect(elBoton(tester).onPressed, isNull);
    });
  });

  group('40A·05 · Enviando y 40A·06 · Enviada', () {
    Future<ArnesTransferencias> listaParaEnviar(
      WidgetTester tester, {
      TransferenciasEnMemoria? repo,
      double escala = 1,
    }) async {
      final arnes = await montarTransferencias(tester, repo: repo, escala: escala, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      return arnes;
    }

    testWidgets('pedir guarda la transferencia por autorizar y muestra «Transferencia pedida»', (
      tester,
    ) async {
      final arnes = await listaParaEnviar(tester);
      await tocar(tester, botonPrincipal);

      expect(find.text('Transferencia pedida'), findsOneWidget);
      expect(find.text('Tu coordinadora la tiene que autorizar'), findsOneWidget);
      expect(find.text('Te avisamos cuando la autorice o la rechace.'), findsOneWidget);
      expect(find.text('Le pediste a'), findsOneWidget);
      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(find.text('Salud y Hogar'), findsOneWidget);
      expect(find.text('× 2'), findsOneWidget);
      expect(find.text('Ver transferencias'), findsOneWidget);

      final t = arnes.repo.pedidos.single;
      expect(t.estado, EstadoDeTransferencia.porAutorizar);
      expect(t.origenId, 'ana');
      expect(t.destinoId, 'juan');
      expect(t.lineas.single.productoId, 'p-1');
      expect(t.lineas.single.cantidad, 2);
    });

    testWidgets('«Ver transferencias» cierra y le avisa a quien la abrió', (tester) async {
      final arnes = await listaParaEnviar(tester);
      await tocar(tester, botonPrincipal);
      await tocar(tester, botonPrincipal);

      expect(paginaPedir, findsNothing);
      expect(arnes.pedir, [true]);
    });

    testWidgets('mientras envía, el botón está ocupado y un doble toque no pide dos', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..compuerta = Completer<void>();
      final arnes = await listaParaEnviar(tester, repo: repo);
      await traerAlAlcance(tester, botonPrincipal);
      await tester.tap(botonPrincipal);
      await tester.pump();
      await tester.tap(botonPrincipal, warnIfMissed: false);
      await tester.pump();

      expect(find.text('Enviando…'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNull);

      repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(arnes.repo.pedidos, hasLength(1));
      expect(find.text('Transferencia pedida'), findsOneWidget);
    });

    testWidgets('mientras envía, el atrás y el ✕ no cierran la pantalla', (tester) async {
      final repo = TransferenciasEnMemoria()..compuerta = Completer<void>();
      await listaParaEnviar(tester, repo: repo);
      await tocar(tester, botonPrincipal);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(paginaPedir, findsOneWidget);
      repo.compuerta!.complete();
      await asentarAgendar(tester);
    });

    testWidgets('el atrás del sistema en «Transferencia pedida» cierra sin pedir confirmar', (
      tester,
    ) async {
      final arnes = await listaParaEnviar(tester);
      await tocar(tester, botonPrincipal);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(paginaPedir, findsNothing);
      expect(arnes.pedir, [null]);
    });
  });

  group('40A·07 · Sin conexión: queda en cola', () {
    testWidgets('el aviso y el botón lo dicen, y pedir igual guarda la transferencia', (
      tester,
    ) async {
      final arnes = await montarTransferencias(tester, sinConexion: true, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');

      expect(
        find.text('Sin conexión. La transferencia queda en cola y sube sola cuando vuelva.'),
        findsOneWidget,
      );
      expect(find.text('Pedir cuando haya conexión'), findsOneWidget);
      await tocar(tester, botonPrincipal);

      expect(arnes.repo.pedidos, hasLength(1));
      expect(arnes.repo.pedidos.single.enCola, isTrue);
      expect(find.text('Transferencia pedida'), findsOneWidget);
    });

    testWidgets('al volver la conexión el aviso desaparece solo', (tester) async {
      final arnes = await montarTransferencias(tester, sinConexion: true, abrir: 'pedir');
      expect(find.byKey(const Key('pedir_transferencia_sin_conexion')), findsOneWidget);

      arnes.conexion.cambiarA(TipoConexion.wifi);
      await asentarAgendar(tester);

      expect(find.byKey(const Key('pedir_transferencia_sin_conexion')), findsNothing);
    });
  });

  group('40A·08 · Error al enviar', () {
    testWidgets('el aviso, lo elegido queda y el botón vuelve a habilitarse como «Reintentar»', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()
        ..fallas.add(const FailureTransferenciaNoGuardada(causa: 'x'));
      final arnes = await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1', 2);
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);

      expect(find.byKey(const Key('pedir_transferencia_error')), findsOneWidget);
      expect(
        find.text('No pudimos enviar la transferencia. No se envió nada: probá de nuevo.'),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull, reason: 'el botón no queda trabado');
      expect(find.text('Libros · 2'), findsOneWidget, reason: 'lo elegido sigue ahí');
      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(arnes.repo.pedidos, isEmpty);
    });

    testWidgets('reintentar pide la transferencia una sola vez, con el mismo id', (tester) async {
      final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
      final arnes = await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      await tocar(tester, botonPrincipal);

      expect(find.text('Transferencia pedida'), findsOneWidget);
      expect(arnes.repo.pedidos, hasLength(1));
      expect(arnes.repo.pedidos.single.id, 'id-1');
    });

    testWidgets('si la falla es una excepción, tampoco queda el botón ocupado', (tester) async {
      final repo = _RepoQueLanza();
      await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);

      expect(find.byKey(const Key('pedir_transferencia_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
    });

    testWidgets('cambiar lo elegido borra el aviso de la falla de antes', (tester) async {
      final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
      await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      expect(find.byKey(const Key('pedir_transferencia_error')), findsOneWidget);

      await sumar(tester, 'p-3');

      expect(find.byKey(const Key('pedir_transferencia_error')), findsNothing);
      expect(find.text('Pedir transferencia'), findsOneWidget);
    });

    testWidgets('dos fallas seguidas: sigue pudiéndose reintentar', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..fallas.addAll(const [FailureTransferenciaNoGuardada(), FailureTransferenciaNoGuardada()]);
      await montarTransferencias(tester, repo: repo, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      await tocar(tester, botonPrincipal);

      expect(find.byKey(const Key('pedir_transferencia_error')), findsOneWidget);
      expect(elBoton(tester).onPressed, isNotNull);
      await tocar(tester, botonPrincipal);
      expect(find.text('Transferencia pedida'), findsOneWidget);
    });
  });

  group('40A·09 · No hay a quién pedirle', () {
    const sinNadie = CompanierosDeCampania(campania: 'Primavera 2026', companieros: []);

    testWidgets('lo dice y ofrece hacer un pedido a la casa editora cuando esa pantalla existe', (
      tester,
    ) async {
      final arnes = await montarTransferencias(
        tester,
        companieros: CompanierosFalsos(resultado: sinNadie),
        conHacerUnPedido: true,
        abrir: 'pedir',
      );

      expect(find.text('No hay otro colportor en tu campaña'), findsOneWidget);
      expect(find.text('Para sumar materiales, hacé un pedido a la casa editora.'), findsOneWidget);
      await tocar(tester, find.text('Hacer un pedido'));
      expect(arnes.hicieronUnPedido, 1);
    });

    testWidgets('mientras el pedido a la casa editora no esté en la app, el botón solo vuelve', (
      tester,
    ) async {
      final arnes = await montarTransferencias(
        tester,
        companieros: CompanierosFalsos(resultado: sinNadie),
        abrir: 'pedir',
      );
      expect(find.text('Hacer un pedido'), findsNothing);
      await tocar(tester, find.text('Volver'));

      expect(paginaPedir, findsNothing);
      expect(arnes.pedir, [null]);
    });

    testWidgets('el atrás del sistema también cierra, sin preguntar', (tester) async {
      await montarTransferencias(
        tester,
        companieros: CompanierosFalsos(resultado: sinNadie),
        abrir: 'pedir',
      );

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(paginaPedir, findsNothing);
    });
  });

  group('Volver atrás y reentrar', () {
    testWidgets('con algo elegido pregunta antes de descartar; «Seguir escribiendo» queda', (
      tester,
    ) async {
      await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(find.text('Seguir escribiendo'), findsOneWidget);
      await tocar(tester, find.text('Seguir escribiendo'));
      expect(paginaPedir, findsOneWidget);
      expect(find.text('Libros · 1'), findsOneWidget);
    });

    testWidgets('«Descartar» cierra y, al reentrar, la pantalla arranca limpia y con otro id', (
      tester,
    ) async {
      final arnes = await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      await tocar(tester, find.text('Descartar'));
      expect(paginaPedir, findsNothing);

      await abrirPantalla(tester, 'pedir');

      expect(find.text('Libros · 1'), findsNothing);
      expect(find.text('Sumá al menos un material.'), findsOneWidget);
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      expect(arnes.repo.pedidos.single.id, 'id-2');
    });

    testWidgets('sin nada elegido el atrás cierra sin preguntar', (tester) async {
      await montarTransferencias(tester, abrir: 'pedir');

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);

      expect(paginaPedir, findsNothing);
    });

    testWidgets('pedir dos veces seguidas desde el mismo inicio son dos transferencias distintas', (
      tester,
    ) async {
      final arnes = await montarTransferencias(tester, abrir: 'pedir');
      await sumar(tester, 'p-1');
      await elegirColportor(tester, 'Ana Pereira');
      await tocar(tester, botonPrincipal);
      await tocar(tester, botonPrincipal);

      await abrirPantalla(tester, 'pedir');
      await sumar(tester, 'p-3', 3);
      await elegirColportor(tester, 'Bruno Techera');
      await tocar(tester, botonPrincipal);

      expect(arnes.repo.pedidos, hasLength(2));
      expect(
        {for (final t in arnes.repo.pedidos) t.id},
        hasLength(2),
        reason: 'cada una con su id',
      );
      expect(arnes.repo.pedidos.last.origenId, 'bruno');
    });
  });

  group('Datos límite', () {
    for (final escala in [1.0, 2.0]) {
      testWidgets('textScaler $escala: ningún estado se desborda', (tester) async {
        final repo = TransferenciasEnMemoria()..fallas.add(const FailureTransferenciaNoGuardada());
        await montarTransferencias(
          tester,
          repo: repo,
          escala: escala,
          sinConexion: true,
          tamano: const Size(360, 640),
          abrir: 'pedir',
        );
        await sumar(tester, 'p-1', 2);
        await elegirColportor(tester, 'Ana Pereira');
        await tocar(tester, botonPrincipal);
        expect(tester.takeException(), isNull);
        await tocar(tester, botonPrincipal);
        expect(find.text('Transferencia pedida'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('nombres larguísimos y 40 materiales: se leen y se desplazan sin desbordar', (
      tester,
    ) async {
      final largos = [
        for (var i = 0; i < 40; i++)
          MaterialDeTransferencia(
            id: 'x-$i',
            nombre:
                'Un material con un nombre larguísimo para probar el recorte número $i de la lista',
            categoria: materialesDelCanvas.first.categoria,
            tengo: i,
          ),
      ];
      final falsos = CompanierosFalsos(
        resultado: const CompanierosDeCampania(
          campania: 'Primavera 2026 con un nombre muy pero muy largo de campaña',
          companieros: [
            CompanieroDeCampania(
              id: 'ana',
              nombre: 'Ana María de los Ángeles Pereira Techera de Silva',
              lugar: 'Tranqueras, departamento de Rivera, zona norte',
            ),
          ],
        ),
      );
      await montarTransferencias(
        tester,
        materiales: largos,
        companieros: falsos,
        escala: 2,
        tamano: const Size(360, 640),
        abrir: 'pedir',
      );
      await sumar(tester, 'x-39', 3);
      await tocar(tester, tarjetaDeColportor);
      expect(tester.takeException(), isNull);
      await tocar(tester, find.textContaining('Ana María'));
      await tocar(tester, listoDelSelector);

      expect(tester.takeException(), isNull);
      expect(elBoton(tester).onPressed, isNotNull);
    });
  });
}

/// Un repositorio cuyo `pedir` lanza una excepción en vez de devolver una falla.
class _RepoQueLanza extends TransferenciasEnMemoria {
  @override
  Future<Either<Failure, TransferenciaPedida>> pedir(Transferencia transferencia) async =>
      throw StateError('falló');
}
