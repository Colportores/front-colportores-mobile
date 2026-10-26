import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/ubicacion.dart';
import '../formato_ubicaciones.dart';
import '../providers/alta_ubicacion_notifier.dart';
import '../salida_alta_ubicacion.dart';
import '../textos_alta_por_pin.dart';
import 'campos_ubicacion.dart';
import 'hoja_alta.dart' show AvisoCiudadDelAlta, CampoCiudadDelAlta, TextosAlta, mensajeFallaAlta;
import 'hoja_ciudad.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart' show ColoresLista;
import 'pin_nueva_casa.dart';
import 'resolver_duplicados_alta.dart';

/// Abre N·02 «¿Qué hay acá?» (vista 39) sobre el alta de [parametros] y devuelve cómo terminó: la
/// ubicación registrada ([UbicacionCreada]), la que ya existía ([UbicacionReutilizada], si la
/// colportora eligió «Reutilizar esta» en el aviso de duplicado) o `null` si volvió sin registrar.
///
/// El estado vive en `altaUbicacionProvider(parametros)`: quien abre la hoja lo mantiene vivo, y por eso
/// «Volver» y entrar de nuevo conserva el tipo y el número que se había escrito.
Future<SalidaAltaUbicacion?> mostrarHojaQueHayAca(
  BuildContext context, {
  required ParametrosAlta parametros,
}) => showModalBottomSheet<SalidaAltaUbicacion>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras registra, la hoja no se cierra (el arrastre no pasa por el
  // `PopScope`). Las salidas son «Volver» y el atrás del sistema.
  enableDrag: false,
  backgroundColor: Colors.white,
  barrierColor: const Color(0x730E1A2B),
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaQueHayAca(parametros: parametros),
);

/// N·02 «¿Qué hay acá?» (vista 39): el tipo de lo que hay en el lugar (casa, edificio o negocio, con la
/// casa elegida de entrada) y el número, que sale del mapa y se corrige acá, una sola vez. «Seguir»
/// registra la ubicación con las reglas de las vistas 03 y 04 (duplicado a 5 m, dirección única a
/// 100 m, ciudad de la campaña) y sale con el resultado.
///
/// - Si el mapa no conoce la calle, el campo «Calle» aparece para escribirla (vista 03: «calle y número
///   quedan vacíos para escribirlos»); si conoce la calle, queda como subtítulo.
/// - La ciudad la propone la app sola. Solo si no puede (la campaña tiene varias ciudades y ninguna
///   zona contiene el punto, no tiene ciudades, o no se pudieron leer) el campo aparece acá, con
///   «Elegir» o «Reintentar».
/// - Doble toque en «Seguir»: un solo registro; una falla deja todo como estaba y el botón vuelve.
class HojaQueHayAca extends ConsumerStatefulWidget {
  const HojaQueHayAca({super.key, required this.parametros});

  final ParametrosAlta parametros;

  @override
  ConsumerState<HojaQueHayAca> createState() => _HojaQueHayAcaState();
}

class _HojaQueHayAcaState extends ConsumerState<HojaQueHayAca> {
  final _calle = TextEditingController();
  final _numero = TextEditingController();
  final _lugarDeLaFalla = GlobalKey();

  /// Hay un registro en curso. Es un campo y no solo `guardando`: el segundo toque tiene que cortarse
  /// aunque llegue antes de que el notifier avise.
  var _enCurso = false;
  var _saliendo = false;
  var _eligiendoCiudad = false;

  /// El campo «Calle» aparece cuando el mapa no la conoce y se queda: si no, desaparecería al escribir.
  var _pedirCalle = false;

  AltaUbicacionNotifier get _notificador =>
      ref.read(altaUbicacionProvider(widget.parametros).notifier);

