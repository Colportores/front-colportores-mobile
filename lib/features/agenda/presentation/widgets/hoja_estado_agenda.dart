import 'package:flutter/material.dart';

import '../../domain/entities/filtros_agenda.dart';
import '../formato_agenda.dart';
import 'piezas_agenda.dart';

const _scrim = Color(0x730E1A2B);

/// Abre la hoja «Estado» (23B·04) y devuelve el estado elegido al tocar «Aplicar», o `null` si se
/// cerró sin aplicar. Elegir una opción solo la marca: el filtro cambia con «Aplicar».
Future<EstadoFiltroAgenda?> mostrarHojaEstadoAgenda(
  BuildContext context, {
  required EstadoFiltroAgenda actual,
}) => showModalBottomSheet<EstadoFiltroAgenda>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: _scrim,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaEstadoAgenda(actual: actual),
);

/// La hoja «Estado» de la agenda: Pendientes, Cumplidas, No cumplidas, Canceladas y Todas.
class HojaEstadoAgenda extends StatefulWidget {
  const HojaEstadoAgenda({super.key, required this.actual});

  final EstadoFiltroAgenda actual;

  @override
  State<HojaEstadoAgenda> createState() => _HojaEstadoAgendaState();
}

class _HojaEstadoAgendaState extends State<HojaEstadoAgenda> {
  late EstadoFiltroAgenda _elegido = widget.actual;

  /// «Aplicar» cierra la hoja una sola vez: un segundo toque no la cierra de nuevo.
  var _cerrando = false;

  void _aplicar() {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(_elegido);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 10, bottom: 8),
              child: Center(
                child: SizedBox(
                  width: 40,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0xFFCFD6E1),
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Semantics(
                header: true,
                child: const Text(
                  TextosAgenda.hojaEstadoTitulo,
                  style: TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            for (final estado in EstadoFiltroAgenda.values)
              _OpcionEstado(
                estado: estado,
                elegida: estado == _elegido,
                alPresionar: () => setState(() => _elegido = estado),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: FilledButton(
                key: const Key('agenda_aplicar_estado'),
                onPressed: _aplicar,
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresAgenda.navy,
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text(TextosAgenda.aplicar),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionEstado extends StatelessWidget {
  const _OpcionEstado({required this.estado, required this.elegida, required this.alPresionar});

  final EstadoFiltroAgenda estado;
  final bool elegida;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    final texto = FormatoAgenda.estado(estado);
    final detalle = FormatoAgenda.detalleDeEstado(estado);
    return Semantics(
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      label: detalle == null ? texto : '$texto. $detalle',
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('agenda_estado_${estado.name}'),
          onTap: alPresionar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      elegida ? '✓' : '',
                      style: const TextStyle(
                        color: ColoresAgenda.navy,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          texto,
                          style: TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 16,
                            fontWeight: elegida ? FontWeight.w600 : null,
                          ),
                        ),
                        if (detalle != null)
                          Text(
                            detalle,
                            style: const TextStyle(
                              fontFamily: 'Inter',
                              fontSize: 12.5,
                              color: ColoresAgenda.gris,
                            ),
                          ),
                      ],
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
