import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../mapa/presentation/formato_ubicaciones.dart';
import '../../../mapa/presentation/providers/personas_providers.dart';
import '../../../mapa/presentation/textos_personas.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/entrega_pendiente.dart';
import '../../domain/usecases/cumplir_entrega_use_case.dart';
import '../../domain/usecases/diferir_entrega_use_case.dart';
import 'ventas_providers.dart';

// El estado de la entrega diferida (vista 27, grupo C, HU-VEN-003): «Entregar otro día» (27C·01), la
// lista «Entregas pendientes» (27C·02) y «Marcar entregado» (27C·03 y 27C·04). Todo es local: sin
// conexión funciona igual y la entrega se envía cuando vuelve la señal (vista 25).

Duration? _sinReintentos(int intento, Object error) => null;

/// Quién y dónde es una entrega pendiente, como se lee en la lista: «María Fernández» y «Mataojo 2044
/// · Depto 3B». Lo que ya no está en el teléfono queda vacío: la pantalla dice lo que sabe.
typedef RotuloDeEntrega = ({String persona, String direccion});

/// La clave de [rotuloDeEntregaProvider]: la casa y el vínculo de la persona.
typedef QuienEntrega = ({String? espacioId, String espacioPersonaId});

final rotuloDeEntregaProvider = FutureProvider.autoDispose.family<RotuloDeEntrega, QuienEntrega>((
  ref,
  quien,
) async {
  var persona = '';
  var direccion = '';
  final espacioId = quien.espacioId;
  if (espacioId == null) return (persona: persona, direccion: direccion);
  try {
    final lugar = await ref.watch(contextoEspacioProvider(espacioId).future);
    if (lugar != null) {
      direccion = FormatoPersonas.dondeEstaElEspacio(lugar.espacio, lugar.ubicacion);
      if (direccion.isEmpty) direccion = FormatoUbicaciones.direccionPropia(lugar.ubicacion);
    }
  } on Object {
    // Sin dirección: la tarjeta muestra lo demás.
  }
  try {
    final personas = await ref.watch(personasDelEspacioProvider(espacioId).future);
    for (final p in personas) {
      if (p.vinculo.id == quien.espacioPersonaId) {
        persona = '${p.persona.nombre} ${p.persona.apellido}'.trim();
        break;
      }
    }
  } on Object {
    // Sin nombre: idem.
  }
  return (persona: persona, direccion: direccion);
}, retry: _sinReintentos);

/// Los nombres de lo que falta entregar (`producto.id` → nombre), o `null` si el catálogo no se puede
/// leer (nunca un nombre inventado). La lista dice «N productos» y «Marcar entregado» pide
/// «Reintentar».
final nombresDeLosPendientesProvider = FutureProvider.autoDispose<Map<String, String>?>((
  ref,
) async {
  final lista = await ref.watch(entregasPendientesProvider.future);
  final ids = {
    for (final entrega in lista)
      for (final linea in entrega.lineas) linea.productoId,
  };
  if (ids.isEmpty) return const {};
  final leido = await ref
      .watch(fuenteDeProductosDeLaEntregaProvider)
      .leer(productoIds: ids, comboIds: const {});
  return leido.fold<Map<String, String>?>((_) => null, (productos) => productos.nombres);
}, retry: _sinReintentos);

/// Lo que falta entregar de la venta [ventaId], en vivo; `null` si ya no queda nada.
final entregaPendienteDeVentaProvider = Provider.autoDispose
    .family<AsyncValue<EntregaPendiente?>, String>(
      (ref, ventaId) => ref.watch(entregasPendientesProvider).whenData((lista) {
        for (final entrega in lista) {
          if (entrega.ventaId == ventaId) return entrega;
        }
        return null;
      }),
    );

// --- «Entregar otro día» (27C·01) ---

/// Con qué se abre «Entregar otro día»: la venta, quién entrega y, si la venta todavía no tiene filas
/// de entrega, qué se vendió. Si ya las tiene («Poner fecha»), [productos] va vacío.
final class ArgumentosOtroDia extends Equatable {
  const ArgumentosOtroDia({
    required this.ventaId,
    required this.colportorId,
    this.productos = const [],
  });

  final String ventaId;
  final String colportorId;
  final List<ComponenteVendido> productos;

  @override
  List<Object?> get props => [ventaId, colportorId, productos];
}

final class OtroDiaState extends Equatable {
  const OtroDiaState({this.fecha, this.guardando = false, this.falla, this.guardada});

  /// Cuándo se acordó entregar (día y hora); `null` hasta que se elige.
  final DateTime? fecha;
  final bool guardando;

  /// Lo que salió mal al guardar; `null` si no hubo falla o ya se cambió algo.
  final Failure? falla;

  /// La entrega ya guardada.
  final ResultadoDiferirEntrega? guardada;

  OtroDiaState copiar({
    DateTime? fecha,
    bool? guardando,
    Failure? falla,
    bool sinFalla = false,
    ResultadoDiferirEntrega? guardada,
  }) => OtroDiaState(
    fecha: fecha ?? this.fecha,
    guardando: guardando ?? this.guardando,
    falla: sinFalla ? null : (falla ?? this.falla),
    guardada: guardada ?? this.guardada,
  );

  @override
  List<Object?> get props => [fecha, guardando, falla, guardada];
}

class OtroDiaNotifier extends Notifier<OtroDiaState> {
  OtroDiaNotifier(this.args);

  final ArgumentosOtroDia args;

  @override
  OtroDiaState build() => const OtroDiaState();

  /// Elige el día y la hora. No hace nada mientras se guarda ni después de guardar.
  void elegirFecha(DateTime fecha) {
    if (state.guardando || state.guardada != null) return;
    state = state.copiar(fecha: fecha, sinFalla: true);
  }