  @override
  void initState() {
    super.initState();
    final estado = ref.read(altaUbicacionProvider(widget.parametros));
    _calle.text = estado.calle.texto;
    _numero.text = estado.numero.texto;
    // La casa viene elegida (canvas N·02); si ya se eligió otro tipo (volvió y reentró), se conserva.
    if (estado.tipo == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(altaUbicacionProvider(widget.parametros)).tipo == null) {
          _notificador.elegirTipo(TipoUbicacion.casa);
        }
      });
    }
  }

  @override
  void dispose() {
    _calle.dispose();
    _numero.dispose();
    super.dispose();
  }

  void _salir(SalidaAltaUbicacion? salida) {
    if (_saliendo) return;
    _saliendo = true;
    Navigator.of(context).pop(salida);
  }

  Future<void> _seguir() async {
    if (_enCurso || _saliendo) return;
    _enCurso = true;
    try {
      final resultado = await _notificador.registrar();
      if (!mounted) return;
      switch (resultado) {
        case AltaCreada(:final ubicacion):
          _salir(UbicacionCreada(ubicacion));
        case AltaConCandidatas(:final candidatas):
          final salida = await resolverDuplicadosDelAlta(
            context,
            ref,
            parametros: widget.parametros,
            candidatas: candidatas,
          );
          if (mounted && salida != null) _salir(salida);
        case AltaFallida() || AltaIgnorada():
          break;
      }
    } finally {
      _enCurso = false;
    }
  }

  Future<void> _elegirCiudad() async {
    if (_eligiendoCiudad) return;
    _eligiendoCiudad = true;
    try {
      await mostrarHojaCiudad(
        context,
        colportorId: widget.parametros.colportorId,
        elegidaId: ref.read(altaUbicacionProvider(widget.parametros)).ciudad?.id,
        alElegir: _notificador.elegirCiudad,
      );
    } finally {
      _eligiendoCiudad = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final proveedor = altaUbicacionProvider(widget.parametros);
    final estado = ref.watch(proveedor);
    ref.listen(proveedor.select((s) => s.calle), (_, c) {
      if (c.texto != _calle.text) _calle.text = c.texto;
    });
    ref.listen(proveedor.select((s) => s.numero), (_, n) {
      if (n.texto != _numero.text) _numero.text = n.texto;
    });
    ref.listen(proveedor.select((s) => s.falla), (anterior, nueva) {
      if (nueva == null || nueva == anterior) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final lugar = _lugarDeLaFalla.currentContext;
        if (mounted && lugar != null) {
          unawaited(Scrollable.ensureVisible(lugar, duration: const Duration(milliseconds: 150)));
        }
      });
    });
    if (!_pedirCalle && !estado.buscandoDireccion && estado.calle.fuente == FuenteCampo.vacio) {
      _pedirCalle = true;
    }
    final theme = Theme.of(context);
    final direccion = TextosAltaPorPin.direccion(estado);
    final registrando = estado.guardando;
    final puedeSeguir =
        !registrando && estado.punto != null && estado.tipo != null && estado.ciudad != null;
    final sinCiudad = estado.ciudad == null;

    return PopScope(
      // Mientras registra no se sale: el resultado se perdería.
      canPop: !registrando,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          key: ClavesPinNuevaCasa.queHayAca,
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _Asa(),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: const Text(
                  TextosAltaPorPin.queHayAca,
                  style: TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    color: ColoresLista.tinta,
                  ),
                ),
              ),
              if (direccion.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  direccion,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: ColoresAlta.tinta,
                    height: 1.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              _OpcionesDeTipo(
                tipo: estado.tipo,
                alElegir: registrando ? null : _notificador.elegirTipo,
              ),
              if (_pedirCalle) ...[
                const SizedBox(height: 14),
                CampoDireccionUbicacion(
                  claveCampo: ClavesPinNuevaCasa.campoCalle,
                  etiqueta: TextosAltaPorPin.calle,
                  sugerencia: 'Calle',
                  campo: estado.calle,
                  controlador: _calle,
                  alCambiar: _notificador.editarCalle,
                  limite: 120,
                  accion: TextInputAction.next,
                  bloqueado: registrando,
                ),
                if (estado.calle.fuente == FuenteCampo.vacio)
                  const _Ayuda(TextosAltaPorPin.calleSinMapa),
              ],
              const SizedBox(height: 14),
              CampoDireccionUbicacion(
                claveCampo: ClavesPinNuevaCasa.campoNumero,
                etiqueta: TextosAltaPorPin.numero,
                sugerencia: 'Nº',
                campo: estado.numero,
                controlador: _numero,
                alCambiar: _notificador.editarNumero,
                limite: 20,
                accion: TextInputAction.done,
                bloqueado: registrando,
              ),
              _Ayuda(switch (estado.numero.fuente) {
                FuenteCampo.delMapa => TextosAltaPorPin.numeroDelMapa,
                FuenteCampo.editado => '',
                FuenteCampo.vacio =>
                  estado.buscandoDireccion
                      ? TextosAltaPorPin.numeroBuscando
                      : TextosAltaPorPin.numeroSinMapa,
              }),
              if (sinCiudad) ...[
                const SizedBox(height: 14),
                CampoCiudadDelAlta(estado: estado, alTocar: _elegirCiudad),
                if (estado.origenCiudad == OrigenCiudad.sinCiudades ||
                    estado.origenCiudad == OrigenCiudad.noSePudoLeer) ...[
                  const SizedBox(height: 10),
                  AvisoCiudadDelAlta(
                    sinCiudades: estado.origenCiudad == OrigenCiudad.sinCiudades,
                    alReintentar: _notificador.reintentarCiudad,
                  ),
                ] else if (estado.origenCiudad == OrigenCiudad.porElegir)
                  const _Ayuda(TextosAlta.elegiLaCiudad),
              ],
              if (estado.falla != null) ...[
                const SizedBox(height: 14),
                KeyedSubtree(
                  key: _lugarDeLaFalla,
                  child: AvisoAlta(
                    key: ClavesPinNuevaCasa.falla,
                    color: ColoresAlta.rojo,
                    glyph: '!',
                    texto: mensajeFallaAlta(estado.falla!),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                key: ClavesPinNuevaCasa.seguir,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
                onPressed: puedeSeguir ? () => unawaited(_seguir()) : null,
                child: registrando
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(
                              key: ClavesPinNuevaCasa.registrando,
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Flexible(
                            child: Text(TextosAltaPorPin.registrando, textAlign: TextAlign.center),
                          ),
                        ],
                      )
                    : const Text(TextosAltaPorPin.seguir, textAlign: TextAlign.center),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                key: ClavesPinNuevaCasa.volver,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: const StadiumBorder(),
                  foregroundColor: ColoresAlta.tinta,
                  side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                onPressed: registrando ? null : () => _salir(null),
                child: const Text(TextosAltaPorPin.volver, textAlign: TextAlign.center),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La línea de ayuda de un campo (gris, chica). Sin texto no ocupa lugar.
class _Ayuda extends StatelessWidget {
  const _Ayuda(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) {
    if (texto.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        texto,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: ColoresAlta.gris, fontSize: 12.5, height: 1.4),
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

/// El bloque `tipo` del canvas: casa, edificio y negocio, cada uno con su ayuda, uno por renglón.
class _OpcionesDeTipo extends StatelessWidget {
  const _OpcionesDeTipo({required this.tipo, required this.alElegir});

  final TipoUbicacion? tipo;
  final ValueChanged<TipoUbicacion>? alElegir;

  /// El orden del canvas: casa, edificio, negocio.
  static const _orden = [TipoUbicacion.casa, TipoUbicacion.edificio, TipoUbicacion.negocio];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        for (final t in _orden)
          _OpcionDeTipo(
            tipo: t,
            elegido: tipo == t,
            alTocar: alElegir == null ? null : () => alElegir!(t),
          ),
      ],
    );
  }
}

class _OpcionDeTipo extends StatelessWidget {
  const _OpcionDeTipo({required this.tipo, required this.elegido, required this.alTocar});

  final TipoUbicacion tipo;
  final bool elegido;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);
    final nombre = FormatoUbicaciones.tipo(tipo);
    final ayuda = TextosAltaPorPin.ayudaDelTipo(tipo);
    return Semantics(
      button: true,
      selected: elegido,
      inMutuallyExclusiveGroup: true,
      enabled: alTocar != null,
      label: '$nombre. $ayuda',
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        key: ClavesPinNuevaCasa.tipo(tipo.name),
        color: elegido ? ColoresAlta.azulFondo : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: elegido ? navy : ColoresAlta.grisBorde, width: 1.5),
        ),
        child: InkWell(
          onTap: alTocar,
          borderRadius: BorderRadius.circular(14),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nombre,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: ColoresLista.tinta,
                          ),
                        ),
                        Text(
                          ayuda,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ColoresAlta.tinta,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (elegido) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.check_circle, size: 22, color: navy),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
