import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/espacio.dart';
import '../../domain/entities/motivo_rechazo_espacio.dart';
import '../../domain/entities/resultado_baja_espacio.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/usecases/agregar_espacio_use_case.dart';
import '../../domain/usecases/dar_de_baja_espacio_use_case.dart';
import '../../domain/usecases/modificar_espacio_use_case.dart';
import '../formato_espacios.dart';
import '../formato_ubicaciones.dart';
import '../providers/espacios_providers.dart';
import '../providers/personas_providers.dart';
import 'campos_ubicacion.dart';
import 'piezas_alta.dart';

/// Las claves de la hoja de un depto (vista 11·02 y 11·03).
abstract final class ClavesHojaDepto {
  static const hoja = Key('depto_hoja');
  static const numero = Key('depto_numero');
  static const piso = Key('depto_piso');
  static const agregar = Key('depto_agregar');
  static const agregarYCargarOtro = Key('depto_agregar_y_cargar_otro');
  static const guardar = Key('depto_guardar');
  static const darDeBaja = Key('depto_dar_de_baja');
  static const repetido = Key('depto_repetido');
  static const verRepetido = Key('depto_ver_repetido');
  static const falla = Key('depto_falla');
  static const agregado = Key('depto_agregado');
  static const alternarTecladoNumero = Key('depto_teclado_numero');
  static const alternarTecladoPiso = Key('depto_teclado_piso');
  static const confirmarBaja = Key('depto_confirmar_baja');
  static const cancelarBaja = Key('depto_cancelar_baja');
  static const bajaBloqueada = Key('depto_baja_bloqueada');
}

/// El tope de caracteres del número y del piso. Un depto se nombra con pocas letras y números
/// («3B», «PB-A», «Local 4»): más que esto es un error de tipeo o un pegado de otra cosa.
const topeNumeroDepto = 40;
const topePisoDepto = 20;

/// Cómo se cerró la hoja de un depto.
sealed class SalidaHojaDepto {
  const SalidaHojaDepto();
}

/// Se agregó el depto [espacio] (y no se pidió cargar otro).
final class DeptoAgregado extends SalidaHojaDepto {
  const DeptoAgregado(this.espacio);

  final Espacio espacio;
}

/// Se guardaron los cambios del depto [espacio].
final class DeptoEditado extends SalidaHojaDepto {
  const DeptoEditado(this.espacio);

  final Espacio espacio;
}

/// Se dio de baja el depto [espacio].
final class DeptoDadoDeBaja extends SalidaHojaDepto {
  const DeptoDadoDeBaja(this.espacio);

  final Espacio espacio;
}

/// Ya había un depto con ese número y el colportor eligió «Ver depto 102 ›» (vista 11·03): la lista lo
/// deja a la vista.
final class VerDeptoElegido extends SalidaHojaDepto {
  const VerDeptoElegido(this.espacioId);

  final String espacioId;
}

/// Abre la hoja del alta de un depto (vista 11·02) o, con [espacio], la de su edición. Devuelve cómo
/// terminó, o `null` si el colportor cerró sin hacer nada. «Agregar y cargar otro» no cierra la hoja:
/// el último resultado llega cuando se cierra con «Agregar» (o por fuera, como `null`).
Future<SalidaHojaDepto?> mostrarHojaDepto(
  BuildContext context, {
  required Ubicacion ubicacion,
  required String colportorId,
  Espacio? espacio,
}) => showModalBottomSheet<SalidaHojaDepto>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras guarda, la hoja no se puede cerrar de costado.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaDepto(ubicacion: ubicacion, colportorId: colportorId, espacio: espacio),
);

