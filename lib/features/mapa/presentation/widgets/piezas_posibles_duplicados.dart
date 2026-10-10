import 'package:flutter/material.dart';

import '../../domain/entities/estado_casa.dart';
import '../../domain/entities/ubicacion.dart';
import '../formato_lista_ubicaciones.dart';
import '../formato_ubicaciones.dart';
import 'piezas_lista_ubicaciones.dart';
import 'textos_posibles_duplicados.dart';

/// La letra de la ubicación en el par: un cuadrado oscuro con «A» o «B» (canvas 10·01).
class LetraPar extends StatelessWidget {
  const LetraPar(this.letra, {super.key});

  final String letra;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ColoresLista.tinta,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          letra,
          // El cuadrado no crece con el texto: la letra se lee igual con la fuente grande.
          textScaler: TextScaler.noScaling,
          style: const TextStyle(
            fontFamily: 'JetBrainsMono',
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Colors.white,
            height: 1,
          ),
        ),
      ),
    );
  }
}

/// El gris del texto secundario de la fila («Casa · 2 espacios»): el `#5B6B82` del canvas 10·02, que
/// llega a 4,6:1 también sobre el azul claro de la opción elegida (`ColoresLista.grisEstado`, que
/// usa la Lista, da 3,9:1 ahí). Es solo de esta vista: el token compartido no se toca.
const _grisSecundario = Color(0xFF5B6B82);

/// Una ubicación del par: su letra, el estado de la casa si se sabe, la dirección y «Casa · 2
/// espacios» (canvas 10·01 y 10·02). Para el lector de pantalla es un solo renglón.
class FilaUbicacionPar extends StatelessWidget {
  const FilaUbicacionPar({
    super.key,
    required this.letra,
    required this.ubicacion,
    required this.espacios,
    this.estado,
    this.etiqueta,
  });

  final String letra;
  final Ubicacion ubicacion;
  final int espacios;

  /// El estado de la casa; `null` = no se sabe (todavía no hay `house_status` en el teléfono) y no
  /// se dibuja nada en su lugar.
  final EstadoCasa? estado;

  /// Lo que dice el lector de pantalla antes de la dirección (por ejemplo, «Ubicación A, la que se
  /// conserva»). Sin esto dice la letra.
  final String? etiqueta;

  /// Lo que dice el lector de pantalla de esta fila, de corrido: «Ubicación A, la que se conserva:
  /// Av. Italia 1234, Casa · 2 espacios, Entrevista agendada». Lo usan también las opciones tocables
  /// de la hoja, que llevan la etiqueta en el nodo que se toca.
  static String descripcion({
    required String letra,
    required Ubicacion ubicacion,
    required int espacios,
    EstadoCasa? estado,
    String? etiqueta,
  }) {
    final direccion = FormatoUbicaciones.direccion(ubicacion);
    final resumen = TextosPosiblesDuplicados.resumen(ubicacion, espacios);
    final estadoDicho = estado == null ? '' : ', ${FormatoListaUbicaciones.estado(estado)}';
    return '${etiqueta ?? 'Ubicación $letra'}: $direccion, $resumen$estadoDicho';
  }

  @override
  Widget build(BuildContext context) {
    final direccion = FormatoUbicaciones.direccion(ubicacion);
    final resumen = TextosPosiblesDuplicados.resumen(ubicacion, espacios);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: descripcion(
        letra: letra,
        ubicacion: ubicacion,
        espacios: espacios,
        estado: estado,
        etiqueta: etiqueta,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          LetraPar(letra),
          const SizedBox(width: 10),
          if (estado != null) ...[
            InsigniaEstadoCasa(estado: estado!, tamano: 22),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  direccion,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  resumen,
                  style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 12.5,
                    color: _grisSecundario,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// La pastilla del motivo del par («Misma calle y número») y la distancia («a 12 m»).
class EncabezadoMotivoPar extends StatelessWidget {
  const EncabezadoMotivoPar({super.key, required this.motivo, required this.distancia});

  final String motivo;
  final String distancia;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 8,
      runSpacing: 4,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF1DA),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            motivo,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6E5212),
            ),
          ),
        ),
        Text(distancia, style: const TextStyle(fontFamily: 'JetBrainsMono', fontSize: 12.5)),
      ],
    );
  }
}
