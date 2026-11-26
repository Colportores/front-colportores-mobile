// «Transferencias» (vista 40 B, HU-STK-005, #512): la lista de las dos puntas y el detalle (40B·01 a
// 40B·11) con los casos límite de cada flujo.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/item_de_precio.dart'
    show CategoriaDePrecios;
import 'package:colportores_mobile/features/transferencias/domain/entities/companiero_de_campania.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/material_de_transferencia.dart';
import 'package:colportores_mobile/features/transferencias/domain/entities/transferencia.dart';
import 'package:colportores_mobile/features/transferencias/presentation/pages/detalle_de_transferencia_page.dart';
import 'package:dartz/dartz.dart' show Either;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/agendar_visita_arnes.dart' show asentarAgendar;
import '../../helpers/transferencias_arnes.dart';
import '../../helpers/transferencias_en_memoria.dart';

/// Hoy 14:35 en Montevideo = 17:35 UTC; el «ahora» del arnés es hoy 15:00.
DateTime _hoy([int hora = 17, int minuto = 35]) => DateTime.utc(2026, 10, 23, hora, minuto);

/// Las cinco filas de 40B·01.
TransferenciasEnMemoria _repoDelCanvas() => TransferenciasEnMemoria()
  ..sembrar(transferenciaDeEjemplo(id: 't-1', creada: _hoy()))
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-2',
      origen: 'juan',
      destino: 'bruno',
      solicitante: 'bruno',
      creada: DateTime.utc(2026, 10, 22, 15),
      lineas: const [LineaDeTransferencia(id: 'l-2', productoId: 'p-3', cantidad: 10)],
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-3',
      estado: EstadoDeTransferencia.autorizada,
      creada: DateTime.utc(2026, 10, 15, 12),
      lineas: const [LineaDeTransferencia(id: 'l-3', productoId: 'p-2', cantidad: 1)],
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-4',
      origen: 'bruno',
      estado: EstadoDeTransferencia.rechazada,
      creada: DateTime.utc(2026, 10, 9, 12),
      lineas: const [LineaDeTransferencia(id: 'l-4', productoId: 'p-1', cantidad: 4)],
      motivoRechazo: 'Ana los necesita esta semana',
    ),
  )
  ..sembrar(
    transferenciaDeEjemplo(
      id: 't-5',
      origen: 'juan',
      destino: 'vale',
      solicitante: 'vale',
      estado: EstadoDeTransferencia.cancelada,
      creada: DateTime.utc(2026, 10, 2, 12),
      lineas: const [LineaDeTransferencia(id: 'l-5', productoId: 'p-3', cantidad: 6)],
    ),
  );