/// La hoja corta del alta de un depto (canvas 11·02: «Nuevo departamento», número y piso) y de su
/// edición: los mismos campos con el depto cargado y «Guardar», más «Dar de baja este depto» al pie
/// (como la edición de una ubicación, vista 07).
///
/// - El número es obligatorio y no puede repetir el de otro depto activo del edificio, sin contar
///   espacios ni mayúsculas (11·03: «Ya existe el departamento 102 en este edificio.» con «Ver depto
///   102 ›»). El teclado arranca numérico y una tecla lo pasa a letras («3B», «PB-A»).
/// - Un id por formulario ([AgregarEspacioUseCase.nuevoId]): un doble toque, o un reintento después
///   de una falla, no crea dos deptos. «Agregar y cargar otro» deja el formulario listo para el
///   siguiente, con otro id y el mismo piso.
/// - Mientras guarda, nada más se puede tocar y la hoja no se cierra; si falla, todo vuelve a estar
///   habilitado con el aviso.
class HojaDepto extends ConsumerStatefulWidget {
  const HojaDepto({super.key, required this.ubicacion, required this.colportorId, this.espacio});

  final Ubicacion ubicacion;
  final String colportorId;

  /// El depto que se edita; `null` es el alta de uno nuevo.
  final Espacio? espacio;

  @override
  ConsumerState<HojaDepto> createState() => _HojaDeptoState();
}

enum _Accion { agregar, agregarYCargarOtro, guardar, darDeBaja }

class _HojaDeptoState extends ConsumerState<HojaDepto> {
  late final _numero = TextEditingController(text: widget.espacio?.numeroDepto ?? '');
  late final _piso = TextEditingController(text: widget.espacio?.piso ?? '');
  final _focoNumero = FocusNode();
  final _focoPiso = FocusNode();

  /// El teclado arranca numérico (canvas); una tecla lo pasa a letras.
  var _numericoNumero = true;
  var _numericoPiso = true;

  late var _idAlta = ref.read(agregarEspacioUseCaseProvider).nuevoId();

  _Accion? _enCurso;
  String? _errorNumero;
  String? _falla;

  /// «Depto 301 agregado.»: la confirmación visible de «Agregar y cargar otro». Se va cuando empieza
  /// a escribir el siguiente número (o al volver a guardar).
  String? _agregado;

  /// El depto con el mismo número (11·03): su número tal como se escribió y su id.
  ({String numero, String id})? _repetido;

  bool get _esAlta => widget.espacio == null;
  bool get _enviando => _enCurso != null;

  @override
  void dispose() {
    _numero.dispose();
    _piso.dispose();
    _focoNumero.dispose();
    _focoPiso.dispose();
    super.dispose();
  }

  void _limpiarAvisos() {
    _errorNumero = null;
    _falla = null;
    _repetido = null;
    _agregado = null;
  }

  void _alEscribirNumero(String _) {
    // El aviso de «repetido» o «obligatorio» era de lo que había escrito: al cambiarlo se va.
    if (_errorNumero != null || _repetido != null || _agregado != null) {
      setState(() {
        _errorNumero = null;
        _repetido = null;
        _agregado = null;
      });
    }
  }

