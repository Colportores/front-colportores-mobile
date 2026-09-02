// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'db.dart';

// ignore_for_file: type=lint
class $SyncQueueTable extends SyncQueue
    with TableInfo<$SyncQueueTable, FilaDeCola> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncQueueTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _clientOpIdMeta = const VerificationMeta(
    'clientOpId',
  );
  @override
  late final GeneratedColumn<String> clientOpId = GeneratedColumn<String>(
    'client_op_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _entityMeta = const VerificationMeta('entity');
  @override
  late final GeneratedColumn<String> entity = GeneratedColumn<String>(
    'entity',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _opMeta = const VerificationMeta('op');
  @override
  late final GeneratedColumn<String> op = GeneratedColumn<String>(
    'op',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _payloadMeta = const VerificationMeta(
    'payload',
  );
  @override
  late final GeneratedColumn<String> payload = GeneratedColumn<String>(
    'payload',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncVersionMeta = const VerificationMeta(
    'syncVersion',
  );
  @override
  late final GeneratedColumn<int> syncVersion = GeneratedColumn<int>(
    'sync_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _codeMeta = const VerificationMeta('code');
  @override
  late final GeneratedColumn<String> code = GeneratedColumn<String>(
    'code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _messageMeta = const VerificationMeta(
    'message',
  );
  @override
  late final GeneratedColumn<String> message = GeneratedColumn<String>(
    'message',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _doneAtMeta = const VerificationMeta('doneAt');
  @override
  late final GeneratedColumn<DateTime> doneAt = GeneratedColumn<DateTime>(
    'done_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _claimedAtMeta = const VerificationMeta(
    'claimedAt',
  );
  @override
  late final GeneratedColumn<DateTime> claimedAt = GeneratedColumn<DateTime>(
    'claimed_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    clientOpId,
    entity,
    op,
    payload,
    syncVersion,
    createdAt,
    state,
    code,
    message,
    doneAt,
    claimedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_queue';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaDeCola> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('client_op_id')) {
      context.handle(
        _clientOpIdMeta,
        clientOpId.isAcceptableOrUnknown(
          data['client_op_id']!,
          _clientOpIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientOpIdMeta);
    }
    if (data.containsKey('entity')) {
      context.handle(
        _entityMeta,
        entity.isAcceptableOrUnknown(data['entity']!, _entityMeta),
      );
    } else if (isInserting) {
      context.missing(_entityMeta);
    }
    if (data.containsKey('op')) {
      context.handle(_opMeta, op.isAcceptableOrUnknown(data['op']!, _opMeta));
    } else if (isInserting) {
      context.missing(_opMeta);
    }
    if (data.containsKey('payload')) {
      context.handle(
        _payloadMeta,
        payload.isAcceptableOrUnknown(data['payload']!, _payloadMeta),
      );
    } else if (isInserting) {
      context.missing(_payloadMeta);
    }
    if (data.containsKey('sync_version')) {
      context.handle(
        _syncVersionMeta,
        syncVersion.isAcceptableOrUnknown(
          data['sync_version']!,
          _syncVersionMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('code')) {
      context.handle(
        _codeMeta,
        code.isAcceptableOrUnknown(data['code']!, _codeMeta),
      );
    }
    if (data.containsKey('message')) {
      context.handle(
        _messageMeta,
        message.isAcceptableOrUnknown(data['message']!, _messageMeta),
      );
    }
    if (data.containsKey('done_at')) {
      context.handle(
        _doneAtMeta,
        doneAt.isAcceptableOrUnknown(data['done_at']!, _doneAtMeta),
      );
    }
    if (data.containsKey('claimed_at')) {
      context.handle(
        _claimedAtMeta,
        claimedAt.isAcceptableOrUnknown(data['claimed_at']!, _claimedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FilaDeCola map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaDeCola(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      clientOpId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_op_id'],
      )!,
      entity: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entity'],
      )!,
      op: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}op'],
      )!,
      payload: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}payload'],
      )!,
      syncVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sync_version'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      code: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code'],
      )!,
      message: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}message'],
      )!,
      doneAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}done_at'],
      ),
      claimedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}claimed_at'],
      ),
    );
  }

  @override
  $SyncQueueTable createAlias(String alias) {
    return $SyncQueueTable(attachedDatabase, alias);
  }
}

class FilaDeCola extends DataClass implements Insertable<FilaDeCola> {
  /// Id local. Es lo que la app le pasa a `engine.requeue(jobId)`.
  final String id;

  /// La idempotencia del intento (§5.3). Único: encolar dos veces el mismo
  /// intento es un bug del llamador, y acá se corta.
  final String clientOpId;
  final String entity;
  final String op;

  /// El payload tal como lo devolvió `toSyncJson()`, en JSON.
  final String payload;
  final int? syncVersion;

