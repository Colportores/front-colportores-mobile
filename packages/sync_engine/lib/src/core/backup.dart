// La cadena de backups (ADR-003, §5.7).
//
// Un backup incremental solo sirve si se puede reconstruir la fila completa
// desde la base hasta la punta. Por eso los backups no son una lista: son una
// cadena, cada uno apuntando a su padre. Verificarla es lo que evita descubrir
// en el peor momento —un colportor sin celular— que falta un eslabón.

/// Una entrada del `appDataFolder` de Google Drive.
class BackupEntry {
  const BackupEntry({
    required this.id,
    required this.createdAt,
    required this.contentHash,
    required this.watermark,
    this.parentId,
    this.bytes = 0,
    this.exportedAt,
    this.storedHash,
    this.keyId,
  });

  /// Identidad en Drive.
  final String id;

  final DateTime createdAt;

  /// Hash del payload **cifrado**, tal como quedó subido. El motor nunca ve el
  /// contenido en claro de un backup ajeno, así que solo puede verificar esto.
  final String contentHash;

  /// El watermark de pull que tenía la DB al momento del backup.
  /// Es de donde arranca la fase 3 de §7.
  final String watermark;

  /// `null` en la base: el único backup completo de la cadena.
  final String? parentId;

  final int bytes;

  /// El instante, **del reloj del teléfono**, en que empezó a leerse la DB para
  /// armar este backup. El siguiente incremental parte de acá y no de
  /// [createdAt]: ese es el reloj de Drive y llega después de la subida, así que
  /// una fila escrita mientras se subía quedaba entre los dos y no entraba en
  /// ningún backup (HU-SYNC-005: nunca se pierde una venta). Repetir filas es
  /// inofensivo —el restore es un upsert—; saltearlas, no. `null` en un backup
  /// de una versión anterior: se usa [createdAt].
  final DateTime? exportedAt;

  /// El hash que **el archivo remoto** calculó sobre lo que guardó (en Drive, el
  /// `sha256Checksum` del archivo). Con él la integridad de la cadena se
  /// verifica sin bajar nada (HU-SYNC-009): si no coincide con [contentHash],
  /// lo que está en Drive no es lo que se subió. `null` si el archivo no lo
  /// informa; ahí `verifyChain` baja el blob.
  final String? storedHash;

  /// De qué llave es esta entrada: el identificador que dejó quien la subió
  /// ([CryptoPort.keyId]). Dos instalaciones con llaves distintas —el teléfono
  /// nuevo de una persona que cambió de equipo— comparten el mismo
  /// `appDataFolder` pero no pueden leer lo que escribió la otra. El respaldo
  /// solo encadena y solo poda lo que tiene su misma llave; lo ajeno, o lo que
  /// no trae identificador, no se toca nunca. `null` si el archivo no lo trae.
  final String? keyId;

  bool get isBase => parentId == null;

  /// Lo que se subió y lo que Drive guardó no es lo mismo.
  bool get corrupta => storedHash != null && storedHash != contentHash;
}

/// Qué le puede pasar a una cadena.
enum ChainProblem {
  /// No hay ningún backup completo del que partir.
  missingBase,

  /// Un incremental apunta a un padre que no está en Drive.
  brokenLink,

  /// Dos entradas comparten padre: dos dispositivos escribiendo la misma
  /// cadena. No se puede saber cuál rama es la buena.
  fork,

  /// Los enlaces se muerden la cola.
  cycle,

  /// Hay entradas que no cuelgan de la base.
  orphan,

  /// Una entrada existe pero lo que guarda el archivo remoto no es lo que se
  /// subió: rompe el restore igual que una que falta.
  corrupt,
}

class ChainStatus {
  const ChainStatus({
    required this.problems,
    required this.ordered,
    this.superseded = const [],
    this.corruptIds = const {},
  });

  final Set<ChainProblem> problems;

  /// Lo que quedó de una base anterior (la rotación sube la nueva antes de
  /// borrar la vieja, y borrar puede fallar). No es un problema: es basura que
  /// se poda después del próximo backup.
  final List<BackupEntry> superseded;

