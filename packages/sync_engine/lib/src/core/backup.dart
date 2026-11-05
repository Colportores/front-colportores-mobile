// La cadena de backups (ADR-003, §5.7).
//
// Un backup incremental solo sirve si se puede reconstruir la fila completa
// desde la base hasta la punta. Por eso los backups no son una lista: son una
// cadena, cada uno apuntando a su padre. Verificarla es lo que evita descubrir
// en el peor momento —un colportor sin celular— que falta un eslabón.

import 'dart:convert';

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
    this.firma,
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

  /// La firma de las anotaciones de este archivo (`parent_id`, `content_hash`,
  /// `exported_at`), hecha con una llave derivada de la de la usuaria
  /// ([CryptoPort.sign]). Es lo que impide que alguien con acceso a la carpeta
  /// de Drive reencadene archivos tocando sus anotaciones sin que se note.
  /// `null` si el archivo no la trae (un respaldo de antes de la firma): ante
  /// una verificación cuenta como cadena rota y se regenera.
  final String? firma;

  /// Lo que dice la firma de este archivo: [mensajeDeFirma] de sus anotaciones.
  String get mensajeFirmado => mensajeDeFirma(
        parentId: parentId,
        contentHash: contentHash,
        exportedAt: exportedAt,
      );

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

  /// Una entrada no trae la firma de sus anotaciones, o la que trae no
  /// coincide con la que da la llave de la usuaria: las anotaciones (padre,
  /// hash, instante) se tocaron o no las puso esta llave. Se trata como una
  /// cadena rota: el próximo respaldo parte de una base nueva.
  badSignature,
}

/// Lo que se firma de cada archivo del respaldo: el padre, el hash y el instante
/// de exportación, en ese orden y en un arreglo JSON, para que ningún valor se
/// pueda confundir con el borde del vecino (cualquier separador de texto
/// plano permitiría mover un carácter de un campo al otro). Lleva una versión
/// del esquema como primer elemento. Sin padre (la base) o sin instante, el
/// campo va como cadena vacía, igual que en las anotaciones de Drive.
///
/// El instante va como lo escribe el archivo (UTC, ISO 8601): el mismo que
/// vuelve al leerlo.
String mensajeDeFirma({
  required String? parentId,
  required String contentHash,
  required DateTime? exportedAt,
}) =>
    jsonEncode([
      'colportores/backup/anotaciones/v1',
      parentId ?? '',
      contentHash,
      exportedAt?.toUtc().toIso8601String() ?? '',
    ]);

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

/// La parte de una cadena que se puede restaurar.
///
/// [buildChain] es todo o nada, porque una cadena a medias no se *extiende*.
/// Restaurar es otra cosa: si un incremental del medio está dañado, lo que
/// viene antes sigue siendo la copia de la persona hasta esa fecha, y
/// descartarla es perder más de lo necesario (HU-SYNC-006, «Restore parcial»).
class RestorableChain {
  const RestorableChain({
    required this.ordered,
    this.problem = '',
  });

  /// De la base hacia la punta, hasta antes del primer eslabón dañado o
  /// ambiguo. Vacío si no hay base.
  final List<BackupEntry> ordered;

  /// Por qué la cadena no llega entera (`corrupt`, `fork`, `orphan`,
  /// `brokenLink`, `missingBase`), o vacío si es la cadena completa.
  final String problem;

  bool get intact => problem.isEmpty && ordered.isNotEmpty;
}

