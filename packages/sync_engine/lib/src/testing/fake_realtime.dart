import 'dart:async';

import '../core/ports.dart';

/// Supabase Realtime controlado por el test.
///
/// `emit('precio_por_zona')` es lo que en producción llega cuando el
/// administrador cambia un precio: un timbre, sin datos adentro.
class FakeRealtime implements RealtimePort {
  final _control = StreamController<String>.broadcast();

  /// A qué se suscribió el motor, en orden. Volver a suscribirse deja otra
  /// entrada: es lo que verifica que `recover()` resuscribe.
  final List<List<String>> subscriptions = [];

  bool get subscribed => subscriptions.isNotEmpty && !_unsubscribed;
  bool _unsubscribed = false;

  /// Llegó un cambio de [entity] en el servidor.
  void emit(String entity) => _control.add(entity);

  @override
  Stream<String> subscribe(List<String> entities) {
    subscriptions.add(List.of(entities));
    _unsubscribed = false;
    return _control.stream;
  }

  @override
  Future<void> unsubscribe() async => _unsubscribed = true;

  Future<void> dispose() => _control.close();
}