  /// Guarda la entrega para la fecha elegida. Devuelve lo guardado, o `null` si no se pudo (queda la
  /// falla en el estado y la fecha intacta), si falta elegir la fecha o si ya había un guardado en
  /// curso: un doble toque no hace nada.
  Future<ResultadoDiferirEntrega?> guardar() async {
    final s = state;
    final fecha = s.fecha;
    if (s.guardando || s.guardada != null || fecha == null) return null;
    state = s.copiar(guardando: true, sinFalla: true);

    Either<Failure, ResultadoDiferirEntrega> resultado;
    try {
      resultado = await ref
          .read(diferirEntregaUseCaseProvider)
          .call(
            DiferirEntregaParams(
              ventaId: args.ventaId,
              colportorId: args.colportorId,
              fechaPrevista: fecha,
              productos: args.productos,
            ),
          );
    } on Object {
      // Sin base abierta o cualquier falla inesperada: nada se guardó y la fecha sigue.
      resultado = const Left(FailureEntregaNoGuardada());
    }
    if (!ref.mounted) return resultado.fold((_) => null, (r) => r);
    return resultado.fold(
      (falla) {
        state = state.copiar(guardando: false, falla: falla);
        return null;
      },
      (guardada) {
        state = state.copiar(guardando: false, guardada: guardada);
        return guardada;
      },
    );
  }
}

final otroDiaProvider = NotifierProvider.autoDispose
    .family<OtroDiaNotifier, OtroDiaState, ArgumentosOtroDia>(OtroDiaNotifier.new);

// --- «Marcar entregado» (27C·03 y 27C·04) ---

final class MarcarState extends Equatable {
  const MarcarState({
    this.desmarcadas = const {},
    this.nuevaFecha,
    this.guardando = false,
    this.falla,
    this.guardada,
  });

  /// Las filas (`entrega.id`) que la colportora destildó: siguen pendientes. Al abrir no hay ninguna
  /// (se entrega todo lo que falta).
  final Set<String> desmarcadas;

  /// Para cuándo queda lo que no se entrega; `null`: «Sin fecha».
  final DateTime? nuevaFecha;
  final bool guardando;
  final Failure? falla;
  final ResultadoCumplirEntrega? guardada;

  MarcarState copiar({
    Set<String>? desmarcadas,
    DateTime? nuevaFecha,
    bool sinNuevaFecha = false,
    bool? guardando,
    Failure? falla,
    bool sinFalla = false,
    ResultadoCumplirEntrega? guardada,
  }) => MarcarState(
    desmarcadas: desmarcadas ?? this.desmarcadas,
    nuevaFecha: sinNuevaFecha ? null : (nuevaFecha ?? this.nuevaFecha),
    guardando: guardando ?? this.guardando,
    falla: sinFalla ? null : (falla ?? this.falla),
    guardada: guardada ?? this.guardada,
  );

  @override
  List<Object?> get props => [desmarcadas, nuevaFecha, guardando, falla, guardada];
}

class MarcarNotifier extends Notifier<MarcarState> {
  MarcarNotifier(this.ventaId);

  final String ventaId;

  @override
  MarcarState build() => const MarcarState();

  /// Tilda o destilda una fila. No hace nada mientras se guarda ni después de guardar.
  void alternar(String entregaId) {
    if (state.guardando || state.guardada != null) return;
    final desmarcadas = {...state.desmarcadas};
    if (!desmarcadas.remove(entregaId)) desmarcadas.add(entregaId);
    state = state.copiar(desmarcadas: desmarcadas, sinFalla: true);
  }

  /// Elige para cuándo queda lo que no se entrega; `null` lo deja «Sin fecha».
  void elegirNuevaFecha(DateTime? fecha) {
    if (state.guardando || state.guardada != null) return;
    state = state.copiar(nuevaFecha: fecha, sinNuevaFecha: fecha == null, sinFalla: true);
  }

  /// Marca como entregado lo tildado de [filas] (las filas pendientes de ahora). Devuelve lo guardado,
  /// o `null` si no se pudo (queda la falla en el estado y lo tildado intacto), si no hay nada
  /// tildado o si ya había un guardado en curso: un doble toque no hace nada.
  Future<ResultadoCumplirEntrega?> marcar(List<String> filas) async {
    final s = state;
    if (s.guardando || s.guardada != null) return null;
    final aEntregar = {
      for (final id in filas)
        if (!s.desmarcadas.contains(id)) id,
    };
    if (aEntregar.isEmpty) return null;
    state = s.copiar(guardando: true, sinFalla: true);

    // Solo hay fecha nueva si queda algo sin entregar.
    final queda = aEntregar.length < filas.length;
    Either<Failure, ResultadoCumplirEntrega> resultado;
    try {
      resultado = await ref
          .read(cumplirEntregaUseCaseProvider)
          .call(
            CumplirEntregaParams(
              ventaId: ventaId,
              entregaIds: aEntregar,
              nuevaFecha: queda ? s.nuevaFecha : null,
            ),
          );
    } on Object {
      resultado = const Left(FailureEntregaNoGuardada());
    }
    if (!ref.mounted) return resultado.fold((_) => null, (r) => r);
    return resultado.fold(
      (falla) {
        state = state.copiar(guardando: false, falla: falla);
        return null;
      },
      (guardada) {
        state = state.copiar(guardando: false, guardada: guardada);
        return guardada;
      },
    );
  }
}

final marcarProvider = NotifierProvider.autoDispose.family<MarcarNotifier, MarcarState, String>(
  MarcarNotifier.new,
);
