import 'package:equatable/equatable.dart';

import '../../../../core/domain/entities/auditoria.dart';

/// Punto de contacto dentro de una ubicación (esquema-datos.md §Modelo de Espacio, tabla
/// `espacio`). Para casa/negocio: 1 espacio con `numeroDepto == null`; para edificio: 1 espacio
/// por departamento.
class Espacio extends Equatable {
  const Espacio({
    required this.id,
    required this.ubicacionId,
    this.numeroDepto,
    this.piso,
    required this.auditoria,
  });

  /// `numero_depto` del espacio default que el alta crea para una casa (HU-UBI-001, Supuesto
  /// S13).
  ///
  /// ADR-001 y esquema-datos.md dicen `NULL` ("para casa y negocio es uno solo, con
  /// `numero_depto` nulo"); la HU y el issue #192 dicen `"—"`. Se sigue al modelo de datos, que es
  /// lo que el cloud recibe; el `"—"` queda como lo que muestra la pantalla. Para confirmar en
  /// #192: cambiarlo es cambiar esta constante.
  static const String? deptoPorDefecto = null;

  static final _ignorados = RegExp(r'[\s\-\u2010-\u2015]+');

  /// La clave con la que dos números de depto se consideran el mismo: sin espacios, sin guiones y sin
  /// distinguir mayúsculas («3B», «3 b» y «3b» son el mismo depto; «PB-A», «pb a» y «PBA» también:
  /// canvas 11, «“PB-A” y “pb a” son el mismo»). Los guiones largos (– y —, que pone el autocorrector)
  /// cuentan como guion; los puntos y las barras siguen contando. `null` si no hay número (el espacio
  /// sin número no se compara con otro).
  ///
  /// Es el único detector de repetidos: lo usan la validación del alta y la edición y la pantalla.
  static String? claveDeNumero(String? numeroDepto) {
    final limpio = numeroDepto?.replaceAll(_ignorados, '').toLowerCase();
    return limpio == null || limpio.isEmpty ? null : limpio;
  }

  final String id;

  /// FK a `ubicacion.id`.
  final String ubicacionId;

  /// Nullable (esquema-datos.md). Texto libre: en la práctica alfanumérico (ej. "3B").
  final String? numeroDepto;

  /// Nullable (esquema-datos.md). Texto libre por el mismo motivo que [numeroDepto]
  /// (ej. "PB", "1").
  final String? piso;

  final Auditoria auditoria;

  bool get estaBorrada => auditoria.estaBorrada;

  /// [claveDeNumero] de este espacio.
  String? get clave => claveDeNumero(numeroDepto);

  /// El espacio no tiene número (el espacio único de una casa que se unió a un edificio): se ve como
  /// «Sin número» y se numera con «Editar».
  bool get sinNumero => clave == null;

  @override
  List<Object?> get props => [id, ubicacionId, numeroDepto, piso, auditoria];
}
