import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../catalogo/domain/entities/item_de_precio.dart';
import '../../domain/entities/cliente_de_la_venta.dart';
import '../../domain/entities/componente_vendido.dart';
import '../../domain/entities/linea_de_venta.dart';
import '../../domain/entities/nueva_venta.dart';
import '../../domain/repositories/venta_repository.dart';
import '../../domain/services/reglas_de_venta.dart';
import '../../domain/usecases/registrar_venta_use_case.dart';
import '../formato_venta.dart';
import 'ventas_providers.dart';

// El estado de una venta que se está armando (vista 27, HU-VEN-001): lo que lleva, el talonario, el
// monto a mano y el guardado. Nada se escribe hasta «Registrar venta»; ahí es una sola transacción.

/// Con qué se abre una venta: quién vende, a quién y, si sale de una entrevista, su visita.
final class ArgumentosDeVenta extends Equatable {
  const ArgumentosDeVenta({required this.colportorId, required this.cliente, this.visitaId});

  final String colportorId;
  final ClienteDeLaVenta cliente;

  /// La visita que la entrevista cerrada como VENTA creó (#428); `null` si la venta no sale de una.
  final String? visitaId;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [colportorId, cliente, visitaId];
}

/// Un producto suelto con la cantidad que se vende (27A·07 y 27A·08). Un misionero va siempre a
/// $ 0: ni el precio de lista ni un monto a voluntad (decisión de Cristian, 28/10, «Misionero»).
final class ProductoElegido extends Equatable {
  const ProductoElegido({required this.producto, required this.cantidad});

  final PrecioDeProducto producto;
  final int cantidad;

  bool get esMisionero => producto.categoria == CategoriaDePrecios.misioneros;

  @override
  List<Object?> get props => [producto, cantidad];
}

/// Una fila de «EN LA VENTA»: una colección o un producto suelto, con cómo se muestra.
final class RenglonDeVenta extends Equatable {
  const RenglonDeVenta({
    required this.clave,
    required this.linea,
    required this.titulo,
    this.detalle,
    this.nombresBase = const [],
    this.idsElegidos = const [],
    this.nombresElegidos = const [],
  });

  /// Identifica la fila en pantalla (no es el id del ítem, que se genera al guardar).
  final String clave;
  final LineaDeVenta linea;
  final String titulo;

  /// «Salud y Hogar · Nuestros Hijos» (los libros elegidos de una colección).
  final String? detalle;

  /// Lo que lleva siempre la colección: «El camino a Cristo», «Vida Feliz»…
  final List<String> nombresBase;

  /// Los libros que la colportora eligió, en orden (para volver a abrir la colección: 27A·06).
  final List<String> idsElegidos;
  final List<String> nombresElegidos;

  bool get esColeccion => linea is LineaDeCombo;

  int get subtotalCentavos => linea.subtotalCentavos;

  RenglonDeVenta conLinea(LineaDeVenta nueva) => RenglonDeVenta(
    clave: clave,
    linea: nueva,
    titulo: titulo,
    detalle: detalle,
    nombresBase: nombresBase,
    idsElegidos: idsElegidos,
    nombresElegidos: nombresElegidos,
  );

  @override
  List<Object?> get props => [
    clave,
    linea,
    titulo,
    detalle,
    nombresBase,
    idsElegidos,
    nombresElegidos,
  ];
}

final class NuevaVentaState extends Equatable {
  const NuevaVentaState({
    this.talonario = '',
    this.talonarioRepetido,
    this.renglones = const [],
    this.editandoMonto = false,
    this.montoTexto = '',
    this.motivo = '',
    this.guardando = false,
    this.falla,
    this.guardada,
  });

  final String talonario;

  /// El talonario que escribió ya se usó este año (27A·11); no deja registrar.
  final FailureTalonarioRepetido? talonarioRepetido;
  final List<RenglonDeVenta> renglones;

  /// «Cambiar el monto» está abierto (27A·12).
  final bool editandoMonto;
  final String montoTexto;
  final String motivo;
  final bool guardando;

  /// Lo que salió mal al guardar (27A·13); `null` si no hubo falla o ya se editó algo.
  final Failure? falla;

  /// La venta ya guardada: la pantalla se cierra devolviéndola.
  final VentaGuardada? guardada;

