import '../domain/transaccion_local.dart';
import 'app_database.dart';

/// [TransaccionLocal] sobre una transacción de Drift: las transacciones de los data sources que corren
/// adentro se vuelven puntos de guardado de esta, así que si el cuerpo lanza se revierte todo.
final class TransaccionLocalDrift implements TransaccionLocal {
  const TransaccionLocalDrift(this._db);

  final AppDatabase _db;

  @override
  Future<T> correr<T>(Future<T> Function() cuerpo) => _db.transaction(cuerpo);
}
