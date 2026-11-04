import 'dart:convert';

import '../../../../core/secure_storage/almacen_seguro.dart';

/// El id del usuario de la sesión que `supabase_flutter` dejó en el almacén seguro
/// (`ClaveSegura.sesionAuth`), o `null` si no hay sesión guardada o no se puede leer.
///
/// Es para quien corre **sin la app** (el respaldo nocturno, un isolate de segundo plano) y necesita
/// saber de quién es la DB sin levantar Supabase ni mirar si la sesión sigue vigente: eso es de la
/// app. Solo lee el id; no devuelve ni registra el token.
///
/// Nunca lanza: un almacén que falla o un valor que no es la sesión esperada es «sin sesión», y
/// quien la pide se queda sin trabajo esa noche (el respaldo del cierre de jornada y el de la vuelta
/// a la app siguen cubriendo).
Future<String?> usuarioDeLaSesionGuardada(AlmacenSeguro almacen) async {
  try {
    final guardada = await almacen.leer(ClaveSegura.sesionAuth);
    if (guardada == null) return null;
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
