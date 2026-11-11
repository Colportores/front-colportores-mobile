import 'dart:convert';

/// Lo que colgaba del espacio único de B que la unión fundió en el único de A: el espacio de B (que
/// quedó de baja), el de A y los `id` de los vínculos, visitas y agendas que pasaron de uno al otro.
final class EspacioFundido {
  const EspacioFundido({
    required this.espacioId,
    required this.unicoDeA,
    this.vinculos = const [],
    this.visitas = const [],
    this.agendas = const [],
  });

  factory EspacioFundido.fromJson(Map<String, Object?> json) => EspacioFundido(
    espacioId: json['espacio_id']! as String,
    unicoDeA: json['unico_de_a']! as String,
    vinculos: _ids(json['vinculos']),
    visitas: _ids(json['visitas']),
    agendas: _ids(json['agendas']),
  );

  /// El espacio único de B, que la unión dio de baja.
  final String espacioId;

  /// El espacio único de A, que recibió lo que colgaba de [espacioId].
  final String unicoDeA;

  /// `espacio_persona`, `visita` y `agenda` que pasaron de [espacioId] a [unicoDeA].
  final List<String> vinculos;
  final List<String> visitas;
  final List<String> agendas;

  Map<String, Object?> toJson() => {
    'espacio_id': espacioId,
    'unico_de_a': unicoDeA,
    'vinculos': vinculos,
    'visitas': visitas,
    'agendas': agendas,
  };
}

/// Qué movió una unión de duplicados en el teléfono (HU-UBI-006), para deshacerla si el servidor
/// rechaza su trabajo (decisión de Cristian, 10/11, «Unión rech.»; #679). Solo `id`: ningún dato de
/// las personas. Se guarda como JSON en `ubicacion_union_local.movimientos`.
final class MovimientosDeUnion {
  const MovimientosDeUnion({
    this.espaciosPasados = const [],
    this.espaciosFundidos = const [],
    this.agendasAlternativas = const [],
    this.vinculosAlternativos = const [],
    this.notasDelLugar = const [],
    required this.duplicadaDadaDeBaja,
    required this.conservadaPasoAEdificio,
  });

  factory MovimientosDeUnion.fromJson(Map<String, Object?> json) => MovimientosDeUnion(
    espaciosPasados: _ids(json['espacios_pasados']),
    espaciosFundidos: [
      for (final f in (json['espacios_fundidos'] as List<Object?>?) ?? const <Object?>[])
        EspacioFundido.fromJson((f! as Map).cast<String, Object?>()),
    ],
    agendasAlternativas: _ids(json['agendas_alternativas']),
    vinculosAlternativos: _ids(json['vinculos_alternativos']),
    notasDelLugar: _ids(json['notas_del_lugar']),
    duplicadaDadaDeBaja: json['duplicada_dada_de_baja'] == true,
    conservadaPasoAEdificio: json['conservada_paso_a_edificio'] == true,
  );

  factory MovimientosDeUnion.decodificar(String texto) =>
      MovimientosDeUnion.fromJson((jsonDecode(texto) as Map).cast<String, Object?>());

  /// Los espacios activos de B que pasaron enteros a A (cambió su `ubicacion_id`).
  final List<String> espaciosPasados;

  /// Los espacios únicos de B fundidos en el único de A.
  final List<EspacioFundido> espaciosFundidos;

  /// Las agendas (`ubicacion_alt_id`) y los vínculos (`ubicacion_cobranza_alt_id`) que nombraban a B
  /// como casa alternativa y pasaron a nombrar a A.
  final List<String> agendasAlternativas;
  final List<String> vinculosAlternativos;

  /// Las notas del lugar de B que pasaron a A.
  final List<String> notasDelLugar;

  /// Si la unión dio de baja a B (estaba viva). Si B ya estaba de baja, deshacer no la reactiva.
  final bool duplicadaDadaDeBaja;

  /// Si A era casa y pasó a edificio por la unión («Unir tipos»).
  final bool conservadaPasoAEdificio;

  int get cantidadPasados => espaciosPasados.length;
  int get cantidadFundidos => espaciosFundidos.length;

  Map<String, Object?> toJson() => {
    'espacios_pasados': espaciosPasados,
    'espacios_fundidos': [for (final f in espaciosFundidos) f.toJson()],
    'agendas_alternativas': agendasAlternativas,
    'vinculos_alternativos': vinculosAlternativos,
    'notas_del_lugar': notasDelLugar,
    'duplicada_dada_de_baja': duplicadaDadaDeBaja,
    'conservada_paso_a_edificio': conservadaPasoAEdificio,
  };

  String codificar() => jsonEncode(toJson());
}

List<String> _ids(Object? valor) => [
  for (final id in (valor as List<Object?>?) ?? const <Object?>[]) id! as String,
];
