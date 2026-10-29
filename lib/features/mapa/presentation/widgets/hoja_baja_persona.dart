import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/persona.dart';
import '../../domain/entities/resultado_baja_persona.dart';
import '../../domain/services/cuenta_de_persona.dart';
import '../../domain/usecases/baja_persona_use_cases.dart';
import '../providers/baja_persona_providers.dart';
import '../textos_baja_persona.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart' show textoGrande;

/// Cómo se cerró la hoja de baja de una persona.
sealed class SalidaHojaBajaPersona {
  const SalidaHojaBajaPersona();
}

/// La persona quedó de baja en el teléfono (o ya lo estaba: un doble toque).
final class PersonaBajaRealizada extends SalidaHojaBajaPersona {
  const PersonaBajaRealizada(this.persona);

  final Persona persona;
}

/// Abre la hoja de «¿Dar de baja a …?» de [persona] (vista 32D, artboards 01 a 03). Devuelve cómo
/// terminó, o `null` si la colportora cerró sin hacer nada.
///
/// La abre quien tiene a la persona delante (la ficha, HU-UBI-009): de ahí sale el menú «⋯».
Future<SalidaHojaBajaPersona?> mostrarHojaBajaPersona(
  BuildContext context, {
  required Persona persona,
}) => showModalBottomSheet<SalidaHojaBajaPersona>(
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
  builder: (_) => HojaBajaPersona(persona: persona),
);

enum _Fase { revisando, errorRevision, sinSaldo, resumen, confirmar }

/// La hoja de baja de una persona (32D·01, 32D·02 y 32D·03): primero mira la cuenta de la persona y,
/// según eso, pide una confirmación o dos.
///
/// - **Revisando**: «Revisando la cuenta de …»; si no se pudo leer, el aviso rojo con «Reintentar»
///   (no se da de baja a quien quizá debe: ante la duda se frena).
/// - **32D·01** sin saldo: una confirmación, «Dar de baja».
/// - **32D·02** con saldo: el resumen (cuánto debe, entregas pendientes, comprado, entregado, pagado
///   y saldo) y «Dar de baja igual», que no escribe nada: lleva a la segunda confirmación.
/// - **32D·03**: «¿Seguro?», «Sí, dar de baja» escribe; «No, volver» vuelve al resumen.
/// - Mientras la baja se escribe, «Dando de baja…» y nada se puede tocar ni cerrar; si falla, el aviso
///   rojo y el botón vuelve a quedar habilitado.
class HojaBajaPersona extends ConsumerStatefulWidget {
  const HojaBajaPersona({super.key, required this.persona});

  final Persona persona;

  @override
  ConsumerState<HojaBajaPersona> createState() => _HojaBajaPersonaState();
}

class _HojaBajaPersonaState extends ConsumerState<HojaBajaPersona> {
  var _fase = _Fase.revisando;
  ResumenCuentaPersona? _cuenta;
  var _enviando = false;
  String? _falla;

  String get _nombre => FormatoBajaPersona.nombreDePila(widget.persona);

  @override
  void initState() {
    super.initState();
    unawaited(_revisar());
  }

  Future<void> _revisar() async {
    if (_fase != _Fase.revisando) setState(() => _fase = _Fase.revisando);
    ResumenCuentaPersona? cuenta;
    var fallo = false;
    try {
      final lectura = await ref.read(consultarCuentaDePersonaUseCaseProvider)(widget.persona.id);
      lectura.fold((_) => fallo = true, (c) => cuenta = c);
    } on Object {
      fallo = true;
    }
    if (!mounted) return;
    setState(() {
      _cuenta = cuenta;
      _fase = fallo
          ? _Fase.errorRevision
          : (cuenta?.tieneSaldo ?? false)
          ? _Fase.resumen
          : _Fase.sinSaldo;
    });
  }

