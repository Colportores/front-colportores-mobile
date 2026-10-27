import 'dart:async';

import '../../../../core/secure_storage/almacen_seguro.dart';
import '../../../agenda/domain/entities/anticipacion_recordatorio.dart';
import '../../../agenda/domain/services/recordatorios.dart';
import '../../domain/entities/preferencias_recordatorios.dart';
import '../../domain/repositories/preferencias_recordatorios_repository.dart';

/// [PreferenciasRecordatoriosRepository] sobre el almacén seguro: `ClaveSegura.recordatoriosActivados`
/// (`0` apagados; cualquier otra cosa o sin clave, prendidos) y `ClaveSegura.anticipacionRecordatorios`
/// (minutos).
///
/// Es también lo que lee `RecordatoriosLocales` al programar ([AnticipacionRecordatorios] y
/// [RecordatoriosActivados]): una preferencia recién guardada vale para el próximo recordatorio.
/// Serializa las operaciones: cada una espera a la anterior, así una lectura pedida después de un
/// guardado ve lo nuevo.
final class PreferenciasRecordatoriosRepositoryImpl
    implements
        PreferenciasRecordatoriosRepository,
        AnticipacionRecordatorios,
        RecordatoriosActivados {
  PreferenciasRecordatoriosRepositoryImpl(this._almacen);

  final AlmacenSeguro _almacen;

  static const _apagados = '0';
  static const _prendidos = '1';

  Future<void> _cola = Future<void>.value();

  Future<T> _encolar<T>(Future<T> Function() operacion) {
    final resultado = _cola.then((_) => operacion());
    _cola = resultado.then<void>((_) {}, onError: (Object _) {});
    return resultado;
  }

  @override
  Future<PreferenciasRecordatorios> leer() => _encolar(() async {
    final activados = await _almacen.leer(ClaveSegura.recordatoriosActivados);
    final minutos = int.tryParse(
      (await _almacen.leer(ClaveSegura.anticipacionRecordatorios)) ?? '',
    );
    return PreferenciasRecordatorios(
      activados: activados != _apagados,
      anticipacionMinutos: AnticipacionRecordatorio.acotar(
        minutos ?? AnticipacionRecordatorio.porDefecto,
      ),
    );
  });

  @override
  Future<void> guardarActivados({required bool activados}) => _encolar(
    () => _almacen.escribir(ClaveSegura.recordatoriosActivados, activados ? _prendidos : _apagados),
  );

  @override
  Future<void> guardarAnticipacion(int minutos) => _encolar(
    () => _almacen.escribir(
      ClaveSegura.anticipacionRecordatorios,
      AnticipacionRecordatorio.acotar(minutos).toString(),
    ),
  );

  @override
  Future<bool> estan() async => (await leer()).activados;

  @override
  Future<int> minutos() async => (await leer()).anticipacionMinutos;
}

/// [PreferenciasRecordatoriosRepository] en memoria: el default de los tests y de la app sin
/// Keystore. **No es código de producción**: `main.dart` lo reemplaza por
/// [PreferenciasRecordatoriosRepositoryImpl].
class PreferenciasRecordatoriosRepositoryEnMemoria
    implements
        PreferenciasRecordatoriosRepository,
        AnticipacionRecordatorios,
        RecordatoriosActivados {
  PreferenciasRecordatoriosRepositoryEnMemoria({
    this.preferencias = const PreferenciasRecordatorios(),
  });

  PreferenciasRecordatorios preferencias;

  /// Con `true`, las lecturas lanzan (simula un almacén roto).
  bool fallaAlLeer = false;

  /// Con `true`, los guardados lanzan y no guardan nada.
  bool fallaAlGuardar = false;

  /// Si no es `null`, [guardarActivados] y [guardarAnticipacion] esperan a que se complete (el
  /// almacén todavía no contestó).
  Completer<void>? guardadoDemorado;

  /// Si no es `null`, [leer] espera a que se complete (el almacén todavía no contestó).
  Completer<void>? lecturaDemorada;

  /// Cada guardado en el orden en que llegó: `activados:true`, `minutos:60`.
  final List<String> guardados = [];

  @override
  Future<PreferenciasRecordatorios> leer() async {
    await lecturaDemorada?.future;
    if (fallaAlLeer) throw const AlmacenSeguroException(operacion: 'leer');
    return preferencias;
  }

  @override
  Future<void> guardarActivados({required bool activados}) async {
    guardados.add('activados:$activados');
    await guardadoDemorado?.future;
    if (fallaAlGuardar) throw const AlmacenSeguroException(operacion: 'escribir');
    preferencias = preferencias.copyWith(activados: activados);
  }

  @override
  Future<void> guardarAnticipacion(int minutos) async {
    guardados.add('minutos:$minutos');
    await guardadoDemorado?.future;
    if (fallaAlGuardar) throw const AlmacenSeguroException(operacion: 'escribir');
    preferencias = preferencias.copyWith(
      anticipacionMinutos: AnticipacionRecordatorio.acotar(minutos),
    );
  }

  @override
  Future<bool> estan() async => (await leer()).activados;

  @override
  Future<int> minutos() async => (await leer()).anticipacionMinutos;
}
