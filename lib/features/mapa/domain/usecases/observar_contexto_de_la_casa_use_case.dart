import 'dart:async';

import '../entities/contexto_de_la_casa.dart';
import '../entities/espacio.dart';
import '../entities/nota_del_lugar.dart';
import '../entities/persona_del_espacio.dart';
import '../entities/ubicacion.dart';
import '../repositories/espacio_repository.dart';
import '../repositories/persona_repository.dart';
import '../services/cuotas_de_personas.dart';
import '../services/lector_entrevistas_de_personas.dart';
import '../services/lector_notas_del_lugar.dart';
import '../services/saldos_de_personas.dart';

/// Arma, y mantiene al día, lo que la hoja de la casa muestra de una ubicación (vista 39, C·01): su
/// espacio, las personas, lo que debe cada una, cuándo fue su última entrevista y la nota más
/// reciente.
///
/// - Una casa o un negocio tiene un solo espacio (el que crea el alta): ese es el contexto. Un
///   **edificio** no: el contexto es siempre el depto (39, «Reglas comunes») y sin uno elegido no hay
///   espacio ni personas.
/// - Emite cuando cambian las personas (un alta, una baja) o la nota, con los saldos ya leídos de
///   esas personas. Un saldo que no se puede leer no frena nada: esa persona queda sin saldo (no se
///   afirma lo que no se sabe).
/// - **Al día sin recargar** (HU-COB-005): cada vez que [cambios] avisa que algo de lo que se debe pudo
///   cambiar (un cobro, una venta, una cuota), vuelve a leer los saldos y las cuotas de las personas
///   que tiene y emite solo si algo cambió. Dos avisos seguidos no se pisan: gana la última lectura.
/// - Un error al leer el espacio, las personas o la nota sale por el `Stream`.
final class ObservarContextoDeLaCasaUseCase {
  ObservarContextoDeLaCasaUseCase({
    required this._espacios,
    required this._personas,
    required this._saldos,
    required this._notas,
    this._entrevistas = const LectorEntrevistasSinFuente(),
    this._cuotas = const CuotasDePersonasSinFuente(),
    this._cambios = sinCambiosDeLoQueSeDebe,
  });

  final EspacioRepository _espacios;
  final PersonaRepository _personas;
  final SaldosDePersonas _saldos;
  final LectorNotasDelLugar _notas;
  final LectorEntrevistasDePersonas _entrevistas;
  final CuotasDePersonas _cuotas;
  final CambiosDeLoQueSeDebe _cambios;

  /// El contexto de la ubicación [ubicacionId], que es de tipo [tipo] (el tipo decide si hay un solo
  /// espacio o un depto por elegir).
  Stream<ContextoDeLaCasa> call({required String ubicacionId, required TipoUbicacion tipo}) {
    late final StreamController<ContextoDeLaCasa> salida;
    var cancelado = false;
    StreamSubscription<List<PersonaDelEspacio>>? alPersonas;
    StreamSubscription<NotaDelLugar?>? alNota;
    StreamSubscription<void>? alosCambios;

    String? espacioId;
    List<PersonaDelEspacio>? personas;
    var saldos = const <String, int>{};
    var entrevistas = const <String, DateTime>{};
    var cuotas = const <String, DateTime>{};
    NotaDelLugar? nota;
    var notaLeida = false;
    // Cada lista de personas pide sus saldos: la respuesta de una lista vieja se descarta.
    var secuencia = 0;
    // Lecturas de una lista de personas en vuelo, y si llegó un aviso de cambio mientras tanto: la
    // lista que se está leyendo pudo haber leído antes del cambio, así que se vuelve a leer al final.
    var listasEnVuelo = 0;
    var cambioPendiente = false;
    var lecturasDeCambios = 0;

    void emitir() {
      final lista = personas;
      if (cancelado || lista == null || !notaLeida) return;
      salida.add(
        ContextoDeLaCasa(
          espacioId: espacioId,
          personas: lista,
          saldosCentavos: saldos,
          ultimaEntrevistaDe: entrevistas,
          proximaCuotaDe: cuotas,
          nota: nota,
        ),
      );
    }

    Future<Map<String, int>> leerSaldos(List<PersonaDelEspacio> lista) async {
      try {
        return await _saldos.saldosPendientes([for (final p in lista) p.persona.id]);
      } on Object {
        // Sin saldo conocido, no se muestra ninguno.
        return const {};
      }
    }

    Future<Map<String, DateTime>> leerCuotas(List<PersonaDelEspacio> lista) async {
      try {
        return await _cuotas.proximaCuotaDe([for (final p in lista) p.persona.id]);
      } on Object {
        // Sin cuota conocida, la fila dice solo lo que debe (no se afirma lo que no se sabe).
        return const {};
      }
    }

    late final Future<void> Function() alCambiarLoQueSeDebe;

    Future<void> alLlegarPersonas(List<PersonaDelEspacio> lista) async {
      final numero = ++secuencia;
      listasEnVuelo++;
      try {
        final leidos = await leerSaldos(lista);
        final cuotasLeidas = await leerCuotas(lista);
        var entrevistasLeidas = const <String, DateTime>{};
        try {
          final porVinculo = await _entrevistas.ultimaEntrevistaDe([
            for (final p in lista) p.vinculo.id,
          ]);
          entrevistasLeidas = {for (final p in lista) p.persona.id: ?porVinculo[p.vinculo.id]};
        } on Object {
          // Sin fecha conocida, la fila no dice nada (no se afirma lo que no se sabe).
        }
        if (cancelado || numero != secuencia) return;
        personas = lista;
        saldos = leidos;
        cuotas = cuotasLeidas;
        entrevistas = entrevistasLeidas;
        emitir();
      } finally {
        listasEnVuelo--;
        if (listasEnVuelo == 0 && cambioPendiente && !cancelado) {
          cambioPendiente = false;
          unawaited(alCambiarLoQueSeDebe());
        }
      }
    }

    // Algo de lo que se debe pudo cambiar: se vuelve a leer lo de las personas que ya se tienen y se
    // emite solo si el resultado es distinto (el aviso llega también al suscribirse y por cambios de
    // tablas que no mueven ningún saldo).
    alCambiarLoQueSeDebe = () async {
      if (cancelado) return;
      if (listasEnVuelo > 0) {
        cambioPendiente = true;
        return;
      }
      final lista = personas;
      if (lista == null) return;
      final deLaLista = secuencia;
      final numero = ++lecturasDeCambios;
      final leidos = await leerSaldos(lista);
      final cuotasLeidas = await leerCuotas(lista);
      if (cancelado || numero != lecturasDeCambios || deLaLista != secuencia) return;
      if (_mismo(leidos, saldos) && _mismo(cuotasLeidas, cuotas)) return;
      saldos = leidos;
      cuotas = cuotasLeidas;
      emitir();
    };

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
        // Un aviso que falla no frena la hoja: queda con lo último que leyó.
        alosCambios = _cambios().listen(
          (_) => unawaited(alCambiarLoQueSeDebe()),
          onError: (Object _) {},
        );
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
        await alosCambios?.cancel();
      },
    );
    return salida.stream;
  }

  /// Dos mapas con las mismas claves y los mismos valores.
  static bool _mismo<V>(Map<String, V> a, Map<String, V> b) =>
      a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
}
