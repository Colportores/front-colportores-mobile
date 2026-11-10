import 'package:equatable/equatable.dart';

import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../services/cuenta_de_persona.dart';
import 'contexto_notas_persona.dart';
import 'espacio.dart';
import 'nota_persona.dart';
import 'persona.dart';
import 'ubicacion.dart';

/// Un renglón de un movimiento: un producto o una colección y cuántos («Nuestros Hijos × 1»).
class LineaDeFicha extends Equatable {
  const LineaDeFicha({required this.nombre, required this.cantidad, this.libros});

  final String nombre;
  final int cantidad;

  /// Si el renglón es un combo (colección), los libros que trae **una** unidad (`venta_item.componentes`)
  /// con su nombre y cuántos; `null` si es un producto suelto. Un libro que el catálogo ya no trae
  /// lleva el nombre vacío: no se inventa.
  final List<LineaDeFicha>? libros;

  bool get esCombo => libros != null;

  /// Cuántos libros son en total: un combo cuenta su cantidad por los libros de cada unidad (la misma
  /// regla que cobranzas, decisión del 10/11, rev 1120). Un combo sin componentes cuenta una por unidad.
  int get cuantosLibros {
    final deUnaUnidad = libros?.fold<int>(0, (n, l) => n + l.cantidad) ?? 0;
    return libros == null || deUnaUnidad == 0 ? cantidad : cantidad * deUnaUnidad;
  }

  @override
  List<Object?> get props => [nombre, cantidad, libros];
}

/// Una cosa que le pasó a la persona (vista 32B, «HISTORIAL»): una visita, una venta, una entrega o un
/// cobro. Se ordenan por [fecha], la más nueva primero.
sealed class MovimientoDeFicha extends Equatable {
  const MovimientoDeFicha({required this.id, required this.fecha});

  final String id;

  /// Cuándo pasó (UTC). Para una entrega pendiente, cuándo está prevista.
  final DateTime fecha;
}

/// Una visita (`visita`) con su resultado: «Entrevista hecha», «No contestó»…
final class VisitaEnFicha extends MovimientoDeFicha {
  const VisitaEnFicha({
    required super.id,
    required super.fecha,
    required this.resultado,
    this.misioneros = 0,
  });

  final TipoResultadoVisita resultado;

  /// Cuántos misioneros se dejaron en esa visita sin venta («Lo que dejaste», 42B·08E): la fila dice
  /// «✦ 3 misioneros». 0 si no se dejó ninguno.
  final int misioneros;

  @override
  List<Object?> get props => [id, fecha, resultado, misioneros];
}

/// Una venta (`venta`) con lo que se vendió.
final class VentaEnFicha extends MovimientoDeFicha {
  const VentaEnFicha({
    required super.id,
    required super.fecha,
    required this.numeroTalonario,
    required this.montoCentavos,
    required this.lineas,
  });

  /// El número del talonario («0042»).
  final String numeroTalonario;

  final int montoCentavos;
  final List<LineaDeFicha> lineas;

  @override
  List<Object?> get props => [id, fecha, numeroTalonario, montoCentavos, lineas];
}

/// Una entrega de lo vendido: hecha o [pendiente] (con [fecha] prevista).
final class EntregaEnFicha extends MovimientoDeFicha {
  const EntregaEnFicha({
    required super.id,
    required super.fecha,
    required this.pendiente,
    required this.lineas,
    this.ventaId,
  });

  final bool pendiente;
  final List<LineaDeFicha> lineas;

  /// La venta de la que sale lo entregado (HU-VEN-005): con ella «Entregar», en una entrega pendiente,
  /// abre el destino ya en esa venta, sin preguntar «¿Qué venta?». `null` si no se conoce.
  final String? ventaId;

  @override
  List<Object?> get props => [id, fecha, pendiente, lineas, ventaId];
}

/// Un cobro de una venta.
final class CobroEnFicha extends MovimientoDeFicha {
  const CobroEnFicha({
    required super.id,
    required super.fecha,
    required this.montoCentavos,
    required this.efectivo,
    required this.ventaId,
    this.numeroTalonario,
  });

  final int montoCentavos;

  /// `true`: en efectivo («$ 600 en efectivo»). Hoy es el único medio que se registra.
  final bool efectivo;

  /// La venta que se cobró. El talonario se puede repetir entre años (es único por colportor y año): lo
  /// que une un cobro con su venta es este `id`, no el número.
  final String ventaId;

  /// El número de la venta que se cobró, si se conoce («Venta 0042»).
  final String? numeroTalonario;

  @override
  List<Object?> get props => [id, fecha, montoCentavos, efectivo, ventaId, numeroTalonario];
}

/// Las notas de la persona (las activas), de la más nueva a la más vieja: solo la última se muestra
/// en la ficha; las demás están en «Notas de …».
class NotasDeLaFicha extends Equatable {
  const NotasDeLaFicha({required this.total, this.ultima});

  static const ninguna = NotasDeLaFicha(total: 0);

  /// Cuántas notas activas tiene.
  final int total;

  /// La más reciente, o `null` si no tiene ninguna.
  final NotaPersona? ultima;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [total, ultima];
}

/// La ficha 360 de una persona (HU-UBI-009, vista 32B): sus datos, dónde está, las notas, el historial y
/// la cuenta. Todo sale de la DB local.
///
/// **PII**: lleva nombre, teléfono y notas; no se imprime ni va a los logs (`stringify` apagado).
class FichaDePersona extends Equatable {
  const FichaDePersona({
    required this.persona,
    required this.espacioId,
    required this.lugar,
    required this.contexto,
    required this.notas,
    required this.historial,
    this.resumen,
  });

  final Persona persona;

  /// El espacio desde el que se abrió (en un edificio, el depto).
  final String espacioId;

  /// El espacio y su ubicación; `null` si ya no están en el teléfono (el pull no garantiza el orden).
  final ({Espacio espacio, Ubicacion ubicacion})? lugar;

  /// Si la ficha es de solo lectura y por qué (el mismo que usan las notas, para que digan lo mismo).
  final ContextoNotasPersona contexto;

  final NotasDeLaFicha notas;

  /// Todos los movimientos, el más nuevo primero. La pantalla los pagina.
  final List<MovimientoDeFicha> historial;

  /// Lo que compró, recibió y pagó; `null` si no tiene ventas («Sin movimientos aún»).
  final ResumenCuentaPersona? resumen;

  bool get soloLectura => contexto.soloLectura;

  bool get personaDeBaja => contexto.causa == CausaSoloLectura.personaDeBaja;

  @override
  bool? get stringify => false;

  @override
  List<Object?> get props => [persona, espacioId, lugar, contexto, notas, historial, resumen];
}
