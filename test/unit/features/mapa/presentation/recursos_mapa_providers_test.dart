// Los recursos del mapa (#286, #288): si la copia de glyphs y sprites falla, el mapa no queda muerto
// toda la sesión: los recursos vienen sin directorio (la vista arma el estilo sin ellos) y la copia
// se vuelve a intentar la próxima vez que se abre un mapa.
import 'dart:io';

import 'package:colportores_mobile/features/mapa/data/services/preparador_recursos_mapa.dart';
import 'package:colportores_mobile/features/mapa/presentation/mapa_base/recursos_mapa_providers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// El preparador con la copia reemplazada: devuelve lo que diga [accion] y cuenta las llamadas.
class _PreparadorFalso extends PreparadorRecursosMapa {
  _PreparadorFalso(this.accion) : super(directorioBase: () async => Directory.systemTemp);

  Future<String> Function() accion;
  var llamadas = 0;

  @override
  Future<String> preparar() {
    llamadas++;
    return accion();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _PreparadorFalso preparador;
  late ProviderContainer contenedor;

  setUp(() {
    preparador = _PreparadorFalso(() async => '/data/user/0/uy.colportores/files/mapa/v1');
    contenedor = ProviderContainer(
      overrides: [preparadorRecursosMapaProvider.overrideWithValue(preparador)],
    );
    addTearDown(contenedor.dispose);
  });

  /// Abre un mapa: alguien escucha los recursos mientras dure. Cerrarlo es cerrar la suscripción.
  ProviderSubscription<AsyncValue<RecursosMapa>> abrirMapa() =>
      contenedor.listen(recursosMapaProvider, (_, _) {});

  Future<RecursosMapa> recursos() => contenedor.read(recursosMapaProvider.future);

  test('con la copia hecha trae el directorio y el estilo de backend', () async {
    final abierto = abrirMapa();
    final r = await recursos();
    abierto.close();

    expect(r.directorio, '/data/user/0/uy.colportores/files/mapa/v1');
    expect(r.estiloBase, await rootBundle.loadString(rutaEstiloBaseMapa));
  });

  test(
    'si la copia falla (disco lleno) igual hay estilo, sin directorio: el mapa no muere',
    () async {
      preparador.accion = () async => throw const FileSystemException('No space left on device');
      final abierto = abrirMapa();

      final r = await recursos();
      abierto.close();

      expect(r.directorio, isNull);
      expect(r.estiloBase, contains('"layers"'));
    },
  );

  test('la copia que salió bien se conserva: volver a abrir un mapa no la repite', () async {
    final primera = abrirMapa();
    await recursos();
    primera.close();
    await contenedor.pump();

    final segunda = abrirMapa();
    final r = await recursos();
    segunda.close();

    expect(r.directorio, isNotNull);
    expect(preparador.llamadas, 1);
  });

  test('la que falló se reintenta al volver a abrir un mapa, y esa vez sí sale', () async {
    preparador.accion = () async => throw const FileSystemException('No space left on device');
    final primera = abrirMapa();
    expect((await recursos()).directorio, isNull);
    primera.close();
    await contenedor.pump();

    // Alguien liberó espacio: la próxima vez la copia sale.
    preparador.accion = () async => '/data/user/0/uy.colportores/files/mapa/v1';
    final segunda = abrirMapa();
    final r = await recursos();
    segunda.close();

    expect(preparador.llamadas, 2);
    expect(r.directorio, '/data/user/0/uy.colportores/files/mapa/v1');
  });

  test('mientras el mapa sigue abierto el fallo no se reintenta solo', () async {
    preparador.accion = () async => throw const FileSystemException('No space left on device');
    final abierto = abrirMapa();

    await recursos();
    await recursos();
    abierto.close();

    expect(preparador.llamadas, 1);
  });

  test('cerrar el mapa antes de que termine la copia no revienta', () async {
    final copia = Future<String>.value('/data/mapa');
    preparador.accion = () => copia;
    final abierto = abrirMapa();
    abierto.close();
    await contenedor.pump();

    expect(preparador.llamadas, 1);
  });
}
