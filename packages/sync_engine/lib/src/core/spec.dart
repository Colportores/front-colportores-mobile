import 'errors.dart';

/// Las tres políticas de §2. Toda entidad de la DB local tiene exactamente una.
enum SyncPolicy {
  /// cloud → local. Réplica de solo lectura; la app nunca escribe estas tablas.
  pull,

  /// local → cloud. La app escribe y *stagea*; el motor encola y sube por lotes.
  push,

  /// Jamás sale del dispositivo por sync. Solo backup E2E (ADR-003).
  local,
}

/// La declaración de una entidad: qué política tiene y con qué opciones (§3).
class SyncSpec {
  const SyncSpec._(
    this.entity,
    this.policy, {
    this.realtime = false,
    this.alsoPull = false,
    this.critical = false,
  });

  /// Réplica de solo lectura. Con [realtime], además se suscribe a cambios y
  /// baja el delta al instante (§5.6).
  factory SyncSpec.pull(String entity, {bool realtime = false}) =>
      SyncSpec._(entity, SyncPolicy.pull, realtime: realtime);

  /// Sube local → cloud.
  ///
  /// [critical] dispara el trigger de escritura crítica (§5.2): una venta o un
  /// cobro no espera al próximo trigger. [alsoPull] la hace bidireccional, con
  /// LWW por `sync_version`.
  factory SyncSpec.push(
    String entity, {
    bool critical = false,
    bool alsoPull = false,
  }) =>
      SyncSpec._(entity, SyncPolicy.push,
          critical: critical, alsoPull: alsoPull);

  /// Nunca sale por sync. Intentar stagearla lanza [LocalOnlyViolationError].
  factory SyncSpec.local(String entity) => SyncSpec._(entity, SyncPolicy.local);

  final String entity;
  final SyncPolicy policy;
  final bool realtime;
  final bool alsoPull;
  final bool critical;

  /// Si el motor baja delta de esta entidad: las `pull`, y las `push` con
  /// [alsoPull].
  bool get pullable => policy == SyncPolicy.pull || alsoPull;

  @override
  String toString() => 'SyncSpec($entity, ${policy.name}'
      '${realtime ? ", realtime" : ""}${alsoPull ? ", alsoPull" : ""}'
      '${critical ? ", critical" : ""})';
}

/// El registro de políticas, validado al arrancar.
///
/// Recibe [allEntities] —todas las tablas de la DB local— y no solo las
/// declaradas: es la única forma de detectar la tabla nueva que nadie registró.
/// Sin ese cruce, olvidarse de declarar una tabla con datos personales sería
/// exactamente igual de silencioso que declararla mal.
class SpecRegistry {
  factory SpecRegistry(List<SyncSpec> specs,
      {required Set<String> allEntities}) {
    final porEntidad = <String, SyncSpec>{};
    for (final spec in specs) {
      if (porEntidad.containsKey(spec.entity)) {
        throw DuplicateSpecError(spec.entity);
      }
      porEntidad[spec.entity] = spec;
    }

    final sinDeclarar = allEntities.difference(porEntidad.keys.toSet());
    if (sinDeclarar.isNotEmpty) {
      throw UnregisteredEntityError(sinDeclarar.toList()..sort());
    }

    return SpecRegistry._(porEntidad);
  }

  const SpecRegistry._(this._specs);

  final Map<String, SyncSpec> _specs;

  Iterable<SyncSpec> get all => _specs.values;

  SyncSpec of(String entity) =>
      _specs[entity] ?? (throw UnregisteredEntityError([entity]));

  SyncPolicy policyOf(String entity) => of(entity).policy;

  List<String> get pushable => [
        for (final s in all)
          if (s.policy == SyncPolicy.push) s.entity,
      ];

  /// Las que bajan delta: `pull` puras más las `push` con `alsoPull` (§7 fase 3).
  List<String> get pullable => [
        for (final s in all)
          if (s.pullable) s.entity,
      ];

  /// Solo los catálogos: política `pull` pura, sin las `alsoPull`.
  ///
  /// Es lo que pide la fase 4 de §7. Las `alsoPull` ya vinieron en la fase 3,
  /// desde el watermark del backup; volver a pedirlas desde cero las traería
  /// dos veces y además reviviría filas anteriores al backup que la DB
  /// restaurada ya tenía.
  List<String> get replicaOnly => [
        for (final s in all)
          if (s.policy == SyncPolicy.pull) s.entity,
      ];

  List<String> get realtime => [
        for (final s in all)
          if (s.realtime) s.entity,
      ];

  /// Lanza si [entity] no puede recibir un `stage()` (§2).
  void assertStageable(String entity) {
    switch (of(entity).policy) {
      case SyncPolicy.local:
        throw LocalOnlyViolationError(entity);
      case SyncPolicy.pull:
        throw ReadOnlyEntityError(entity);
      case SyncPolicy.push:
        return;
    }
  }
}
