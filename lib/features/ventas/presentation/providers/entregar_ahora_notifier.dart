import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/entrega.dart';
import '../../domain/entities/linea_para_entregar.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/usecases/entregar_ahora_use_case.dart';
import 'ventas_providers.dart';

// El estado de «Entregar ahora» (vista 27, 27B·01, HU-VEN-002): qué filas están tildadas y el guardado.
// Nada se escribe hasta «Entregar»; ahí es una sola transacción.

/// Con qué se abre «Entregar ahora»: la venta recién guardada y las filas de lo que se vendió.
final class ArgumentosDeEntrega extends Equatable {
  const ArgumentosDeEntrega({required this.guardada, required this.lineas});

  final VentaGuardada guardada;
  final List<LineaParaEntregar> lineas;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [guardada, lineas];
}

final class EntregarAhoraState extends Equatable {
  const EntregarAhoraState({
    required this.marcadas,
    this.entregando = false,
    this.falla,
    this.registrada,
  });

  /// Las claves de las filas tildadas (al abrir, todas: la colportora «lleva los materiales
  /// encima»).
  final Set<String> marcadas;
  final bool entregando;

  /// Lo que salió mal al guardar; `null` si no hubo falla o ya se cambió algo.
  final Failure? falla;

  /// La entrega ya guardada: la pantalla pasa a 27B·03 o 27B·04.
  final EntregaRegistrada? registrada;

  EntregarAhoraState copiar({
    Set<String>? marcadas,
    bool? entregando,
    Failure? falla,
    bool sinFalla = false,
    EntregaRegistrada? registrada,
  }) => EntregarAhoraState(
    marcadas: marcadas ?? this.marcadas,
    entregando: entregando ?? this.entregando,
    falla: sinFalla ? null : (falla ?? this.falla),
    registrada: registrada ?? this.registrada,
  );

  @override
  List<Object?> get props => [marcadas, entregando, falla, registrada];
}

class EntregarAhoraNotifier extends Notifier<EntregarAhoraState> {
  EntregarAhoraNotifier(this.args);

  final ArgumentosDeEntrega args;

  @override
  EntregarAhoraState build() =>
      EntregarAhoraState(marcadas: {for (final linea in args.lineas) linea.clave});

  /// Tilda o destilda una fila. No hace nada mientras se guarda ni después de guardar.
  void alternar(String clave) {
    if (state.entregando || state.registrada != null) return;
    final marcadas = {...state.marcadas};
    if (!marcadas.remove(clave)) marcadas.add(clave);
    state = state.copiar(marcadas: marcadas, sinFalla: true);
  }

  /// Entrega lo tildado y deja pendiente lo destildado. Devuelve lo guardado, o `null` si no se pudo
  /// (queda la falla en el estado y lo tildado intacto), si no hay nada tildado o si ya había un
  /// guardado en curso: un doble toque no hace nada.
  Future<EntregaRegistrada?> entregar() async {
    final s = state;
    if (s.entregando || s.registrada != null || s.marcadas.isEmpty) return null;
    state = s.copiar(entregando: true, sinFalla: true);

    final venta = args.guardada.venta;
    List<ComponenteVendido> productosDe(bool tildadas) => [
      for (final linea in args.lineas)
        if (s.marcadas.contains(linea.clave) == tildadas) ...linea.productos,
    ];
    final resultado = await _guardar(
      EntregarAhoraParams(
        ventaId: venta.id,
        colportorId: venta.colportorId,
        aEntregar: productosDe(true),
        quedanPendientes: productosDe(false),
      ),
    );
    if (!ref.mounted) return resultado.fold((_) => null, (r) => r);
    return resultado.fold(
      (falla) {
        state = state.copiar(entregando: false, falla: falla);
        return null;
      },
      (registrada) {
        state = state.copiar(entregando: false, registrada: registrada);
        return registrada;
      },
    );
  }

  Future<Either<Failure, EntregaRegistrada>> _guardar(EntregarAhoraParams params) async {
    try {
      return await ref.read(entregarAhoraUseCaseProvider).call(params);
    } on Object {
      // Sin base abierta o cualquier falla inesperada: nada se guardó y lo tildado sigue.
      return const Left(FailureEntregaNoGuardada());
    }
  }
}

final entregarAhoraProvider = NotifierProvider.autoDispose
    .family<EntregarAhoraNotifier, EntregarAhoraState, ArgumentosDeEntrega>(
      EntregarAhoraNotifier.new,
    );
