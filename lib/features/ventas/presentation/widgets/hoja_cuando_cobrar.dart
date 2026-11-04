import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../formato_venta.dart';

/// Lo que la colportora contesta a «¿Cuándo volvés a cobrar?».
enum CuandoCobrar { hoy, manana, otroDia, sinFecha }

/// Los textos de «¿Cuándo volvés a cobrar?» (decisión de Cristian, 23/10, «Agenda cobro»: «Ana elige
/// el día al guardar»). El canvas no dibuja esta pregunta: los textos son propuesta (mapa §2:
/// texto/aviso).
abstract final class TextosCuandoCobrar {
  static const titulo = '¿Cuándo volvés a cobrar?';
  static const hoy = 'Hoy';
  static const hoySub = 'Elegís la hora';
  static const manana = 'Mañana';
  static const mananaSub = 'Elegís la hora';
  static const otroDia = 'Otro día';
  static const otroDiaSub = 'Elegís el día y la hora';
  static const sinFecha = 'Sin fecha';
  static const sinFechaSub = 'No agendamos nada. Podés agendarla después desde la casa.';

  /// «Quedan $ 1.200 por cobrar a Pedro.»
  static String saldo(int centavos, String persona) => persona.trim().isEmpty
      ? 'Quedan ${FormatoVenta.monto(centavos)} por cobrar.'
      : 'Quedan ${FormatoVenta.monto(centavos)} por cobrar a ${persona.trim()}.';

  /// Lo que lee el lector de pantalla de cada opción.
  static String opcionParaLector(String titulo, String ayuda) => '$titulo. $ayuda';

  /// La venta quedó guardada pero la cita de cobranza no.
  static const noSePudoAgendar =
      'La venta se guardó, pero no pudimos agendar el cobro. Agendalo desde la casa.';

  /// «Venta 0039 guardada. Cobranza agendada para el sáb 26/10 · 12:30.»
  static String agendada(String numeroTalonario, String cuando) =>
      'Venta $numeroTalonario guardada. Cobranza agendada para $cuando.';
}

/// Las claves de la hoja, para los tests y para quien la monta.
abstract final class ClavesCuandoCobrar {
  static const hoja = Key('cuando_cobrar_hoja');
  static Key opcion(CuandoCobrar o) => Key('cuando_cobrar_${o.name}');
}

/// Abre «¿Cuándo volvés a cobrar?» al guardar una venta con saldo. Devuelve lo que eligió.
///
/// **No se puede cerrar sin elegir** (ni arrastrando, ni tocando afuera, ni con el atrás): la venta ya
/// está guardada y esta pregunta decide si queda una cita; la salida «Sin fecha» siempre está.
Future<CuandoCobrar> mostrarHojaCuandoCobrar(
  BuildContext context, {
  required int saldoCentavos,
  required String persona,
}) async {
  final elegida = await showModalBottomSheet<CuandoCobrar>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => HojaCuandoCobrar(saldoCentavos: saldoCentavos, persona: persona),
  );
  return elegida ?? CuandoCobrar.sinFecha;
}

/// «¿Cuándo volvés a cobrar?»: hoy, mañana, otro día o sin fecha. Ver [mostrarHojaCuandoCobrar].
class HojaCuandoCobrar extends StatefulWidget {
  const HojaCuandoCobrar({super.key, required this.saldoCentavos, required this.persona});

  final int saldoCentavos;
  final String persona;

  @override
  State<HojaCuandoCobrar> createState() => _HojaCuandoCobrarState();
}

class _HojaCuandoCobrarState extends State<HojaCuandoCobrar> {
  /// Ya se eligió: un segundo toque (o dos opciones casi a la vez) no cierra la hoja dos veces.
  var _elegida = false;

  void _elegir(CuandoCobrar opcion) {
    if (_elegida) return;
    _elegida = true;
    Navigator.of(context).pop(opcion);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: SingleChildScrollView(
        key: ClavesCuandoCobrar.hoja,
        padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(TextosCuandoCobrar.titulo, style: theme.textTheme.headlineSmall),
            ),
            const SizedBox(height: 6),
            Text(
              TextosCuandoCobrar.saldo(widget.saldoCentavos, widget.persona),
              style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAgenda.tinta, height: 1.5),
            ),
            const SizedBox(height: 16),
            _Opcion(
              opcion: CuandoCobrar.hoy,
              titulo: TextosCuandoCobrar.hoy,
              ayuda: TextosCuandoCobrar.hoySub,
              alTocar: _elegir,
            ),
            const SizedBox(height: 10),
            _Opcion(
              opcion: CuandoCobrar.manana,
              titulo: TextosCuandoCobrar.manana,
              ayuda: TextosCuandoCobrar.mananaSub,
              alTocar: _elegir,
            ),
            const SizedBox(height: 10),
            _Opcion(
              opcion: CuandoCobrar.otroDia,
              titulo: TextosCuandoCobrar.otroDia,
              ayuda: TextosCuandoCobrar.otroDiaSub,
              alTocar: _elegir,
            ),
            const SizedBox(height: 10),
            _Opcion(
              opcion: CuandoCobrar.sinFecha,
              titulo: TextosCuandoCobrar.sinFecha,
              ayuda: TextosCuandoCobrar.sinFechaSub,
              alTocar: _elegir,
            ),
          ],
        ),
      ),
    );
  }
}

class _Opcion extends StatelessWidget {
  const _Opcion({
    required this.opcion,
    required this.titulo,
    required this.ayuda,
    required this.alTocar,
  });

  final CuandoCobrar opcion;
  final String titulo;
  final String ayuda;
  final void Function(CuandoCobrar) alTocar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      label: TextosCuandoCobrar.opcionParaLector(titulo, ayuda),
      onTap: () => alTocar(opcion),
      child: Material(
        key: ClavesCuandoCobrar.opcion(opcion),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE3E7EE)),
        ),
        child: InkWell(
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: () => alTocar(opcion),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          titulo,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF0E1A2B),
                          ),
                        ),
                        Text(
                          ayuda,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ColoresAgenda.tinta,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ExcludeSemantics(
                    child: Text(
                      '›',
                      style: theme.textTheme.titleLarge?.copyWith(color: ColoresAgenda.gris),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
