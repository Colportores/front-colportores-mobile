import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../../../core/presentation/mensaje_para.dart';
import '../../domain/entities/motivo_baja.dart';
import '../../domain/entities/pendientes_ubicacion.dart';
import '../../domain/entities/resultado_baja_ubicacion.dart';
import '../../domain/entities/ubicacion.dart';
import '../../domain/usecases/baja_ubicacion_use_cases.dart';
import '../formato_baja.dart';
import '../formato_ubicaciones.dart';
import '../providers/baja_ubicacion_providers.dart';
import 'piezas_alta.dart';

/// Textos de la vista 09 (HU-UBI-005, «Dar de baja y reactivar»). Los rótulos son los de «TEXTOS
/// PROPUESTA» del canvas y el aviso de ventas o visitas de otro colportor es el literal de la HU. Lo
/// que ninguno dice está marcado como provisorio (pendientes de #205).
abstract final class TextosBaja {
  // Canvas 09·01.
  static String titulo(String direccion) => '¿Dar de baja $direccion?';
  static const cuerpo =
      'Deja de aparecer en el mapa y en la lista. Las visitas y ventas quedan guardadas y la podés '
      'reactivar.';
  static const motivo = 'MOTIVO · OBLIGATORIO';
  static const darDeBaja = 'Dar de baja';
  static const cancelar = 'Cancelar';

  // Canvas 09·02.
  static const bloqueadaTitulo = 'Todavía no se puede dar de baja';
  static const irALaCobranza = 'Ir a la cobranza';
  static String bloqueoCobranza(CobranzaPendiente cobranza) =>
      'Tiene una cobranza pendiente de ${FormatoBaja.cobranza(cobranza)}. '
      'Registrá el cobro antes de darla de baja.';

  // La HU (decisión de Cristian, 02/10): ventas o visitas de otro colportor.
  static const bloqueoVentasOVisitasAjenas =
      'No podés dar de baja esta casa porque tiene ventas o visitas de otro colportor. '
      'Si ya no existe, avisale a tu coordinador.';

  // Provisorios: ni la HU ni el canvas los traen.
  static const entendido = 'Entendido';
  static const revisando = 'Revisando la ubicación…';
  static const noPudimosRevisar = 'No pudimos revisar la ubicación. Probá de nuevo.';
  static const reintentar = 'Reintentar';
  static const dandoDeBaja = 'Dando de baja…';
  static const noPudimosDarDeBaja = 'No pudimos dar de baja la ubicación. Probá de nuevo.';
  static const elegiUnMotivo = 'Elegí un motivo para dar de baja.';
  static const otroPista = 'Contanos qué pasó (opcional)';
  static const otroEtiqueta = 'Qué pasó';

  /// El aviso de la segunda confirmación: el texto de la HU y los botones.
  static const confirmarCancelar = 'Cancelar';
}

/// Cómo se cerró la hoja de baja.
sealed class SalidaHojaBaja {
  const SalidaHojaBaja();
}

/// La ubicación quedó de baja en el teléfono (o ya lo estaba: un doble toque).
final class BajaRealizada extends SalidaHojaBaja {
  const BajaRealizada(this.ubicacion);

  final Ubicacion ubicacion;
}

/// La baja estaba bloqueada por una cobranza y el colportor eligió «Ir a la cobranza».
final class IrALaCobranzaElegido extends SalidaHojaBaja {
  const IrALaCobranzaElegido(this.ubicacionId);

  final String ubicacionId;
}

/// El texto del aviso rojo cuando no se pudo dar de baja: la falla inesperada dice qué pasó y qué
/// hacer; las demás (incluida «Esta ubicación cambió recién…») pasan por [mensajePara].
String mensajeFallaBaja(Failure falla) => switch (falla) {
  FailureInesperado() => TextosBaja.noPudimosDarDeBaja,
  _ => mensajePara(falla, accion: 'dar de baja la ubicación.'),
};

