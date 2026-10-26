import 'dart:async';

import 'package:flutter/material.dart';

import '../textos_registrar_visita.dart';
import 'piezas_alta.dart';

/// Lo que se puede elegir en «Registrar visita: ¿qué pasó?» (vista 39, C·06).
enum OpcionQuePaso {
  /// Un toque: guarda la visita y la casa queda gris.
  noContesto,

  /// Un toque: guarda la visita y la casa queda roja.
  rechazo,

  /// Sigue a «¿Con quién?» y a la agenda (#408).
  programarEntrevista,

  /// Sigue a «¿Con quién?» y a la entrevista en curso (#450).
  entrevistaDada,

  /// Sigue al cobro (C·08, #440). Solo se ofrece si alguien de la casa debe.
  cobranza,
}

/// Lo que pasó al elegir una opción: la hoja se cierra, queda abierta sin decir nada (la colportora
/// volvió atrás de un paso siguiente) o queda abierta con un aviso.
sealed class SalidaDeOpcion {
  const SalidaDeOpcion();
}

/// La opción se resolvió: la hoja se cierra.
final class OpcionResuelta extends SalidaDeOpcion {
  const OpcionResuelta();
}

/// La colportora volvió atrás desde el paso siguiente: la hoja sigue abierta, sin avisos.
final class OpcionCancelada extends SalidaDeOpcion {
  const OpcionCancelada();
}

/// No se pudo: la hoja sigue abierta con [texto] (qué pasó y qué hacer) y se puede volver a elegir.
final class OpcionFallida extends SalidaDeOpcion {
  const OpcionFallida(this.texto);

  final String texto;
}

/// Quién debe y cuánto, para la ayuda de «Cobranza».
typedef CobroOfrecido = ({String persona, int saldoCentavos});

/// Las claves de la hoja (para los tests y la QA).
abstract final class ClavesQuePaso {
  static const hoja = Key('que_paso_hoja');
  static const falla = Key('que_paso_falla');
  static const guardando = Key('que_paso_guardando');
  static Key opcion(OpcionQuePaso o) => Key('que_paso_${o.name}');
  static const cancelar = Key('que_paso_cancelar');
}

/// Los colores y glifos del canvas de cada opción (C·06).
abstract final class _Canvas {
  static const tinta = Color(0xFF0E1A2B);
  static const ayuda = Color(0xFF2A3A52);
  static const borde = Color(0xFFE3E7EE);
  static const bordeBoton = Color(0xFFCFD6E1);
  static const flecha = Color(0xFF5B6B82);
}

class _Fila {
  const _Fila({
    required this.opcion,
    required this.titulo,
    required this.ayuda,
    required this.glifo,
    required this.fondo,
    this.tinta = Colors.white,
    this.redondo = true,
  });

  final OpcionQuePaso opcion;
  final String titulo;
  final String ayuda;
  final String glifo;
  final Color fondo;
  final Color tinta;

  /// Los cuatro primeros glifos son círculos; el de «Cobranza», un cuadrado de borde 6.
  final bool redondo;
}

/// Abre «¿Qué pasó?» y devuelve `true` si algo se resolvió (se guardó, o siguió a otro flujo) y la
/// hoja se cerró por eso; `false` si se cerró con «Cancelar», el atrás o tocando afuera.
///
/// [ofrecidas] son las opciones que tienen a dónde llevar: las que no (todavía) no se dibujan (HU-UBI-003:
/// «los botones no se muestran mientras no tengan a dónde llevar»). [cobro] solo hace falta con
/// [OpcionQuePaso.cobranza]. [alElegir] hace lo que corresponde a la opción y dice cómo salió; mientras
/// corre, la hoja no admite otro toque ni se cierra.
Future<bool> mostrarHojaQuePaso(
  BuildContext context, {
  required String direccion,
  required Set<OpcionQuePaso> ofrecidas,
  required Future<SalidaDeOpcion> Function(OpcionQuePaso opcion) alElegir,
  CobroOfrecido? cobro,
  String etiquetaCancelar = TextosRegistrarVisita.cancelar,
}) async {
  final resultado = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Sin arrastrar para cerrar: el arrastre no pasa por el `PopScope` y mientras se guarda la hoja no
    // se cierra. Las salidas son «Cancelar», el atrás y el toque afuera.
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => HojaQuePaso(
      direccion: direccion,
      ofrecidas: ofrecidas,
      cobro: cobro,
      alElegir: alElegir,
      etiquetaCancelar: etiquetaCancelar,
    ),
  );
  return resultado ?? false;
}

