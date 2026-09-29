// Test de data: el repositorio contra los data sources en memoria y los archivos falsos.
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/data/datasources/fakes/paquetes_tiles_en_memoria.dart';
import 'package:colportores_mobile/features/tiles/data/datasources/paquetes_tiles_data_sources.dart';
import 'package:colportores_mobile/features/tiles/data/repositories/paquetes_tiles_repository_impl.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';
import '../../../../../helpers/tiles_falsos.dart';

void main() {
  late CatalogoPaquetesTilesEnMemoria catalogo;
  late RegistroPaquetesDescargadosEnMemoria registro;
  late ArchivosEnMemoria archivos;
  late PaquetesTilesRepositoryImpl repositorio;
  final paquete = paqueteDe(bytesDePrueba(10));
  final descargado = PaqueteDescargado(paquete: paquete, ruta: '/tiles/zona-centro.pmtiles');

  setUp(() {
    catalogo = CatalogoPaquetesTilesEnMemoria([paquete]);
    registro = RegistroPaquetesDescargadosEnMemoria();
    archivos = ArchivosEnMemoria()..contenido[descargado.ruta] = bytesDePrueba(10);
    repositorio = PaquetesTilesRepositoryImpl(
      catalogo: catalogo,
      registro: registro,
      archivos: archivos,
      logger: loggerMudo(),
    );
  });

  group('catalogo', () {
    test('dado el catálogo, lo devuelve', () async {
      final resultado = await repositorio.catalogo();

      expect(resultado.getOrElse(() => fail('Left')), [paquete]);
    });

    test('dado que no hay red, devuelve FailureSinConexion', () async {
      catalogo.sinRed = true;

      final resultado = await repositorio.catalogo();

      expect(resultado, const Left<Failure, List<PaqueteTiles>>(FailureSinConexion()));
    });

    test('dado que el servidor responde con error, devuelve FailureServidor', () async {
      catalogo.statusError = 503;

      final resultado = await repositorio.catalogo();

      expect(resultado, const Left<Failure, List<PaqueteTiles>>(FailureServidor(status: 503)));
    });
  });

  test('dado un catálogo que lanza otra cosa, devuelve FailureInesperado', () async {
    final roto = PaquetesTilesRepositoryImpl(
      catalogo: _CatalogoRoto(),
      registro: registro,
      archivos: archivos,
      logger: loggerMudo(),
    );

    final resultado = await roto.catalogo();

    expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
  });

  group('descargados', () {
    test('dado un paquete registrado, lo devuelve; si falta su archivo, no', () async {
      await repositorio.registrar(descargado);
      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), [descargado]);

      archivos.contenido.clear();

      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });

    test('dado que el registro falla, registrar, quitar y descargados devuelven Left', () async {
      registro.fallarCon = StateError('disco');

      expect((await repositorio.registrar(descargado)).isLeft(), isTrue);
      expect((await repositorio.quitar(paquete.id)).isLeft(), isTrue);
      expect((await repositorio.descargados()).isLeft(), isTrue);
    });
  });

  test('observarDescargados emite al suscribirse y con cada registrar y quitar', () async {
    final emitidos = <List<PaqueteDescargado>>[];
    final suscripcion = repositorio.observarDescargados().listen(emitidos.add);
    Future<void> dejarCorrer() => Future<void>.delayed(Duration.zero);
    await dejarCorrer();

    await repositorio.registrar(descargado);
    await dejarCorrer();
    await repositorio.quitar(paquete.id);
    await dejarCorrer();
    registro.fallarCon = StateError('disco');
    await repositorio.quitar(paquete.id);
    await dejarCorrer();

    expect(emitidos, [<PaqueteDescargado>[], [descargado], <PaqueteDescargado>[]]);
    await suscripcion.cancel();
  });
}

final class _CatalogoRoto implements CatalogoPaquetesTilesRemoteDataSource {
  @override
  Future<List<PaqueteTiles>> listar() async => throw const FormatException('catálogo roto');
}
