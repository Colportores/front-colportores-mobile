// Qué revisa la app al arrancar y al volver al frente (HU-SYNC-005, R30; HU-SYNC-009): un respaldo
// si lleva más de 24 horas sin uno, y la verificación de la cadena si pasaron 7 días.
import 'package:colportores_mobile/features/respaldo/data/services/revision_del_respaldo.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:flutter_test/flutter_test.dart';

final _ahora = DateTime.utc(2026, 11, 2, 22);

final class _Servicio implements ServicioRespaldo {
  final List<OrigenRespaldo> respaldos = [];
  int verificaciones = 0;

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    respaldos.add(origen);
    return RespaldoHecho(fecha: _ahora, esBase: false);
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async {
    verificaciones++;
    return const CadenaIntegra(hayRespaldo: true);
  }
}

void main() {
  late _Servicio servicio;

  RevisionDelRespaldo armar({
    DateTime? ultimoRespaldo,
    DateTime? ultimaVerificacion,
    bool falla = false,
  }) => RevisionDelRespaldo(
    servicio: servicio,
    ultimoRespaldo: () async => falla ? throw StateError('motor') : ultimoRespaldo,
    ultimaVerificacion: () async => ultimaVerificacion,
    ahora: () => _ahora,
  );

  setUp(() => servicio = _Servicio());

  test('nunca hubo un respaldo ni una verificación: hace las dos cosas', () async {
    await armar().revisar();

    expect(servicio.respaldos, [OrigenRespaldo.alAbrir]);
    expect(servicio.verificaciones, 1);
  });

  test('un respaldo de hace 23 h y una verificación de hace 6 días: no hace nada', () async {
    await armar(
      ultimoRespaldo: _ahora.subtract(const Duration(hours: 23)),
      ultimaVerificacion: _ahora.subtract(const Duration(days: 6)),
    ).revisar();

    expect(servicio.respaldos, isEmpty);
    expect(servicio.verificaciones, 0);
  });

  test('a las 24 h justas toca el respaldo; a los 7 días justos, la verificación', () async {
    await armar(
      ultimoRespaldo: _ahora.subtract(const Duration(hours: 24)),
      ultimaVerificacion: _ahora.subtract(const Duration(days: 7)),
    ).revisar();

    expect(servicio.respaldos, hasLength(1));
    expect(servicio.verificaciones, 1);
  });

  test('con el respaldo al día solo verifica si le toca', () async {
    await armar(
      ultimoRespaldo: _ahora.subtract(const Duration(hours: 1)),
      ultimaVerificacion: _ahora.subtract(const Duration(days: 9)),
    ).revisar();

    expect(servicio.respaldos, isEmpty);
    expect(servicio.verificaciones, 1);
  });

  test('si no se pueden leer las fechas no lanza: se mira la próxima vez', () async {
    await armar(falla: true).revisar();

    expect(servicio.respaldos, isEmpty);
    expect(servicio.verificaciones, 0);
  });
}