/// Arma lo que se puede restaurar de [entries]: la base vigente y los
/// incrementales encadenados sobre ella, cortando en el primero cuyo contenido
/// remoto no coincide con lo subido, o donde la cadena se bifurca. Solo mira
/// metadatos: un eslabón dañado que el archivo remoto no delata por su hash se
/// descubre al bajarlo.
RestorableChain buildRestorableChain(List<BackupEntry> entries) {
  final bases = entries.where((e) => e.isBase).toList()
    ..sort((a, b) {
      final porFecha = a.createdAt.compareTo(b.createdAt);
      return porFecha != 0 ? porFecha : a.id.compareTo(b.id);
    });
  if (bases.isEmpty) {
    return const RestorableChain(ordered: [], problem: 'missingBase');
  }
  final vigente = bases.last;
  if (vigente.corrupta) {
    return const RestorableChain(ordered: [], problem: 'corrupt');
  }

  final porId = {for (final e in entries) e.id: e};
  final hijosPorPadre = <String, List<BackupEntry>>{};
  for (final e in entries) {
    if (e.isBase || !porId.containsKey(e.parentId)) continue;
    (hijosPorPadre[e.parentId!] ??= []).add(e);
  }

  final ordenados = <BackupEntry>[vigente];
  final vistos = {vigente.id};
  var problema = '';
  var actual = vigente;
  while (true) {
    final hijos = hijosPorPadre[actual.id];
    if (hijos == null) break;
    if (hijos.length > 1) {
      problema = 'fork';
      break;
    }
    final hijo = hijos.single;
    if (!vistos.add(hijo.id)) {
      problema = 'cycle';
      break;
    }
    if (hijo.corrupta) {
      problema = 'corrupt';
      break;
    }
    ordenados.add(hijo);
    actual = hijo;
  }

  if (problema.isEmpty) {
    // Entradas más nuevas que la base que no cuelgan de ella: quedaron afuera.
    for (final e in entries) {
      if (vistos.contains(e.id) || e.createdAt.isBefore(vigente.createdAt)) {
        continue;
      }
      problema = e.isBase
          ? 'fork'
          : (porId.containsKey(e.parentId) ? 'orphan' : 'brokenLink');
      break;
    }
  }
  return RestorableChain(ordered: ordenados, problem: problema);
}

/// Una cadena de Drive que se puede restaurar, resumida para que la persona (o
/// la app) elija cuál cuando hay más de una.
class ChainCandidate {
  const ChainCandidate({
    required this.keyId,
    required this.tip,
    required this.parts,
    required this.bytes,
    required this.intact,
  });

  /// De qué llave es ([CryptoPort.keyId]); `null` si el archivo no lo trae.
  final String? keyId;

  /// La entrada más nueva de lo restaurable: de cuándo son los datos.
  final BackupEntry tip;

  /// Cuántas partes se pueden aplicar.
  final int parts;

  /// Cuántos bytes pesan, cifrados.
  final int bytes;

  /// La cadena llega entera; si no, el restore es parcial.
  final bool intact;
}

/// Lo que dejó un restore (HU-SYNC-006).
class RestoreOutcome {
  const RestoreOutcome({
    required this.tip,
    required this.applied,
    required this.total,
    required this.bytes,
    this.problem = '',
  });

  /// La última parte aplicada: de cuándo son los datos restaurados.
  final BackupEntry tip;

  /// Cuántas partes se aplicaron (la base y los incrementales).
  final int applied;

  /// Cuántas partes tenía la cadena.
  final int total;

  /// Cuántos bytes (cifrados) se aplicaron.
  final int bytes;

  /// Por qué la cadena no llegó entera, o vacío.
  final String problem;

  /// Quedaron partes afuera: lo posterior a [tip] no se restauró.
  bool get partial => problem.isNotEmpty;
}

/// Una cadena ya bajada, verificada y descifrada, lista para aplicar (HU-SYNC-006).
///
/// Todavía no se tocó la DB: [BackupService.applyChains] aplica varias juntas.
class DownloadedChain {
  const DownloadedChain({required this.payloads, required this.outcome});

  /// Los payloads descifrados, de la base a la punta.
  final List<List<int>> payloads;

  /// Qué se bajó: la punta, cuántas partes y si la cadena llegó entera.
  final RestoreOutcome outcome;
}

/// Las cadenas que se pueden restaurar de [entries], una por llave
/// ([BackupEntry.keyId]; las entradas sin identificador son una más). Las que
/// no tienen ni una base usable no aparecen.
List<ChainCandidate> chainCandidates(List<BackupEntry> entries) {
  final porLlave = <String?, List<BackupEntry>>{};
  for (final e in entries) {
    (porLlave[e.keyId] ??= []).add(e);
  }
  return [
    for (final MapEntry(:key, :value) in porLlave.entries)
      if (buildRestorableChain(value) case final cadena
          when cadena.ordered.isNotEmpty)
        ChainCandidate(
          keyId: key,
          tip: cadena.ordered.last,
          parts: cadena.ordered.length,
          bytes: cadena.ordered.fold(0, (n, e) => n + e.bytes),
          intact: cadena.intact,
        ),
  ];
}
