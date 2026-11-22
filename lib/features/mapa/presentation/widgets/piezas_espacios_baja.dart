import 'package:flutter/material.dart';

import '../../domain/entities/espacio.dart';
import '../formato_espacios.dart';
import 'piezas_alta.dart';
import 'piezas_lista_ubicaciones.dart';

/// Las claves de «Dados de baja» al pie de la hoja del edificio (vista 11, #473).
abstract final class ClavesDadosDeBaja {
  static const cabecera = Key('ubicacion_hoja_bajas');
  static const error = Key('ubicacion_hoja_bajas_error');
  static const reintentar = Key('ubicacion_hoja_bajas_reintentar');

  /// La fila del depto dado de baja [id].
  static Key fila(String id) => Key('ubicacion_hoja_baja_fila_$id');

  /// El «Reactivar» del depto dado de baja [id].
  static Key reactivar(String id) => Key('ubicacion_hoja_baja_reactivar_$id');
}

/// La cabecera plegable de «Dados de baja» (con la cuenta). Se toca para desplegar o plegar la lista.
class CabeceraDadosDeBaja extends StatelessWidget {
  const CabeceraDadosDeBaja({
    super.key,
    required this.cantidad,
    required this.abierta,
    required this.alAlternar,
  });

  final int cantidad;
  final bool abierta;
  final VoidCallback alAlternar;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      expanded: abierta,
      label: TextosEspacios.dadosDeBajaSemantica(cantidad),
      excludeSemantics: true,
      onTap: alAlternar,
      child: Material(
        color: ColoresLista.filaBaja,
        child: InkWell(
          key: ClavesDadosDeBaja.cabecera,
          onTap: alAlternar,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: ColoresLista.grisBorde),
                  bottom: BorderSide(color: ColoresLista.grisBorde),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${TextosEspacios.dadosDeBaja} · $cantidad',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: ColoresLista.grisTexto,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    abierta ? '▴' : '▾',
                    style: const TextStyle(fontSize: 16, color: ColoresLista.grisTexto),
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

/// Un depto dado de baja con su «Reactivar». Con [reactivando] el botón dice «Reactivando…» y no se
/// toca: un doble toque no reactiva dos veces.
class FilaDeptoDeBaja extends StatelessWidget {
  const FilaDeptoDeBaja({
    super.key,
    required this.espacio,
    required this.reactivando,
    required this.alReactivar,
  });

  final Espacio espacio;
  final bool reactivando;

  /// `null`: el botón queda apagado (hay otra cosa en curso).
  final VoidCallback? alReactivar;

  @override
  Widget build(BuildContext context) {
    final sinNumero = espacio.sinNumero;
    final pisoEscrito = espacio.piso?.trim();
    final piso = pisoEscrito == null || pisoEscrito.isEmpty ? null : pisoEscrito;
    final etiqueta = reactivando ? TextosEspacios.reactivando : TextosEspacios.reactivar;
    final apagado = reactivando || alReactivar == null;
    final info = Semantics(
      container: true,
      label: [
        TextosEspacios.filaBajaSemantica(espacio),
        if (piso != null) '${TextosEspacios.pisoDeLaFila(piso)}.',
      ].join(' '),
      excludeSemantics: true,
      child: Row(
        children: [
          const InsigniaBaja(),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  TextosEspacios.depto(espacio),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: ColoresLista.grisTexto,
                    fontStyle: sinNumero ? FontStyle.italic : FontStyle.normal,
                  ),
                ),
                if (piso != null)
                  Text(
                    TextosEspacios.pisoDeLaFila(piso),
                    style: const TextStyle(fontSize: 12.5, color: ColoresAlta.gris),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    final boton = Semantics(
      container: true,
      button: true,
      enabled: !apagado,
      label: reactivando
          ? TextosEspacios.reactivandoSemantica(espacio)
          : TextosEspacios.reactivarSemantica(espacio),
      excludeSemantics: true,
      onTap: apagado ? null : alReactivar,
      child: OutlinedButton(
        key: ClavesDadosDeBaja.reactivar(espacio.id),
        onPressed: apagado ? null : alReactivar,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          foregroundColor: ColoresAlta.azul,
          side: const BorderSide(color: ColoresAlta.grisBorde, width: 1.5),
        ),
        child: Text(etiqueta, textAlign: TextAlign.center),
      ),
    );
    return Container(
      key: ClavesDadosDeBaja.fila(espacio.id),
      constraints: const BoxConstraints(minHeight: 64),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: ColoresLista.filaBaja,
        border: Border(bottom: BorderSide(color: ColoresLista.grisBorde)),
      ),
      // Con el texto grande el botón no entra al lado del depto: baja a su propio renglón.
      child: textoGrande(context)
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                info,
                const SizedBox(height: 8),
                Align(alignment: AlignmentDirectional.centerStart, child: boton),
              ],
            )
          : Row(
              children: [
                Expanded(child: info),
                const SizedBox(width: 8),
                boton,
              ],
            ),
    );
  }
}

/// Lo que se ve cuando no se pudo leer «Dados de baja»: el aviso y «Reintentar».
class ErrorDadosDeBaja extends StatelessWidget {
  const ErrorDadosDeBaja({super.key, required this.alReintentar});

  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) => Padding(
    key: ClavesDadosDeBaja.error,
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AvisoAlta(color: ColoresAlta.rojo, glyph: '!', texto: TextosEspacios.errorBajas),
        const SizedBox(height: 8),
        OutlinedButton(
          key: ClavesDadosDeBaja.reintentar,
          onPressed: alReintentar,
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: const Text(TextosEspacios.reintentar),
        ),
      ],
    ),
  );
}
