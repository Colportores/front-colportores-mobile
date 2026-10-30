// La cola que sube las fotos de los tickets cuando hay red y la fila ya llegó al servidor
// (HU-COB-007, #426): `colaDeSubidaDeFotosProvider` con un repositorio y un servidor falsos.
import 'dart:async';
import 'dart:typed_data';

import 'package:colportores_mobile/core/conectividad/conectividad_providers.dart';
import 'package:colportores_mobile/core/database/app_database.dart';
import 'package:colportores_mobile/core/database/database_providers.dart';
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tickets/domain/entities/ticket.dart';
import 'package:colportores_mobile/features/tickets/domain/repositories/ticket_repository.dart';
import 'package:colportores_mobile/features/tickets/domain/services/puertos_de_fotos.dart';
import 'package:colportores_mobile/features/tickets/presentation/providers/tickets_providers.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:dartz/dartz.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';
import '../../../helpers/tickets_falsos.dart';

class _DbFija extends DbLocalNotifier {
  _DbFija(this._db);

  final AppDatabase? _db;

  @override
  AppDatabase? build() => _db;
}

/// El repositorio: una cola con una foto por subir y un flujo de «cuántas hay» que el test maneja.
final class _Repo implements TicketRepository {
  final cantidad = StreamController<int>.broadcast();
  final marcadas = <String>[];
  var hayFoto = true;

  @override
  Stream<int> cantidadDeFotosPorSubir() => cantidad.stream;

  @override
  Future<Either<Failure, List<FotoPorSubir>>> fotosPorSubir() async => Right([
    if (hayFoto)
      FotoPorSubir(ticket: ticketDePrueba('t-1', syncVersion: 1), foto: fotoLocalDePrueba('t-1')),
  ]);

  @override
  Future<Either<Failure, Uint8List?>> bytesDeLaFoto(String ticketId) async => Right(fotoDePrueba());

  @override
  Future<Either<Failure, Ticket>> marcarFotoSubida(String ticketId, String ruta) async {
    marcadas.add(ruta);
    hayFoto = false;
    return Right(ticketDePrueba(ticketId, urlCloud: ruta));
  }

  @override
  Future<Either<Failure, Unit>> anotarIntentoFallido(
    String ticketId, {
    required String codigo,
    required bool definitivo,
  }) async => const Right(unit);

  @override
  Future<Either<Failure, TicketRegistrado>> registrar(
    Ticket ticket, {
    required Uint8List foto,
    required TipoDeImagen tipoDeImagen,
    String? cobroId,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> borrarCopiaLocal(String ticketId) => throw UnimplementedError();

  @override
  Stream<TicketRegistrado?> observarTicket(String ticketId) => const Stream.empty();

  @override
  Stream<Set<String>> cobrosConTicketPendiente() => const Stream.empty();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late _Repo repo;
  late StreamController<TipoConexion> conexion;
  late ServidorDeFotosGuionado servidor;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory(), logger: loggerMudo());
    repo = _Repo();
    conexion = StreamController<TipoConexion>.broadcast();
    servidor = ServidorDeFotosGuionado([const FotoSubida('u/t-1.jpg')]);
  });
  tearDown(() async {
    await conexion.close();
    await repo.cantidad.close();
    await db.close();
  });

  ProviderContainer armar({AppDatabase? base}) {
    final contenedor = ProviderContainer(
      overrides: [
        dbLocalProvider.overrideWith(() => _DbFija(base)),
        ticketRepositoryProvider.overrideWithValue(repo),
        servidorDeFotosDeTicketProvider.overrideWithValue(servidor),
        monitorConectividadProvider.overrideWithValue(_Monitor(conexion.stream)),
      ],
    );
    addTearDown(contenedor.dispose);
    contenedor.listen(colaDeSubidaDeFotosProvider, (_, _) {});
    return contenedor;
  }

  test('con red, cuando hay una foto por subir, la sube y guarda la ruta', () async {
    armar(base: db);
    await pumpEventQueue();

    repo.cantidad.add(1);
    await pumpEventQueue();

    expect(servidor.pedidos.map((p) => p.ticketId), ['t-1']);
    expect(repo.marcadas, ['u/t-1.jpg']);
  });

  test('sin red no sube; cuando vuelve la red, sube', () async {
    armar(base: db);
    await pumpEventQueue();
    conexion.add(TipoConexion.sinConexion);
    await pumpEventQueue();
    repo.cantidad.add(1);
    await pumpEventQueue();
    expect(servidor.pedidos, isEmpty);

    conexion.add(TipoConexion.datosMoviles);
    await pumpEventQueue();

    expect(servidor.pedidos.map((p) => p.ticketId), ['t-1']);
    expect(repo.marcadas, ['u/t-1.jpg']);
  });

  test('sin fotos por subir, volver la red no llama al servidor', () async {
    armar(base: db);
    await pumpEventQueue();
    repo.cantidad.add(0);
    await pumpEventQueue();

    conexion.add(TipoConexion.wifi);
    await pumpEventQueue();

    expect(servidor.pedidos, isEmpty);
  });

  test(
    'un fallo de la subida no rompe la cola: la próxima vez que cambie, vuelve a intentar',
    () async {
      servidor = ServidorDeFotosGuionado([
        const SubidaFallida(codigo: 'red', reintentable: true),
        const FotoSubida('u/t-1.jpg'),
      ]);
      armar(base: db);
      await pumpEventQueue();
      repo.cantidad.add(1);
      await pumpEventQueue();
      expect(repo.marcadas, isEmpty);

      conexion.add(TipoConexion.datosMoviles);
      await pumpEventQueue();

      expect(servidor.pedidos, hasLength(2));
      expect(repo.marcadas, ['u/t-1.jpg']);
    },
  );

  test('sin la base abierta no hace nada', () async {
    armar();
    conexion.add(TipoConexion.wifi);
    repo.cantidad.add(1);
    await pumpEventQueue();

    expect(servidor.pedidos, isEmpty);
  });
}

final class _Monitor implements MonitorConectividad {
  _Monitor(this._cambios);

  final Stream<TipoConexion> _cambios;

  /// La conexión de arranque: con Wi-Fi.
  @override
  Future<TipoConexion> actual() async => TipoConexion.wifi;

  @override
  Stream<TipoConexion> get cambios => _cambios;
}
