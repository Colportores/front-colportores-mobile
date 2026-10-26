// Falsos del historial de avisos y del centro de notificaciones (HU-NOT-005, vista 24, grupo C):
// el repositorio en memoria (con puertas para detener cada operación a mitad y fallas
// programables), el consultor de destinos y el arnés que monta el centro con ellos.
import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/core/theme/tema_colportaje.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/destino_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/entities/tipo_notificacion.dart';
import 'package:colportores_mobile/features/notificaciones/domain/repositories/historial_notificaciones_repository.dart';
import 'package:colportores_mobile/features/notificaciones/domain/usecases/historial_notificaciones_use_cases.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/pages/centro_notificaciones_page.dart';
import 'package:colportores_mobile/features/notificaciones/presentation/providers/historial_notificaciones_providers.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// El «ahora» de los tests del centro: viernes 23 de octubre de 2026, 16:10 (hora local).
final ahoraDelCentro = DateTime(2026, 10, 23, 16, 10);

/// Un recordatorio de visita recibido [hace] antes de [ahoraDelCentro].
Notificacion aviso(
  String id, {
  Duration hace = const Duration(minutes: 40),
  String titulo = 'Cobranza a las 16:00',
  String? detalle = 'Av. Italia 2810',
  bool leida = false,
  DestinoNotificacion? destino,
  bool conDestino = true,
}) => Notificacion(
  id: id,
  tipo: TipoNotificacion.recordatorioVisita,
  titulo: titulo,
  detalle: detalle,
  destino: conDestino ? (destino ?? DestinoAgenda('agenda-$id')) : null,
  recibidaEn: ahoraDelCentro.subtract(hace),
  leidaEn: leida ? ahoraDelCentro : null,
);

/// El repositorio en memoria. Emite de nuevo con cada cambio, como la DB.
final class HistorialEnMemoria implements HistorialNotificacionesRepository {
  HistorialEnMemoria([Iterable<Notificacion> avisos = const []]) : _filas = [...avisos];

  final List<Notificacion> _filas;
  final _cambios = StreamController<void>.broadcast();

  /// Lo que se registró, marcó y borró (para afirmar sobre las llamadas).
  final marcadas = <String>[];
  int llamadasMarcarTodas = 0;
  final borrados = <DateTime?>[];

  /// Una falla para la próxima llamada de cada operación (y las siguientes, mientras valga).
  bool fallaAlMarcar = false;
  bool fallaAlMarcarTodas = false;
  bool fallaAlBorrar = false;
  Object? errorAlObservar;

  /// Puertas: la operación espera a que se complete antes de hacer nada.
  Completer<void>? puertaAlMarcar;
  Completer<void>? puertaAlMarcarTodas;
  Completer<void>? puertaAlBorrar;

  /// La primera emisión de `observar` espera a esta puerta (para ver «cargando»).
  Completer<void>? puertaAlObservar;

  List<Notificacion> get filas => List.unmodifiable(_filas);

  /// Llega un aviso mientras la pantalla está abierta.
  void llegaUno(Notificacion n) {
    _filas.add(n);
    _cambios.add(null);
  }

  List<Notificacion> _vista(TipoNotificacion? tipo) {
    final lista =
        [
          for (final f in _filas)
            if (tipo == null || f.tipo == tipo) f,
        ]..sort((a, b) {
          final porHora = b.recibidaEn.compareTo(a.recibidaEn);
          return porHora != 0 ? porHora : b.id.compareTo(a.id);
        });
    return lista;
  }

  @override
  Stream<List<Notificacion>> observar({TipoNotificacion? tipo, required DateTime ahora}) async* {
    final puerta = puertaAlObservar;
    if (puerta != null) await puerta.future;
    final error = errorAlObservar;
    if (error != null) throw error;
    yield _vista(tipo);
    await for (final _ in _cambios.stream) {
      yield _vista(tipo);
    }
  }

  @override
  Stream<int> observarNoLeidas({required DateTime ahora}) async* {
    yield _filas.where((f) => !f.leida).length;
    await for (final _ in _cambios.stream) {
      yield _filas.where((f) => !f.leida).length;
    }
  }

  @override
  Future<Either<Failure, bool>> registrar(
    Notificacion notificacion, {
    required DateTime ahora,
  }) async {
    if (_filas.any((f) => f.id == notificacion.id)) return const Right(false);
    llegaUno(notificacion);
    return const Right(true);
  }

