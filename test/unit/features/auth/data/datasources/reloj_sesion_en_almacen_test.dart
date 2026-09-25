// HU-AUTH-007 — el reloj de la sesión no vuelve atrás.
import 'package:colportores_mobile/core/secure_storage/almacen_seguro.dart';
import 'package:colportores_mobile/core/secure_storage/fakes/almacen_seguro_en_memoria.dart';
import 'package:colportores_mobile/features/auth/data/datasources/reloj_sesion_en_almacen.dart';
import 'package:test/test.dart';

import '../../../../../helpers/logger_mudo.dart';

void main() {
  final base = DateTime.utc(2026, 9, 24, 12);
  late AlmacenSeguroEnMemoria almacen;
  late DateTime sistema;

  RelojSesionEnAlmacen crear() =>
      RelojSesionEnAlmacen(almacen, sistema: () => sistema, logger: loggerMudo());

  setUp(() {
    almacen = AlmacenSeguroEnMemoria();
    sistema = base;
  });

  test('devuelve la hora del equipo y la recuerda en el almacén seguro', () async {
    expect(await crear().ahora(), base);
    expect(almacen.contenido[ClaveSegura.relojSesion], base.toIso8601String());
  });

  test('si atrasan el reloj del equipo, sigue en la hora más alta que vio, también después de '
      'reiniciar la app', () async {
    await crear().ahora();
    sistema = base.subtract(const Duration(days: 20));

    expect(await crear().ahora(), base, reason: 'otra instancia: lee el almacén');
  });

  test('cuando el reloj del equipo vuelve a pasar la marca, avanza con él', () async {
    await crear().ahora();
    sistema = base.add(const Duration(hours: 1));

    expect(await crear().ahora(), base.add(const Duration(hours: 1)));
  });

  test('registrar solo sube la marca (p. ej. con el iat de un JWT)', () async {
    final reloj = crear();

    await reloj.registrar(base.add(const Duration(days: 2)));
    await reloj.registrar(base);

    expect(await reloj.ahora(), base.add(const Duration(days: 2)));
  });

  test('si el almacén falla, usa lo que tiene en memoria sin romper', () async {
    final reloj = crear();
    await reloj.ahora();
    almacen.simularFalla = true;
    sistema = base.subtract(const Duration(days: 1));

    expect(await reloj.ahora(), base);
  });

  test('una marca ilegible se ignora', () async {
    almacen = AlmacenSeguroEnMemoria({ClaveSegura.relojSesion: 'no-es-fecha'});

    expect(await crear().ahora(), base);
  });

  test('el reloj en memoria (demo y tests) tampoco vuelve atrás', () async {
    final reloj = RelojSesionEnMemoria(sistema: () => sistema);
    await reloj.ahora();
    sistema = base.subtract(const Duration(days: 3));
    await reloj.registrar(base.subtract(const Duration(days: 5)));

    expect(await reloj.ahora(), base);
  });
}