  int get totalCalculado => renglones.fold(0, (suma, r) => suma + r.subtotalCentavos);

  /// El monto que escribió la colportora, o `null` si no lo está cambiando o no es un monto.
  int? get montoManual => editandoMonto ? FormatoVenta.parsearMonto(montoTexto) : null;

  /// Hay algo que cobrar: no todo lo que lleva la venta son misioneros. Con solo misioneros no hay
  /// total que cambiar a mano: no cuenta como venta y vale $ 0.
  bool get cobraAlgo => renglones.isNotEmpty && !ReglasDeVenta.soloMisioneros(_lineas);

  Iterable<LineaDeVenta> get _lineas => renglones.map((r) => r.linea);

  /// «Cambiar el monto» está abierto y se aplica (hay algo que cobrar).
  bool get cambiandoElMonto => editandoMonto && cobraAlgo;

  bool get montoValido => !cambiandoElMonto || montoManual != null;

  /// El total cambiado a mano pide su motivo (27A·12): sin él no se registra.
  bool get motivoFalta => ReglasDeVenta.faltaElMotivo(
    calculado: totalCalculado,
    cobrado: cambiandoElMonto ? montoManual : null,
    motivo: motivo,
  );

  int get totalACobrar => (cambiandoElMonto ? montoManual : null) ?? totalCalculado;

  bool get talonarioVacio => talonario.trim().isEmpty;

  bool get puedeRegistrar =>
      !guardando &&
      guardada == null &&
      !talonarioVacio &&
      renglones.isNotEmpty &&
      talonarioRepetido == null &&
      montoValido &&
      !motivoFalta;

  /// La cantidad de [productoId] (cualquiera sea su forma de cobro) que ya está en la venta.
  int cantidadDe(String productoId) {
    for (final r in renglones) {
      final linea = r.linea;
      if (linea is LineaDeProducto && linea.productoId == productoId) return linea.cantidad;
    }
    return 0;
  }

  NuevaVentaState copiar({
    String? talonario,
    FailureTalonarioRepetido? talonarioRepetido,
    bool sinTalonarioRepetido = false,
    List<RenglonDeVenta>? renglones,
    bool? editandoMonto,
    String? montoTexto,
    String? motivo,
    bool? guardando,
    Failure? falla,
    bool sinFalla = false,
    VentaGuardada? guardada,
  }) => NuevaVentaState(
    talonario: talonario ?? this.talonario,
    talonarioRepetido: sinTalonarioRepetido ? null : (talonarioRepetido ?? this.talonarioRepetido),
    renglones: renglones ?? this.renglones,
    editandoMonto: editandoMonto ?? this.editandoMonto,
    montoTexto: montoTexto ?? this.montoTexto,
    motivo: motivo ?? this.motivo,
    guardando: guardando ?? this.guardando,
    falla: sinFalla ? null : (falla ?? this.falla),
    guardada: guardada ?? this.guardada,
  );

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [
    talonario,
    talonarioRepetido,
    renglones,
    editandoMonto,
    montoTexto,
    motivo,
    guardando,
    falla,
    guardada,
  ];
}

class NuevaVentaNotifier extends Notifier<NuevaVentaState> {
  NuevaVentaNotifier(this.args);

  final ArgumentosDeVenta args;

  /// El id de la venta es uno solo para todos los intentos de guardarla: un doble toque o un
  /// «Reintentar» después de una falla no puede dejar dos ventas.
  late String _ventaId;
  var _verificacion = 0;
  var _siguienteClave = 0;

  @override
  NuevaVentaState build() {
    _ventaId = ref.read(generadorIdVentaProvider)();
    return const NuevaVentaState();
  }

  String _clave() => 'r${_siguienteClave++}';

  // --- Talonario ---------------------------------------------------------------------------

