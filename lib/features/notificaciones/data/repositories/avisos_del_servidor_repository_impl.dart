import 'dart:async';

import '../../domain/entities/avisos_del_servidor.dart';
import '../../domain/repositories/avisos_del_servidor_repository.dart';
import '../datasources/preferencias_de_avisos_local_data_source_drift.dart';

/// [AvisosDelServidorRepository] sobre la DB local (backend-supabase 0207, #313, «Avisos s/red» de Cristian,
/// 24/11): lee y guarda `preferencia_de_avisos`, la fila de la persona que viaja por el sync en las dos
/// direcciones. **No necesita conexión**: guardar es escribir en el teléfono (el cambio sube con la
/// sincronización) y leer es leer lo último que bajó, así que la pantalla nunca dice «necesitás conexión».
///
/// Si la base local no puede leer o guardar, lanza lo que lanzó (la pantalla lo traduce a su aviso de error
/// con «Reintentar»).
final class AvisosDelServidorLocal implements AvisosDelServidorRepository {
  AvisosDelServidorLocal(this._local);

  final PreferenciasDeAvisosLocalDataSourceDrift _local;

  @override
  Future<AvisosDelServidor> leer() async => AvisosDelServidor.desdeJson(await _local.leer());

  @override
  Future<void> guardar(AvisosDelServidor avisos) => _local.guardar(avisos.aJson());
}

/// [AvisosDelServidorRepository] en memoria: el default de los tests y de la app sin base local abierta
/// (demo). **No es código de producción**: sin base no hay a dónde guardar, solo recuerda lo que se le dijo
/// mientras la app está abierta.
class AvisosDelServidorEnMemoria implements AvisosDelServidorRepository {
  AvisosDelServidorEnMemoria({this.avisos = const AvisosDelServidor()});

  AvisosDelServidor avisos;

  /// Si no es `null`, [leer] lanza esto.
  AvisosDelServidorException? fallaAlLeer;

  /// Si no es `null`, [guardar] lanza esto y no guarda nada.
  AvisosDelServidorException? fallaAlGuardar;

  /// Si no es `null`, [leer] espera a que se complete (el servidor todavía no contestó).
  Completer<void>? lecturaDemorada;

  /// Si no es `null`, [guardar] espera a que se complete.
  Completer<void>? guardadoDemorado;

  /// Cada objeto que se mandó a guardar, en el orden en que llegó (también los que fallaron).
  final List<Map<String, Object?>> guardados = [];

  /// Cuántas veces se leyó.
  int lecturas = 0;

  @override
  Future<AvisosDelServidor> leer() async {
    lecturas++;
    await lecturaDemorada?.future;
    final falla = fallaAlLeer;
    if (falla != null) throw falla;
    return avisos;
  }

  @override
  Future<void> guardar(AvisosDelServidor nuevos) async {
    guardados.add(nuevos.aJson());
    await guardadoDemorado?.future;
    final falla = fallaAlGuardar;
    if (falla != null) throw falla;
    avisos = nuevos;
  }
}
