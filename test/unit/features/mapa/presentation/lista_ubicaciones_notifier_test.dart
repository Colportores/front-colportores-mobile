// HU-UBI-002 / vista 05: las reglas de la lista (reactividad, filtros, búsqueda, orden, páginas de
// 50, errores y GPS) sin widgets ni plugins.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/estado_casa.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion_con_resumen.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart';
import 'package:colportores_mobile/features/mapa/presentation/providers/lista_ubicaciones_notifier.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../../helpers/alta_ubicacion_falsos.dart';
import '../../../../helpers/lista_ubicaciones_falsos.dart';

final class _Banco {
  _Banco({RepoListaFalso? repo, GpsFalso? gps})
    : repo = repo ?? RepoListaFalso(),
      gps = gps ?? GpsFalso() {
    contenedor = ProviderContainer(
      overrides: overridesLista(repo: this.repo, gps: this.gps),
    );
    contenedor.listen(proveedor, (_, _) {});
  }

  final RepoListaFalso repo;
  final GpsFalso gps;
  late final ProviderContainer contenedor;
  final proveedor = listaUbicacionesProvider('col-1');

  ListaUbicacionesState get estado => contenedor.read(proveedor);
  ListaUbicacionesNotifier get notificador => contenedor.read(proveedor.notifier);

  List<String> get ids => [for (final i in estado.lista!.items) i.ubicacion.id];

  void cerrar() => contenedor.dispose();
}

/// Un banco con [repo] y el ciclo de vida del test.
_Banco _banco({RepoListaFalso? repo, GpsFalso? gps}) {
  final b = _Banco(repo: repo, gps: gps);
  addTearDown(b.cerrar);
  return b;
}

/// Deja correr los microtasks y los eventos pendientes (la base emite en el turno siguiente).
Future<void> _esperar() => pumpEventQueue();