  /// Mientras escribe, avisa si ese número ya se usó este año (27A·11), sin esperar al guardado.
  Future<void> escribirTalonario(String texto) async {
    state = state.copiar(talonario: texto, sinTalonarioRepetido: true, sinFalla: true);
    final secuencia = ++_verificacion;
    final numero = texto.trim();
    if (numero.isEmpty) return;
    try {
      final uso = await ref
          .read(ventaRepositoryProvider)
          .talonarioUsado(
            colportorId: args.colportorId,
            numero: numero,
            fecha: ref.read(relojVentaProvider)(),
          );
      if (!ref.mounted || secuencia != _verificacion) return;
      uso.fold((_) {}, (usado) {
        if (usado == null) return;
        state = state.copiar(
          talonarioRepetido: FailureTalonarioRepetido(
            numero: numero,
            ventaDel: ReglasDeVenta.diaDeMontevideo(usado.fecha),
          ),
        );
      });
    } on Object {
      // No se pudo mirar: el guardado lo vuelve a comprobar con la misma regla.
    }
  }

  // --- Lo que se vende ---------------------------------------------------------------------

  /// Deja [elegidos] en la venta (27A·07, 27A·08): cantidad 0 saca el producto, otra cantidad la
  /// reemplaza (la pantalla parte de lo que ya había). Un misionero queda a $ 0, sin el precio de
  /// lista.
  void fijarProductos(List<ProductoElegido> elegidos) {
    final renglones = [...state.renglones];
    for (final e in elegidos) {
      final i = renglones.indexWhere(
        (r) =>
            r.linea is LineaDeProducto && (r.linea as LineaDeProducto).productoId == e.producto.id,
      );
      if (e.cantidad <= 0) {
        if (i >= 0) renglones.removeAt(i);
        continue;
      }
      final nuevo = RenglonDeVenta(
        clave: i >= 0 ? renglones[i].clave : _clave(),
        linea: LineaDeProducto(
          productoId: e.producto.id,
          cantidad: e.cantidad,
          precioCentavos: e.esMisionero ? 0 : e.producto.centavos,
          sinCobrar: e.esMisionero,
        ),
        titulo: e.producto.nombre,
      );
      if (i >= 0) {
        renglones[i] = nuevo;
      } else {
        renglones.add(nuevo);
      }
    }
    state = _conLista(renglones);
  }

  /// Deja [renglones] como la lista de la venta. Mientras quede algo vendido, el monto a mano sigue
  /// abierto con lo escrito y su motivo; si la lista queda vacía, vuelve al monto calculado y se
  /// borran el monto y el motivo (así no se registra un monto de una venta que ya no existe).
  NuevaVentaState _conLista(List<RenglonDeVenta> renglones) => renglones.isEmpty
      ? state.copiar(
          renglones: renglones,
          editandoMonto: false,
          montoTexto: '',
          motivo: '',
          sinFalla: true,
        )
      : state.copiar(renglones: renglones, sinFalla: true);

  /// Suma una colección armada (27A·04): la base que siempre va y los libros elegidos. Dos
  /// colecciones iguales son una con cantidad 2; con libros distintos son dos ítems de 1.
  ///
  /// Con [reemplazaClave] (27A·06) cambia los libros de una que ya estaba: si era de varias
  /// unidades, solo cambia una.
  void ponerColeccion({
    required PrecioDeCombo combo,
    required List<ComponenteVendido> base,
    required List<String> nombresBase,
    required List<PrecioDeProducto> elegidos,
    String? reemplazaClave,
  }) {
    final cuentas = <String, int>{};
    for (final c in base) {
      cuentas[c.productoId] = (cuentas[c.productoId] ?? 0) + c.cantidad;
    }
    for (final libro in elegidos) {
      cuentas[libro.id] = (cuentas[libro.id] ?? 0) + 1;
    }
    final ids = cuentas.keys.toList()..sort();
    final componentes = [
      for (final id in ids) ComponenteVendido(productoId: id, cantidad: cuentas[id]!),
    ];

    final renglones = [...state.renglones];
    if (reemplazaClave != null) {
      final i = renglones.indexWhere((r) => r.clave == reemplazaClave);
      if (i >= 0) {
        final actual = renglones[i];
        if (actual.linea.cantidad > 1) {
          renglones[i] = actual.conLinea(
            LineaDeCombo(
              comboId: (actual.linea as LineaDeCombo).comboId,
              cantidad: actual.linea.cantidad - 1,
              precioCentavos: actual.linea.precioCentavos,
              componentes: (actual.linea as LineaDeCombo).componentes,
            ),
          );
        } else {
          renglones.removeAt(i);
        }
      }
    }

    final igual = renglones.indexWhere((r) {
      final l = r.linea;
      return l is LineaDeCombo && l.comboId == combo.id && listEquals(l.componentes, componentes);
    });
    if (igual >= 0) {
      final actual = renglones[igual];
      renglones[igual] = actual.conLinea(
        LineaDeCombo(
          comboId: combo.id,
          cantidad: actual.linea.cantidad + 1,
          precioCentavos: actual.linea.precioCentavos,
          componentes: componentes,
        ),
      );
    } else {
      renglones.add(
        RenglonDeVenta(
          clave: _clave(),
          linea: LineaDeCombo(
            comboId: combo.id,
            cantidad: 1,
            precioCentavos: combo.centavos,
            componentes: componentes,
          ),
          titulo: combo.nombre,
          detalle: elegidos.map((l) => l.nombre).join(' · '),
          nombresBase: nombresBase,
          idsElegidos: [for (final l in elegidos) l.id],
          nombresElegidos: [for (final l in elegidos) l.nombre],
        ),
      );
    }
    state = state.copiar(renglones: renglones, sinFalla: true);
  }