  @override
  Future<Either<Failure, Unit>> marcarLeida(String id, {required DateTime ahora}) async {
    final puerta = puertaAlMarcar;
    if (puerta != null) await puerta.future;
    if (fallaAlMarcar) return const Left(FailureInesperado());
    marcadas.add(id);
    final i = _filas.indexWhere((f) => f.id == id);
    if (i >= 0 && !_filas[i].leida) {
      final f = _filas[i];
      _filas[i] = Notificacion(
        id: f.id,
        tipo: f.tipo,
        titulo: f.titulo,
        detalle: f.detalle,
        destino: f.destino,
        recibidaEn: f.recibidaEn,
        leidaEn: ahora,
      );
      _cambios.add(null);
    }
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> marcarTodasLeidas({required DateTime ahora}) async {
    llamadasMarcarTodas++;
    final puerta = puertaAlMarcarTodas;
    if (puerta != null) await puerta.future;
    if (fallaAlMarcarTodas) return const Left(FailureInesperado());
    for (var i = 0; i < _filas.length; i++) {
      final f = _filas[i];
      if (f.leida) continue;
      _filas[i] = Notificacion(
        id: f.id,
        tipo: f.tipo,
        titulo: f.titulo,
        detalle: f.detalle,
        destino: f.destino,
        recibidaEn: f.recibidaEn,
        leidaEn: ahora,
      );
    }
    _cambios.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, int>> borrarTodas({DateTime? hasta}) async {
    borrados.add(hasta);
    final puerta = puertaAlBorrar;
    if (puerta != null) await puerta.future;
    if (fallaAlBorrar) return const Left(FailureInesperado());
    final antes = _filas.length;
    _filas.removeWhere((f) => hasta == null || !f.recibidaEn.isAfter(hasta));
    _cambios.add(null);
    return Right(antes - _filas.length);
  }

  @override
  Future<Either<Failure, int>> purgarVencidas({required DateTime ahora}) async => const Right(0);
}

/// Qué destinos existen.
final class DestinosEnMemoria implements ConsultorDestinosNotificacion {
  DestinosEnMemoria({this.todosExisten = true});

  bool todosExisten;
  final inexistentes = <DestinoNotificacion>{};
  bool falla = false;
  Completer<void>? puerta;
  final consultados = <DestinoNotificacion>[];

  @override
  Future<bool> existe(DestinoNotificacion destino) async {
    consultados.add(destino);
    final p = puerta;
    if (p != null) await p.future;
    if (falla) throw StateError('no se pudo consultar');
    return todosExisten && !inexistentes.contains(destino);
  }
}

/// Los destinos que se abrieron, en orden.
final class AbridorGrabador {
  final abiertos = <DestinoNotificacion>[];
  Completer<void>? puerta;

  /// Si no es null, abrir lanza esto.
  Object? falla;

  Future<void> call(BuildContext context, DestinoNotificacion destino) async {
    abiertos.add(destino);
    if (falla case final error?) throw error;
    final p = puerta;
    if (p != null) await p.future;
  }
}

/// Todo lo que hace falta para el centro: el historial, los destinos y el abridor.
final class CentroArnes {
  CentroArnes({Iterable<Notificacion> avisos = const [], DestinosEnMemoria? destinos})
    : historial = HistorialEnMemoria(avisos),
      destinos = destinos ?? DestinosEnMemoria();

  final HistorialEnMemoria historial;
  final DestinosEnMemoria destinos;
  final abridor = AbridorGrabador();

  List<Override> get overrides => [
    historialNotificacionesRepositoryProvider.overrideWithValue(historial),
    consultorDestinosNotificacionProvider.overrideWithValue(destinos),
    abridorDestinoNotificacionProvider.overrideWithValue(abridor.call),
    relojHistorialNotificacionesProvider.overrideWithValue(() => ahoraDelCentro),
  ];
}

/// Abre el centro suelto (con el tema de la app) y espera a que cargue.
Future<void> abrirCentro(
  WidgetTester tester,
  CentroArnes arnes, {
  Size tamano = const Size(390, 844),
  double texto = 1,
  bool esperar = true,
}) async {
  tester.view
    ..physicalSize = tamano
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.textScaleFactorTestValue = texto;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  await tester.pumpWidget(
    ProviderScope(
      overrides: arnes.overrides,
      child: MaterialApp(theme: temaClaro(), home: const CentroNotificacionesPage()),
    ),
  );
  if (esperar) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final centroPagina = find.byKey(const Key('centro_notificaciones_pagina'));
final centroMenu = find.byKey(const Key('centro_menu'));
final centroLista = find.byKey(const Key('centro_lista'));
final centroVacio = find.byKey(const Key('centro_vacio'));
final centroCargando = find.byKey(const Key('centro_cargando'));
final centroError = find.byKey(const Key('centro_error'));
final centroReintentar = find.byKey(const Key('centro_reintentar'));
final menuMarcarTodas = find.byKey(const Key('centro_menu_marcar_todas'));
final menuBorrarTodas = find.byKey(const Key('centro_menu_borrar_todas'));
final menuCerrar = find.byKey(const Key('centro_menu_cerrar'));
final borrarTitulo = find.byKey(const Key('centro_borrar_titulo'));
final borrarConfirmar = find.byKey(const Key('centro_borrar_confirmar'));
final borrarCancelar = find.byKey(const Key('centro_borrar_cancelar'));
final borrarError = find.byKey(const Key('centro_borrar_error'));

Finder filaDe(String id) => find.byKey(Key('centro_aviso_$id'));