  Future<void> _darDeBaja({required bool confirmaSaldo}) async {
    if (_enviando) return;
    setState(() {
      _enviando = true;
      _falla = null;
    });
    Failure? falla;
    ResultadoBajaPersona? resultado;
    try {
      final r = await ref.read(darDeBajaPersonaUseCaseProvider)(
        DarDeBajaPersonaParams(personaId: widget.persona.id, confirmaSaldo: confirmaSaldo),
      );
      r.fold((f) => falla = f, (x) => resultado = x);
    } on Object catch (e) {
      falla = FailureInesperado(causa: e.runtimeType.toString());
    }
    if (!mounted) return;
    switch (resultado) {
      case PersonaDadaDeBaja(:final persona):
        Navigator.of(context).pop<SalidaHojaBajaPersona>(PersonaBajaRealizada(persona));
      case BajaPersonaRequiereConfirmacion(:final cuenta):
        // Entre que se abrió la hoja y que se confirmó apareció una deuda: se muestra el resumen.
        setState(() {
          _enviando = false;
          _cuenta = cuenta;
          _fase = _Fase.resumen;
        });
      case null:
        setState(() {
          _enviando = false;
          _falla = mensajeDeFallaDePersona(
            falla ?? const FailureInesperado(),
            TextosBajaPersona.noPudimosDarDeBaja(_nombre),
          );
        });
    }
  }

  void _irA(_Fase fase) => setState(() {
    _fase = fase;
    _falla = null;
  });

  @override
  Widget build(BuildContext context) {
    final nombre = _nombre;
    final cuenta = _cuenta;
    final (titulo, contenido, acciones) = switch (_fase) {
      _Fase.revisando => (
        TextosBajaPersona.titulo(nombre),
        _revisando(nombre),
        <Widget>[_secundario(TextosBajaPersona.cancelar, _cerrar)],
      ),
      _Fase.errorRevision => (
        TextosBajaPersona.titulo(nombre),
        AvisoAlta(
          color: ColoresAlta.rojo,
          glyph: '!',
          texto: TextosBajaPersona.noPudimosRevisar(nombre),
        ),
        <Widget>[
          _principal(TextosBajaPersona.reintentar, () => unawaited(_revisar()), peligro: false),
          _secundario(TextosBajaPersona.cancelar, _cerrar),
        ],
      ),
      _Fase.sinSaldo => (
        TextosBajaPersona.titulo(nombre),
        _cuerpo(TextosBajaPersona.cuerpoSinSaldo),
        <Widget>[
          _principal(
            TextosBajaPersona.darDeBaja,
            () => unawaited(_darDeBaja(confirmaSaldo: false)),
          ),
          _secundario(TextosBajaPersona.cancelar, _cerrar),
        ],
      ),
      _Fase.resumen when cuenta != null => (
        TextosBajaPersona.titulo(nombre),
        _resumen(nombre, cuenta),
        <Widget>[
          _principal(TextosBajaPersona.darDeBajaIgual, () => _irA(_Fase.confirmar)),
          _secundario(TextosBajaPersona.cancelar, _cerrar),
        ],
      ),
      _Fase.confirmar when cuenta != null => (
        TextosBajaPersona.seguro,
        _cuerpo(TextosBajaPersona.deudaSigue(nombre, cuenta.saldoCentavos)),
        <Widget>[
          _principal(
            TextosBajaPersona.siDarDeBaja,
            () => unawaited(_darDeBaja(confirmaSaldo: true)),
          ),
          _secundario(TextosBajaPersona.noVolver, () => _irA(_Fase.resumen)),
        ],
      ),
      // Sin cuenta no hay resumen que mostrar: no puede pasar, pero ante la duda se vuelve a revisar.
      _ => (
        TextosBajaPersona.titulo(nombre),
        _revisando(nombre),
        <Widget>[_secundario(TextosBajaPersona.cancelar, _cerrar)],
      ),
    };

    return PopScope(
      // Mientras la baja se escribe no se sale: el resultado se perdería.
      canPop: !_enviando,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
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
                      if (_falla != null) ...[
                        const SizedBox(height: 12),
                        AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: _falla!),
                      ],
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

  void _cerrar() {
    if (!_enviando) Navigator.of(context).pop();
  }

  Widget _cuerpo(String texto) => Text(
    texto,
    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: ColoresAlta.tinta, height: 1.5),
  );