/// Abre la hoja de «Dar de baja» de [ubicacion] (vista 09, artboards 01 y 02). Devuelve cómo terminó,
/// o `null` si el colportor cerró sin hacer nada.
///
/// Con [alIrALaCobranza] la hoja bloqueada por una cobranza ofrece «Ir a la cobranza»; sin él, solo
/// el aviso y «Entendido» (la pantalla de cobranzas todavía no existe).
Future<SalidaHojaBaja?> mostrarHojaBaja(
  BuildContext context, {
  required Ubicacion ubicacion,
  bool ofreceIrALaCobranza = false,
}) => showModalBottomSheet<SalidaHojaBaja>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  // Sin arrastrar para cerrar: mientras la baja se escribe la hoja no se puede cerrar de costado (el
  // arrastre no pasa por el `PopScope`). Las salidas son «Cancelar», el atrás y el toque afuera.
  enableDrag: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaBajaUbicacion(ubicacion: ubicacion, ofreceIrALaCobranza: ofreceIrALaCobranza),
);

enum _Fase { revisando, errorRevision, motivo, bloqueada }

/// La hoja de «Dar de baja» (vista 09·01 y 09·02): primero mira lo que el teléfono sabe de la
/// ubicación y, según eso, pide el motivo o explica por qué todavía no se puede.
///
/// - **Revisando**: «Revisando la ubicación…»; si no se pudo leer, el aviso rojo con «Reintentar».
/// - **09·01**: cuatro motivos (ninguno viene elegido), «Otro» con texto libre. «Dar de baja» se
///   habilita recién con un motivo. Con visitas pendientes propias, un segundo aviso pide confirmar.
/// - **09·02**: cobranza pendiente, ventas o visitas de otro colportor: el aviso de la HU, sin escribir
///   nada.
/// - Mientras la baja se escribe, «Dando de baja…» y nada se puede tocar ni cerrar; si falla, el aviso
///   rojo y el botón vuelve a quedar habilitado con el motivo elegido.
class HojaBajaUbicacion extends ConsumerStatefulWidget {
  const HojaBajaUbicacion({super.key, required this.ubicacion, this.ofreceIrALaCobranza = false});

  final Ubicacion ubicacion;

  /// La hoja bloqueada por una cobranza ofrece «Ir a la cobranza».
  final bool ofreceIrALaCobranza;

  @override
  ConsumerState<HojaBajaUbicacion> createState() => _HojaBajaUbicacionState();
}

class _HojaBajaUbicacionState extends ConsumerState<HojaBajaUbicacion> {
  final _otro = TextEditingController();
  var _fase = _Fase.revisando;
  BloqueoBaja? _bloqueo;

  /// Uno de [MotivosBaja.rapidos] o [MotivosBaja.otro]; `null` = todavía no eligió.
  String? _elegido;
  var _enviando = false;
  Failure? _falla;

  @override
  void initState() {
    super.initState();
    unawaited(_revisar());
  }

  @override
  void dispose() {
    _otro.dispose();
    super.dispose();
  }

  /// El motivo como se guarda: el elegido o, con «Otro», el texto (o «Otro» si no escribió nada).
  String? get _motivo {
    final elegido = _elegido;
    if (elegido == null) return null;
    if (elegido != MotivosBaja.otro) return elegido;
    return MotivosBaja.paraGuardar(_otro.text) ?? MotivosBaja.otro;
  }

