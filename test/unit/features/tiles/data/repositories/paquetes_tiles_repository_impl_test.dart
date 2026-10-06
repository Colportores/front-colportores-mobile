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
  late DateTime ahora;
  final bytes = bytesDePrueba(10);
  final paquete = paqueteDe(bytes);
  final descargado = descargadoDe(paquete);

  PaquetesTilesRepositoryImpl crear({CatalogoPaquetesTilesRemoteDataSource? remoto}) {
    return PaquetesTilesRepositoryImpl(
      catalogo: remoto ?? catalogo,
      registro: registro,
      archivos: archivos,
      checksum: ChecksumFalso(archivos),
      ahora: () => ahora,
      logger: loggerMudo(),
    );
  }

  /// Deja el paquete bajado y anotado, como lo deja una descarga terminada.
  Future<void> instalar(PaqueteDescargado d, List<List<int>> partes) async {
    for (var i = 0; i < partes.length; i++) {
      archivos.contenido[d.rutas[i]] = partes[i];
      archivos.modificados[d.rutas[i]] = ahora.subtract(const Duration(days: 1));
    }
    await registro.guardar(d);
  }

  setUp(() {
    ahora = DateTime(2026, 10, 7, 12);
    catalogo = CatalogoPaquetesTilesEnMemoria([paquete]);
    registro = RegistroPaquetesDescargadosEnMemoria();
    archivos = ArchivosEnMemoria()..ahora = ahora;
    repositorio = crear();
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

    test('dado un catálogo que no es de este formato, devuelve FailureServidor', () async {
      final resultado = await crear(
        remoto: _CatalogoQueLanza(const FormatException('v2')),
      ).catalogo();

      expect(resultado, const Left<Failure, List<PaqueteTiles>>(FailureServidor()));
    });

    test('dado un catálogo que lanza otra cosa, devuelve FailureInesperado', () async {
      final resultado = await crear(remoto: _CatalogoQueLanza(StateError('roto'))).catalogo();

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });
  });

  group('descargados', () {
    test('dado un paquete registrado, lo devuelve; si falta su archivo, no', () async {
      await repositorio.registrar(descargado);
      archivos.contenido[descargado.rutas.single] = bytes;
      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), [descargado]);

      archivos.contenido.clear();

      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });

    test('un paquete en partes solo está si están todas las partes', () async {
      final partes = [bytesDePrueba(8), bytesDePrueba(6, semilla: 9)];
      final enPartes = paqueteEnPartes(partes);
      final d = descargadoDe(enPartes);
      await instalar(d, partes);
      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), [d]);

      archivos.contenido.remove(d.rutas.last);

      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });

    test('un registro con menos rutas que partes no se informa', () async {
      final partes = [bytesDePrueba(8), bytesDePrueba(6, semilla: 9)];
      final enPartes = paqueteEnPartes(partes);
      final incompleto = PaqueteDescargado(paquete: enPartes, rutas: [rutaFinalDe(enPartes, 0)]);
      archivos.contenido[incompleto.rutas.single] = partes.first;
      await registro.guardar(incompleto);

      expect((await repositorio.descargados()).getOrElse(() => fail('Left')), isEmpty);
    });

    test('dado que el registro falla, registrar, quitar y descargados devuelven Left', () async {
      registro.fallarCon = StateError('disco');

      expect((await repositorio.registrar(descargado)).isLeft(), isTrue);
      expect((await repositorio.quitar(paquete.id)).isLeft(), isTrue);
      expect((await repositorio.descargados()).isLeft(), isTrue);
    });
  });

  group('registrar', () {
    test('al registrar una versión nueva, borra los archivos de la anterior', () async {
      final anterior = descargadoDe(paquete);
      await instalar(anterior, [bytes]);
      final nuevosBytes = bytesDePrueba(12, semilla: 77);
      final nuevo = paqueteDe(nuevosBytes);
      final nuevoDescargado = descargadoDe(nuevo);
      archivos.contenido[nuevoDescargado.rutas.single] = nuevosBytes;

      final resultado = await repositorio.registrar(nuevoDescargado);

      expect(resultado.isRight(), isTrue);
      expect(archivos.borrados, [anterior.rutas.single]);
      expect(archivos.contenido.keys, [nuevoDescargado.rutas.single]);
      expect((await registro.leer()).single, nuevoDescargado);
    });

    test('registrar lo mismo otra vez no borra nada', () async {
      await instalar(descargado, [bytes]);

      await repositorio.registrar(descargado);

      expect(archivos.borrados, isEmpty);
      expect(archivos.contenido, contains(descargado.rutas.single));
    });

    test('si no se puede borrar la versión anterior, igual queda registrada la nueva', () async {
      await instalar(descargado, [bytes]);
      final nuevosBytes = bytesDePrueba(12, semilla: 77);
      final nuevoDescargado = descargadoDe(paqueteDe(nuevosBytes));
      archivos.contenido[nuevoDescargado.rutas.single] = nuevosBytes;
      archivos.fallaAlBorrar = true;

      final resultado = await repositorio.registrar(nuevoDescargado);

      expect(resultado.isRight(), isTrue);
      expect((await registro.leer()).single, nuevoDescargado);
    });

    test('si el registro no se puede escribir, no borra la versión anterior', () async {
      await instalar(descargado, [bytes]);
      final nuevosBytes = bytesDePrueba(12, semilla: 77);
      final nuevoDescargado = descargadoDe(paqueteDe(nuevosBytes));
      registro.fallarCon = StateError('disco');

      final resultado = await repositorio.registrar(nuevoDescargado);

      expect(resultado.isLeft(), isTrue);
      expect(archivos.borrados, isEmpty);
      expect(archivos.contenido, contains(descargado.rutas.single));
    });
  });

  test('observarDescargados emite al suscribirse y con cada registrar y quitar', () async {
    final emitidos = <List<PaqueteDescargado>>[];
    final suscripcion = repositorio.observarDescargados().listen(emitidos.add);
    Future<void> dejarCorrer() => Future<void>.delayed(Duration.zero);
    await dejarCorrer();

    archivos.contenido[descargado.rutas.single] = bytes;
    await repositorio.registrar(descargado);
    await dejarCorrer();
    await repositorio.quitar(paquete.id);
    await dejarCorrer();
    registro.fallarCon = StateError('disco');
    await repositorio.quitar(paquete.id);
    await dejarCorrer();

    expect(emitidos, [
      <PaqueteDescargado>[],
      [descargado],
      <PaqueteDescargado>[],
    ]);
    await suscripcion.cancel();
  });

  test('observarDescargados con dos acciones seguidas emite el estado final en orden', () async {
    final emitidos = <List<PaqueteDescargado>>[];
    final suscripcion = repositorio.observarDescargados().listen(emitidos.add);
    await Future<void>.delayed(Duration.zero);
    archivos.contenido[descargado.rutas.single] = bytes;

    await Future.wait([repositorio.registrar(descargado), repositorio.quitar(paquete.id)]);
    await Future<void>.delayed(Duration.zero);

    // Sea cual sea el orden en que terminaron, lo último que se emite es el estado real.
    expect(emitidos.last, (await repositorio.descargados()).getOrElse(() => fail('Left')));
    await suscripcion.cancel();
  });

  group('reconciliar', () {
    test('un paquete intacto queda como está, con sus archivos', () async {
      await instalar(descargado, [bytes]);

      final resultado = await repositorio.reconciliar();

      expect(resultado.isRight(), isTrue);
      expect(await registro.leer(), [descargado]);
      expect(archivos.borrados, isEmpty);
    });

    test('un paquete al que le falta el archivo se saca del registro', () async {
      await registro.guardar(descargado);

      await repositorio.reconciliar();

      expect(await registro.leer(), isEmpty);
    });

    test(
      'un archivo que no pesa lo que dice el catálogo se trata como no bajado y se borra',
      () async {
        await instalar(descargado, [bytes.sublist(0, 6)]);

        await repositorio.reconciliar();

        expect(await registro.leer(), isEmpty);
        expect(archivos.contenido, isEmpty);
      },
    );

    test('un archivo del tamaño justo pero con otro contenido no pasa el checksum', () async {
      final alterado = [...bytes]..[3] = (bytes[3] + 1) % 251;
      await instalar(descargado, [alterado]);

      await repositorio.reconciliar();

      expect(await registro.leer(), isEmpty);
      expect(archivos.contenido, isEmpty);
    });

    test('un paquete en partes con una parte alterada se saca entero', () async {
      final partes = [bytesDePrueba(8), bytesDePrueba(6, semilla: 9)];
      final d = descargadoDe(paqueteEnPartes(partes));
      await instalar(d, [partes.first, bytesDePrueba(6, semilla: 10)]);

      await repositorio.reconciliar();

      expect(await registro.leer(), isEmpty);
      expect(archivos.contenido, isEmpty);
    });

    test('un .pmtiles sin registrar de hace tiempo se borra; uno reciente no', () async {
      archivos.contenido['/tiles/viejo-p1-aaaaaaaaaaaa.pmtiles'] = [1];
      archivos.modificados['/tiles/viejo-p1-aaaaaaaaaaaa.pmtiles'] = ahora.subtract(
        PaquetesTilesRepositoryImpl.gracia,
      );
      archivos.contenido['/tiles/nuevo-p1-bbbbbbbbbbbb.pmtiles'] = [2];
      archivos.modificados['/tiles/nuevo-p1-bbbbbbbbbbbb.pmtiles'] = ahora.subtract(
        const Duration(minutes: 1),
      );

      await repositorio.reconciliar();

      expect(archivos.contenido.keys, ['/tiles/nuevo-p1-bbbbbbbbbbbb.pmtiles']);
    });

    test('un .part se conserva hasta 7 días para reanudarlo', () async {
      archivos.contenido['/tiles/a-p1-aaaaaaaaaaaa.pmtiles.part'] = [1];
      archivos.modificados['/tiles/a-p1-aaaaaaaaaaaa.pmtiles.part'] = ahora.subtract(
        const Duration(days: 6),
      );
      archivos.contenido['/tiles/b-p1-bbbbbbbbbbbb.pmtiles.part'] = [2];
      archivos.modificados['/tiles/b-p1-bbbbbbbbbbbb.pmtiles.part'] = ahora.subtract(
        PaquetesTilesRepositoryImpl.vigenciaParcial,
      );

      await repositorio.reconciliar();

      expect(archivos.contenido.keys, ['/tiles/a-p1-aaaaaaaaaaaa.pmtiles.part']);
    });

    test('lo que no es .pmtiles ni .part no lo toca', () async {
      archivos.contenido['/tiles/registro.json'] = [1];
      archivos.modificados['/tiles/registro.json'] = ahora.subtract(const Duration(days: 90));

      await repositorio.reconciliar();

      expect(archivos.contenido, contains('/tiles/registro.json'));
    });

    test('al sacar un paquete del registro avisa a los que observan', () async {
      await instalar(descargado, [bytes.sublist(0, 6)]);
      final emitidos = <List<PaqueteDescargado>>[];
      final suscripcion = repositorio.observarDescargados().listen(emitidos.add);
      await Future<void>.delayed(Duration.zero);

      await repositorio.reconciliar();
      await Future<void>.delayed(Duration.zero);

      expect(emitidos, [
        [descargado],
        <PaqueteDescargado>[],
      ]);
      await suscripcion.cancel();
    });

    test('dado que el registro falla, devuelve Left', () async {
      registro.fallarCon = StateError('disco');

      final resultado = await repositorio.reconciliar();

      expect(resultado.fold((f) => f, (_) => null), isA<FailureInesperado>());
    });
  });
}

final class _CatalogoQueLanza implements CatalogoPaquetesTilesRemoteDataSource {
  _CatalogoQueLanza(this._error);

  final Object _error;

  @override
  Future<List<PaqueteTiles>> listar() async => throw _error;
}