void main() {
  group('40B·01 · Las que pedí y las que me piden', () {
    testWidgets('una sola lista para las dos puntas, con quién le pidió a quién y su estado', (
      tester,
    ) async {
      await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'lista');

      expect(find.text('Transferencias'), findsOneWidget);
      expect(find.text('MI CUENTA'), findsOneWidget);
      expect(find.text('HOY · LE PEDISTE A ANA PEREIRA'), findsOneWidget);
      expect(find.text('AYER · TE PIDIÓ BRUNO TECHERA'), findsOneWidget);
      expect(find.text('15/10 · LE PEDISTE A ANA PEREIRA'), findsOneWidget);
      expect(find.text('09/10 · LE PEDISTE A BRUNO TECHERA'), findsOneWidget);
      expect(find.text('02/10 · TE PIDIÓ VALENTINA SILVA'), findsOneWidget);
      expect(find.text('Salud y Hogar × 2'), findsOneWidget);
      expect(find.text('Vida Feliz × 10'), findsOneWidget);
      expect(find.text('Nuestros Hijos × 1'), findsOneWidget);
      expect(find.text('Por autorizar'), findsNWidgets(3), reason: 'el chip y las dos filas');
      expect(find.text('Autorizada'), findsOneWidget);
      expect(find.text('Rechazada'), findsOneWidget);
      expect(find.text('Cancelada'), findsOneWidget);
      expect(find.text('+ Pedir transferencia'), findsOneWidget);
    });

    testWidgets(
      'los filtros dejan solo lo que dicen; «Cerradas» son las rechazadas y las canceladas',
      (tester) async {
        await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'lista');

        await tocar(tester, find.byKey(const Key('transferencias_filtro_porAutorizar')));
        expect(find.byKey(const Key('transferencia_t-1')), findsOneWidget);
        expect(find.byKey(const Key('transferencia_t-2')), findsOneWidget);
        expect(find.byKey(const Key('transferencia_t-3')), findsNothing);

        await tocar(tester, find.byKey(const Key('transferencias_filtro_autorizadas')));
        expect(find.byKey(const Key('transferencia_t-3')), findsOneWidget);
        expect(find.byKey(const Key('transferencia_t-1')), findsNothing);

        await tocar(tester, find.byKey(const Key('transferencias_filtro_cerradas')));
        expect(find.byKey(const Key('transferencia_t-4')), findsOneWidget);
        expect(find.byKey(const Key('transferencia_t-5')), findsOneWidget);
        expect(find.byKey(const Key('transferencia_t-3')), findsNothing);

        await tocar(tester, find.byKey(const Key('transferencias_filtro_todas')));
        expect(find.byKey(const Key('transferencia_t-1')), findsOneWidget);
      },
    );

    testWidgets('un filtro sin ninguna lo dice en vez de dejar la pantalla en blanco', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo());
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      await tocar(tester, find.byKey(const Key('transferencias_filtro_cerradas')));

      expect(find.byKey(const Key('transferencias_filtro_vacio')), findsOneWidget);
      expect(find.text('No hay transferencias con este filtro.'), findsOneWidget);
    });

    testWidgets('la que todavía no subió dice «En cola»', (tester) async {
      final repo = TransferenciasEnMemoria();
      await repo.pedir(
        Transferencia(
          id: 't-9',
          origenId: 'ana',
          destinoId: 'juan',
          estado: EstadoDeTransferencia.porAutorizar,
          lineas: const [LineaDeTransferencia(id: 'l-9', productoId: 'p-1', cantidad: 2)],
          auditoria: transferenciaDeEjemplo(creada: _hoy()).auditoria,
        ),
      );
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(find.text('En cola'), findsOneWidget);
      expect(find.text('HOY · LE PEDISTE A ANA PEREIRA'), findsOneWidget);
    });

    testWidgets('la que armó la coordinadora dice quién entrega o recibe', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(id: 't-c', solicitante: null, creador: 'marta', creada: _hoy()),
        )
        ..sembrar(
          transferenciaDeEjemplo(
            id: 't-d',
            origen: 'juan',
            destino: 'bruno',
            solicitante: null,
            creador: 'marta',
            creada: DateTime.utc(2026, 10, 22, 15),
          ),
        );
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(
        find.textContaining('TU COORDINADORA LA ARMÓ: TE ENTREGA ANA PEREIRA'),
        findsOneWidget,
      );
      expect(
        find.textContaining('TU COORDINADORA LA ARMÓ: LE ENTREGÁS A BRUNO TECHERA'),
        findsOneWidget,
      );
    });

    testWidgets('con varias líneas el título dice cuántas más hay', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(
            lineas: const [
              LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 2),
              LineaDeTransferencia(id: 'l-2', productoId: 'p-2', cantidad: 1),
              LineaDeTransferencia(id: 'l-3', productoId: 'p-3', cantidad: 5),
            ],
          ),
        );
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(find.text('Salud y Hogar × 2 y 2 más'), findsOneWidget);
    });

    testWidgets('sin el nombre de la otra punta (el servidor no lo dio) dice «otro colportor»', (
      tester,
    ) async {
      await montarTransferencias(
        tester,
        repo: TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo(creada: _hoy())),
        companieros: CompanierosFalsos(),
        abrir: 'lista',
      );

      expect(find.text('HOY · LE PEDISTE A OTRO COLPORTOR'), findsOneWidget);
    });

    testWidgets(
      'un producto que no está en el catálogo se llama «Material» y la fila no se rompe',
      (tester) async {
        final repo = TransferenciasEnMemoria()
          ..sembrar(
            transferenciaDeEjemplo(
              lineas: const [LineaDeTransferencia(id: 'l-1', productoId: 'p-borrado', cantidad: 3)],
            ),
          );
        await montarTransferencias(tester, repo: repo, abrir: 'lista');

        expect(find.text('Material × 3'), findsOneWidget);
      },
    );

    testWidgets('una transferencia cuyas líneas todavía no bajaron no rompe la lista', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo(lineas: const []));
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(find.text('Materiales sin detallar'), findsOneWidget);
    });
  });

  group('40B·08, 40B·09, 40B·10 y 40B·11 · Vacía, cargando, error y sin conexión', () {
    testWidgets('40B·08: sin transferencias dice qué hacer', (tester) async {
      await montarTransferencias(tester, abrir: 'lista');

      expect(find.text('Todavía no hay transferencias'), findsOneWidget);
      expect(
        find.text('Si te falta un material y otro colportor de tu campaña tiene, pedíselo acá.'),
        findsOneWidget,
      );
      expect(find.text('Todas'), findsNothing, reason: 'sin filas no hay filtros');
    });

    testWidgets('40B·09: mientras se lee, tres bloques grises y no «todavía no hay»', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()..compuertaDeLectura = Completer<void>();
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(find.byKey(const Key('transferencias_cargando')), findsOneWidget);
      expect(find.text('Todavía no hay transferencias'), findsNothing);

      repo.compuertaDeLectura!.complete();
      await asentarAgendar(tester);
      expect(find.byKey(const Key('transferencias_cargando')), findsNothing);
    });

    testWidgets('40B·10: si no se puede leer, el error con «Reintentar», nunca «todavía no hay»', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()
        ..errorDeLectura = const FailureTransferenciasNoDisponibles();
      await montarTransferencias(tester, repo: repo, abrir: 'lista');

      expect(find.byKey(const Key('transferencias_error')), findsOneWidget);
      expect(find.text('No pudimos traer tus transferencias.'), findsOneWidget);
      expect(find.text('Todavía no hay transferencias'), findsNothing);

      repo
        ..errorDeLectura = null
        ..sembrar(transferenciaDeEjemplo(creada: _hoy()));
      await tocar(tester, find.text('Reintentar'));

      expect(find.byKey(const Key('transferencias_error')), findsNothing);
      expect(find.text('Salud y Hogar × 2'), findsOneWidget);
    });

    testWidgets('40B·11: sin conexión se ven las del teléfono con la hora de la última bajada', (
      tester,
    ) async {
      await montarTransferencias(
        tester,
        repo: _repoDelCanvas(),
        sinConexion: true,
        ultimaBajada: DateTime.utc(2026, 10, 23),
        abrir: 'lista',
      );

      expect(find.byKey(const Key('transferencias_sin_conexion')), findsOneWidget);
      expect(
        find.text('Sin conexión. Ves las transferencias como estaban ayer a las 21:00.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('transferencia_t-1')), findsOneWidget);
    });

    testWidgets('40B·11 sin ninguna bajada guardada no afirma ninguna hora', (tester) async {
      await montarTransferencias(tester, repo: _repoDelCanvas(), sinConexion: true, abrir: 'lista');

      expect(
        find.text('Sin conexión. Ves las transferencias que tenés en el teléfono.'),
        findsOneWidget,
      );
    });

    testWidgets('con muchas transferencias y letra 2.0 se desplaza sin desbordar', (tester) async {
      final repo = TransferenciasEnMemoria();
      for (var i = 0; i < 60; i++) {
        repo.sembrar(
          transferenciaDeEjemplo(
            id: 't-$i',
            creada: DateTime.utc(2026, 9, 1).add(Duration(hours: i)),
            lineas: [LineaDeTransferencia(id: 'l-$i', productoId: 'p-1', cantidad: i + 1)],
          ),
        );
      }
      await montarTransferencias(
        tester,
        repo: repo,
        escala: 2,
        tamano: const Size(360, 640),
        companieros: CompanierosFalsos(
          resultado: const CompanierosDeCampania(
            campania: 'X',
            companieros: [
              CompanieroDeCampania(
                id: 'ana',
                nombre: 'Ana María de los Ángeles Pereira Techera de Silva Larrañaga',
              ),
            ],
          ),
        ),
        abrir: 'lista',
      );

      await traerAlAlcance(tester, find.byKey(const Key('transferencia_t-0')));
      expect(tester.takeException(), isNull);
    });
  });

  group('Abrir y volver', () {
    testWidgets('una fila abre su detalle y el atrás vuelve a la lista', (tester) async {
      await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'lista');

      await tocar(tester, find.byKey(const Key('transferencia_t-1')));
      expect(paginaDetalle, findsOneWidget);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaDetalle, findsNothing);
      expect(paginaLista, findsOneWidget);
    });

    testWidgets('un doble toque en una fila no abre dos detalles', (tester) async {
      await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'lista');
      await traerAlAlcance(tester, find.byKey(const Key('transferencia_t-1')));
      await tester.tap(find.byKey(const Key('transferencia_t-1')));
      await tester.tap(find.byKey(const Key('transferencia_t-1')), warnIfMissed: false);
      await asentarAgendar(tester);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaLista, findsOneWidget, reason: 'un solo atrás vuelve a la lista');
    });

    testWidgets(
      '«+ Pedir transferencia» abre la pantalla de pedir y, al pedir, la lista la muestra «En cola»',
      (tester) async {
        final arnes = await montarTransferencias(tester, abrir: 'lista');
        await tocar(tester, find.text('+ Pedir transferencia'));
        expect(paginaPedir, findsOneWidget);

        await sumar(tester, 'p-1');
        await elegirColportor(tester, 'Ana Pereira');
        await tocar(tester, botonPrincipal);
        await tocar(tester, botonPrincipal);

        expect(paginaPedir, findsNothing);
        expect(arnes.repo.pedidos, hasLength(1));
        expect(find.text('En cola'), findsOneWidget);
        expect(find.text('Salud y Hogar × 1'), findsOneWidget);
      },
    );

    testWidgets('lo que la coordinadora decide mientras se mira aparece solo', (tester) async {
      final repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo(creada: _hoy()));
      await montarTransferencias(tester, repo: repo, abrir: 'lista');
      expect(find.text('Por autorizar'), findsNWidgets(2));

      repo.sembrar(
        transferenciaDeEjemplo(estado: EstadoDeTransferencia.autorizada, creada: _hoy()),
      );
      await asentarAgendar(tester);

      expect(find.text('Autorizada'), findsOneWidget);
    });
  });

  group('40B·02 · Detalle: por autorizar, la pedí yo', () {
    testWidgets('dice que la coordinadora todavía no la autorizó, quién pide y quién entrega', (
      tester,
    ) async {
      await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'detalle');

      expect(find.text('TRANSFERENCIA DE HOY'), findsOneWidget);
      expect(find.text('Salud y Hogar × 2'), findsOneWidget);
      expect(find.text('Por autorizar'), findsOneWidget);
      expect(find.text('Tu coordinadora todavía no la autorizó.'), findsOneWidget);
      expect(find.text('Pide'), findsOneWidget);
      expect(find.text('Vos'), findsOneWidget);
      expect(find.text('Entrega'), findsOneWidget);
      expect(find.text('Ana Pereira'), findsOneWidget);
      expect(find.text('Pedida'), findsOneWidget);
      expect(find.text('hoy 14:35'), findsOneWidget);
      expect(find.text('Cancelar transferencia'), findsOneWidget);
    });

    testWidgets('con varias líneas el detalle las lista una por una', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(
            creada: _hoy(),
            lineas: const [
              LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 2),
              LineaDeTransferencia(id: 'l-2', productoId: 'p-2', cantidad: 7),
            ],
          ),
        );
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Salud y Hogar × 2 y 1 más'), findsOneWidget);
      expect(find.text('Nuestros Hijos'), findsOneWidget);
      expect(find.text('× 7'), findsOneWidget);
    });

    testWidgets('la que todavía no subió lo dice', (tester) async {
      final repo = TransferenciasEnMemoria();
      await repo.pedir(
        Transferencia(
          id: 't-1',
          origenId: 'ana',
          destinoId: 'juan',
          estado: EstadoDeTransferencia.porAutorizar,
          lineas: const [LineaDeTransferencia(id: 'l-1', productoId: 'p-1', cantidad: 2)],
          auditoria: transferenciaDeEjemplo(creada: _hoy()).auditoria,
        ),
      );
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('En cola'), findsOneWidget);
      expect(
        find.text('Todavía no salió de tu teléfono. Sube sola cuando haya conexión.'),
        findsOneWidget,
      );
      expect(
        find.text('Cancelar transferencia'),
        findsOneWidget,
        reason: 'se puede cancelar antes de subir',
      );
    });

    testWidgets('si no está en el teléfono, lo dice y no rompe', (tester) async {
      await montarTransferencias(tester, transferenciaId: 'nada', abrir: 'detalle');

      expect(find.byKey(const Key('detalle_transferencia_ausente')), findsOneWidget);
      expect(botonCancelar, findsNothing);
    });

    testWidgets('si no se puede leer, el error con «Reintentar»', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..errorDeLectura = const FailureTransferenciasNoDisponibles();
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.byKey(const Key('detalle_transferencia_error')), findsOneWidget);
    });
  });

  group('40B·03 y 40B·04 · Cancelar', () {
    Future<ArnesTransferencias> enElDetalle(WidgetTester tester, {TransferenciasEnMemoria? repo}) =>
        montarTransferencias(tester, repo: repo ?? _repoDelCanvas(), abrir: 'detalle');

    testWidgets('la hoja explica qué pasa y ofrece «Cancelar transferencia» o «Volver»', (
      tester,
    ) async {
      await enElDetalle(tester);
      await tocar(tester, botonCancelar);

      expect(find.text('¿Cancelar la transferencia?'), findsOneWidget);
      expect(
        find.text(
          'Ana Pereira y tu coordinadora dejan de verla como pendiente. Si la necesitás después, la pedís de nuevo.',
        ),
        findsOneWidget,
      );
      expect(cancelarSi, findsOneWidget);
      expect(cancelarNo, findsOneWidget);
    });

    testWidgets('«Volver» no cancela nada', (tester) async {
      final arnes = await enElDetalle(tester);
      await tocar(tester, botonCancelar);
      await tocar(tester, cancelarNo);

      expect(paginaDetalle, findsOneWidget);
      expect(arnes.repo.cancelaciones, 0);
      expect(arnes.repo['t-1']!.estado, EstadoDeTransferencia.porAutorizar);
    });

    testWidgets(
      'confirmar la pasa a cancelada, cierra el detalle y la lista avisa «Transferencia cancelada.»',
      (tester) async {
        final arnes = await montarTransferencias(tester, repo: _repoDelCanvas(), abrir: 'lista');
        await tocar(tester, find.byKey(const Key('transferencia_t-1')));
        await tocar(tester, botonCancelar);
        await tocar(tester, cancelarSi);

        expect(arnes.repo['t-1']!.estado, EstadoDeTransferencia.cancelada);
        expect(paginaDetalle, findsNothing);
        expect(find.text('Transferencia cancelada.'), findsOneWidget);
        expect(find.text('Cancelada'), findsNWidgets(2), reason: 'la fila de t-1 y la de t-5');
      },
    );

    testWidgets('el detalle devuelve «cancelada» a quien lo abrió', (tester) async {
      final arnes = await enElDetalle(tester);
      await tocar(tester, botonCancelar);
      await tocar(tester, cancelarSi);

      expect(arnes.detalle, [SalidaDelDetalle.cancelada]);
    });

    testWidgets('un doble toque en «Cancelar transferencia» no cancela dos veces', (tester) async {
      final repo = _repoDelCanvas()..compuerta = Completer<void>();
      final arnes = await enElDetalle(tester, repo: repo);
      await tocar(tester, botonCancelar);
      await tester.tap(cancelarSi);
      await tester.pump();
      await tester.tap(cancelarSi, warnIfMissed: false);
      await tester.pump();

      expect(find.text('Cancelando…'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(botonCancelar).onPressed, isNull);

      repo.compuerta!.complete();
      await asentarAgendar(tester);
      expect(arnes.repo.cancelaciones, 1);
    });

    testWidgets('mientras cancela, el atrás no cierra el detalle', (tester) async {
      final repo = _repoDelCanvas()..compuerta = Completer<void>();
      await enElDetalle(tester, repo: repo);
      await tocar(tester, botonCancelar);
      await tocar(tester, cancelarSi);

      await tester.binding.handlePopRoute();
      await asentarAgendar(tester);
      expect(paginaDetalle, findsOneWidget);

      repo.compuerta!.complete();
      await asentarAgendar(tester);
    });

    testWidgets(
      'falla a mitad: el botón vuelve a habilitarse, la transferencia sigue por autorizar y se reintenta',
      (tester) async {
        final repo = _repoDelCanvas()
          ..fallas.add(const FailureTransferenciaNoCancelada(causa: 'x'));
        final arnes = await enElDetalle(tester, repo: repo);
        await tocar(tester, botonCancelar);
        await tocar(tester, cancelarSi);

        expect(find.byKey(const Key('detalle_transferencia_falla')), findsOneWidget);
        expect(
          find.text('No pudimos cancelar la transferencia. Sigue por autorizar: probá de nuevo.'),
          findsOneWidget,
        );
        expect(
          tester.widget<OutlinedButton>(botonCancelar).onPressed,
          isNotNull,
          reason: 'no queda trabado',
        );
        expect(find.text('Cancelar transferencia'), findsWidgets);
        expect(arnes.repo['t-1']!.estado, EstadoDeTransferencia.porAutorizar);

        await tocar(tester, botonCancelar);
        await tocar(tester, cancelarSi);
        expect(arnes.repo['t-1']!.estado, EstadoDeTransferencia.cancelada);
        expect(paginaDetalle, findsNothing);
      },
    );

    testWidgets('si hasta una excepción corta la cancelación, el botón vuelve a habilitarse', (
      tester,
    ) async {
      final repo = _RepoQueLanzaAlCancelar()..sembrar(transferenciaDeEjemplo(creada: _hoy()));
      await enElDetalle(tester, repo: repo);
      await tocar(tester, botonCancelar);
      await tocar(tester, cancelarSi);

      expect(find.byKey(const Key('detalle_transferencia_falla')), findsOneWidget);
      expect(tester.widget<OutlinedButton>(botonCancelar).onPressed, isNotNull);
    });

    testWidgets(
      'la coordinadora ya la había decidido: lo dice, se ve su estado y ya no hay «Cancelar»',
      (tester) async {
        final repo = _repoDelCanvas()..fallas.add(const FailureTransferenciaNoCancelable());
        await enElDetalle(tester, repo: repo);
        await tocar(tester, botonCancelar);
        repo.sembrar(
          transferenciaDeEjemplo(estado: EstadoDeTransferencia.autorizada, creada: _hoy()),
        );
        await tocar(tester, cancelarSi);

        expect(
          find.text('Tu coordinadora ya la decidió: ya no se puede cancelar.'),
          findsOneWidget,
        );
        expect(botonCancelar, findsNothing);
        expect(find.text('Autorizada el'), findsNothing);
        expect(find.text('Autorizada'), findsOneWidget);
      },
    );

    testWidgets('la decide la coordinadora mientras se mira: el botón desaparece solo', (
      tester,
    ) async {
      final repo = _repoDelCanvas();
      await enElDetalle(tester, repo: repo);
      expect(botonCancelar, findsOneWidget);

      repo.sembrar(
        transferenciaDeEjemplo(
          estado: EstadoDeTransferencia.rechazada,
          creada: _hoy(),
          motivoRechazo: 'No hay',
        ),
      );
      await asentarAgendar(tester);

      expect(botonCancelar, findsNothing);
    });

    testWidgets(
      'abrir el mismo detalle otra vez después de cancelar la muestra cancelada, sin botón',
      (tester) async {
        final arnes = await enElDetalle(tester);
        await tocar(tester, botonCancelar);
        await tocar(tester, cancelarSi);

        await abrirPantalla(tester, 'detalle');

        expect(find.text('La cancelaron: nadie tiene que hacer nada.'), findsOneWidget);
        expect(botonCancelar, findsNothing);
        expect(arnes.repo.cancelaciones, 1);
      },
    );
  });

  group('40B·05 a 40B·07 · Autorizada, rechazada y me piden a mí', () {
    testWidgets('40B·05 autorizada: coordinar la entrega, con quién y cuándo se decidió', (
      tester,
    ) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(
            estado: EstadoDeTransferencia.autorizada,
            creada: _hoy(),
            decididoEn: DateTime.utc(2026, 10, 23, 12, 12),
          ),
        );
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Autorizada el 23/10 · 09:12'), findsOneWidget);
      expect(
        find.text('Tu coordinadora la autorizó. Coordiná con Ana Pereira la entrega.'),
        findsOneWidget,
      );
      expect(botonCancelar, findsNothing, reason: 'autorizada ya no se cancela');
      expect(botonPrincipal, findsNothing);
    });

    testWidgets('40B·06 rechazada: el motivo de la coordinadora y «Pedir otra»', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(
          transferenciaDeEjemplo(
            estado: EstadoDeTransferencia.rechazada,
            creada: _hoy(),
            decididoEn: DateTime.utc(2026, 10, 23, 12, 12),
            motivoRechazo: 'Ana los necesita esta semana',
          ),
        );
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Rechazada el 23/10 · 09:12'), findsOneWidget);
      expect(
        find.text('Tu coordinadora no la autorizó: «Ana los necesita esta semana».'),
        findsOneWidget,
      );
      expect(botonCancelar, findsNothing);
      expect(find.text('Pedir otra'), findsOneWidget);
    });

    testWidgets(
      '«Pedir otra» abre la pantalla de pedir; al terminar con «Ver transferencias» vuelve a la lista',
      (tester) async {
        final repo = TransferenciasEnMemoria()
          ..sembrar(
            transferenciaDeEjemplo(
              estado: EstadoDeTransferencia.rechazada,
              creada: _hoy(),
              motivoRechazo: 'No',
            ),
          );
        await montarTransferencias(tester, repo: repo, abrir: 'detalle');
        await tocar(tester, find.text('Pedir otra'));
        expect(paginaPedir, findsOneWidget);

        await sumar(tester, 'p-1');
        await elegirColportor(tester, 'Ana Pereira');
        await tocar(tester, botonPrincipal);
        await tocar(tester, botonPrincipal);

        expect(paginaPedir, findsNothing);
        expect(paginaDetalle, findsNothing);
      },
    );

    testWidgets('rechazada sin motivo no inventa uno', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(transferenciaDeEjemplo(estado: EstadoDeTransferencia.rechazada, creada: _hoy()));
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Tu coordinadora no la autorizó.'), findsOneWidget);
    });

    testWidgets(
      '40B·07 me piden a mí: lo que ve quien entrega, con lo que tiene hoy y sin botones',
      (tester) async {
        final repo = TransferenciasEnMemoria()..sembrar(transferenciaDeEjemplo(creada: _hoy()));
        await montarTransferencias(
          tester,
          repo: repo,
          colportor: 'ana',
          companieros: CompanierosFalsos(
            resultado: const CompanierosDeCampania(
              campania: 'Primavera 2026',
              companieros: [CompanieroDeCampania(id: 'juan', nombre: 'Juan Duarte')],
            ),
          ),
          materiales: const [
            MaterialDeTransferencia(
              id: 'p-1',
              nombre: 'Salud y Hogar',
              categoria: CategoriaDePrecios.libros,
              tengo: 6,
            ),
          ],
          abrir: 'detalle',
        );

        expect(find.text('Te la pidió Juan Duarte · por autorizar'), findsOneWidget);
        expect(
          find.text('Si tu coordinadora la autoriza, salen de lo que tenés. Hoy tenés 6.'),
          findsOneWidget,
        );
        expect(find.text('Juan Duarte'), findsOneWidget);
        expect(find.text('Ana Pereira (vos)'), findsNothing);
        expect(botonCancelar, findsNothing, reason: 'quien entrega solo la ve');
        expect(botonPrincipal, findsNothing);
      },
    );

    testWidgets('la que armó la coordinadora no se cancela desde el teléfono', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(transferenciaDeEjemplo(solicitante: null, creador: 'marta', creada: _hoy()));
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Tu coordinadora todavía no la autorizó.'), findsOneWidget);
      expect(botonCancelar, findsNothing);
    });

    testWidgets('cancelada: la lista la muestra y el detalle no ofrece nada', (tester) async {
      final repo = TransferenciasEnMemoria()
        ..sembrar(transferenciaDeEjemplo(estado: EstadoDeTransferencia.cancelada, creada: _hoy()));
      await montarTransferencias(tester, repo: repo, abrir: 'detalle');

      expect(find.text('Cancelada'), findsOneWidget);
      expect(botonCancelar, findsNothing);
    });

    for (final escala in [1.0, 2.0]) {
      testWidgets('textScaler $escala: el detalle con motivo larguísimo no se desborda', (
        tester,
      ) async {
        final repo = TransferenciasEnMemoria()
          ..sembrar(
            transferenciaDeEjemplo(
              estado: EstadoDeTransferencia.rechazada,
              creada: _hoy(),
              motivoRechazo:
                  'Ana necesita todos los libros esta semana para la feria de la plaza. ' * 6,
              lineas: [
                for (var i = 1; i <= 3; i++)
                  LineaDeTransferencia(id: 'l-$i', productoId: 'p-$i', cantidad: i),
              ],
            ),
          );
        await montarTransferencias(
          tester,
          repo: repo,
          escala: escala,
          tamano: const Size(360, 640),
          abrir: 'detalle',
        );

        expect(tester.takeException(), isNull);
        await traerAlAlcance(tester, find.text('Pedir otra'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

class _RepoQueLanzaAlCancelar extends TransferenciasEnMemoria {
  @override
  Future<Either<Failure, Transferencia>> cancelar({
    required String id,
    required String colportorId,
    required DateTime ahora,
  }) async => throw StateError('falló');
}