/// «Registrar visita: ¿qué pasó?» (vista 39, C·06). Ver [mostrarHojaQuePaso].
///
/// Cada opción es un renglón de 56 de alto como mínimo, con su glifo de color, su ayuda y un «›». Mientras
/// una opción corre se ve «Guardando…» en su renglón y todos los demás quedan apagados; si falla, el
/// aviso rojo dice qué pasó y la hoja vuelve a admitir un toque.
class HojaQuePaso extends StatefulWidget {
  const HojaQuePaso({
    super.key,
    required this.direccion,
    required this.ofrecidas,
    required this.alElegir,
    this.cobro,
    this.etiquetaCancelar = TextosRegistrarVisita.cancelar,
  });

  final String direccion;

  /// El rótulo de la salida: «Cancelar» desde la hoja de la casa y «Volver» en N·03, la casa recién
  /// registrada (vista 39).
  final String etiquetaCancelar;
  final Set<OpcionQuePaso> ofrecidas;
  final CobroOfrecido? cobro;
  final Future<SalidaDeOpcion> Function(OpcionQuePaso opcion) alElegir;

  @override
  State<HojaQuePaso> createState() => _HojaQuePasoState();
}

class _HojaQuePasoState extends State<HojaQuePaso> {
  /// La opción que corre. Es un campo y no solo estado de la UI: la guarda tiene que cortar el segundo
  /// toque aunque llegue antes de que se vuelva a dibujar.
  OpcionQuePaso? _corriendo;

  /// Ya se está cerrando: ningún otro toque cierra otra vez.
  var _cerrando = false;

  String? _falla;

  /// Donde vive el aviso de falla: para llevar la hoja hasta él (con texto grande la persona ya
  /// bajó hasta el renglón que tocó).
  final _lugarDeLaFalla = GlobalKey();

  Future<void> _elegir(OpcionQuePaso opcion) async {
    if (_corriendo != null || _cerrando) return;
    _corriendo = opcion;
    setState(() => _falla = null);
    SalidaDeOpcion salida;
    try {
      salida = await widget.alElegir(opcion);
    } on Object {
      // Nada del error al mensaje: puede traer datos de la casa (convenciones §7.5).
      salida = const OpcionFallida(TextosRegistrarVisita.noPudimosGuardar);
    }
    if (!mounted) return;
    switch (salida) {
      case OpcionResuelta():
        _cerrando = true;
        Navigator.of(context).pop(true);
      case OpcionCancelada():
        setState(() => _corriendo = null);
      case OpcionFallida(:final texto):
        setState(() {
          _corriendo = null;
          _falla = texto;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final lugar = _lugarDeLaFalla.currentContext;
          if (!mounted || lugar == null) return;
          unawaited(
            Scrollable.ensureVisible(
              lugar,
              duration: const Duration(milliseconds: 150),
              alignment: 0.05,
            ),
          );
        });
    }
  }