  Widget _revisando(String nombre) => Row(
    children: [
      const ExcludeSemantics(
        child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Semantics(
          liveRegion: true,
          child: Text(
            TextosBajaPersona.revisando(nombre),
            style: const TextStyle(color: ColoresAlta.tinta),
          ),
        ),
      ),
    ],
  );

  Widget _resumen(String nombre, ResumenCuentaPersona cuenta) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      AvisoAlta(
        color: ColoresAlta.ambarBorde,
        colorInsignia: ColoresAlta.ambar,
        glyph: '!',
        texto: TextosBajaPersona.resumenDeSaldo(nombre, cuenta),
      ),
      const SizedBox(height: 12),
      _CuadroDeCuenta(cuenta: cuenta),
    ],
  );

  /// La acción de la hoja. Trabajando, «Dando de baja…» y sin otro toque.
  Widget _principal(String etiqueta, VoidCallback alTocar, {bool peligro = true}) {
    final trabajando = _enviando && peligro;
    return FilledButton(
      onPressed: _enviando ? null : alTocar,
      style: FilledButton.styleFrom(
        backgroundColor: peligro ? ColoresAlta.rojo : null,
        disabledBackgroundColor: peligro ? ColoresAlta.rojo.withValues(alpha: .85) : null,
        disabledForegroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
      ),
      child: trabajando
          ? const Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 10,
              children: [
                ExcludeSemantics(
                  child: SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                ),
                Flexible(child: Text(TextosBajaPersona.dandoDeBaja, textAlign: TextAlign.center)),
              ],
            )
          : Text(etiqueta, textAlign: TextAlign.center),
    );
  }

  Widget _secundario(String etiqueta, VoidCallback alTocar) => TextButton(
    onPressed: _enviando ? null : alTocar,
    style: TextButton.styleFrom(
      foregroundColor: ColoresAlta.azul,
      minimumSize: const Size.fromHeight(48),
      textStyle: const TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600),
    ),
    child: Text(etiqueta, textAlign: TextAlign.center),
  );
}

/// «Comprado, Entregado, Pagado, Saldo» (canvas 32D·02): cuatro renglones de rótulo y valor, el saldo
/// en negrita.
class _CuadroDeCuenta extends StatelessWidget {
  const _CuadroDeCuenta({required this.cuenta});

  final ResumenCuentaPersona cuenta;

  @override
  Widget build(BuildContext context) {
    final filas = [
      (TextosBajaPersona.comprado, FormatoBajaPersona.monto(cuenta.compradoCentavos), false, true),
      (TextosBajaPersona.entregado, TextosBajaPersona.entregas(cuenta), false, false),
      (TextosBajaPersona.pagado, FormatoBajaPersona.monto(cuenta.pagadoCentavos), false, true),
      (TextosBajaPersona.saldo, FormatoBajaPersona.monto(cuenta.saldoCentavos), true, true),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ColoresAlta.grisBorde),
      ),
      child: Column(
        children: [
          for (final (rotulo, valor, fuerte, mono) in filas)
            MergeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                // Con el texto grande (desde 1,4×) no entran el rótulo y el valor lado a lado sin
                // partir uno de los dos a mitad de palabra o de número: van uno sobre el otro.
                child: textoGrande(context)
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            rotulo,
                            style: const TextStyle(fontSize: 14, color: ColoresAlta.gris),
                          ),
                          Text(
                            valor,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontFamily: mono ? 'JetBrainsMono' : null,
                              fontSize: 14,
                              fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
                              color: ColoresAlta.tinta,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // El rótulo es una palabra y manda (3 partes contra 2): con el texto grande y un valor
                          // ancho no se parte a mitad de palabra («Comprad» / «o»); el valor, que puede ser
                          // ancho, se acomoda en el resto.
                          Flexible(
                            flex: 3,
                            child: Text(
                              rotulo,
                              style: const TextStyle(fontSize: 14, color: ColoresAlta.gris),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Flexible(
                            flex: 2,
                            child: Text(
                              valor,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                fontFamily: mono ? 'JetBrainsMono' : null,
                                fontSize: 14,
                                fontWeight: fuerte ? FontWeight.w700 : FontWeight.w500,
                                color: ColoresAlta.tinta,
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
