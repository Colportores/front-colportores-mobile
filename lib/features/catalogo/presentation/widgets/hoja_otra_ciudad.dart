import 'package:flutter/material.dart';

import '../../domain/entities/ciudad_consultable.dart';
import '../formato_precios.dart';
import 'piezas_precios.dart';

const _scrim = Color(0x730E1A2B);

/// Abre «Ver precios de» (26·04) y devuelve la ciudad elegida al tocar «Ver precios», o `null` si se
/// cerró sin aplicar. Elegir una opción solo la marca: la lista cambia con el botón.
///
/// [marcas] pone el rótulo de dónde está la colportora al lado de la campaña («Donde estás ·
/// Primavera 2026»): por `campaniaCiudadId`.
Future<CiudadConsultable?> mostrarHojaOtraCiudad(
  BuildContext context, {
  required List<CiudadConsultable> ciudades,
  required CiudadConsultable? actual,
  Map<String, String> marcas = const {},
}) => showModalBottomSheet<CiudadConsultable>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  barrierColor: _scrim,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaOtraCiudad(ciudades: ciudades, actual: actual, marcas: marcas),
);

/// La hoja «Ver precios de» (26·04): una opción por ciudad de las campañas en curso o por empezar.
class HojaOtraCiudad extends StatefulWidget {
  const HojaOtraCiudad({
    super.key,
    required this.ciudades,
    required this.actual,
    this.marcas = const {},
  });

  final List<CiudadConsultable> ciudades;

  /// La que se está viendo; `null` si todavía no hay ninguna (sin zona ni GPS: la elige ella).
  final CiudadConsultable? actual;
  final Map<String, String> marcas;

  @override
  State<HojaOtraCiudad> createState() => _HojaOtraCiudadState();
}

class _HojaOtraCiudadState extends State<HojaOtraCiudad> {
  late CiudadConsultable? _elegida = widget.actual;

  /// «Ver precios» cierra la hoja una sola vez: un segundo toque no la cierra de nuevo.
  var _cerrando = false;

  void _aplicar() {
    final elegida = _elegida;
    if (_cerrando || elegida == null) return;
    _cerrando = true;
    Navigator.of(context).pop(elegida);
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
              padding: const EdgeInsets.fromLTRB(22, 4, 22, 8),
              child: Semantics(
                header: true,
                child: const Text(
                  TextosPrecios.hojaOtraCiudadTitulo,
                  style: TextStyle(
                    fontFamily: 'SourceSerif4',
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              child: Column(
                children: [
                  for (final ciudad in widget.ciudades)
                    _OpcionDeCiudad(
                      ciudad: ciudad,
                      subtitulo: FormatoPrecios.ciudadEnLaHoja(
                        ciudad,
                        marca: widget.marcas[ciudad.campaniaCiudadId],
                      ),
                      elegida: ciudad.campaniaCiudadId == _elegida?.campaniaCiudadId,
                      alPresionar: () => setState(() => _elegida = ciudad),
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(22, 8, 22, 0),
              child: Text(
                TextosPrecios.hojaOtraCiudadNota,
                style: TextStyle(fontFamily: 'Inter', fontSize: 12.5, color: ColoresPrecios.gris),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 16),
              child: FilledButton(
                key: const Key('precios_aplicar_ciudad'),
                onPressed: _elegida == null ? null : _aplicar,
                style: FilledButton.styleFrom(
                  backgroundColor: ColoresPrecios.navy,
                  minimumSize: const Size.fromHeight(56),
                ),
                child: const Text(TextosPrecios.hojaOtraCiudadAccion),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpcionDeCiudad extends StatelessWidget {
  const _OpcionDeCiudad({
    required this.ciudad,
    required this.subtitulo,
    required this.elegida,
    required this.alPresionar,
  });

  final CiudadConsultable ciudad;
  final String subtitulo;
  final bool elegida;
  final VoidCallback alPresionar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: elegida,
      inMutuallyExclusiveGroup: true,
      label: '${ciudad.nombre}. $subtitulo',
      onTap: alPresionar,
      child: ExcludeSemantics(
        child: InkWell(
          key: Key('precios_opcion_${ciudad.campaniaCiudadId}'),
          onTap: alPresionar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: elegida ? ColoresPrecios.navy : Colors.white,
                      border: Border.all(
                        color: elegida ? ColoresPrecios.navy : ColoresPrecios.gris,
                        width: 2,
                      ),
                    ),
                    child: elegida
                        ? const Text(
                            '●',
                            textScaler: TextScaler.noScaling,
                            style: TextStyle(color: Colors.white, fontSize: 9, height: 1),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ciudad.nombre,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          subtitulo,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            color: ColoresPrecios.tinta,
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