  /// Las entradas cuyo contenido remoto no coincide con lo subido.
  final Set<String> corruptIds;

  /// De la base a la punta. Es el orden en que hay que aplicar los payloads
  /// para reconstruir la DB. Vacío si la cadena no sirve.
  final List<BackupEntry> ordered;

  bool get ok => problems.isEmpty;

  BackupEntry? get tip => ordered.isEmpty ? null : ordered.last;

  /// De cuándo son los datos que se pueden recuperar.
  DateTime? get lastBackupAt => tip?.createdAt;

  @override
  String toString() => ok
      ? 'ChainStatus(ok, ${ordered.length} entradas, punta ${tip?.createdAt})'
      : 'ChainStatus(${problems.map((p) => p.name).join(", ")})';
}

/// Arma la cadena a partir de lo que hay en Drive y dice si sirve.
///
/// Es pura: no descarga nada. Lo que verifica son los enlaces y, si el archivo
/// remoto los informa, los hashes que **él** calculó ([BackupEntry.storedHash]).
/// Un archivo que no informa su hash se verifica bajándolo, en `verifyChain()`.
///
/// **La base vigente es la más nueva.** La rotación (30 días o 30 backups) sube
/// una base nueva y recién cuando está confirmada borra la anterior, así que
/// durante un rato hay dos. Lo que es más viejo que la base vigente y no
/// cuelga de ella es de una cadena anterior: va a [ChainStatus.superseded], no
/// es un error. Lo que es más nuevo y no cuelga de ella sí lo es.
ChainStatus buildChain(List<BackupEntry> entries) {
  if (entries.isEmpty) {
    return const ChainStatus(problems: {ChainProblem.missingBase}, ordered: []);
  }

  final porId = {for (final e in entries) e.id: e};
  final bases = entries.where((e) => e.isBase).toList()
    ..sort((a, b) {
      final porFecha = a.createdAt.compareTo(b.createdAt);
      return porFecha != 0 ? porFecha : a.id.compareTo(b.id);
    });
  if (bases.isEmpty) {
    return const ChainStatus(problems: {ChainProblem.missingBase}, ordered: []);
  }
  final vigente = bases.last;

  final hijosPorPadre = <String, List<BackupEntry>>{};
  for (final e in entries) {
    if (e.isBase || !porId.containsKey(e.parentId)) continue;
    (hijosPorPadre[e.parentId!] ??= []).add(e);
  }

  final problemas = <ChainProblem>{};
  final ordenados = <BackupEntry>[];
  final vistos = <String>{};
  var actual = vigente;
  while (true) {
    if (!vistos.add(actual.id)) {
      return const ChainStatus(problems: {ChainProblem.cycle}, ordered: []);
    }
    ordenados.add(actual);
    final hijos = hijosPorPadre[actual.id];
    if (hijos == null) break;
    if (hijos.length > 1) {
      // Dos entradas con el mismo padre: dos dispositivos escribiendo la misma
      // cadena. No se puede saber cuál rama es la buena.
      problemas.add(ChainProblem.fork);
      break;
    }
    actual = hijos.single;
  }

  final superseded = <BackupEntry>[];
  for (final e in entries) {
    if (vistos.contains(e.id)) continue;
    if (e.createdAt.isBefore(vigente.createdAt)) {
      superseded.add(e);
    } else if (e.isBase) {
      problemas.add(ChainProblem.fork);
    } else if (!porId.containsKey(e.parentId)) {
      problemas.add(ChainProblem.brokenLink);
    } else if (!problemas.contains(ChainProblem.fork)) {
      problemas.add(ChainProblem.orphan);
    }
  }

  final corruptas = {
    for (final e in ordenados)
      if (e.corrupta) e.id,
  };
  if (corruptas.isNotEmpty) problemas.add(ChainProblem.corrupt);

  if (problemas.isNotEmpty) {
    // No se ofrece una cadena a medias.
    return ChainStatus(
      problems: problemas,
      ordered: const [],
      corruptIds: corruptas,
    );
  }
  return ChainStatus(problems: const {}, ordered: ordenados, superseded: superseded);
}