  void _alternarTeclado({required bool numero}) {
    final foco = numero ? _focoNumero : _focoPiso;
    setState(() {
      if (numero) {
        _numericoNumero = !_numericoNumero;
      } else {
        _numericoPiso = !_numericoPiso;
      }
    });
    // El teclado del sistema no cambia de tipo con el campo abierto: se vuelve a pedir.
    foco.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) foco.requestFocus();
    });
  }

  // ---------------------------------------------------------------- guardar

  Future<void> _guardar(_Accion accion) async {
    if (_enviando) return;
    setState(() {
      _enCurso = accion;
      _limpiarAvisos();
    });
    final ubicacionId = widget.ubicacion.id;
    final Espacio? guardado;
    Failure? falla;
    try {
      final resultado = _esAlta
          ? await ref.read(agregarEspacioUseCaseProvider)(
              AgregarEspacioParams(
                id: _idAlta,
                ubicacionId: ubicacionId,
                colportorId: widget.colportorId,
                numeroDepto: _numero.text,
                piso: _piso.text,
              ),
            )
          : await ref.read(modificarEspacioUseCaseProvider)(
              ModificarEspacioParams(
                id: widget.espacio!.id,
                numeroDepto: _numero.text,
                piso: _piso.text,
              ),
            );
      falla = resultado.fold<Failure?>((f) => f, (_) => null);
      guardado = resultado.fold<Espacio?>((_) => null, (e) => e);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _enCurso = null;
        _falla = TextosEspacios.noPudimosGuardar;
      });
      _registrar(e);
      return;
    }
    if (!mounted) return;
    if (guardado != null) {
      ref.invalidate(espaciosDeUbicacionProvider(ubicacionId));
      _terminar(guardado, accion);
      return;
    }
    await _mostrarFalla(falla!);
  }

  void _registrar(Object _) {}

  void _terminar(Espacio guardado, _Accion accion) {
    if (accion == _Accion.agregarYCargarOtro) {
      // El formulario queda listo para el siguiente: otro id, el número vacío y el piso como estaba.
      final numero = guardado.numeroDepto ?? '';
      final aviso = TextosEspacios.agregado(numero);
      setState(() {
        _enCurso = null;
        _idAlta = ref.read(agregarEspacioUseCaseProvider).nuevoId();
        _numero.clear();
        _agregado = aviso;
      });
      _focoNumero.requestFocus();
      unawaited(
        SemanticsService.sendAnnouncement(View.of(context), aviso, Directionality.of(context)),
      );
      return;
    }
    Navigator.of(
      context,
    ).pop<SalidaHojaDepto>(_esAlta ? DeptoAgregado(guardado) : DeptoEditado(guardado));
  }

  Future<void> _mostrarFalla(Failure falla) async {
    if (falla is FailureValidacion) {
      final deNumero = falla.campos['numeroDepto'];
      if (deNumero != null) {
        if (deNumero == MotivoRechazoEspacio.deptoDuplicado.mensaje) {
          await _mostrarRepetido();
          return;
        }
        setState(() {
          _enCurso = null;
          _errorNumero = deNumero;
        });
        return;
      }
    }
    setState(() {
      _enCurso = null;
      _falla = switch (falla) {
        FailureInesperado() => TextosEspacios.noPudimosGuardar,
        FailureValidacion(:final campos) when campos.isNotEmpty => campos.values.first,
        _ => mensajePara(falla, accion: 'guardar el departamento.'),
      };
    });
  }

  /// Otro depto activo tiene ese número: se lee la lista al día para saber cuál es (11·03).
  Future<void> _mostrarRepetido() async {
    final ubicacionId = widget.ubicacion.id;
    ref.invalidate(espaciosDeUbicacionProvider(ubicacionId));
    Espacio? existente;
    try {
      final todos = await ref.read(espaciosDeUbicacionProvider(ubicacionId).future);
      final clave = Espacio.claveDeNumero(_numero.text);
      for (final e in todos) {
        if (e.id != widget.espacio?.id && e.clave == clave) existente = e;
      }
    } on Object {
      existente = null;
    }
    if (!mounted) return;
    setState(() {
      _enCurso = null;
      final numero = existente?.numeroDepto ?? _numero.text.trim();
      _repetido = (numero: numero, id: existente?.id ?? '');
    });
  }

  // ---------------------------------------------------------------- baja

  Future<void> _darDeBaja() async {
    if (_enviando) return;
    final espacio = widget.espacio!;
    setState(() {
      _enCurso = _Accion.darDeBaja;
      _limpiarAvisos();
    });
    final baja = ref.read(darDeBajaEspacioUseCaseProvider);
    final Failure? falla;
    Espacio? dadoDeBaja;
    try {
      final personas = await ref.read(contadorPersonasEspacioProvider).activasEn(espacio.id);
      if (!mounted) return;
      // Sin personas el caso de uso da de baja de una: se pregunta antes. Con personas, la pregunta es
      // el aviso de la HU que devuelve el caso de uso.
      if (personas == 0 && !await _confirmar(_preguntaBaja(espacio))) {
        if (mounted) setState(() => _enCurso = null);
        return;
      }
      if (!mounted) return;
      var respuesta = await baja(DarDeBajaEspacioParams(id: espacio.id));
      if (!mounted) return;
      final aviso = respuesta.fold<BajaRequiereConfirmacion?>(
        (_) => null,
        (r) => r is BajaRequiereConfirmacion ? r : null,
      );
      if (aviso != null) {
        if (!await _confirmar(_avisoConPersonas(aviso))) {
          if (mounted) setState(() => _enCurso = null);
          return;
        }
        if (!mounted) return;
        respuesta = await baja(DarDeBajaEspacioParams(id: espacio.id, confirmaConPersonas: true));
        if (!mounted) return;
      }
      falla = respuesta.fold<Failure?>((f) => f, (_) => null);
      dadoDeBaja = respuesta.fold<Espacio?>(
        (_) => null,
        (r) => r is BajaRealizada ? r.espacio : null,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _enCurso = null;
        _falla = TextosEspacios.noPudimosDarDeBaja;
      });
      return;
    }
    if (!mounted) return;
    if (dadoDeBaja != null) {
      ref.invalidate(espaciosDeUbicacionProvider(widget.ubicacion.id));
      Navigator.of(context).pop<SalidaHojaDepto>(DeptoDadoDeBaja(dadoDeBaja));
      return;
    }
    if (falla is FailureUltimoEspacioConPersonas) {
      setState(() => _enCurso = null);
      await _avisarBajaBloqueada(falla.mensaje);
      return;
    }
    setState(() {
      _enCurso = null;
      _falla = switch (falla) {
        FailureInesperado() || null => TextosEspacios.noPudimosDarDeBaja,
        _ => mensajePara(falla, accion: 'dar de baja el departamento.'),
      };
    });
  }

  ({String titulo, String? cuerpo}) _preguntaBaja(Espacio espacio) => (
    titulo: TextosEspacios.preguntaBaja(espacio),
    cuerpo: TextosEspacios.cuerpoBaja(widget.ubicacion.tipo),
  );

  ({String titulo, String? cuerpo}) _avisoConPersonas(BajaRequiereConfirmacion aviso) =>
      (titulo: TextosEspacios.darDeBaja, cuerpo: aviso.aviso);

  Future<bool> _confirmar(({String titulo, String? cuerpo}) pregunta) async {
    final respuesta = await showDialog<bool>(
      context: context,
      builder: (contexto) => AlertDialog(
        scrollable: true,
        title: Text(pregunta.titulo),
        content: pregunta.cuerpo == null ? null : Text(pregunta.cuerpo!),
        actions: [
          TextButton(
            key: ClavesHojaDepto.cancelarBaja,
            onPressed: () => Navigator.of(contexto).pop(false),
            child: const Text(TextosEspacios.cancelar),
          ),
          FilledButton(
            key: ClavesHojaDepto.confirmarBaja,
            onPressed: () => Navigator.of(contexto).pop(true),
            style: FilledButton.styleFrom(backgroundColor: ColoresAlta.rojo),
            child: const Text(TextosEspacios.darDeBajaAccion),
          ),
        ],
      ),
    );
    return respuesta ?? false;
  }

  Future<void> _avisarBajaBloqueada(String mensaje) => showDialog<void>(
    context: context,
    builder: (contexto) => AlertDialog(
      key: ClavesHojaDepto.bajaBloqueada,
      scrollable: true,
      title: const Text(TextosEspacios.noSePuedeDarDeBaja),
      content: Text(mensaje),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(contexto).pop(),
          child: const Text(TextosEspacios.entendido),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------------- dibujo

  @override
  Widget build(BuildContext context) {
    final tipo = widget.ubicacion.tipo;
    final repetido = _repetido;
    final teclado = MediaQuery.viewInsetsOf(context).bottom;
    return PopScope(
      canPop: !_enviando,
      child: SafeArea(
        child: Padding(
          key: ClavesHojaDepto.hoja,
          padding: EdgeInsets.only(bottom: teclado),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 10, bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF90A0B7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '${FormatoUbicaciones.direccion(widget.ubicacion)} · '
                                '${FormatoUbicaciones.tipo(tipo)}'
                            .toUpperCase(),
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: ColoresAlta.gris,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Semantics(
                        header: true,
                        child: Text(
                          _esAlta
                              ? TextosEspacios.nuevoDepartamento
                              : TextosEspacios.editarDepartamento,
                          style: const TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 23,
                            fontWeight: FontWeight.w600,
                            height: 1.2,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_agregado != null) ...[
                        _DeptoAgregado(key: ClavesHojaDepto.agregado, texto: _agregado!),
                        const SizedBox(height: 10),
                      ],
                      _CampoDepto(
                        key: ClavesHojaDepto.numero,
                        etiqueta: TextosEspacios.numeroObligatorio,
                        controlador: _numero,
                        foco: _focoNumero,
                        limite: topeNumeroDepto,
                        numerico: _numericoNumero,
                        autofocus: _esAlta,
                        error: _errorNumero,
                        conBorde: _errorNumero != null || repetido != null,
                        bloqueado: _enviando,
                        accion: TextInputAction.next,
                        alCambiar: _alEscribirNumero,
                        alAlternarTeclado: () => _alternarTeclado(numero: true),
                        claveAlternar: ClavesHojaDepto.alternarTecladoNumero,
                        alEnviar: (_) => _focoPiso.requestFocus(),
                      ),
                      if (repetido != null) ...[
                        const SizedBox(height: 10),
                        AvisoAlta(
                          key: ClavesHojaDepto.repetido,
                          color: ColoresAlta.rojo,
                          glyph: '!',
                          texto: TextosEspacios.repetido(repetido.numero, tipo),
                          acciones: repetido.id.isEmpty
                              ? null
                              : Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: EnlaceAlta(
                                    key: ClavesHojaDepto.verRepetido,
                                    texto: TextosEspacios.verDepto(repetido.numero),
                                    alPresionar: _enviando
                                        ? null
                                        : () => Navigator.of(
                                            context,
                                          ).pop<SalidaHojaDepto>(VerDeptoElegido(repetido.id)),
                                  ),
                                ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _CampoDepto(
                        key: ClavesHojaDepto.piso,
                        etiqueta: TextosEspacios.pisoOpcional,
                        controlador: _piso,
                        foco: _focoPiso,
                        limite: topePisoDepto,
                        numerico: _numericoPiso,
                        bloqueado: _enviando,
                        accion: TextInputAction.done,
                        alAlternarTeclado: () => _alternarTeclado(numero: false),
                        claveAlternar: ClavesHojaDepto.alternarTecladoPiso,
                        alEnviar: (_) =>
                            unawaited(_guardar(_esAlta ? _Accion.agregar : _Accion.guardar)),
                      ),
                      if (_falla != null) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(
                          key: ClavesHojaDepto.falla,
                          color: ColoresAlta.rojo,
                          glyph: '!',
                          texto: _falla!,
                        ),
                      ],
                      const SizedBox(height: 16),
                      ..._acciones(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _acciones() {
    if (_esAlta) {
      return [
        FilledButton(
          key: ClavesHojaDepto.agregar,
          onPressed: _enviando ? null : () => unawaited(_guardar(_Accion.agregar)),
          style: _estiloPrimario,
          child: Text(
            _enCurso == _Accion.agregar ? TextosEspacios.agregando : TextosEspacios.agregar,
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ClavesHojaDepto.agregarYCargarOtro,
          onPressed: _enviando ? null : () => unawaited(_guardar(_Accion.agregarYCargarOtro)),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            foregroundColor: ColoresAlta.azul,
            side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
          ),
          child: Text(
            _enCurso == _Accion.agregarYCargarOtro
                ? TextosEspacios.agregando
                : TextosEspacios.agregarYCargarOtro,
            textAlign: TextAlign.center,
          ),
        ),
      ];
    }
    return [
      FilledButton(
        key: ClavesHojaDepto.guardar,
        onPressed: _enviando ? null : () => unawaited(_guardar(_Accion.guardar)),
        style: _estiloPrimario,
        child: Text(
          _enCurso == _Accion.guardar ? TextosEspacios.guardando : TextosEspacios.guardar,
          textAlign: TextAlign.center,
        ),
      ),
      const SizedBox(height: 4),
      TextButton(
        key: ClavesHojaDepto.darDeBaja,
        onPressed: _enviando ? null : () => unawaited(_darDeBaja()),
        style: TextButton.styleFrom(
          foregroundColor: ColoresAlta.rojo,
          minimumSize: const Size.fromHeight(48),
          textStyle: const TextStyle(
            fontFamily: 'Inter',
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        child: Text(
          _enCurso == _Accion.darDeBaja ? TextosEspacios.dandoDeBaja : TextosEspacios.darDeBaja,
          textAlign: TextAlign.center,
        ),
      ),
    ];
  }

  static final _estiloPrimario = FilledButton.styleFrom(minimumSize: const Size.fromHeight(52));
}

/// Un campo de texto de la hoja del depto: la etiqueta de arriba, el campo y, a la derecha, la tecla
/// «ABC» / «123» que pasa el teclado de números a letras y de vuelta (canvas 11: «el teclado arranca
/// numérico con una tecla para cambiar a letras»).
/// La línea que confirma, a quien mira la pantalla, que el depto anterior quedó guardado («Depto 301
/// agregado.»). No es región viva: el lector ya lo recibe como anuncio al guardar, una sola vez.
class _DeptoAgregado extends StatelessWidget {
  const _DeptoAgregado({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const InsigniaCirculo(color: ColoresAlta.verde, glyph: '✓', tamano: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: ColoresAlta.verde,
            ),
          ),
        ),
      ],
    );
  }
}

class _CampoDepto extends StatelessWidget {
  const _CampoDepto({
    super.key,
    required this.etiqueta,
    required this.controlador,
    required this.foco,
    required this.limite,
    required this.numerico,
    required this.bloqueado,
    required this.accion,
    required this.alAlternarTeclado,
    required this.claveAlternar,
    required this.alEnviar,
    this.alCambiar,
    this.error,
    this.conBorde = false,
    this.autofocus = false,
  });

  final String etiqueta;
  final TextEditingController controlador;
  final FocusNode foco;
  final int limite;
  final bool numerico;
  final bool bloqueado;
  final TextInputAction accion;
  final VoidCallback alAlternarTeclado;
  final Key claveAlternar;
  final ValueChanged<String> alEnviar;
  final ValueChanged<String>? alCambiar;
  final String? error;
  final bool conBorde;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder borde(Color color) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: 1.5),
    );
    final colorBorde = conBorde ? ColoresAlta.rojo : ColoresAlta.grisBorde;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EtiquetaCampoUbicacion(etiqueta),
        const SizedBox(height: 6),
        TextField(
          controller: controlador,
          focusNode: foco,
          autofocus: autofocus,
          readOnly: bloqueado,
          keyboardType: numerico ? TextInputType.number : TextInputType.text,
          textInputAction: accion,
          textCapitalization: TextCapitalization.characters,
          onChanged: alCambiar,
          onSubmitted: alEnviar,
          inputFormatters: [
            // Un número o un piso pegado en varias líneas queda en una.
            FilteringTextInputFormatter.deny(RegExp(r'[\r\n  ]+'), replacementString: ' '),
            LengthLimitingTextInputFormatter(limite),
          ],
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            constraints: const BoxConstraints(minHeight: 48),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            errorText: error,
            errorMaxLines: 6,
            errorStyle: const TextStyle(color: ColoresAlta.rojo, fontSize: 13),
            border: borde(colorBorde),
            enabledBorder: borde(colorBorde),
            focusedBorder: borde(
              conBorde ? ColoresAlta.rojo : Theme.of(context).colorScheme.primary,
            ),
            errorBorder: borde(ColoresAlta.rojo),
            focusedErrorBorder: borde(ColoresAlta.rojo),
            suffixIcon: Semantics(
              button: true,
              label: numerico ? TextosEspacios.tecladoALetras : TextosEspacios.tecladoANumeros,
              excludeSemantics: true,
              onTap: bloqueado ? null : alAlternarTeclado,
              child: TextButton(
                key: claveAlternar,
                onPressed: bloqueado ? null : alAlternarTeclado,
                style: TextButton.styleFrom(
                  foregroundColor: ColoresAlta.azul,
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: Text(numerico ? TextosEspacios.teclaLetras : TextosEspacios.teclaNumeros),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