  /// El orden de subida es este, no el de inserción (§5.5).
  final DateTime createdAt;
  final String state;
  final String code;
  final String message;

  /// Cuándo pasó a `DONE`, para la purga a los 7 días (§5.8).
  final DateTime? doneAt;

  /// Cuándo un ciclo se lo llevó a `IN_FLIGHT`.
  ///
  /// Es lo que distingue "alguien lo está mandando ahora" de "quedó colgado
  /// cuando murió el proceso". Sin esto, el ciclo de segundo plano —que corre
  /// en otro isolate sobre esta misma base— reclamaría jobs que el primer
  /// plano tiene en la mano y los reenviaría en paralelo.
  final DateTime? claimedAt;
  const FilaDeCola({
    required this.id,
    required this.clientOpId,
    required this.entity,
    required this.op,
    required this.payload,
    this.syncVersion,
    required this.createdAt,
    required this.state,
    required this.code,
    required this.message,
    this.doneAt,
    this.claimedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['client_op_id'] = Variable<String>(clientOpId);
    map['entity'] = Variable<String>(entity);
    map['op'] = Variable<String>(op);
    map['payload'] = Variable<String>(payload);
    if (!nullToAbsent || syncVersion != null) {
      map['sync_version'] = Variable<int>(syncVersion);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['state'] = Variable<String>(state);
    map['code'] = Variable<String>(code);
    map['message'] = Variable<String>(message);
    if (!nullToAbsent || doneAt != null) {
      map['done_at'] = Variable<DateTime>(doneAt);
    }
    if (!nullToAbsent || claimedAt != null) {
      map['claimed_at'] = Variable<DateTime>(claimedAt);
    }
    return map;
  }

  SyncQueueCompanion toCompanion(bool nullToAbsent) {
    return SyncQueueCompanion(
      id: Value(id),
      clientOpId: Value(clientOpId),
      entity: Value(entity),
      op: Value(op),
      payload: Value(payload),
      syncVersion: syncVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(syncVersion),
      createdAt: Value(createdAt),
      state: Value(state),
      code: Value(code),
      message: Value(message),
      doneAt: doneAt == null && nullToAbsent
          ? const Value.absent()
          : Value(doneAt),
      claimedAt: claimedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(claimedAt),
    );
  }

  factory FilaDeCola.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaDeCola(
      id: serializer.fromJson<String>(json['id']),
      clientOpId: serializer.fromJson<String>(json['clientOpId']),
      entity: serializer.fromJson<String>(json['entity']),
      op: serializer.fromJson<String>(json['op']),
      payload: serializer.fromJson<String>(json['payload']),
      syncVersion: serializer.fromJson<int?>(json['syncVersion']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      state: serializer.fromJson<String>(json['state']),
      code: serializer.fromJson<String>(json['code']),
      message: serializer.fromJson<String>(json['message']),
      doneAt: serializer.fromJson<DateTime?>(json['doneAt']),
      claimedAt: serializer.fromJson<DateTime?>(json['claimedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'clientOpId': serializer.toJson<String>(clientOpId),
      'entity': serializer.toJson<String>(entity),
      'op': serializer.toJson<String>(op),
      'payload': serializer.toJson<String>(payload),
      'syncVersion': serializer.toJson<int?>(syncVersion),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'state': serializer.toJson<String>(state),
      'code': serializer.toJson<String>(code),
      'message': serializer.toJson<String>(message),
      'doneAt': serializer.toJson<DateTime?>(doneAt),
      'claimedAt': serializer.toJson<DateTime?>(claimedAt),
    };
  }

  FilaDeCola copyWith({
    String? id,
    String? clientOpId,
    String? entity,
    String? op,
    String? payload,
    Value<int?> syncVersion = const Value.absent(),
    DateTime? createdAt,
    String? state,
    String? code,
    String? message,
    Value<DateTime?> doneAt = const Value.absent(),
    Value<DateTime?> claimedAt = const Value.absent(),
  }) => FilaDeCola(
    id: id ?? this.id,
    clientOpId: clientOpId ?? this.clientOpId,
    entity: entity ?? this.entity,
    op: op ?? this.op,
    payload: payload ?? this.payload,
    syncVersion: syncVersion.present ? syncVersion.value : this.syncVersion,
    createdAt: createdAt ?? this.createdAt,
    state: state ?? this.state,
    code: code ?? this.code,
    message: message ?? this.message,
    doneAt: doneAt.present ? doneAt.value : this.doneAt,
    claimedAt: claimedAt.present ? claimedAt.value : this.claimedAt,
  );
  FilaDeCola copyWithCompanion(SyncQueueCompanion data) {
    return FilaDeCola(
      id: data.id.present ? data.id.value : this.id,
      clientOpId: data.clientOpId.present
          ? data.clientOpId.value
          : this.clientOpId,
      entity: data.entity.present ? data.entity.value : this.entity,
      op: data.op.present ? data.op.value : this.op,
      payload: data.payload.present ? data.payload.value : this.payload,
      syncVersion: data.syncVersion.present
          ? data.syncVersion.value
          : this.syncVersion,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      state: data.state.present ? data.state.value : this.state,
      code: data.code.present ? data.code.value : this.code,
      message: data.message.present ? data.message.value : this.message,
      doneAt: data.doneAt.present ? data.doneAt.value : this.doneAt,
      claimedAt: data.claimedAt.present ? data.claimedAt.value : this.claimedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaDeCola(')
          ..write('id: $id, ')
          ..write('clientOpId: $clientOpId, ')
          ..write('entity: $entity, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('code: $code, ')
          ..write('message: $message, ')
          ..write('doneAt: $doneAt, ')
          ..write('claimedAt: $claimedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    clientOpId,
    entity,
    op,
    payload,
    syncVersion,
    createdAt,
    state,
    code,
    message,
    doneAt,
    claimedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaDeCola &&
          other.id == this.id &&
          other.clientOpId == this.clientOpId &&
          other.entity == this.entity &&
          other.op == this.op &&
          other.payload == this.payload &&
          other.syncVersion == this.syncVersion &&
          other.createdAt == this.createdAt &&
          other.state == this.state &&
          other.code == this.code &&
          other.message == this.message &&
          other.doneAt == this.doneAt &&
          other.claimedAt == this.claimedAt);
}

class SyncQueueCompanion extends UpdateCompanion<FilaDeCola> {
  final Value<String> id;
  final Value<String> clientOpId;
  final Value<String> entity;
  final Value<String> op;
  final Value<String> payload;
  final Value<int?> syncVersion;
  final Value<DateTime> createdAt;
  final Value<String> state;
  final Value<String> code;
  final Value<String> message;
  final Value<DateTime?> doneAt;
  final Value<DateTime?> claimedAt;
  final Value<int> rowid;
  const SyncQueueCompanion({
    this.id = const Value.absent(),
    this.clientOpId = const Value.absent(),
    this.entity = const Value.absent(),
    this.op = const Value.absent(),
    this.payload = const Value.absent(),
    this.syncVersion = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.state = const Value.absent(),
    this.code = const Value.absent(),
    this.message = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncQueueCompanion.insert({
    required String id,
    required String clientOpId,
    required String entity,
    required String op,
    required String payload,
    this.syncVersion = const Value.absent(),
    required DateTime createdAt,
    required String state,
    this.code = const Value.absent(),
    this.message = const Value.absent(),
    this.doneAt = const Value.absent(),
    this.claimedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       clientOpId = Value(clientOpId),
       entity = Value(entity),
       op = Value(op),
       payload = Value(payload),
       createdAt = Value(createdAt),
       state = Value(state);
  static Insertable<FilaDeCola> custom({
    Expression<String>? id,
    Expression<String>? clientOpId,
    Expression<String>? entity,
    Expression<String>? op,
    Expression<String>? payload,
    Expression<int>? syncVersion,
    Expression<DateTime>? createdAt,
    Expression<String>? state,
    Expression<String>? code,
    Expression<String>? message,
    Expression<DateTime>? doneAt,
    Expression<DateTime>? claimedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (clientOpId != null) 'client_op_id': clientOpId,
      if (entity != null) 'entity': entity,
      if (op != null) 'op': op,
      if (payload != null) 'payload': payload,
      if (syncVersion != null) 'sync_version': syncVersion,
      if (createdAt != null) 'created_at': createdAt,
      if (state != null) 'state': state,
      if (code != null) 'code': code,
      if (message != null) 'message': message,
      if (doneAt != null) 'done_at': doneAt,
      if (claimedAt != null) 'claimed_at': claimedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncQueueCompanion copyWith({
    Value<String>? id,
    Value<String>? clientOpId,
    Value<String>? entity,
    Value<String>? op,
    Value<String>? payload,
    Value<int?>? syncVersion,
    Value<DateTime>? createdAt,
    Value<String>? state,
    Value<String>? code,
    Value<String>? message,
    Value<DateTime?>? doneAt,
    Value<DateTime?>? claimedAt,
    Value<int>? rowid,
  }) {
    return SyncQueueCompanion(
      id: id ?? this.id,
      clientOpId: clientOpId ?? this.clientOpId,
      entity: entity ?? this.entity,
      op: op ?? this.op,
      payload: payload ?? this.payload,
      syncVersion: syncVersion ?? this.syncVersion,
      createdAt: createdAt ?? this.createdAt,
      state: state ?? this.state,
      code: code ?? this.code,
      message: message ?? this.message,
      doneAt: doneAt ?? this.doneAt,
      claimedAt: claimedAt ?? this.claimedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (clientOpId.present) {
      map['client_op_id'] = Variable<String>(clientOpId.value);
    }
    if (entity.present) {
      map['entity'] = Variable<String>(entity.value);
    }
    if (op.present) {
      map['op'] = Variable<String>(op.value);
    }
    if (payload.present) {
      map['payload'] = Variable<String>(payload.value);
    }
    if (syncVersion.present) {
      map['sync_version'] = Variable<int>(syncVersion.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (code.present) {
      map['code'] = Variable<String>(code.value);
    }
    if (message.present) {
      map['message'] = Variable<String>(message.value);
    }
    if (doneAt.present) {
      map['done_at'] = Variable<DateTime>(doneAt.value);
    }
    if (claimedAt.present) {
      map['claimed_at'] = Variable<DateTime>(claimedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncQueueCompanion(')
          ..write('id: $id, ')
          ..write('clientOpId: $clientOpId, ')
          ..write('entity: $entity, ')
          ..write('op: $op, ')
          ..write('payload: $payload, ')
          ..write('syncVersion: $syncVersion, ')
          ..write('createdAt: $createdAt, ')
          ..write('state: $state, ')
          ..write('code: $code, ')
          ..write('message: $message, ')
          ..write('doneAt: $doneAt, ')
          ..write('claimedAt: $claimedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FilasTable extends Filas with TableInfo<$FilasTable, FilaLocal> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FilasTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _entidadMeta = const VerificationMeta(
    'entidad',
  );
  @override
  late final GeneratedColumn<String> entidad = GeneratedColumn<String>(
    'entidad',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _datosMeta = const VerificationMeta('datos');
  @override
  late final GeneratedColumn<String> datos = GeneratedColumn<String>(
    'datos',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _actualizadoEnMeta = const VerificationMeta(
    'actualizadoEn',
  );
  @override
  late final GeneratedColumn<DateTime> actualizadoEn =
      GeneratedColumn<DateTime>(
        'actualizado_en',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  @override
  List<GeneratedColumn> get $columns => [entidad, id, datos, actualizadoEn];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'filas';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaLocal> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('entidad')) {
      context.handle(
        _entidadMeta,
        entidad.isAcceptableOrUnknown(data['entidad']!, _entidadMeta),
      );
    } else if (isInserting) {
      context.missing(_entidadMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('datos')) {
      context.handle(
        _datosMeta,
        datos.isAcceptableOrUnknown(data['datos']!, _datosMeta),
      );
    } else if (isInserting) {
      context.missing(_datosMeta);
    }
    if (data.containsKey('actualizado_en')) {
      context.handle(
        _actualizadoEnMeta,
        actualizadoEn.isAcceptableOrUnknown(
          data['actualizado_en']!,
          _actualizadoEnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_actualizadoEnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {entidad, id};
  @override
  FilaLocal map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaLocal(
      entidad: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}entidad'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      datos: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}datos'],
      )!,
      actualizadoEn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}actualizado_en'],
      )!,
    );
  }

  @override
  $FilasTable createAlias(String alias) {
    return $FilasTable(attachedDatabase, alias);
  }
}

class FilaLocal extends DataClass implements Insertable<FilaLocal> {
  final String entidad;
  final String id;
  final String datos;

  /// Cuándo la escribió el dispositivo. Es lo que hace posible el backup
  /// incremental (`export(since:)`): sin esto, cada backup tendría que subir la
  /// base entera y ADR-003 dejaría de cerrar en el plan de datos del colportor.
  ///
  /// Es hora local de escritura, no el `updated_at` del servidor: lo que
  /// interesa acá es qué cambió en este dispositivo desde el último backup.
  final DateTime actualizadoEn;
  const FilaLocal({
    required this.entidad,
    required this.id,
    required this.datos,
    required this.actualizadoEn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['entidad'] = Variable<String>(entidad);
    map['id'] = Variable<String>(id);
    map['datos'] = Variable<String>(datos);
    map['actualizado_en'] = Variable<DateTime>(actualizadoEn);
    return map;
  }

  FilasCompanion toCompanion(bool nullToAbsent) {
    return FilasCompanion(
      entidad: Value(entidad),
      id: Value(id),
      datos: Value(datos),
      actualizadoEn: Value(actualizadoEn),
    );
  }

  factory FilaLocal.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaLocal(
      entidad: serializer.fromJson<String>(json['entidad']),
      id: serializer.fromJson<String>(json['id']),
      datos: serializer.fromJson<String>(json['datos']),
      actualizadoEn: serializer.fromJson<DateTime>(json['actualizadoEn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'entidad': serializer.toJson<String>(entidad),
      'id': serializer.toJson<String>(id),
      'datos': serializer.toJson<String>(datos),
      'actualizadoEn': serializer.toJson<DateTime>(actualizadoEn),
    };
  }

  FilaLocal copyWith({
    String? entidad,
    String? id,
    String? datos,
    DateTime? actualizadoEn,
  }) => FilaLocal(
    entidad: entidad ?? this.entidad,
    id: id ?? this.id,
    datos: datos ?? this.datos,
    actualizadoEn: actualizadoEn ?? this.actualizadoEn,
  );
  FilaLocal copyWithCompanion(FilasCompanion data) {
    return FilaLocal(
      entidad: data.entidad.present ? data.entidad.value : this.entidad,
      id: data.id.present ? data.id.value : this.id,
      datos: data.datos.present ? data.datos.value : this.datos,
      actualizadoEn: data.actualizadoEn.present
          ? data.actualizadoEn.value
          : this.actualizadoEn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaLocal(')
          ..write('entidad: $entidad, ')
          ..write('id: $id, ')
          ..write('datos: $datos, ')
          ..write('actualizadoEn: $actualizadoEn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(entidad, id, datos, actualizadoEn);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaLocal &&
          other.entidad == this.entidad &&
          other.id == this.id &&
          other.datos == this.datos &&
          other.actualizadoEn == this.actualizadoEn);
}

class FilasCompanion extends UpdateCompanion<FilaLocal> {
  final Value<String> entidad;
  final Value<String> id;
  final Value<String> datos;
  final Value<DateTime> actualizadoEn;
  final Value<int> rowid;
  const FilasCompanion({
    this.entidad = const Value.absent(),
    this.id = const Value.absent(),
    this.datos = const Value.absent(),
    this.actualizadoEn = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FilasCompanion.insert({
    required String entidad,
    required String id,
    required String datos,
    required DateTime actualizadoEn,
    this.rowid = const Value.absent(),
  }) : entidad = Value(entidad),
       id = Value(id),
       datos = Value(datos),
       actualizadoEn = Value(actualizadoEn);
  static Insertable<FilaLocal> custom({
    Expression<String>? entidad,
    Expression<String>? id,
    Expression<String>? datos,
    Expression<DateTime>? actualizadoEn,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (entidad != null) 'entidad': entidad,
      if (id != null) 'id': id,
      if (datos != null) 'datos': datos,
      if (actualizadoEn != null) 'actualizado_en': actualizadoEn,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FilasCompanion copyWith({
    Value<String>? entidad,
    Value<String>? id,
    Value<String>? datos,
    Value<DateTime>? actualizadoEn,
    Value<int>? rowid,
  }) {
    return FilasCompanion(
      entidad: entidad ?? this.entidad,
      id: id ?? this.id,
      datos: datos ?? this.datos,
      actualizadoEn: actualizadoEn ?? this.actualizadoEn,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (entidad.present) {
      map['entidad'] = Variable<String>(entidad.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (datos.present) {
      map['datos'] = Variable<String>(datos.value);
    }
    if (actualizadoEn.present) {
      map['actualizado_en'] = Variable<DateTime>(actualizadoEn.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FilasCompanion(')
          ..write('entidad: $entidad, ')
          ..write('id: $id, ')
          ..write('datos: $datos, ')
          ..write('actualizadoEn: $actualizadoEn, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WatermarksTable extends Watermarks
    with TableInfo<$WatermarksTable, FilaWatermark> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WatermarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _scopeMeta = const VerificationMeta('scope');
  @override
  late final GeneratedColumn<String> scope = GeneratedColumn<String>(
    'scope',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valorMeta = const VerificationMeta('valor');
  @override
  late final GeneratedColumn<String> valor = GeneratedColumn<String>(
    'valor',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [scope, valor];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'watermarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<FilaWatermark> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('scope')) {
      context.handle(
        _scopeMeta,
        scope.isAcceptableOrUnknown(data['scope']!, _scopeMeta),
      );
    } else if (isInserting) {
      context.missing(_scopeMeta);
    }
    if (data.containsKey('valor')) {
      context.handle(
        _valorMeta,
        valor.isAcceptableOrUnknown(data['valor']!, _valorMeta),
      );
    } else if (isInserting) {
      context.missing(_valorMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {scope};
  @override
  FilaWatermark map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FilaWatermark(
      scope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}scope'],
      )!,
      valor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}valor'],
      )!,
    );
  }

  @override
  $WatermarksTable createAlias(String alias) {
    return $WatermarksTable(attachedDatabase, alias);
  }
}

class FilaWatermark extends DataClass implements Insertable<FilaWatermark> {
  final String scope;
  final String valor;
  const FilaWatermark({required this.scope, required this.valor});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['scope'] = Variable<String>(scope);
    map['valor'] = Variable<String>(valor);
    return map;
  }

  WatermarksCompanion toCompanion(bool nullToAbsent) {
    return WatermarksCompanion(scope: Value(scope), valor: Value(valor));
  }

  factory FilaWatermark.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FilaWatermark(
      scope: serializer.fromJson<String>(json['scope']),
      valor: serializer.fromJson<String>(json['valor']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'scope': serializer.toJson<String>(scope),
      'valor': serializer.toJson<String>(valor),
    };
  }

  FilaWatermark copyWith({String? scope, String? valor}) =>
      FilaWatermark(scope: scope ?? this.scope, valor: valor ?? this.valor);
  FilaWatermark copyWithCompanion(WatermarksCompanion data) {
    return FilaWatermark(
      scope: data.scope.present ? data.scope.value : this.scope,
      valor: data.valor.present ? data.valor.value : this.valor,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FilaWatermark(')
          ..write('scope: $scope, ')
          ..write('valor: $valor')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(scope, valor);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FilaWatermark &&
          other.scope == this.scope &&
          other.valor == this.valor);
}

class WatermarksCompanion extends UpdateCompanion<FilaWatermark> {
  final Value<String> scope;
  final Value<String> valor;
  final Value<int> rowid;
  const WatermarksCompanion({
    this.scope = const Value.absent(),
    this.valor = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WatermarksCompanion.insert({
    required String scope,
    required String valor,
    this.rowid = const Value.absent(),
  }) : scope = Value(scope),
       valor = Value(valor);
  static Insertable<FilaWatermark> custom({
    Expression<String>? scope,
    Expression<String>? valor,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (scope != null) 'scope': scope,
      if (valor != null) 'valor': valor,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WatermarksCompanion copyWith({
    Value<String>? scope,
    Value<String>? valor,
    Value<int>? rowid,
  }) {
    return WatermarksCompanion(
      scope: scope ?? this.scope,
      valor: valor ?? this.valor,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (scope.present) {
      map['scope'] = Variable<String>(scope.value);
    }
    if (valor.present) {
      map['valor'] = Variable<String>(valor.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WatermarksCompanion(')
          ..write('scope: $scope, ')
          ..write('valor: $valor, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$DbLocal extends GeneratedDatabase {
  _$DbLocal(QueryExecutor e) : super(e);
  $DbLocalManager get managers => $DbLocalManager(this);
  late final $SyncQueueTable syncQueue = $SyncQueueTable(this);
  late final $FilasTable filas = $FilasTable(this);
  late final $WatermarksTable watermarks = $WatermarksTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    syncQueue,
    filas,
    watermarks,
  ];
}

typedef $$SyncQueueTableCreateCompanionBuilder =
    SyncQueueCompanion Function({
      required String id,
      required String clientOpId,
      required String entity,
      required String op,
      required String payload,
      Value<int?> syncVersion,
      required DateTime createdAt,
      required String state,
      Value<String> code,
      Value<String> message,
      Value<DateTime?> doneAt,
      Value<DateTime?> claimedAt,
      Value<int> rowid,
    });
typedef $$SyncQueueTableUpdateCompanionBuilder =
    SyncQueueCompanion Function({
      Value<String> id,
      Value<String> clientOpId,
      Value<String> entity,
      Value<String> op,
      Value<String> payload,
      Value<int?> syncVersion,
      Value<DateTime> createdAt,
      Value<String> state,
      Value<String> code,
      Value<String> message,
      Value<DateTime?> doneAt,
      Value<DateTime?> claimedAt,
      Value<int> rowid,
    });

class $$SyncQueueTableFilterComposer
    extends Composer<_$DbLocal, $SyncQueueTable> {
  $$SyncQueueTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientOpId => $composableBuilder(
    column: $table.clientOpId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncQueueTableOrderingComposer
    extends Composer<_$DbLocal, $SyncQueueTable> {
  $$SyncQueueTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientOpId => $composableBuilder(
    column: $table.clientOpId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get entity => $composableBuilder(
    column: $table.entity,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get op => $composableBuilder(
    column: $table.op,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get payload => $composableBuilder(
    column: $table.payload,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get code => $composableBuilder(
    column: $table.code,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get message => $composableBuilder(
    column: $table.message,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get doneAt => $composableBuilder(
    column: $table.doneAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get claimedAt => $composableBuilder(
    column: $table.claimedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncQueueTableAnnotationComposer
    extends Composer<_$DbLocal, $SyncQueueTable> {
  $$SyncQueueTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get clientOpId => $composableBuilder(
    column: $table.clientOpId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get entity =>
      $composableBuilder(column: $table.entity, builder: (column) => column);

  GeneratedColumn<String> get op =>
      $composableBuilder(column: $table.op, builder: (column) => column);

  GeneratedColumn<String> get payload =>
      $composableBuilder(column: $table.payload, builder: (column) => column);

  GeneratedColumn<int> get syncVersion => $composableBuilder(
    column: $table.syncVersion,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get code =>
      $composableBuilder(column: $table.code, builder: (column) => column);

  GeneratedColumn<String> get message =>
      $composableBuilder(column: $table.message, builder: (column) => column);

  GeneratedColumn<DateTime> get doneAt =>
      $composableBuilder(column: $table.doneAt, builder: (column) => column);

  GeneratedColumn<DateTime> get claimedAt =>
      $composableBuilder(column: $table.claimedAt, builder: (column) => column);
}

class $$SyncQueueTableTableManager
    extends
        RootTableManager<
          _$DbLocal,
          $SyncQueueTable,
          FilaDeCola,
          $$SyncQueueTableFilterComposer,
          $$SyncQueueTableOrderingComposer,
          $$SyncQueueTableAnnotationComposer,
          $$SyncQueueTableCreateCompanionBuilder,
          $$SyncQueueTableUpdateCompanionBuilder,
          (FilaDeCola, BaseReferences<_$DbLocal, $SyncQueueTable, FilaDeCola>),
          FilaDeCola,
          PrefetchHooks Function()
        > {
  $$SyncQueueTableTableManager(_$DbLocal db, $SyncQueueTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncQueueTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncQueueTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncQueueTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> clientOpId = const Value.absent(),
                Value<String> entity = const Value.absent(),
                Value<String> op = const Value.absent(),
                Value<String> payload = const Value.absent(),
                Value<int?> syncVersion = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String> code = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<DateTime?> doneAt = const Value.absent(),
                Value<DateTime?> claimedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion(
                id: id,
                clientOpId: clientOpId,
                entity: entity,
                op: op,
                payload: payload,
                syncVersion: syncVersion,
                createdAt: createdAt,
                state: state,
                code: code,
                message: message,
                doneAt: doneAt,
                claimedAt: claimedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String clientOpId,
                required String entity,
                required String op,
                required String payload,
                Value<int?> syncVersion = const Value.absent(),
                required DateTime createdAt,
                required String state,
                Value<String> code = const Value.absent(),
                Value<String> message = const Value.absent(),
                Value<DateTime?> doneAt = const Value.absent(),
                Value<DateTime?> claimedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncQueueCompanion.insert(
                id: id,
                clientOpId: clientOpId,
                entity: entity,
                op: op,
                payload: payload,
                syncVersion: syncVersion,
                createdAt: createdAt,
                state: state,
                code: code,
                message: message,
                doneAt: doneAt,
                claimedAt: claimedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncQueueTableProcessedTableManager =
    ProcessedTableManager<
      _$DbLocal,
      $SyncQueueTable,
      FilaDeCola,
      $$SyncQueueTableFilterComposer,
      $$SyncQueueTableOrderingComposer,
      $$SyncQueueTableAnnotationComposer,
      $$SyncQueueTableCreateCompanionBuilder,
      $$SyncQueueTableUpdateCompanionBuilder,
      (FilaDeCola, BaseReferences<_$DbLocal, $SyncQueueTable, FilaDeCola>),
      FilaDeCola,
      PrefetchHooks Function()
    >;
typedef $$FilasTableCreateCompanionBuilder =
    FilasCompanion Function({
      required String entidad,
      required String id,
      required String datos,
      required DateTime actualizadoEn,
      Value<int> rowid,
    });
typedef $$FilasTableUpdateCompanionBuilder =
    FilasCompanion Function({
      Value<String> entidad,
      Value<String> id,
      Value<String> datos,
      Value<DateTime> actualizadoEn,
      Value<int> rowid,
    });

class $$FilasTableFilterComposer extends Composer<_$DbLocal, $FilasTable> {
  $$FilasTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get entidad => $composableBuilder(
    column: $table.entidad,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get datos => $composableBuilder(
    column: $table.datos,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FilasTableOrderingComposer extends Composer<_$DbLocal, $FilasTable> {
  $$FilasTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get entidad => $composableBuilder(
    column: $table.entidad,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get datos => $composableBuilder(
    column: $table.datos,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FilasTableAnnotationComposer extends Composer<_$DbLocal, $FilasTable> {
  $$FilasTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get entidad =>
      $composableBuilder(column: $table.entidad, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get datos =>
      $composableBuilder(column: $table.datos, builder: (column) => column);

  GeneratedColumn<DateTime> get actualizadoEn => $composableBuilder(
    column: $table.actualizadoEn,
    builder: (column) => column,
  );
}

class $$FilasTableTableManager
    extends
        RootTableManager<
          _$DbLocal,
          $FilasTable,
          FilaLocal,
          $$FilasTableFilterComposer,
          $$FilasTableOrderingComposer,
          $$FilasTableAnnotationComposer,
          $$FilasTableCreateCompanionBuilder,
          $$FilasTableUpdateCompanionBuilder,
          (FilaLocal, BaseReferences<_$DbLocal, $FilasTable, FilaLocal>),
          FilaLocal,
          PrefetchHooks Function()
        > {
  $$FilasTableTableManager(_$DbLocal db, $FilasTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FilasTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FilasTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FilasTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> entidad = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<String> datos = const Value.absent(),
                Value<DateTime> actualizadoEn = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FilasCompanion(
                entidad: entidad,
                id: id,
                datos: datos,
                actualizadoEn: actualizadoEn,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String entidad,
                required String id,
                required String datos,
                required DateTime actualizadoEn,
                Value<int> rowid = const Value.absent(),
              }) => FilasCompanion.insert(
                entidad: entidad,
                id: id,
                datos: datos,
                actualizadoEn: actualizadoEn,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FilasTableProcessedTableManager =
    ProcessedTableManager<
      _$DbLocal,
      $FilasTable,
      FilaLocal,
      $$FilasTableFilterComposer,
      $$FilasTableOrderingComposer,
      $$FilasTableAnnotationComposer,
      $$FilasTableCreateCompanionBuilder,
      $$FilasTableUpdateCompanionBuilder,
      (FilaLocal, BaseReferences<_$DbLocal, $FilasTable, FilaLocal>),
      FilaLocal,
      PrefetchHooks Function()
    >;
typedef $$WatermarksTableCreateCompanionBuilder =
    WatermarksCompanion Function({
      required String scope,
      required String valor,
      Value<int> rowid,
    });
typedef $$WatermarksTableUpdateCompanionBuilder =
    WatermarksCompanion Function({
      Value<String> scope,
      Value<String> valor,
      Value<int> rowid,
    });

class $$WatermarksTableFilterComposer
    extends Composer<_$DbLocal, $WatermarksTable> {
  $$WatermarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valor => $composableBuilder(
    column: $table.valor,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WatermarksTableOrderingComposer
    extends Composer<_$DbLocal, $WatermarksTable> {
  $$WatermarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get scope => $composableBuilder(
    column: $table.scope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valor => $composableBuilder(
    column: $table.valor,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WatermarksTableAnnotationComposer
    extends Composer<_$DbLocal, $WatermarksTable> {
  $$WatermarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get scope =>
      $composableBuilder(column: $table.scope, builder: (column) => column);

  GeneratedColumn<String> get valor =>
      $composableBuilder(column: $table.valor, builder: (column) => column);
}

class $$WatermarksTableTableManager
    extends
        RootTableManager<
          _$DbLocal,
          $WatermarksTable,
          FilaWatermark,
          $$WatermarksTableFilterComposer,
          $$WatermarksTableOrderingComposer,
          $$WatermarksTableAnnotationComposer,
          $$WatermarksTableCreateCompanionBuilder,
          $$WatermarksTableUpdateCompanionBuilder,
          (
            FilaWatermark,
            BaseReferences<_$DbLocal, $WatermarksTable, FilaWatermark>,
          ),
          FilaWatermark,
          PrefetchHooks Function()
        > {
  $$WatermarksTableTableManager(_$DbLocal db, $WatermarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WatermarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WatermarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WatermarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> scope = const Value.absent(),
                Value<String> valor = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) =>
                  WatermarksCompanion(scope: scope, valor: valor, rowid: rowid),
          createCompanionCallback:
              ({
                required String scope,
                required String valor,
                Value<int> rowid = const Value.absent(),
              }) => WatermarksCompanion.insert(
                scope: scope,
                valor: valor,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WatermarksTableProcessedTableManager =
    ProcessedTableManager<
      _$DbLocal,
      $WatermarksTable,
      FilaWatermark,
      $$WatermarksTableFilterComposer,
      $$WatermarksTableOrderingComposer,
      $$WatermarksTableAnnotationComposer,
      $$WatermarksTableCreateCompanionBuilder,
      $$WatermarksTableUpdateCompanionBuilder,
      (
        FilaWatermark,
        BaseReferences<_$DbLocal, $WatermarksTable, FilaWatermark>,
      ),
      FilaWatermark,
      PrefetchHooks Function()
    >;

class $DbLocalManager {
  final _$DbLocal _db;
  $DbLocalManager(this._db);
  $$SyncQueueTableTableManager get syncQueue =>
      $$SyncQueueTableTableManager(_db, _db.syncQueue);
  $$FilasTableTableManager get filas =>
      $$FilasTableTableManager(_db, _db.filas);
  $$WatermarksTableTableManager get watermarks =>
      $$WatermarksTableTableManager(_db, _db.watermarks);
}
