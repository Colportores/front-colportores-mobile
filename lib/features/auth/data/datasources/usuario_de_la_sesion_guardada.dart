import 'dart:convert';

import '../../../../core/secure_storage/almacen_seguro.dart';

/// El almacén seguro no se dejó leer al buscar la sesión guardada: **no se sabe** si hay sesión. No es
/// lo mismo que «no hay sesión» (`null` en [usuarioDeLaSesionGuardada]): quien la pide decide si
/// vuelve a probar más tarde.
///
/// No lleva el error del almacén: puede traer un pedazo de lo guardado, y acá es la sesión.
final class SesionGuardadaIlegible implements Exception {
  const SesionGuardadaIlegible();

  @override
  String toString() => 'SesionGuardadaIlegible';
}

/// El id del usuario de la sesión que `supabase_flutter` dejó en el almacén seguro
/// (`ClaveSegura.sesionAuth`), o `null` si no hay sesión guardada.
///
/// Es para quien corre **sin la app** (el respaldo nocturno, un isolate de segundo plano) y necesita
/// saber de quién es la DB sin levantar Supabase ni mirar si la sesión sigue vigente: eso es de la
/// app. Una sesión vencida igual devuelve su usuario: el respaldo de la noche corre con la sesión
/// vencida (decisión del orquestador del 04/11 en #583, por HU-AUTH-007: «la expiración no afecta
/// los datos locales»; precedente #228). Solo lee el id; no devuelve ni registra el token.
///
/// Distingue dos cosas que antes eran la misma (decisión del 04/11 en #583, QA P1; #691):
/// - **no hay sesión** —nada guardado, o un valor que no es la sesión esperada—: `null`;
/// - **no se pudo leer el almacén** (por ejemplo, el Keychain de un iPhone reiniciado que no se
///   desbloqueó): lanza [SesionGuardadaIlegible]. No se afirma «sin sesión» sobre algo que no se
///   pudo mirar.
Future<String?> usuarioDeLaSesionGuardada(AlmacenSeguro almacen) async {
  final String? guardada;
  try {
    guardada = await almacen.leer(ClaveSegura.sesionAuth);
  } on Object {
    throw const SesionGuardadaIlegible();
  }
  if (guardada == null) return null;
  try {
    final json = jsonDecode(guardada);
    if (json is! Map<String, dynamic>) return null;
    final usuario = json['user'];
    if (usuario is! Map<String, dynamic>) return null;
    final id = usuario['id'];
    return id is String && id.trim().isNotEmpty ? id : null;
  } on Object {
    // Sin el mensaje: el `FormatException` de `jsonDecode` lleva un pedazo del texto, y acá es la
    // sesión.
    return null;
  }
}
