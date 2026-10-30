import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../textos_anular_cobro.dart';

// Las piezas de la vista 30 B (Detalle del cobro y Anular un cobro, HU-COB-006). Todas crecen con el
// texto (`textScaler` 2.0): nada tiene alto fijo salvo el mínimo táctil.

const _borde = Color(0xFFE3E7EE);

/// Una línea del detalle: «Fecha · Hoy 14:10».
class DatoDelCobro {
  const DatoDelCobro({required this.clave, required this.rotulo, required this.valor, this.rojo});

  final String clave;
  final String rotulo;
  final String valor;

  /// El valor va en rojo y en negrita (el estado «Anulado · …»).
  final bool? rojo;
}

/// La tarjeta con las líneas rótulo / valor del detalle (30B-01).
class FilasDelCobro extends StatelessWidget {
  const FilasDelCobro({super.key, required this.datos});

  final List<DatoDelCobro> datos;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('detalle_cobro_filas'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        children: [
          for (final d in datos)
            Semantics(
              container: true,
              label: '${d.rotulo}: ${d.valor}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        d.rotulo,
                        style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          d.valor,
                          key: Key(d.clave),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: d.rojo == true ? FontWeight.w600 : FontWeight.w400,
                            color: d.rojo == true ? ColoresAgenda.rojo : ColoresAgenda.tinta,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// El aviso informativo (30B-06): fondo azul claro, sin ser un error ni una advertencia.
class AvisoInformativo extends StatelessWidget {
  const AvisoInformativo({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('detalle_cobro_aviso_info'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: ColoresAgenda.azulFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresAgenda.azul, width: 1.5),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 13.5, height: 1.35, color: ColoresAgenda.azul),
        ),
      ),
    );
  }
}

/// El botón rojo de «Anular cobro» del detalle (30B-01), debajo de la nota del plazo. Apagado, no se
/// toca.
class BotonAnularCobro extends StatelessWidget {
  const BotonAnularCobro({super.key, required this.alPresionar});

  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: const Key('detalle_cobro_anular'),
      onPressed: alPresionar,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        foregroundColor: ColoresAgenda.rojo,
        side: const BorderSide(color: ColoresAgenda.rojo, width: 1.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text(
        TextosAnularCobro.anularCobro,
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    );
  }
}

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// La segunda confirmación (30B-04): «¿Anular el cobro de $ 600?». Devuelve `true` con «Sí, anular» y
/// `false` con «No, volver» o al cerrarla sin elegir. Un segundo toque no vuelve a contestar.
Future<bool> mostrarHojaConfirmarAnulacion(
  BuildContext context, {
  required String titulo,
  required String texto,
}) async {
  final confirmo = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: _formaHoja,
    builder: (_) => HojaConfirmarAnulacion(titulo: titulo, texto: texto),
  );
  return confirmo ?? false;
}

class HojaConfirmarAnulacion extends StatefulWidget {
  const HojaConfirmarAnulacion({super.key, required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  State<HojaConfirmarAnulacion> createState() => _HojaConfirmarAnulacionState();
}

class _HojaConfirmarAnulacionState extends State<HojaConfirmarAnulacion> {
  var _respondio = false;

  void _responder(bool si) {
    if (_respondio) return;
    _respondio = true;
    Navigator.of(context).pop(si);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(
                widget.titulo,
                key: const Key('anular_cobro_confirmar_titulo'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              widget.texto,
              key: const Key('anular_cobro_confirmar_texto'),
              style: const TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.tinta),
            ),
            const SizedBox(height: 18),
            FilledButton(
              key: const Key('anular_cobro_si'),
              onPressed: () => _responder(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.rojo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosAnularCobro.siAnular,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              key: const Key('anular_cobro_no'),
              onPressed: () => _responder(false),
              style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              child: const Text(
                TextosAnularCobro.noVolver,
                style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