void main() {
  final tres = [
    filaLista('casa-1', calle: 'Rivadavia', numero: '100', hace: const Duration(hours: 1)),
    filaLista(
      'neg-1',
      tipo: TipoUbicacion.negocio,
      calle: 'Colonia',
      numero: '2020',
      hace: const Duration(hours: 5),
    ),
    filaLista(
      'edi-1',
      tipo: TipoUbicacion.edificio,
      calle: 'Rivadavia',
      numero: '350',
      hace: const Duration(days: 2),
    ),
  ];

  group('lectura', () {
    test(
      'dado que la pestaña se monta, cuando todavía no llegó la lista, entonces está cargando',
      () {
        final b = _banco(repo: RepoListaFalso(tres));

        expect(b.estado.cargando, isTrue);
        expect(b.estado.lista, isNull);
        expect(b.estado.fallaLectura, isFalse);
      },
    );

    test(
      'dado que la base emite, cuando llega la primera lista, entonces se muestra por recientes',
      () async {
        final b = _banco(repo: RepoListaFalso(tres));

        await _esperar();

        expect(b.estado.cargando, isFalse);
        expect(b.ids, ['casa-1', 'neg-1', 'edi-1']);
        expect(b.estado.lista!.total, 3);
        expect(b.estado.lista!.totalGeneral, 3);
        expect(b.repo.pedidos.single, (colportorId: 'col-1', incluirBajas: false));
      },
    );

    test(
      'dado que no hay ubicaciones, entonces la lista llega vacía y marca el estado vacío',
      () async {
        final b = _banco();

        await _esperar();

        expect(b.estado.lista!.sinUbicaciones, isTrue);
        expect(b.estado.lista!.sinResultados, isFalse);
      },
    );

    test('dado una alta, cuando la base vuelve a emitir, entonces la lista se actualiza sola y sin '
        'abrir otra suscripción (§8.8)', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.repo.emitir([filaLista('nueva', hace: Duration.zero), ...tres]);
      await _esperar();

      expect(b.ids.first, 'nueva');
      expect(b.estado.lista!.total, 4);
      expect(b.repo.suscripciones, 1);
    });

    test('dado que una baja sale de la lista, cuando la base emite, entonces desaparece', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.repo.emitir([tres[0], tres[2]]);
      await _esperar();

      expect(b.ids, ['casa-1', 'edi-1']);
    });

    test('dado que se cierra la pantalla, entonces la suscripción se cancela', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();
      expect(b.repo.activas, 1);

      b.cerrar();
      await _esperar();

      expect(b.repo.activas, 0);
    });

    test('dado que la pantalla se cierra antes de que llegue la primera lista, entonces no se abre '
        'ninguna suscripción', () async {
      final b = _banco(repo: RepoListaFalso(tres));

      b.cerrar();
      await _esperar();

      expect(b.repo.suscripciones, 0);
    });
  });

  group('errores de lectura', () {
    test('dado que la base falla al leer, cuando no hay lista, entonces marca el error', () async {
      final repo = RepoListaFalso(tres)..fallaAlSuscribir = true;
      final b = _banco(repo: repo);

      await _esperar();

      expect(b.estado.fallaLectura, isTrue);
      expect(b.estado.lista, isNull);
      expect(b.estado.cargando, isFalse);
    });

    test(
      'dado el error, cuando se toca «Reintentar», entonces vuelve a leer y se recupera',
      () async {
        final repo = RepoListaFalso(tres)..fallaAlSuscribir = true;
        final b = _banco(repo: repo);
        await _esperar();

        repo.fallaAlSuscribir = false;
        b.notificador.reintentar();
        await _esperar();

        expect(b.estado.fallaLectura, isFalse);
        expect(b.ids, hasLength(3));
        expect(repo.activas, 1);
      },
    );

    test('dado un error con la lista ya a la vista, entonces la lista se conserva', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.repo.fallar(StateError('se cerró la base'));
      await _esperar();

      expect(b.estado.fallaLectura, isTrue);
      expect(b.ids, hasLength(3));

      b.repo.emitir(tres);
      await _esperar();

      expect(b.estado.fallaLectura, isFalse);
    });

    test(
      'dado que no hay base abierta (el repositorio lanza al pedir), entonces no se rompe: marca '
      'el error y se recupera al reintentar',
      () async {
        final repo = RepoListaFalso(tres)..lanzaAlPedir = StateError('sin base');
        final b = _banco(repo: repo);

        await _esperar();

        expect(b.estado.fallaLectura, isTrue);
        expect(b.estado.cargando, isFalse);

        repo.lanzaAlPedir = null;
        b.notificador.reintentar();
        await _esperar();

        expect(b.estado.fallaLectura, isFalse);
        expect(b.ids, hasLength(3));
      },
    );

    test(
      'dado un reintento mientras todavía hay una suscripción, entonces nunca quedan dos vivas',
      () async {
        final b = _banco(repo: RepoListaFalso(tres));
        await _esperar();

        b.notificador.reintentar();
        b.notificador.reintentar();
        await _esperar();

        expect(b.repo.activas, 1);
      },
    );
  });

  group('filtros', () {
    test('dado un filtro de tipo, cuando se aplica, entonces solo quedan los de ese tipo y los '
        'contadores siguen contando todo', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.aplicar(
        tipos: {TipoUbicacion.negocio},
        estados: const {},
        ciudadId: null,
        proximidad: ProximidadLista.cualquiera,
        incluirBajas: false,
      );
      await _esperar();

      expect(b.ids, ['neg-1']);
      expect(b.estado.filtros.cantidadActivos, 1);
      expect(b.estado.lista!.totalGeneral, 3);
      expect(b.estado.lista!.porTipo[TipoUbicacion.casa], 1);
      expect(b.repo.activas, 1);
    });

    test('dado tipo y estado combinados, cuando se aplican, entonces filtran juntos', () async {
      final filas = [
        filaLista('a', estado: EstadoCasa.ventaCompleta),
        filaLista('b', estado: EstadoCasa.rechazo),
        filaLista('c', tipo: TipoUbicacion.negocio, estado: EstadoCasa.ventaCompleta),
      ];
      final b = _banco(repo: RepoListaFalso(filas));
      await _esperar();

      b.notificador.aplicar(
        tipos: {TipoUbicacion.casa},
        estados: {EstadoCasa.ventaCompleta},
        ciudadId: null,
        proximidad: ProximidadLista.cualquiera,
        incluirBajas: false,
      );
      await _esperar();

      expect(b.ids, ['a']);
      expect(b.estado.filtros.cantidadActivos, 2);
    });

    test(
      'dado un filtro de ciudad, cuando se aplica y después se quita, entonces vuelve todo',
      () async {
        final b = _banco(
          repo: RepoListaFalso([
            ...tres,
            filaLista('otra', ciudadId: 'ciu-can', hace: const Duration(days: 3)),
          ]),
        );
        await _esperar();

        b.notificador.aplicar(
          tipos: const {},
          estados: const {},
          ciudadId: 'ciu-can',
          proximidad: ProximidadLista.cualquiera,
          incluirBajas: false,
        );
        await _esperar();
        expect(b.ids, ['otra']);

        b.notificador.quitarCiudad();
        await _esperar();
        expect(b.ids, hasLength(4));
        expect(b.estado.filtros.ciudadId, isNull);
      },
    );

    test('dado «Mostrar bajas», cuando se activa, entonces pide las bajas a la base y las muestra '
        'como baja; al quitarlo desaparecen', () async {
      final repo = RepoListaFalso([
        ...tres,
        filaLista('baja-1', baja: ahoraLista.subtract(const Duration(days: 20))),
      ]);
      final b = _banco(repo: repo);
      await _esperar();
      expect(b.ids, isNot(contains('baja-1')));
      expect(b.estado.lista!.totalBajas, 0);

      b.notificador.aplicar(
        tipos: const {},
        estados: const {},
        ciudadId: null,
        proximidad: ProximidadLista.cualquiera,
        incluirBajas: true,
      );
      await _esperar();

      expect(repo.pedidos.last.incluirBajas, isTrue);
      final baja = b.estado.lista!.items.singleWhere((i) => i.ubicacion.id == 'baja-1');
      expect(baja.esBaja, isTrue);
      expect(baja.esInteractiva, isFalse);
      expect(b.estado.lista!.totalBajas, 1);

      b.notificador.quitarBajas();
      await _esperar();
      expect(b.ids, isNot(contains('baja-1')));
      expect(repo.pedidos.last.incluirBajas, isFalse);
    });

    test('dado cada chip, cuando se quita su ✕, entonces solo se saca ese filtro', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();
      b.notificador.aplicar(
        tipos: {TipoUbicacion.casa, TipoUbicacion.negocio},
        estados: {EstadoCasa.rechazo},
        ciudadId: 'ciu-mvd',
        proximidad: ProximidadLista.trescientos,
        incluirBajas: true,
      );

      b.notificador.quitarTipo(TipoUbicacion.casa);
      expect(b.estado.filtros.tipos, {TipoUbicacion.negocio});
      b.notificador.quitarEstado(EstadoCasa.rechazo);
      expect(b.estado.filtros.estados, isEmpty);
      b.notificador.quitarProximidad();
      expect(b.estado.filtros.proximidad, ProximidadLista.cualquiera);
      b.notificador.quitarBajas();
      expect(b.estado.filtros.incluirBajas, isFalse);
      b.notificador.quitarCiudad();
      expect(b.estado.filtros.ciudadId, isNull);
      expect(b.estado.filtros.cantidadActivos, 1);
      await _esperar();
      expect(b.repo.activas, 1);
    });

    test('dado filtros que no dejan nada, entonces es «sin resultados» y no «vacío»; al limpiar '
        'vuelve todo', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.buscar('zzz');
      await _esperar();

      expect(b.estado.lista!.sinResultados, isTrue);
      expect(b.estado.lista!.sinUbicaciones, isFalse);
      expect(b.estado.filtros.hayFiltrosOBusqueda, isTrue);

      b.notificador.limpiarTodo();
      await _esperar();

      expect(b.estado.filtros.busqueda, isEmpty);
      expect(b.estado.filtros.hayFiltrosOBusqueda, isFalse);
      expect(b.ids, hasLength(3));
    });

    test('dado el mismo filtro dos veces seguidas, entonces no se vuelve a pedir', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.quitarBajas();
      b.notificador.buscar('');
      b.notificador.ordenar(OrdenListaUbicaciones.recientes);

      expect(b.repo.suscripciones, 1);
    });

    test('dado que cambia un filtro, cuando llega la lista nueva, entonces mientras tanto se '
        'conserva la anterior', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();
      b.repo.bloqueo = Completer<void>();

      b.notificador.buscar('colonia');
      await _esperar();

      expect(b.ids, hasLength(3));

      b.repo.bloqueo!.complete();
      await _esperar();

      expect(b.ids, ['neg-1']);
    });
  });

  group('búsqueda', () {
    test('dado texto parcial de calle o número, entonces encuentra por substring sin acentos ni '
        'mayúsculas', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.buscar('RIVAD');
      await _esperar();
      expect(b.ids, ['casa-1', 'edi-1']);

      b.notificador.buscar('rivadavia 35');
      await _esperar();
      expect(b.ids, ['edi-1']);

      b.notificador.buscar('2020');
      await _esperar();
      expect(b.ids, ['neg-1']);
    });

    test('dado que se escribe y se borra todo, entonces vuelve la lista completa', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.buscar('col');
      await _esperar();
      b.notificador.buscar('');
      await _esperar();

      expect(b.ids, hasLength(3));
    });
  });

  group('orden', () {
    test('dado que no hay GPS, cuando se pide «Por cercanía», entonces la lista cae a «Última '
        'actualización»', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.ordenar(OrdenListaUbicaciones.cercania);
      await _esperar();

      expect(b.estado.filtros.orden, OrdenListaUbicaciones.cercania);
      expect(b.estado.lista!.ordenAplicado, OrdenListaUbicaciones.recientes);
    });

    test(
      'dado el GPS, cuando se ordena por cercanía, entonces muestra la distancia y ordena por ella; '
      'al volver a recientes la distancia no se usa',
      () async {
        final filas = [
          filaLista('lejos', metrosAlNorte: 400, hace: const Duration(minutes: 5)),
          filaLista('cerca', metrosAlNorte: 40, hace: const Duration(hours: 9)),
          filaLista('medio', metrosAlNorte: 150, hace: const Duration(hours: 3)),
        ];
        final b = _banco(repo: RepoListaFalso(filas), gps: GpsFalso(Right(lecturaGps(8))));
        await _esperar();
        await b.notificador.alAbrirPestana();
        await _esperar();

        b.notificador.ordenar(OrdenListaUbicaciones.cercania);
        await _esperar();

        expect(b.ids, ['cerca', 'medio', 'lejos']);
        expect(b.estado.lista!.ordenAplicado, OrdenListaUbicaciones.cercania);
        expect(b.estado.lista!.items.first.distanciaMetros, closeTo(40, 1));

        b.notificador.ordenar(OrdenListaUbicaciones.recientes);
        await _esperar();

        expect(b.ids, ['lejos', 'medio', 'cerca']);
      },
    );

    test('dado que se limpian los filtros, entonces el orden elegido se conserva', () async {
      final b = _banco(repo: RepoListaFalso(tres), gps: GpsFalso(Right(lecturaGps(8))));
      await _esperar();
      await b.notificador.alAbrirPestana();
      b.notificador.ordenar(OrdenListaUbicaciones.cercania);

      b.notificador.limpiarTodo();

      expect(b.estado.filtros.orden, OrdenListaUbicaciones.cercania);
    });
  });

  group('proximidad', () {
    test(
      'dado el GPS y «Cerca de mí · 100 m», entonces quedan solo las que están a menos de 100 m',
      () async {
        final filas = [
          filaLista('a-30', metrosAlNorte: 30),
          filaLista('b-250', metrosAlNorte: 250),
          filaLista('c-900', metrosAlNorte: 900),
        ];
        final b = _banco(repo: RepoListaFalso(filas), gps: GpsFalso(Right(lecturaGps(8))));
        await _esperar();
        await b.notificador.alAbrirPestana();
        await _esperar();

        b.notificador.aplicar(
          tipos: const {},
          estados: const {},
          ciudadId: null,
          proximidad: ProximidadLista.cien,
          incluirBajas: false,
        );
        await _esperar();
        expect(b.ids, ['a-30']);

        b.notificador.aplicar(
          tipos: const {},
          estados: const {},
          ciudadId: null,
          proximidad: ProximidadLista.unKilometro,
          incluirBajas: false,
        );
        await _esperar();
        expect(b.ids, hasLength(3));
      },
    );
  });

  group('páginas de 50', () {
    List<UbicacionConResumen> muchas(int n) => [
      for (var i = 0; i < n; i++)
        filaLista('u-${i.toString().padLeft(3, '0')}', hace: Duration(minutes: i + 1)),
    ];

    test('dado más de 50 ubicaciones, entonces muestra 50 y avisa que hay más', () async {
      final b = _banco(repo: RepoListaFalso(muchas(120)));

      await _esperar();

      expect(b.estado.lista!.items, hasLength(50));
      expect(b.estado.lista!.hayMas, isTrue);
      expect(b.estado.lista!.total, 120);
    });

    test(
      'dado «Cargando 50 más…», cuando se piden más, entonces suma una página y al final no hay más',
      () async {
        final b = _banco(repo: RepoListaFalso(muchas(120)));
        await _esperar();

        b.notificador.cargarMas();
        await _esperar();
        expect(b.estado.lista!.items, hasLength(100));
        expect(b.estado.lista!.hayMas, isTrue);

        b.notificador.cargarMas();
        await _esperar();
        expect(b.estado.lista!.items, hasLength(120));
        expect(b.estado.lista!.hayMas, isFalse);

        b.notificador.cargarMas();
        await _esperar();
        expect(b.estado.lista!.items, hasLength(120));
        expect(b.repo.activas, 1);
      },
    );

    test(
      'dado dos pedidos de más seguidos antes de que llegue la página, entonces se suma una sola',
      () async {
        final b = _banco(repo: RepoListaFalso(muchas(220)));
        await _esperar();

        b.notificador.cargarMas();
        b.notificador.cargarMas();
        await _esperar();

        expect(b.estado.lista!.items, hasLength(100));
      },
    );

    test('dado que cambia un filtro, entonces vuelve a la primera página', () async {
      final b = _banco(repo: RepoListaFalso(muchas(120)));
      await _esperar();
      b.notificador.cargarMas();
      await _esperar();
      expect(b.estado.lista!.items, hasLength(100));

      b.notificador.buscar('u-0');
      await _esperar();

      expect(b.estado.filtros.limite, ConsultaListaUbicaciones.tamanoPagina);
      expect(b.estado.lista!.items.length, lessThanOrEqualTo(50));
    });

    test(
      'dado que la base emite mientras se está en la página 2, entonces la página se mantiene',
      () async {
        final filas = muchas(120);
        final b = _banco(repo: RepoListaFalso(filas));
        await _esperar();
        b.notificador.cargarMas();
        await _esperar();

        b.repo.emitir([filaLista('nueva', hace: Duration.zero), ...filas]);
        await _esperar();

        expect(b.estado.lista!.items, hasLength(100));
        expect(b.ids.first, 'nueva');
      },
    );
  });

  group('GPS', () {
    test('dado que la pestaña no se abrió, entonces no se pidió el GPS', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      expect(b.estado.gps, EstadoGpsLista.sinPedir);
      expect(b.gps.lecturas, 0);
    });

    test('dado que la pestaña se abre, entonces busca el GPS y muestra la precisión', () async {
      final b = _banco(repo: RepoListaFalso(tres), gps: GpsFalso(Right(lecturaGps(8))));
      await _esperar();
      b.gps.bloqueo = Completer<void>();

      final lectura = b.notificador.alAbrirPestana();
      await _esperar();
      expect(b.estado.gps, EstadoGpsLista.buscando);

      b.gps.bloqueo!.complete();
      await lectura;

      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.estado.lectura!.precisionMetros, 8);
      expect(b.estado.posicion, puntoItalia);
    });

    test('dado que la lectura trae la posición, entonces la lista se vuelve a pedir una sola vez '
        'con ella', () async {
      final b = _banco(repo: RepoListaFalso(tres), gps: GpsFalso(Right(lecturaGps(8))));
      await _esperar();

      await b.notificador.alAbrirPestana();
      await _esperar();
      expect(b.repo.suscripciones, 2);

      // Una lectura en el mismo punto (la pestaña se vuelve a abrir) no vuelve a pedirla.
      await b.notificador.alAbrirPestana();
      await _esperar();
      expect(b.repo.suscripciones, 2);
      expect(b.gps.lecturas, 2);
    });

    test('dado que el permiso está denegado, entonces queda «sin GPS», la lista funciona y no se '
        'vuelve a pedir en cada apertura', () async {
      final b = _banco(
        repo: RepoListaFalso(tres),
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado))),
      );
      await _esperar();

      await b.notificador.alAbrirPestana();
      await b.notificador.alAbrirPestana();
      await b.notificador.alAbrirPestana();

      expect(b.estado.gps, EstadoGpsLista.sinGps);
      expect(b.estado.motivoSinGps, MotivoSinGps.permisoDenegado);
      expect(b.gps.lecturas, 1);
      expect(b.ids, hasLength(3));
    });

    test('dado «sin señal», entonces cada apertura lo vuelve a intentar', () async {
      final b = _banco(
        repo: RepoListaFalso(tres),
        gps: GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal))),
      );

      await b.notificador.alAbrirPestana();
      await b.notificador.alAbrirPestana();

      expect(b.gps.lecturas, 2);
      expect(b.estado.gps, EstadoGpsLista.sinGps);
    });

    test(
      'dado «sin GPS», cuando se vuelve de los ajustes, entonces lo reintenta y se recupera',
      () async {
        final gps = GpsFalso(
          const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.servicioApagado)),
        );
        final b = _banco(repo: RepoListaFalso(tres), gps: gps);
        await b.notificador.alAbrirPestana();
        expect(b.estado.gps, EstadoGpsLista.sinGps);

        gps.respuesta = Right(lecturaGps(12));
        await b.notificador.reintentarGpsSiHaceFalta();

        expect(b.estado.gps, EstadoGpsLista.conLectura);
        expect(b.estado.motivoSinGps, isNull);
      },
    );

    test('dado que hay GPS, cuando se vuelve a la app, entonces no se pide de nuevo', () async {
      final b = _banco(repo: RepoListaFalso(tres), gps: GpsFalso(Right(lecturaGps(8))));
      await b.notificador.alAbrirPestana();

      await b.notificador.reintentarGpsSiHaceFalta();

      expect(b.gps.lecturas, 1);
    });

    test('dado «Activar GPS», entonces pide el permiso que falta y vuelve a leer', () async {
      final gps = GpsFalso(
        const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado)),
      );
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);
      await b.notificador.alAbrirPestana();
      gps.alActivar = () => gps.respuesta = Right(lecturaGps(5));

      await b.notificador.activarGps();

      expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.estado.lectura!.precisionMetros, 5);
    });

    test('dado que un refresco falla, entonces la última posición buena se conserva', () async {
      final gps = GpsFalso(Right(lecturaGps(8)));
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);
      await b.notificador.alAbrirPestana();

      gps.respuesta = const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal));
      await b.notificador.alAbrirPestana();

      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.estado.lectura!.precisionMetros, 8);
      expect(b.estado.posicion, puntoItalia);
    });

    test(
      'dado dos lecturas en vuelo, cuando la vieja llega después, entonces vale la última pedida',
      () async {
        final lecturas = <int, Completer<Either<Failure, LecturaGps>>>{};
        final gps = GpsFalso()..porLectura = (n) => (lecturas[n] = Completer()).future;
        final b = _banco(repo: RepoListaFalso(tres), gps: gps);

        final primera = b.notificador.alAbrirPestana();
        await _esperar();
        // `alAbrirPestana` no pide otra mientras busca: la segunda sale de «Activar GPS».
        final segunda = b.notificador.activarGps();
        await _esperar();

        const otroPunto = Coordenadas(lat: -34.9, lon: -56.15);
        lecturas[2]!.complete(Right(lecturaGps(6, punto: otroPunto)));
        await segunda;
        lecturas[1]!.complete(Right(lecturaGps(90)));
        await primera;

        expect(b.estado.lectura!.precisionMetros, 6);
        expect(b.estado.posicion, otroPunto);
      },
    );
  });
}