  void _cancelar() {
    if (_corriendo != null || _cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(false);
  }

  List<_Fila> _filas() {
    final cobro = widget.cobro;
    return [
      if (widget.ofrecidas.contains(OpcionQuePaso.noContesto))
        const _Fila(
          opcion: OpcionQuePaso.noContesto,
          titulo: TextosRegistrarVisita.noContesto,
          ayuda: TextosRegistrarVisita.ayudaGuardaYVuelve,
          glifo: '–',
          fondo: Color(0xFF6B7688),
        ),
      if (widget.ofrecidas.contains(OpcionQuePaso.rechazo))
        const _Fila(
          opcion: OpcionQuePaso.rechazo,
          titulo: TextosRegistrarVisita.rechazo,
          ayuda: TextosRegistrarVisita.ayudaGuardaYVuelve,
          glifo: '✕',
          fondo: ColoresAlta.rojo,
        ),
      if (widget.ofrecidas.contains(OpcionQuePaso.programarEntrevista))
        const _Fila(
          opcion: OpcionQuePaso.programarEntrevista,
          titulo: TextosRegistrarVisita.programarEntrevista,
          ayuda: TextosRegistrarVisita.ayudaProgramar,
          glifo: '◷',
          fondo: Color(0xFFE0B43C),
          tinta: _Canvas.tinta,
        ),
      if (widget.ofrecidas.contains(OpcionQuePaso.entrevistaDada))
        const _Fila(
          opcion: OpcionQuePaso.entrevistaDada,
          titulo: TextosRegistrarVisita.entrevistaDada,
          ayuda: TextosRegistrarVisita.ayudaEntrevistaDada,
          glifo: '✓',
          fondo: ColoresAlta.verde,
        ),
      if (widget.ofrecidas.contains(OpcionQuePaso.cobranza) && cobro != null)
        _Fila(
          opcion: OpcionQuePaso.cobranza,
          titulo: TextosRegistrarVisita.cobranza,
          ayuda: TextosRegistrarVisita.ayudaCobranza(cobro.persona, cobro.saldoCentavos),
          glifo: r'$',
          fondo: ColoresAlta.azul,
          redondo: false,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ocupada = _corriendo != null;
    return PopScope(
      // Mientras corre una opción no se sale: el resultado se perdería.
      canPop: !ocupada,
      child: SingleChildScrollView(
        key: ClavesQuePaso.hoja,
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Asa(),
            const SizedBox(height: 16),
            Semantics(
              header: true,
              child: Text(TextosRegistrarVisita.titulo, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 6),
            Text(
              widget.direccion,
              style: theme.textTheme.bodyMedium?.copyWith(color: _Canvas.ayuda, height: 1.5),
            ),
            const SizedBox(height: 16),
            // Arriba de los renglones: con texto grande lo de abajo queda fuera de la vista y la
            // persona no se enteraría de que falló.
            if (_falla != null) ...[
              KeyedSubtree(
                key: _lugarDeLaFalla,
                child: AvisoAlta(
                  key: ClavesQuePaso.falla,
                  color: ColoresAlta.rojo,
                  glyph: '!',
                  texto: _falla!,
                ),
              ),
              const SizedBox(height: 12),
            ],
            for (final fila in _filas()) ...[
              _Renglon(
                fila: fila,
                corriendo: _corriendo == fila.opcion,
                apagado: ocupada,
                alTocar: () => unawaited(_elegir(fila.opcion)),
              ),
              const SizedBox(height: 10),
            ],
            OutlinedButton(
              key: ClavesQuePaso.cancelar,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                foregroundColor: _Canvas.ayuda,
                side: const BorderSide(color: _Canvas.bordeBoton, width: 1.5),
              ),
              onPressed: ocupada ? null : _cancelar,
              child: Text(widget.etiquetaCancelar, textAlign: TextAlign.center),
            ),
          ],
        ),
      ),
    );
  }
}

class _Asa extends StatelessWidget {
  const _Asa();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColoresAlta.grisBorde,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );
}

/// Un renglón: el glifo de color, el título con su ayuda y el «›».
class _Renglon extends StatelessWidget {
  const _Renglon({
    required this.fila,
    required this.corriendo,
    required this.apagado,
    required this.alTocar,
  });

  final _Fila fila;
  final bool corriendo;
  final bool apagado;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ayuda = corriendo ? TextosRegistrarVisita.guardando : fila.ayuda;
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: !apagado,
      label: TextosRegistrarVisita.renglonParaLector(fila.titulo, ayuda),
      onTap: apagado ? null : alTocar,
      child: Opacity(
        opacity: apagado && !corriendo ? 0.55 : 1,
        child: Material(
          key: ClavesQuePaso.opcion(fila.opcion),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: _Canvas.borde),
          ),
          child: InkWell(
            customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            onTap: apagado ? null : alTocar,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 56),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: fila.fondo,
                        shape: fila.redondo ? BoxShape.circle : BoxShape.rectangle,
                        borderRadius: fila.redondo ? null : BorderRadius.circular(6),
                      ),
                      child: Text(
                        fila.glifo,
                        textScaler: TextScaler.noScaling,
                        style: TextStyle(
                          color: fila.tinta,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fila.titulo,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: _Canvas.tinta,
                            ),
                          ),
                          Text(
                            ayuda,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _Canvas.ayuda,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (corriendo)
                      const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(
                          key: ClavesQuePaso.guardando,
                          strokeWidth: 2.5,
                        ),
                      )
                    else
                      const ExcludeSemantics(
                        child: Text('›', style: TextStyle(fontSize: 22, color: _Canvas.flecha)),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
