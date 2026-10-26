import 'dart:async';

import '../entities/contexto_de_la_casa.dart';
import '../entities/espacio.dart';
import '../entities/nota_del_lugar.dart';
import '../entities/persona_del_espacio.dart';
import '../entities/ubicacion.dart';
import '../repositories/espacio_repository.dart';
import '../repositories/persona_repository.dart';
import '../services/lector_notas_del_lugar.dart';
import '../services/saldos_de_personas.dart';

/// Arma, y mantiene al día, lo que la hoja de la casa muestra de una ubicación (vista 39, C·01): su
/// espacio, las personas, lo que debe cada una y la nota más reciente.
///
/// - Una casa o un negocio tiene un solo espacio (el que crea el alta): ese es el contexto. Un
///   **edificio** no: el contexto es siempre el depto (39, «Reglas comunes») y sin uno elegido no hay
///   espacio ni personas.
/// - Emite cuando cambian las personas (un alta, una baja) o la nota, con los saldos ya leídos de
///   esas personas. Un saldo que no se puede leer no frena nada: esa persona queda sin saldo (no se
///   afirma lo que no se sabe).
/// - Un error al leer el espacio, las personas o la nota sale por el `Stream`.
final class ObservarContextoDeLaCasaUseCase {
  ObservarContextoDeLaCasaUseCase({
    required this._espacios,
    required this._personas,
    required this._saldos,
    required this._notas,
  });

  final EspacioRepository _espacios;
  final PersonaRepository _personas;
  final SaldosDePersonas _saldos;
  final LectorNotasDelLugar _notas;

  /// El contexto de la ubicación [ubicacionId], que es de tipo [tipo] (el tipo decide si hay un solo
  /// espacio o un depto por elegir).
  Stream<ContextoDeLaCasa> call({required String ubicacionId, required TipoUbicacion tipo}) {
    late final StreamController<ContextoDeLaCasa> salida;
    var cancelado = false;
    StreamSubscription<List<PersonaDelEspacio>>? alPersonas;
    StreamSubscription<NotaDelLugar?>? alNota;

    String? espacioId;
    List<PersonaDelEspacio>? personas;
    var saldos = const <String, int>{};
    NotaDelLugar? nota;
    var notaLeida = false;
    // Cada lista de personas pide sus saldos: la respuesta de una lista vieja se descarta.
    var secuencia = 0;

    void emitir() {
      final lista = personas;
      if (cancelado || lista == null || !notaLeida) return;
      salida.add(
        ContextoDeLaCasa(espacioId: espacioId, personas: lista, saldosCentavos: saldos, nota: nota),
      );
    }

    Future<void> alLlegarPersonas(List<PersonaDelEspacio> lista) async {
      final numero = ++secuencia;
      var leidos = const <String, int>{};
      try {
        leidos = await _saldos.saldosPendientes([for (final p in lista) p.persona.id]);
      } on Object {
        // Sin saldo conocido, no se muestra ninguno.
      }
      if (cancelado || numero != secuencia) return;
      personas = lista;
      saldos = leidos;
      emitir();
    }

    Future<void> empezar() async {
      try {
        if (tipo != TipoUbicacion.edificio) {
          final lectura = await _espacios.listar(ubicacionId);
          final lista = lectura.fold<List<Espacio>>((falla) => throw falla, (todos) => todos);
          if (lista.isNotEmpty) espacioId = lista.first.id;
        }
        if (cancelado) return;
        final id = espacioId;
        if (id == null) {
          personas = const [];
        } else {
          alPersonas = _personas
              .observarDelEspacio(id)
              .listen(alLlegarPersonas, onError: salida.addError);
        }
        alNota = _notas.observarMasReciente(ubicacionId).listen((n) {
          nota = n;
          notaLeida = true;
          emitir();
        }, onError: salida.addError);
      } on Object catch (error, pila) {
        if (!cancelado) salida.addError(error, pila);
      }
    }

    salida = StreamController<ContextoDeLaCasa>(
      onListen: () => unawaited(empezar()),
      onCancel: () async {
        cancelado = true;
        await alPersonas?.cancel();
        await alNota?.cancel();
      },
    );
    return salida.stream;
  }
}
