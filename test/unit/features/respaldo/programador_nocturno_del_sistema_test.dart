// Cómo se le pide al sistema el respaldo de la noche (HU-SYNC-005, ADR-009, R30, #583): una tarea
// periódica en Android, una tarea por vez en iOS, y nada de lo que falla sale como excepción.
import 'package:colportores_mobile/features/respaldo/data/services/programador_nocturno_del_sistema.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/logger_mudo.dart';

final class _Tareas implements TareasDelSistema {
  final llamadas = <String>[];
  Duration? primeraEspera;
  Duration? cada;
  bool? soloWifi;
  bool? cargando;
  bool? conRed;
  Object? error;

  @override
  Future<void> periodica({
    required String nombre,
    required Duration cada,
    required Duration primeraEspera,
    required bool soloWifi,
    required bool cargando,
  }) async {
    llamadas.add('periodica:$nombre');
    this.cada = cada;
    this.primeraEspera = primeraEspera;
    this.soloWifi = soloWifi;
    this.cargando = cargando;
    if (error case final e?) throw e;
  }

  @override
  Future<void> unaVez({
    required String nombre,
    required Duration espera,
    required bool conRed,
    required bool cargando,
  }) async {
    llamadas.add('unaVez:$nombre');
    primeraEspera = espera;
    this.conRed = conRed;
    this.cargando = cargando;
    if (error case final e?) throw e;
  }

  @override
  Future<void> cancelar(String nombre) async {
    llamadas.add('cancelar:$nombre');
    if (error case final e?) throw e;
  }
}

void main() {
  late _Tareas tareas;

  ProgramadorNocturnoDelSistema armar({required bool esIos}) => ProgramadorNocturnoDelSistema(
    tareas,
    esIos: esIos,
    ahora: () => DateTime(2026, 11, 2, 22),
    logger: loggerMudo(),
  );

  setUp(() => tareas = _Tareas());

  group('Android (WorkManager)', () {
    test('programa una tarea cada 24 h, la primera a las 03:00, con Wi-Fi y cargando', () async {
      await armar(esIos: false).programar();

      expect(tareas.llamadas, ['periodica:$nombreTareaRespaldoNocturno']);
      expect(tareas.cada, const Duration(hours: 24));
      expect(tareas.primeraEspera, const Duration(hours: 5));
      expect(tareas.soloWifi, isTrue);
      expect(tareas.cargando, isTrue);
    });

    test('programar dos veces reemplaza la tarea (mismo nombre)', () async {
      final programador = armar(esIos: false);

      await programador.programar();
      await programador.programar();

      expect(tareas.llamadas, hasLength(2));
      expect(tareas.llamadas.toSet(), {'periodica:$nombreTareaRespaldoNocturno'});
    });
  });

  group('iOS (BGProcessingTask)', () {
    test('programa una tarea de procesamiento para las 03:00, con red y energía externa', () async {
      await armar(esIos: true).programar();

      expect(tareas.llamadas, ['unaVez:$nombreTareaRespaldoNocturno']);
      expect(tareas.primeraEspera, const Duration(hours: 5));
      expect(tareas.conRed, isTrue);
      expect(tareas.cargando, isTrue);
    });
  });

  group('cancelar', () {
    test('saca la tarea por su nombre', () async {
      await armar(esIos: false).cancelar();

      expect(tareas.llamadas, ['cancelar:$nombreTareaRespaldoNocturno']);
    });
  });

  group('lo que falla no lanza', () {
    test('si el sistema rechaza programar o cancelar, sigue sin excepción', () async {
      tareas.error = StateError('el sistema no deja');

      await armar(esIos: false).programar();
      await armar(esIos: true).programar();
      await armar(esIos: false).cancelar();

      expect(tareas.llamadas, hasLength(3));
    });
  });
}
