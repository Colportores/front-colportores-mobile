// HU-UBI-003 / vista 06: las reglas del mapa de ubicaciones (lectura reactiva, GPS, selección,
// errores) sin widgets ni plugins.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/consulta_lista_ubicaciones.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/punto_capturado.dart'
    show LecturaGps;
import 'package:colportores_mobile/features/mapa/presentation/providers/mapa_ubicaciones_notifier.dart';
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
  final proveedor = mapaUbicacionesProvider('col-1');

  MapaUbicacionesState get estado => contenedor.read(proveedor);
  MapaUbicacionesNotifier get notificador => contenedor.read(proveedor.notifier);

  List<String> get ids => [for (final i in estado.lista!.items) i.ubicacion.id];

  void cerrar() => contenedor.dispose();
}

_Banco _banco({RepoListaFalso? repo, GpsFalso? gps}) {
  final b = _Banco(repo: repo, gps: gps);
  addTearDown(b.cerrar);
  return b;
}

Future<void> _esperar() => pumpEventQueue();

Left<Failure, LecturaGps> _sinPermiso() =>
    const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.permisoDenegado));

void main() {
  final tres = [
    filaLista('a', metrosAlNorte: 30),
    filaLista('b', metrosAlNorte: 200),
    filaLista('c', metrosAlNorte: 900),
  ];

  group('lectura', () {
    test('mientras no llega la lista, está cargando; después trae todas, de la más cercana a la '
        'más lejana', () async {
      final b = _banco(repo: RepoListaFalso([...tres.reversed]));
      expect(b.estado.cargando, isTrue);

      await b.notificador.alAbrirPestana();
      await _esperar();

      expect(b.estado.cargando, isFalse);
      expect(b.ids, ['a', 'b', 'c']);
      expect(b.estado.lista!.ordenAplicado, OrdenListaUbicaciones.cercania);
      expect(b.repo.pedidos.every((p) => p.colportorId == 'col-1'), isTrue);
    });

    test('sin ubicaciones, la lista llega vacía y sin error', () async {
      final b = _banco();
      await _esperar();

      expect(b.estado.lista!.sinUbicaciones, isTrue);
      expect(b.estado.fallaLectura, isFalse);
    });

    test(
      'la base emite de nuevo (alta o baja) y el estado la sigue, con una sola suscripción',
      () async {
        final b = _banco(repo: RepoListaFalso(tres));
        await _esperar();

        b.repo.emitir([...tres, filaLista('d', metrosAlNorte: 10)]);
        await _esperar();

        expect(b.estado.lista!.total, 4);
        expect(b.repo.activas, 1);
      },
    );

    test('un error de la base marca la falla; «Reintentar» la limpia y vuelve a leer', () async {
      final b = _banco(repo: RepoListaFalso(tres)..fallaAlSuscribir = true);
      await _esperar();
      expect(b.estado.fallaLectura, isTrue);
      expect(b.estado.cargando, isFalse);

      b.repo.fallaAlSuscribir = false;
      b.notificador.reintentar();
      await _esperar();

      expect(b.estado.fallaLectura, isFalse);
      expect(b.estado.lista!.total, 3);
      expect(b.repo.activas, 1);
    });

    test(
      'una base que ni siquiera se abre (el caso de uso lanza al armarse) es una falla',
      () async {
        final b = _banco(repo: RepoListaFalso(tres)..lanzaAlPedir = StateError('sin base'));
        await _esperar();

        expect(b.estado.fallaLectura, isTrue);
      },
    );

    test('si falla después de haber leído, la última lista se conserva', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.repo.fallar(StateError('se cerró'));
      await _esperar();

      expect(b.estado.fallaLectura, isTrue);
      expect(b.estado.lista!.total, 3);
      expect(b.estado.cargando, isFalse);
    });

    test('al descartarse el provider, la suscripción a la base se cancela', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();
      expect(b.repo.activas, 1);

      b.cerrar();
      await _esperar();

      expect(b.repo.activas, 0);
    });
  });

  group('GPS', () {
    test('al abrir la pestaña lee el GPS; la lista se reordena con la posición', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();
      expect(b.estado.gps, EstadoGpsLista.sinPedir);

      await b.notificador.alAbrirPestana();
      await _esperar();

      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.estado.posicion, puntoItalia);
      expect(b.gps.lecturas, 1);
      expect(b.repo.suscripciones, 2, reason: 'una sin posición y otra con ella');
      expect(b.repo.activas, 1);
    });

    test('mientras lee, está buscando; una segunda apertura no lanza otra lectura', () async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);

      final primera = b.notificador.alAbrirPestana();
      await _esperar();
      expect(b.estado.gps, EstadoGpsLista.buscando);
      await b.notificador.alAbrirPestana();
      expect(gps.lecturas, 1);

      gps.bloqueo!.complete();
      await primera;
      expect(b.estado.gps, EstadoGpsLista.conLectura);
    });

    test(
      'cada apertura posterior refresca la lectura sin volver a pedir la lista si no se movió',
      () async {
        final b = _banco(repo: RepoListaFalso(tres));
        await b.notificador.alAbrirPestana();
        await _esperar();
        final suscripciones = b.repo.suscripciones;

        await b.notificador.alAbrirPestana();
        await _esperar();

        expect(b.gps.lecturas, 2);
        expect(b.repo.suscripciones, suscripciones);
      },
    );

    test('si el colportor se movió, la lista se vuelve a pedir con la posición nueva', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await b.notificador.alAbrirPestana();
      await _esperar();
      final suscripciones = b.repo.suscripciones;

      b.gps.respuesta = Right(
        lecturaGps(5, punto: const Coordenadas(lat: -34.8850, lon: -56.1302)),
      );
      await b.notificador.refrescarGps();
      await _esperar();

      expect(b.repo.suscripciones, suscripciones + 1);
      expect(b.repo.activas, 1);
    });

    test('un refresco que falla no tira la última posición buena', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await b.notificador.alAbrirPestana();
      await _esperar();

      b.gps.respuesta = _sinPermiso();
      await b.notificador.refrescarGps();
      await _esperar();

      expect(b.estado.gps, EstadoGpsLista.conLectura);
      expect(b.estado.posicion, puntoItalia);
      expect(b.estado.motivoSinGps, isNull);
    });

    test('sin permiso: queda sin GPS con el motivo y abrir la pestaña de nuevo no lo vuelve a '
        'pedir', () async {
      final b = _banco(repo: RepoListaFalso(tres), gps: GpsFalso(_sinPermiso()));
      await b.notificador.alAbrirPestana();
      await _esperar();

      expect(b.estado.gps, EstadoGpsLista.sinGps);
      expect(b.estado.motivoSinGps, MotivoSinGps.permisoDenegado);
      expect(b.estado.lectura, isNull);

      await b.notificador.alAbrirPestana();
      expect(b.gps.lecturas, 1);
    });

    test('sin señal sí se reintenta al abrir la pestaña', () async {
      final gps = GpsFalso(const Left(FailureGpsNoDisponible(motivo: MotivoSinGps.sinSenal)));
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);
      await b.notificador.alAbrirPestana();
      await _esperar();

      await b.notificador.alAbrirPestana();

      expect(gps.lecturas, 2);
    });

    test(
      '«Activar GPS» abre el permiso, vuelve a leer y, si lo dieron, queda con lectura',
      () async {
        final gps = GpsFalso(_sinPermiso());
        gps.alActivar = () => gps.respuesta = Right(lecturaGps(6));
        final b = _banco(repo: RepoListaFalso(tres), gps: gps);
        await b.notificador.alAbrirPestana();
        await _esperar();

        await b.notificador.activarGps();
        await _esperar();

        expect(gps.activaciones, [MotivoSinGps.permisoDenegado]);
        expect(b.estado.gps, EstadoGpsLista.conLectura);
        expect(b.estado.motivoSinGps, isNull);
      },
    );

    test(
      'volver de los ajustes reintenta una sola vez, y solo si se había tocado «Activar GPS»',
      () async {
        final gps = GpsFalso(_sinPermiso());
        final b = _banco(repo: RepoListaFalso(tres), gps: gps);
        await b.notificador.alAbrirPestana();
        await _esperar();

        await b.notificador.reintentarGpsSiHaceFalta();
        expect(gps.lecturas, 1, reason: 'volver de WhatsApp no debe pedir nada');

        await b.notificador.activarGps();
        expect(gps.lecturas, 2);
        gps.respuesta = Right(lecturaGps(6));
        await b.notificador.reintentarGpsSiHaceFalta();
        expect(gps.lecturas, 3);
        await b.notificador.reintentarGpsSiHaceFalta();
        expect(gps.lecturas, 3);
      },
    );

    test('«Activar GPS» tocado dos veces seguidas abre un solo diálogo', () async {
      final gps = GpsFalso(_sinPermiso());
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);
      await b.notificador.alAbrirPestana();
      await _esperar();

      final primera = b.notificador.activarGps();
      final segunda = b.notificador.activarGps();
      await Future.wait([primera, segunda]);

      expect(gps.activaciones.length, 1);
    });

    test(
      'si el sistema falla al abrir el permiso, igual vuelve a leer y no deja el botón trabado',
      () async {
        final gps = GpsFalso(_sinPermiso())..alActivar = () => throw StateError('sin ajustes');
        final b = _banco(repo: RepoListaFalso(tres), gps: gps);
        await b.notificador.alAbrirPestana();
        await _esperar();

        await b.notificador.activarGps();
        expect(gps.lecturas, 2);
        expect(b.estado.gps, EstadoGpsLista.sinGps);

        await b.notificador.activarGps();
        expect(gps.activaciones.length, 2);
      },
    );

    test('una lectura vieja que llega después de una nueva se ignora', () async {
      final gps = GpsFalso();
      final vieja = Completer<Either<Failure, LecturaGps>>();
      final nueva = Completer<Either<Failure, LecturaGps>>();
      gps.porLectura = (n) => n == 1 ? vieja.future : nueva.future;
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);

      final a = b.notificador.refrescarGps();
      final c = b.notificador.refrescarGps();
      nueva.complete(Right(lecturaGps(5)));
      await c;
      vieja.complete(Right(lecturaGps(9, punto: const Coordenadas(lat: -34.5, lon: -56.0))));
      await a;

      expect(b.estado.posicion, puntoItalia);
      expect(b.estado.lectura!.precisionMetros, 5);
    });

    test('si el provider se descarta con la lectura en vuelo, no pasa nada al llegar', () async {
      final gps = GpsFalso()..bloqueo = Completer<void>();
      final b = _banco(repo: RepoListaFalso(tres), gps: gps);
      final lectura = b.notificador.alAbrirPestana();
      await _esperar();

      b.cerrar();
      gps.bloqueo!.complete();
      await lectura;
    });
  });

  group('selección', () {
    test('seleccionar abre la vista previa de esa ubicación; cerrar la quita', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.seleccionar('b');
      expect(b.estado.seleccionada!.ubicacion.id, 'b');

      b.notificador.cerrarSeleccion();
      expect(b.estado.seleccionada, isNull);
      expect(b.estado.seleccionadaId, isNull);
    });

    test('elegir otra reemplaza la anterior', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador
        ..seleccionar('a')
        ..seleccionar('c');

      expect(b.estado.seleccionada!.ubicacion.id, 'c');
    });

    test('una id que no está en la lista no abre nada, y si la ubicación se da de baja la vista '
        'previa desaparece', () async {
      final b = _banco(repo: RepoListaFalso(tres));
      await _esperar();

      b.notificador.seleccionar('no-existe');
      expect(b.estado.seleccionada, isNull);

      b.notificador.seleccionar('a');
      expect(b.estado.seleccionada, isNotNull);
      b.repo.emitir(tres.skip(1).toList());
      await _esperar();
      expect(b.estado.seleccionada, isNull);
    });

    test('seleccionar antes de que llegue la lista no falla', () {
      final b = _banco(repo: RepoListaFalso(tres));

      b.notificador.seleccionar('a');

      expect(b.estado.seleccionada, isNull);
    });
  });

  group('MapaUbicacionesState', () {
    test('«cerca tuyo» son 60 m', () {
      expect(MapaUbicacionesState.radioCercaMetros, 60);
    });

    test('copyWith conserva lo que no se cambia y borra el motivo y la selección si se pide', () {
      const base = MapaUbicacionesState(
        gps: EstadoGpsLista.sinGps,
        motivoSinGps: MotivoSinGps.sinSenal,
        seleccionadaId: 'a',
        fallaLectura: true,
      );

      final igual = base.copyWith();
      expect(igual, base);
      final sinNada = base.copyWith(borrarMotivo: true, borrarSeleccion: true);
      expect(sinNada.motivoSinGps, isNull);
      expect(sinNada.seleccionadaId, isNull);
      expect(sinNada.fallaLectura, isTrue);
      expect(sinNada.gps, EstadoGpsLista.sinGps);
    });

    test('con falla de lectura ya no está cargando', () {
      expect(const MapaUbicacionesState().cargando, isTrue);
      expect(const MapaUbicacionesState(fallaLectura: true).cargando, isFalse);
    });
  });
}