  Future<void> _revisar() async {
    if (_fase != _Fase.revisando) setState(() => _fase = _Fase.revisando);
    Failure? falla;
    PendientesUbicacion? pendientes;
    try {
      final r = await ref.read(consultarPendientesBajaUseCaseProvider)(widget.ubicacion.id);
      falla = r.fold<Failure?>((f) => f, (_) => null);
      pendientes = r.fold<PendientesUbicacion?>((_) => null, (p) => p);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e);
    }
    if (!mounted) return;
    setState(() {
      if (falla != null || pendientes == null) {
        _fase = _Fase.errorRevision;
        return;
      }
      _bloqueo = pendientes.bloqueo;
      _fase = _bloqueo != null ? _Fase.bloqueada : _Fase.motivo;
    });
  }

  Future<Either2> _pedir({required bool confirma}) async {
    try {
      final r = await ref.read(darDeBajaUbicacionUseCaseProvider)(
        DarDeBajaUbicacionParams(
          id: widget.ubicacion.id,
          baseUpdatedAt: widget.ubicacion.auditoria.updatedAt,
          motivo: _motivo,
          confirmaPendientes: confirma,
        ),
      );
      return (
        falla: r.fold<Failure?>((f) => f, (_) => null),
        resultado: r.fold<ResultadoBajaUbicacion?>((_) => null, (x) => x),
      );
    } on Object catch (e) {
      return (falla: FailureInesperado(causa: e), resultado: null);
    }
  }

  Future<void> _darDeBaja() async {
    if (_enviando || _motivo == null) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    var confirma = false;
    // Hay una sola segunda confirmación posible (visitas pendientes propias): se pide una vez.
    for (var ronda = 0; ronda < 2; ronda++) {
      final (:falla, :resultado) = await _pedir(confirma: confirma);
      if (!mounted) return;
      if (falla != null || resultado == null) {
        setState(() {
          _enviando = false;
          _falla = falla ?? const FailureInesperado();
        });
        return;
      }
      switch (resultado) {
        case UbicacionDadaDeBaja(:final ubicacion) || BajaSinCambios(:final ubicacion):
          Navigator.of(context).pop(BajaRealizada(ubicacion));
          return;
        case BajaBloqueada(:final bloqueo):
          // Entre que se miró y que se confirmó llegó una venta o una visita (el sync).
          setState(() {
            _enviando = false;
            _bloqueo = bloqueo;
            _fase = _Fase.bloqueada;
          });
          return;
        case BajaRequiereConfirmacion(:final pendientes):
          final confirmo = await _confirmarPendientes(pendientes);
          if (!mounted) return;
          if (!confirmo) {
            setState(() => _enviando = false);
            return;
          }
          confirma = true;
      }
    }
    setState(() => _enviando = false);
  }

  Future<bool> _confirmarPendientes(PendientesUbicacion pendientes) async {
    final confirmo = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(pendientes.resumen.join('\n\n')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            child: const Text(TextosBaja.confirmarCancelar),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: ColoresAlta.rojo,
              minimumSize: const Size(64, 48),
            ),
            child: const Text(TextosBaja.darDeBaja),
          ),
        ],
      ),
    );
    return confirmo ?? false;
  }

  void _elegir(String motivo) => setState(() {
    _elegido = motivo;
    _falla = null;
  });

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    final direccion = FormatoUbicaciones.direccion(widget.ubicacion);
    final (contenido, acciones) = switch (_fase) {
      _Fase.revisando => (_revisando(), <Widget>[_cancelar()]),
      _Fase.errorRevision => (
        _errorRevision(),
        <Widget>[
          FilledButton(
            onPressed: () => unawaited(_revisar()),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            child: const Text(TextosBaja.reintentar, textAlign: TextAlign.center),
          ),
          _cancelar(),
        ],
      ),
      _Fase.motivo => (_motivoVista(context), _accionesMotivo()),
      _Fase.bloqueada => (_bloqueadaVista(), _accionesBloqueada()),
    };
    final titulo = _fase == _Fase.bloqueada
        ? TextosBaja.bloqueadaTitulo
        : TextosBaja.titulo(direccion);

    return PopScope(
      // Mientras la baja se escribe no se sale: el resultado se perdería.
      canPop: !_enviando,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + inset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF90A0B7),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          titulo,
                          style: const TextStyle(
                            fontFamily: 'SourceSerif4',
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      contenido,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              for (var i = 0; i < acciones.length; i++) ...[
                if (i > 0) const SizedBox(height: 4),
                acciones[i],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cancelar() => TextButton(
    onPressed: _enviando ? null : () => Navigator.of(context).pop(),
    style: TextButton.styleFrom(
      foregroundColor: ColoresAlta.azul,
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
    ),
    child: const Text(TextosBaja.cancelar, textAlign: TextAlign.center),
  );

  // ---------------------------------------------------------------- revisando

  Widget _revisando() => Row(
    children: [
      const ExcludeSemantics(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: const Text(TextosBaja.revisando, style: TextStyle(color: ColoresAlta.tinta)),
        ),
      ),
    ],
  );

  Widget _errorRevision() =>
      const AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: TextosBaja.noPudimosRevisar);

  // ---------------------------------------------------------------- 09·01

  Widget _motivoVista(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          TextosBaja.cuerpo,
          style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.5),
        ),
        const SizedBox(height: 16),
        const Text(
          TextosBaja.motivo,
          style: TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 10,
            letterSpacing: 1.4,
            color: ColoresAlta.gris,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final motivo in [...MotivosBaja.rapidos, MotivosBaja.otro])
              _ChipMotivo(
                texto: motivo,
                elegido: _elegido == motivo,
                alTocar: _enviando ? null : () => _elegir(motivo),
              ),
          ],
        ),
        if (_elegido == MotivosBaja.otro) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _otro,
            enabled: !_enviando,
            minLines: 2,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            inputFormatters: [LengthLimitingTextInputFormatter(MotivosBaja.maximoOtro)],
            decoration: InputDecoration(
              labelText: TextosBaja.otroEtiqueta,
              hintText: TextosBaja.otroPista,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(14),
              border: _borde(ColoresAlta.grisBorde),
              enabledBorder: _borde(ColoresAlta.grisBorde),
              focusedBorder: _borde(theme.colorScheme.primary),
            ),
          ),
        ],
        if (_falla != null) ...[
          const SizedBox(height: 12),
          AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: mensajeFallaBaja(_falla!)),
        ],
      ],
    );
  }

  static OutlineInputBorder _borde(Color color) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide(color: color, width: 1.5),
  );

  List<Widget> _accionesMotivo() => [
    FilledButton(
      onPressed: _motivo != null && !_enviando ? () => unawaited(_darDeBaja()) : null,
      style: FilledButton.styleFrom(
        backgroundColor: ColoresAlta.rojo,
        disabledBackgroundColor: ColoresAlta.grisFondo,
        disabledForegroundColor: ColoresAlta.gris,
        minimumSize: const Size.fromHeight(52),
      ),
      child: Text(
        _enviando ? TextosBaja.dandoDeBaja : TextosBaja.darDeBaja,
        textAlign: TextAlign.center,
      ),
    ),
    // Lo que falta para poder tocarlo, debajo del botón apagado (como en el alta).
    if (_motivo == null)
      const Padding(
        padding: EdgeInsets.only(top: 2, bottom: 2),
        child: Text(
          TextosBaja.elegiUnMotivo,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
        ),
      ),
    _cancelar(),
  ];

  // ---------------------------------------------------------------- 09·02

  Widget _bloqueadaVista() {
    final bloqueo = _bloqueo;
    final texto = switch (bloqueo) {
      BloqueoPorCobranza(:final cobranza) => TextosBaja.bloqueoCobranza(cobranza),
      _ => TextosBaja.bloqueoVentasOVisitasAjenas,
    };
    return AvisoAlta(color: ColoresAlta.azul, glyph: '!', texto: texto);
  }

  List<Widget> _accionesBloqueada() {
    final aCobranza = _bloqueo is BloqueoPorCobranza && widget.ofreceIrALaCobranza;
    if (aCobranza) {
      return [
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop<SalidaHojaBaja>(IrALaCobranzaElegido(widget.ubicacion.id)),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          child: const Text(TextosBaja.irALaCobranza, textAlign: TextAlign.center),
        ),
        _cancelar(),
      ];
    }
    return [
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
        child: const Text(TextosBaja.entendido, textAlign: TextAlign.center),
      ),
    ];
  }
}

