// El respaldo de la noche con la app cerrada (HU-SYNC-005, #583): qué hace el sistema con cada
// resultado, que la DB siempre se cierre y que nada lance.
import 'package:colportores_mobile/features/respaldo/domain/services/respaldo_nocturno.dart';
import 'package:colportores_mobile/features/respaldo/domain/services/servicio_respaldo.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

final _ahora = DateTime.utc(2026, 11, 3, 6);

/// [ServicioRespaldo] que contesta lo que el test le diga y cuenta los pedidos.
final class _Servicio implements ServicioRespaldo {
  ResultadoRespaldo resultado = RespaldoHecho(fecha: _ahora, esBase: false);
  Object? errorAlRespaldar;
  final origenes = <OrigenRespaldo>[];
  int verificaciones = 0;

  @override
  Future<ResultadoRespaldo> respaldar(OrigenRespaldo origen) async {
    origenes.add(origen);
    if (errorAlRespaldar case final e?) throw e;
    return resultado;
  }

  @override
  Future<ResultadoVerificacion> verificarIntegridad() async {
    verificaciones++;
    return const CadenaIntegra(hayRespaldo: true);
  }
}

final class _Sesion implements SesionDeRespaldoNocturno {
  _Sesion(this.servicio);

  @override
  final _Servicio servicio;
  DateTime? verificada;
  Object? errorAlCerrar;
  int cierres = 0;

  @override
  Future<DateTime?> ultimaVerificacion() async => verificada;

  @override
  Future<void> cerrar() async {
    cierres++;
    if (errorAlCerrar case final e?) throw e;
  }
}

void main() {
  late _Servicio servicio;
  late _Sesion sesion;
  Object? errorAlAbrir;
  var sinSesion = false;

  RespaldoNocturno armar() => RespaldoNocturno(
    abrir: () async {
      if (errorAlAbrir case final e?) throw e;
      return sinSesion ? null : sesion;
    },
    ahora: () => _ahora,
    logger: loggerMudo(),
  );

  setUp(() {
    servicio = _Servicio();
    sesion = _Sesion(servicio)..verificada = _ahora.subtract(const Duration(days: 1));
    errorAlAbrir = null;
    sinSesion = false;
  });

  group('Escenario: backup nocturno exitoso', () {
    test(
      'dado Drive conectado, cuando corre la noche, pide el respaldo nocturno y termina',
      () async {
        final desenlace = await armar().ejecutar();

        expect(desenlace, DesenlaceNocturno.terminado);
        expect(servicio.origenes, [OrigenRespaldo.nocturno]);
        expect(OrigenRespaldo.nocturno.esAutomatico, isTrue, reason: 'pide Wi-Fi y batería');
        expect(sesion.cierres, 1, reason: 'la DB se cierra siempre');
      },
    );

    test('con la última verificación de hace menos de 7 días no verifica la cadena', () async {
      sesion.verificada = _ahora.subtract(const Duration(days: 6, hours: 23));

      await armar().ejecutar();

      expect(servicio.verificaciones, 0);
    });

    test('pasados 7 días de la última verificación, la hace de noche', () async {
      sesion.verificada = _ahora.subtract(const Duration(days: 7));

      await armar().ejecutar();

      expect(servicio.verificaciones, 1);
    });

    test('si nunca se verificó, la hace', () async {
      sesion.verificada = null;

      await armar().ejecutar();

      expect(servicio.verificaciones, 1);
    });

    test('si el respaldo no salió, tampoco verifica (mismas condiciones)', () async {
      sesion.verificada = null;
      servicio.resultado = const RespaldoOmitido(MotivoOmision.sinWifi);

      await armar().ejecutar();

      expect(servicio.verificaciones, 0);
    });
  });

  group('sin nada para respaldar', () {
    test('sin sesión guardada o sin Drive, termina sin pedir nada', () async {
      sinSesion = true;

      final desenlace = await armar().ejecutar();

      expect(desenlace, DesenlaceNocturno.terminado);
      expect(servicio.origenes, isEmpty);
      expect(sesion.cierres, 0, reason: 'no se abrió nada');
    });
  });

  group('qué hace el sistema con cada resultado', () {
    final casos = <String, (ResultadoRespaldo, DesenlaceNocturno)>{
      'hecho': (RespaldoHecho(fecha: _ahora, esBase: true), DesenlaceNocturno.terminado),
      'sin Drive': (const RespaldoOmitido(MotivoOmision.sinDrive), DesenlaceNocturno.terminado),
      'sin motor': (const RespaldoOmitido(MotivoOmision.sinMotor), DesenlaceNocturno.terminado),
      'en curso': (const RespaldoOmitido(MotivoOmision.enCurso), DesenlaceNocturno.terminado),
      'falló hace poco': (
        const RespaldoOmitido(MotivoOmision.falloReciente),
        DesenlaceNocturno.terminado,
      ),
      'sin Wi-Fi': (const RespaldoOmitido(MotivoOmision.sinWifi), DesenlaceNocturno.reintentar),
      'sin conexión': (
        const RespaldoOmitido(MotivoOmision.sinConexion),
        DesenlaceNocturno.reintentar,
      ),
      'batería baja': (
        const RespaldoOmitido(MotivoOmision.bateriaBaja),
        DesenlaceNocturno.reintentar,
      ),
      'permiso quitado (lo arregla la persona)': (
        const RespaldoFallido(CausaFalloRespaldo.permiso),
        DesenlaceNocturno.terminado,
      ),
      'sin espacio (lo arregla la persona)': (
        const RespaldoFallido(CausaFalloRespaldo.sinEspacio),
        DesenlaceNocturno.terminado,
      ),
      'falló la subida': (
        const RespaldoFallido(CausaFalloRespaldo.otra),
        DesenlaceNocturno.reintentar,
      ),
    };

    casos.forEach((nombre, caso) {
      test('$nombre → ${caso.$2.name}', () async {
        servicio.resultado = caso.$1;

        expect(await armar().ejecutar(), caso.$2);
        expect(sesion.cierres, 1);
      });
    });
  });

  group('lo que falla no lanza y no deja la DB abierta', () {
    test('si el respaldo lanza, pide reintentar y cierra la DB', () async {
      servicio.errorAlRespaldar = StateError('x');

      expect(await armar().ejecutar(), DesenlaceNocturno.reintentar);
      expect(sesion.cierres, 1);
    });

    test('si no se pudo abrir la sesión, pide reintentar', () async {
      errorAlAbrir = StateError('x');

      expect(await armar().ejecutar(), DesenlaceNocturno.reintentar);
    });

    test('si falla el cierre, el resultado del respaldo se conserva', () async {
      sesion.errorAlCerrar = StateError('x');

      expect(await armar().ejecutar(), DesenlaceNocturno.terminado);
      expect(sesion.cierres, 1);
    });
  });
}
