// Test de dominio: Dart puro. Casos de uso de tiles offline (HU-SYNC-010, HU-CAM-005, HU-UBI-003).
import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/estado_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/entities/paquete_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/descargador_paquetes_tiles.dart';
import 'package:colportores_mobile/features/tiles/domain/services/puertos_descarga.dart';
import 'package:colportores_mobile/features/tiles/domain/usecases/descarga_paquete_tiles_use_cases.dart';
import 'package:colportores_mobile/features/tiles/domain/usecases/listar_cobertura_tiles_use_case.dart';
import 'package:colportores_mobile/features/tiles/domain/usecases/observar_paquete_offline_use_case.dart';
import 'package:colportores_mobile/features/tiles/domain/usecases/sugerir_paquete_tiles_use_case.dart';
import 'package:dartz/dartz.dart';
import 'package:test/test.dart';

import '../../../../../helpers/tiles_falsos.dart';

void main() {
  const ambito = AmbitoTrabajo(zonaId: 'z-1', ciudadId: 'c-1', departamentoId: 'd-1');
  final bytes = bytesDePrueba(10);
  late RepositorioTilesEnMemoria repositorio;

  PaqueteTiles construir(NivelCobertura nivel, String? ambitoId) {
    return paqueteDe(bytes, id: '${nivel.name}-$ambitoId', nivel: nivel, ambitoId: ambitoId);
  }

  PaqueteDescargado descargado(PaqueteTiles paquete) => descargadoDe(paquete);

  final zona = construir(NivelCobertura.zona, 'z-1');
  final ciudad = construir(NivelCobertura.ciudad, 'c-1');
  final departamento = construir(NivelCobertura.departamento, 'd-1');
  final uruguay = construir(NivelCobertura.uruguay, null);
  final otraZona = construir(NivelCobertura.zona, 'z-9');

  setUp(() {
    repositorio = RepositorioTilesEnMemoria()
      ..paquetesCatalogo = [uruguay, otraZona, departamento, ciudad, zona];
  });

  group('ListarCoberturaTilesUseCase', () {
    const listar = ListarCoberturaTilesUseCase.new;

    test('dado el catálogo y lo descargado, arma una opción por nivel y aparta los descargados de '
        'otro lugar', () async {
      await repositorio.registrar(descargado(ciudad));
      await repositorio.registrar(descargado(otraZona));

      final cobertura = (await listar(repositorio)(ambito)).getOrElse(() => fail('Left'));

      final niveles = cobertura.opciones.map((o) => o.nivel);
      expect(niveles, NivelCobertura.values);
      expect(cobertura.opciones.map((o) => o.paquete), [zona, ciudad, departamento, uruguay]);
      expect(cobertura.opciones.map((o) => o.descargado), [null, descargado(ciudad), null, null]);
      expect(cobertura.otrosDescargados, [descargado(otraZona)]);
      expect(cobertura.falloCatalogo, isNull);
    });

    test('dado que no se puede leer el catálogo, igual muestra lo descargado', () async {
      repositorio.falloCatalogo = const FailureSinConexion();
      await repositorio.registrar(descargado(ciudad));

      final cobertura = (await listar(repositorio)(ambito)).getOrElse(() => fail('Left'));

      expect(cobertura.opciones.map((o) => o.paquete), everyElement(isNull));
      expect(cobertura.opciones[1].descargado, descargado(ciudad));
      expect(cobertura.falloCatalogo, const FailureSinConexion());
    });

    test('dado que no se pueden leer los descargados, devuelve ese Failure', () async {
      repositorio.falloDescargados = const FailureInesperado();

      final resultado = await listar(repositorio)(ambito);

      expect(resultado.isLeft(), isTrue);
    });
  });

  group('SugerirPaqueteTilesUseCase — HU-CAM-005', () {
    const sugerir = SugerirPaqueteTilesUseCase.new;

    test('dado que cambié de lugar sin paquete, sugiere el de la zona', () async {
      expect(await sugerir(repositorio)(ambito), Right<Failure, PaqueteTiles?>(zona));
    });

    test('dado que el lugar nuevo no tiene zona, sugiere la ciudad; '
        'sin ciudad, el departamento', () async {
      const sinZona = AmbitoTrabajo(ciudadId: 'c-1', departamentoId: 'd-1');
      const soloDepartamento = AmbitoTrabajo(departamentoId: 'd-1');

      expect(await sugerir(repositorio)(sinZona), Right<Failure, PaqueteTiles?>(ciudad));
      expect(
        await sugerir(repositorio)(soloDepartamento),
        Right<Failure, PaqueteTiles?>(departamento),
      );
    });

    test('dado que solo Uruguay cubre el lugar, no sugiere nada (lo elige el colportor)', () async {
      repositorio.paquetesCatalogo = [uruguay];

      expect(await sugerir(repositorio)(ambito), const Right<Failure, PaqueteTiles?>(null));
    });

    test('dado que ya tengo un paquete que cubre el lugar nuevo, no sugiere nada', () async {
      await repositorio.registrar(descargado(departamento));

      expect(await sugerir(repositorio)(ambito), const Right<Failure, PaqueteTiles?>(null));
    });

    test('dado que no se puede leer el catálogo, devuelve ese Failure', () async {
      repositorio.falloCatalogo = const FailureSinConexion();

      final resultado = await sugerir(repositorio)(ambito);

      expect(resultado, const Left<Failure, PaqueteTiles?>(FailureSinConexion()));
    });
  });

  test('ObservarPaqueteOfflineUseCase — HU-UBI-003: emite el paquete que cubre el lugar al '
      'descargarlo y null al eliminarlo', () async {
    final emitidos = <PaqueteDescargado?>[];
    final suscripcion = ObservarPaqueteOfflineUseCase(repositorio)(ambito).listen(emitidos.add);
    Future<void> dejarCorrer() => Future<void>.delayed(Duration.zero);
    await dejarCorrer();

    await repositorio.registrar(descargado(otraZona));
    await dejarCorrer();
    await repositorio.registrar(descargado(zona));
    await dejarCorrer();
    await repositorio.quitar(zona.id);
    await dejarCorrer();

    expect(emitidos, [null, descargado(zona), null]);
    await suscripcion.cancel();
  });

  group('descargar, pausar y eliminar', () {
    late DescargadorPaquetesTiles descargador;
    late ConectividadFalsa conectividad;
    final paquete = paqueteDe(bytesDePrueba(3000));

    setUp(() {
      final archivos = ArchivosEnMemoria();
      conectividad = ConectividadFalsa();
      descargador = DescargadorPaquetesTiles(
        conectividad: conectividad,
        espacio: EspacioFalso(),
        cliente: ServidorFalso()..archivos[paquete.origen] = bytesDePrueba(3000),
        archivos: archivos,
        checksum: ChecksumFalso(archivos),
        repository: repositorio,
      );
    });

    tearDown(() => descargador.cerrar());

    test('dado un paquete, lo descarga, pausar sin descarga no falla y eliminar lo saca', () async {
      final params = DescargarPaqueteTilesParams(paquete: paquete, permitirDatosMoviles: true);
      expect(params, DescargarPaqueteTilesParams(paquete: paquete, permitirDatosMoviles: true));
      expect(params, isNot(DescargarPaqueteTilesParams(paquete: paquete)));

      final resultado = await DescargarPaqueteTilesUseCase(descargador)(params);
      await descargador.esperar(paquete.id);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(repositorio.registrados.map((d) => d.id), [paquete.id]);
      final pausado = await PausarDescargaTilesUseCase(descargador)(paquete.id);
      expect(pausado, const Right<Failure, Unit>(unit));
      final eliminado = await EliminarPaqueteTilesUseCase(descargador)(paquete.id);
      expect(eliminado, const Right<Failure, Unit>(unit));
      expect(repositorio.registrados, isEmpty);
    });

    test('«Descargar mapa» sin conexión pide esperarla: queda en cola y no falla', () async {
      conectividad.cambiarA(TipoConexion.sinConexion);
      final params = DescargarPaqueteTilesParams(
        paquete: paquete,
        permitirDatosMoviles: true,
        esperarConexion: true,
      );
      expect(params.esperarConexion, isTrue);

      final resultado = await DescargarPaqueteTilesUseCase(descargador)(params);

      expect(resultado, const Right<Failure, Unit>(unit));
      expect(descargador.estadoDe(paquete.id), isA<DescargaPausada>());
    });
  });
}
