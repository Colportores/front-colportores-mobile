import 'package:equatable/equatable.dart';

/// Cuánto queda bloqueado el reenvío del email de verificación a una dirección cuando Supabase lo
/// rechaza por límite (decisión de Cristian, 29/09, #221): una hora fija desde el rechazo, porque
/// Supabase no informa cuánto falta.
const Duration bloqueoReenvioVerificacion = Duration(minutes: 60);

/// HU-AUTH-002: «máximo 1 reenvío cada 60 segundos». Se cuenta desde el último correo que salió a
/// esa dirección, sea el del alta o un reenvío (decisión del orquestador, 08/10, #325).
const Duration esperaReenvioVerificacion = Duration(seconds: 60);

/// Lo que el teléfono recuerda del reenvío del email de verificación, **por dirección** (los correos
/// van normalizados: sin espacios alrededor y en minúsculas, como los guarda Supabase).
///
/// Son dos cosas, cada una con su vencimiento:
/// - [bloqueos]: el candado de una hora ([bloqueoReenvioVerificacion]) que sigue a un rechazo por
///   límite (HU-AUTH-002, vista 12-A06; decisión de Cristian, 30/09, #221 y #239).
/// - [esperas]: la espera de 60 s ([esperaReenvioVerificacion]) desde el último correo que salió a
///   esa dirección (el del alta o un reenvío), para que «Reenviar en Ns» no mienta ni se reinicie
///   al salir y volver a entrar (decisión del orquestador, 08/10, #325).
final class ReenviosGuardados extends Equatable {
  const ReenviosGuardados({this.bloqueos = const {}, this.esperas = const {}});

  static const ReenviosGuardados vacio = ReenviosGuardados();

  /// Correo normalizado → instante en que vence el candado.
  final Map<String, DateTime> bloqueos;

  /// Correo normalizado → instante en que vence la espera de 60 s.
  final Map<String, DateTime> esperas;

  bool get estaVacio => bloqueos.isEmpty && esperas.isEmpty;

  /// Lo que sigue vigente a [ahora]: los vencidos se van, y **ninguno dura más que su tope** aunque
  /// cambie la hora del teléfono. Si el vencimiento guardado queda más lejos que el tope (el reloj
  /// se atrasó, o estaba adelantado cuando se guardó), se cuenta el tope completo desde [ahora], no
  /// más. Es la misma regla que ya tiene la espera del enlace de recuperación (decisión del
  /// orquestador, 05/10, #275 y #281).
  ReenviosGuardados vigentesA(DateTime ahora) {
    final instante = ahora.toUtc();
    return ReenviosGuardados(
      bloqueos: _vigentes(bloqueos, instante, bloqueoReenvioVerificacion),
      esperas: _vigentes(esperas, instante, esperaReenvioVerificacion),
    );
  }

  /// Lo mismo, con el candado de [correo] hasta [vence] (reemplaza el anterior de esa dirección).
  ReenviosGuardados conBloqueo(String correo, DateTime vence) =>
      ReenviosGuardados(bloqueos: {...bloqueos, correo: vence.toUtc()}, esperas: esperas);

  /// Lo mismo, con la espera de [correo] hasta [vence] (reemplaza la anterior de esa dirección).
  ReenviosGuardados conEspera(String correo, DateTime vence) =>
      ReenviosGuardados(bloqueos: bloqueos, esperas: {...esperas, correo: vence.toUtc()});

  /// Lo mismo, sin el candado ni la espera de [correo].
  ReenviosGuardados sin(String correo) => ReenviosGuardados(
    bloqueos: {
      for (final MapEntry(key: otro, value: vence) in bloqueos.entries)
        if (otro != correo) otro: vence,
    },
    esperas: {
      for (final MapEntry(key: otro, value: vence) in esperas.entries)
        if (otro != correo) otro: vence,
    },
  );

  static Map<String, DateTime> _vigentes(
    Map<String, DateTime> guardados,
    DateTime ahora,
    Duration tope,
  ) {
    final techo = ahora.add(tope);
    return {
      for (final MapEntry(key: correo, value: vence) in guardados.entries)
        if (vence.isAfter(ahora)) correo: vence.isAfter(techo) ? techo : vence.toUtc(),
    };
  }

  @override
  List<Object?> get props => [bloqueos, esperas];

  /// Las claves de los mapas son correos: no se imprimen nunca, ni con `EquatableConfig.stringify`
  /// en `true` (mismo criterio que los `Params` de los casos de uso; convenciones-desarrollo.md
  /// §7.5).
  @override
  bool? get stringify => false;
}