/// El resultado de pedir la baja, sin el `Either`: una falla o el resultado.
typedef Either2 = ({Failure? falla, ResultadoBajaUbicacion? resultado});

/// Un motivo de la baja (09·01): una píldora que se elige con un toque. Elegida lleva «✓» y el relleno
/// navy; las otras, el borde gris.
class _ChipMotivo extends StatelessWidget {
  const _ChipMotivo({required this.texto, required this.elegido, required this.alTocar});

  final String texto;
  final bool elegido;

  /// `null` mientras la baja se escribe.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final navy = Theme.of(context).colorScheme.primary;
    final activo = alTocar != null;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: elegido,
      enabled: activo,
      label: texto,
      excludeSemantics: true,
      onTap: alTocar,
      child: Material(
        color: elegido ? navy : Colors.white,
        shape: StadiumBorder(
          side: BorderSide(color: elegido ? navy : ColoresAlta.grisBorde, width: 1.5),
        ),
        child: InkWell(
          onTap: alTocar,
          customBorder: const StadiumBorder(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Center(
                widthFactor: 1,
                child: Text(
                  elegido ? '✓ $texto' : texto,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: elegido ? FontWeight.w600 : FontWeight.w400,
                    color: elegido ? Colors.white : (activo ? ColoresAlta.tinta : ColoresAlta.gris),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