  void quitar(String clave) => state = _conLista([
    for (final r in state.renglones)
      if (r.clave != clave) r,
  ]);

  // --- Monto a mano ------------------------------------------------------------------------

  void cambiarElMonto() => state = state.copiar(
    editandoMonto: true,
    montoTexto: FormatoVenta.montoParaEditar(state.totalCalculado),
    sinFalla: true,
  );

  void usarElMontoCalculado() =>
      state = state.copiar(editandoMonto: false, montoTexto: '', motivo: '', sinFalla: true);

  void escribirMonto(String texto) => state = state.copiar(montoTexto: texto, sinFalla: true);

  void escribirMotivo(String texto) => state = state.copiar(motivo: texto, sinFalla: true);

  // --- Guardar -----------------------------------------------------------------------------

  /// Registra la venta. Devuelve la guardada, o `null` si no se pudo (queda la falla en el estado y
  /// todo lo cargado intacto) o si ya había un guardado en curso: un doble toque no hace nada.
  ///
  /// [antesDeGuardar] corre en la misma transacción, antes de la venta (el cierre de la entrevista,
  /// #428): si falla, no se guarda nada.
  Future<VentaGuardada?> registrar({AntesDeGuardarLaVenta? antesDeGuardar}) async {
    if (!state.puedeRegistrar) return null;
    final s = state;
    state = s.copiar(guardando: true, sinFalla: true);
    final venta = NuevaVenta(
      ventaId: _ventaId,
      colportorId: args.colportorId,
      espacioPersonaId: args.cliente.espacioPersonaId,
      numeroTalonario: s.talonario,
      lineas: [for (final r in s.renglones) r.linea],
      totalCobradoCentavos: s.cambiandoElMonto ? s.montoManual : null,
      motivoMontoManual: s.cambiandoElMonto ? s.motivo : '',
      visitaId: args.visitaId,
    );
    final resultado = await _guardar(venta, antesDeGuardar);
    if (!ref.mounted) return resultado.fold((_) => null, (g) => g);
    return resultado.fold(
      (falla) {
        state = switch (falla) {
          final FailureTalonarioRepetido repetido => state.copiar(
            guardando: false,
            talonarioRepetido: repetido,
          ),
          _ => state.copiar(guardando: false, falla: falla),
        };
        return null;
      },
      (guardada) {
        state = state.copiar(guardando: false, guardada: guardada);
        return guardada;
      },
    );
  }

  Future<Either<Failure, VentaGuardada>> _guardar(
    NuevaVenta venta,
    AntesDeGuardarLaVenta? antes,
  ) async {
    try {
      return await ref
          .read(registrarVentaUseCaseProvider)
          .call(RegistrarVentaParams(venta: venta, antesDeGuardar: antes));
    } on Object {
      // Sin base abierta o cualquier falla inesperada: nada se guardó y todo lo cargado sigue.
      return const Left(FailureVentaNoGuardada());
    }
  }
}

final nuevaVentaProvider = NotifierProvider.autoDispose
    .family<NuevaVentaNotifier, NuevaVentaState, ArgumentosDeVenta>(NuevaVentaNotifier.new);
