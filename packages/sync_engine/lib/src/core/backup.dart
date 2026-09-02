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

  bool get isBase => parentId == null;
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
}

class ChainStatus {
  const ChainStatus({required this.problems, required this.ordered});

  final Set<ChainProblem> problems;

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
/// Es pura: no descarga nada. Lo que verifica son los enlaces, no los hashes
/// del contenido — eso necesita bajar los archivos y lo hace `verifyChain()`.
ChainStatus buildChain(List<BackupEntry> entries) {
  if (entries.isEmpty) {
    return const ChainStatus(problems: {ChainProblem.missingBase}, ordered: []);
  }

  final porId = {for (final e in entries) e.id: e};
  final problemas = <ChainProblem>{};

  final bases = entries.where((e) => e.isBase).toList();
  if (bases.isEmpty) problemas.add(ChainProblem.missingBase);
  if (bases.length > 1) problemas.add(ChainProblem.fork);

  final hijosPorPadre = <String, List<BackupEntry>>{};
  for (final e in entries) {
    if (e.isBase) continue;
    if (!porId.containsKey(e.parentId)) {
      problemas.add(ChainProblem.brokenLink);
      continue;
    }
    (hijosPorPadre[e.parentId!] ??= []).add(e);
  }
  if (hijosPorPadre.values.any((h) => h.length > 1)) {
    problemas.add(ChainProblem.fork);
  }

  if (problemas.isNotEmpty) {
    return ChainStatus(problems: problemas, ordered: const []);
  }

  final ordenados = <BackupEntry>[];
  final vistos = <String>{};
  var actual = bases.single;
  while (true) {
    if (!vistos.add(actual.id)) {
      return const ChainStatus(problems: {ChainProblem.cycle}, ordered: []);
    }
    ordenados.add(actual);
    final hijos = hijosPorPadre[actual.id];
    if (hijos == null) break;
    actual = hijos.single;
  }

  if (ordenados.length != entries.length) {
    problemas.add(ChainProblem.orphan);
    return ChainStatus(problems: problemas, ordered: const []);
  }

  return ChainStatus(problems: const {}, ordered: ordenados);
}
