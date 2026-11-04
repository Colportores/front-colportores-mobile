import 'dart:async';

import '../entities/ficha_de_persona.dart';
import '../entities/nota_persona.dart';
import '../repositories/espacio_repository.dart';
import '../repositories/ficha_persona_repository.dart';
import '../repositories/nota_persona_repository.dart';
import '../services/cuenta_de_persona.dart';
import '../services/marcador_de_telefono.dart';
import '../services/movimientos_de_cuenta_de_persona.dart';

/// Arma, y mantiene al día, la ficha de una persona (HU-UBI-009, vista 32B): sus datos, su lugar, la
/// última nota, el historial (visitas, ventas, entregas y cobros por fecha) y la cuenta.
///
/// - Todo es local. Emite de nuevo cuando cambia algo de eso: una visita, una venta, una nota, la
///   persona o su lugar.
/// - Emite `null` si la persona ya no está en el teléfono.
/// - Un error al leer cualquiera de las partes sale por el `Stream` (la ficha dice «No pudimos leer…»
///   y ofrece «Reintentar»): no se muestra una ficha a medias como si estuviera completa.
/// - Cada cambio vuelve a leer el lugar, el contexto y la cuenta; la respuesta de una lectura vieja se
///   descarta si ya hay una más nueva.
final class ObservarFichaDePersonaUseCase {
  ObservarFichaDePersonaUseCase({
    required this._fichas,
    required this._notas,
    required this._espacios,
    required this._cuentas,
    required this._movimientos,
  });

  final FichaPersonaRepository _fichas;
  final NotaPersonaRepository _notas;
  final EspacioRepository _espacios;
  final CuentasDePersonas _cuentas;
  final MovimientosDeCuentaDeLaPersona _movimientos;

  /// La ficha de [personaId] vista desde [espacioId] (en un edificio, el depto).
  Stream<FichaDePersona?> call({required String personaId, required String espacioId}) {
    late final StreamController<FichaDePersona?> salida;
    final suscripciones = <StreamSubscription<Object?>>[];
    var cancelado = false;

    LecturaDeFicha? lectura;
    var lecturaLlego = false;
    List<NotaPersona>? notas;
    List<MovimientoDeFicha>? extras;
    // Cada cambio pide su ficha: la respuesta de una lectura vieja se descarta.
    var secuencia = 0;

    Future<void> armar() async {
      if (cancelado || !lecturaLlego || notas == null || extras == null) return;
      final miSecuencia = ++secuencia;
      final base = lectura;
      if (base == null) {
        salida.add(null);
        return;
      }
      final activas = [
        for (final n in notas!)
          if (!n.estaBorrada) n,
      ];
      try {
        final contexto = (await _notas.leerContexto(
          personaId,
        )).fold((falla) => throw falla, (c) => c);
        final lugar = (await _espacios.buscar(espacioId)).fold((falla) => throw falla, (l) => l);
        final resumen = await _cuentas.resumenDe(personaId);
        if (cancelado || miSecuencia != secuencia) return;
        if (contexto == null) {
          salida.add(null);
          return;
        }
        final historial = [...base.historial, ...extras!]
          ..sort((a, b) {
            final porFecha = b.fecha.compareTo(a.fecha);
            return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
          });
        salida.add(
          FichaDePersona(
            persona: base.persona,
            espacioId: espacioId,
            lugar: lugar,
            contexto: contexto,
            notas: NotasDeLaFicha(
              total: activas.length,
              ultima: activas.isEmpty ? null : activas.first,
            ),
            historial: List.unmodifiable(historial),
            resumen: resumen,
          ),
        );
      } on Object catch (error, pila) {
        if (cancelado || miSecuencia != secuencia) return;
        salida.addError(error, pila);
      }
    }

    void alError(Object error, StackTrace pila) {
      if (!cancelado) salida.addError(error, pila);
    }

    salida = StreamController<FichaDePersona?>(
      onListen: () {
        suscripciones
          ..add(
            _fichas.observar(personaId).listen((l) {
              lectura = l;
              lecturaLlego = true;
              unawaited(armar());
            }, onError: alError),
          )
          ..add(
            _notas.observar(personaId).listen((n) {
              notas = n;
              unawaited(armar());
            }, onError: alError),
          )
          ..add(
            _movimientos.observar(personaId).listen((m) {
              extras = m;
              unawaited(armar());
            }, onError: alError),
          );
      },
      onCancel: () async {
        cancelado = true;
        for (final s in suscripciones) {
          await s.cancel();
        }
      },
    );
    return salida.stream;
  }
}

/// Cómo terminó el toque en «Llamar».
enum ResultadoDeLlamada {
  /// El marcador del teléfono quedó abierto con el número.
  abierto,

  /// La persona no tiene un teléfono que marcar.
  sinTelefono,

  /// No hay marcador (una tablet, iOS) o no respondió: la colportora llama a mano.
  noSePudoAbrir,
}

/// «Llamar» de la ficha (HU-UBI-009): deja el evento `click_to_call` en la auditoría local —**sin el
/// número**— y abre el marcador del teléfono.
///
/// - La auditoría es de mejor esfuerzo: si no se puede escribir, la llamada sigue (la colportora no
///   puede quedarse sin llamar por un registro).
/// - Nunca lanza.
final class LlamarAPersonaUseCase {
  LlamarAPersonaUseCase(this._fichas, this._marcador, {DateTime Function()? ahora})
    : _ahora = ahora ?? DateTime.now;

  final FichaPersonaRepository _fichas;
  final MarcadorDeTelefono _marcador;
  final DateTime Function() _ahora;

  /// El número tal como se le pasa al marcador: solo dígitos y un `+` al comienzo; `null` si no hay
  /// dígitos.
  static String? numeroParaMarcar(String? telefono) {
    final valor = telefono?.trim() ?? '';
    final digitos = valor.replaceAll(RegExp(r'\D'), '');
    if (digitos.isEmpty) return null;
    return valor.startsWith('+') ? '+$digitos' : digitos;
  }

  Future<ResultadoDeLlamada> call({required String personaId, required String? telefono}) async {
    final numero = numeroParaMarcar(telefono);
    if (numero == null) return ResultadoDeLlamada.sinTelefono;
    try {
      await _fichas.registrarLlamada(personaId: personaId, ahora: _ahora());
    } on Object {
      // Sin la auditoría la llamada igual sale.
    }
    try {
      return await _marcador.marcar(numero)
          ? ResultadoDeLlamada.abierto
          : ResultadoDeLlamada.noSePudoAbrir;
    } on Object {
      return ResultadoDeLlamada.noSePudoAbrir;
    }
  }
}
