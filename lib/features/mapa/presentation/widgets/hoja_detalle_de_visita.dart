import 'package:flutter/material.dart';

import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../domain/entities/evento_de_la_casa.dart';
import '../textos_baja_persona.dart' show FormatoBajaPersona;
import '../textos_historial_de_la_casa.dart';
import 'piezas_alta.dart' show ColoresAlta;

/// Las claves con que los tests (y el QA) encuentran lo que dibuja el detalle de una visita.
abstract final class ClavesDetalleDeVisita {
  static const hoja = Key('detalle_visita_hoja');
  static const titulo = Key('detalle_visita_titulo');
  static const subtitulo = Key('detalle_visita_subtitulo');
  static const datos = Key('detalle_visita_datos');
  static const nota = Key('detalle_visita_nota');
  static const verLaVenta = Key('detalle_visita_ver_la_venta');
  static const cerrar = Key('detalle_visita_cerrar');
}

/// Lo que se eligió en el detalle de una visita.
enum AccionDelDetalle {
  /// «Ver la venta»: sigue a donde se ve la venta.
  verLaVenta,
}

/// Abre el detalle de una visita o de una venta (vista 39, C·04): su título con el día, con quién y
/// dónde, los datos de la venta (qué se vendió, total, pagado y saldo) o de la entrevista (cuánto
/// duró), la nota de la visita y «Cerrar». Devuelve la acción elegida, o `null` si se cerró.
///
/// [conVerLaVenta]: se ofrece «Ver la venta» solo si tiene a dónde llevar (HU-UBI-003).
Future<AccionDelDetalle?> mostrarHojaDetalleDeVisita(
  BuildContext context, {
  required EventoDeLaCasa evento,
  required String direccion,
  required DateTime ahora,
  bool conVerLaVenta = false,
}) => showModalBottomSheet<AccionDelDetalle>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaDetalleDeVisita(
    evento: evento,
    direccion: direccion,
    ahora: ahora,
    conVerLaVenta: conVerLaVenta && evento is VentaDeLaCasa,
  ),
);

/// El detalle de una visita o de una venta del historial de la casa. Ver [mostrarHojaDetalleDeVisita].
///
/// **local-only — PII**: el nombre y la nota viven solo en el teléfono y no van a ningún log.
class HojaDetalleDeVisita extends StatefulWidget {
  const HojaDetalleDeVisita({
    super.key,
    required this.evento,
    required this.direccion,
    required this.ahora,
    this.conVerLaVenta = false,
  });

  final EventoDeLaCasa evento;
  final String direccion;
  final DateTime ahora;
  final bool conVerLaVenta;

  @override
  State<HojaDetalleDeVisita> createState() => _HojaDetalleDeVisitaState();
}

class _HojaDetalleDeVisitaState extends State<HojaDetalleDeVisita> {
  /// Ya se eligió algo: un segundo toque no cierra la hoja dos veces.
  var _cerrada = false;

  void _cerrar([AccionDelDetalle? accion]) {
    if (_cerrada) return;
    _cerrada = true;
    Navigator.of(context).pop(accion);
  }

  List<_Dato> get _datos => switch (widget.evento) {
    VentaDeLaCasa(
      :final lineas,
      :final montoCentavos,
      :final pagadoCentavos,
      :final saldoCentavos,
    ) =>
      [
        for (final l in lineas) _Dato(l.nombre, l.cantidad > 1 ? '× ${l.cantidad}' : '× 1'),
        _Dato(TextosHistorialDeLaCasa.total, FormatoBajaPersona.monto(montoCentavos)),
        _Dato(TextosHistorialDeLaCasa.pagado, FormatoBajaPersona.monto(pagadoCentavos)),
        _Dato(TextosHistorialDeLaCasa.saldo, FormatoBajaPersona.monto(saldoCentavos), fuerte: true),
      ],
    CobroDeLaCasa(:final montoCentavos) => [
      _Dato(TextosHistorialDeLaCasa.cobros, FormatoBajaPersona.monto(montoCentavos)),
    ],
    VisitaDeLaCasa(:final resultado, :final duracion) => [
      if (resultado == TipoResultadoVisita.entrevista && duracion != null)
        _Dato(TextosHistorialDeLaCasa.duracion, FormatoHistorialDeLaCasa.duracionLarga(duracion)),
    ],
  };

  String? get _nota => switch (widget.evento) {
    VisitaDeLaCasa(:final nota) => nota,
    VentaDeLaCasa(:final nota) => nota,
    CobroDeLaCasa() => null,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titulo = FormatoHistorialDeLaCasa.tituloDelDetalle(widget.evento, widget.ahora);
    final subtitulo = FormatoHistorialDeLaCasa.subtituloDelDetalle(widget.evento, widget.direccion);
    final datos = _datos;
    final nota = _nota;
    return SingleChildScrollView(
      key: ClavesDetalleDeVisita.hoja,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 26),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              titulo,
              key: ClavesDetalleDeVisita.titulo,
              style: theme.textTheme.headlineSmall,
            ),
          ),
          if (subtitulo.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitulo,
              key: ClavesDetalleDeVisita.subtitulo,
              style: theme.textTheme.bodyMedium?.copyWith(color: ColoresAlta.gris, height: 1.4),
            ),
          ],
          if (datos.isNotEmpty) ...[
            const SizedBox(height: 14),
            Column(
              key: ClavesDetalleDeVisita.datos,
              children: [
                for (var i = 0; i < datos.length; i++) _FilaDeDato(dato: datos[i], conLinea: i > 0),
              ],
            ),
          ],
          if (nota != null) ...[const SizedBox(height: 14), _TarjetaDeNota(texto: nota)],
          const SizedBox(height: 18),
          if (widget.conVerLaVenta) ...[
            FilledButton(
              key: ClavesDetalleDeVisita.verLaVenta,
              onPressed: () => _cerrar(AccionDelDetalle.verLaVenta),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                shape: const StadiumBorder(),
                backgroundColor: const Color(0xFF002856),
                foregroundColor: Colors.white,
                textStyle: const TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              child: const Text(TextosHistorialDeLaCasa.verLaVenta),
            ),
            const SizedBox(height: 6),
          ],
          TextButton(
            key: ClavesDetalleDeVisita.cerrar,
            onPressed: _cerrar,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: ColoresAlta.azul,
              textStyle: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text(TextosHistorialDeLaCasa.cerrar),
          ),
        ],
      ),
    );
  }
}

class _Dato {
  const _Dato(this.clave, this.valor, {this.fuerte = false});

  final String clave;
  final String valor;
  final bool fuerte;
}

/// Una fila de «clave … valor» (canvas, `Bloques` · kv): la clave gris a la izquierda, el valor a la
/// derecha, con una línea fina arriba (más gruesa en la fila fuerte).
class _FilaDeDato extends StatelessWidget {
  const _FilaDeDato({required this.dato, required this.conLinea});

  final _Dato dato;
  final bool conLinea;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${dato.clave}: ${dato.valor}',
      child: Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          border: conLinea
              ? Border(
                  top: BorderSide(
                    color: dato.fuerte ? ColoresAlta.grisBorde : const Color(0xFFEEF0F3),
                    width: dato.fuerte ? 1.5 : 1,
                  ),
                )
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                dato.clave,
                style: const TextStyle(fontSize: 14, color: ColoresAlta.gris, height: 1.3),
              ),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                dato.valor,
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: dato.fuerte ? FontWeight.w600 : FontWeight.w500,
                  color: const Color(0xFF0E1A2B),
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «NOTA DE LA VISITA» con el texto entero (canvas: tarjeta con ✎ en un recuadro celeste).
class _TarjetaDeNota extends StatelessWidget {
  const _TarjetaDeNota({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${TextosHistorialDeLaCasa.notaDeLaVisita}. $texto',
      child: Container(
        key: ClavesDetalleDeVisita.nota,
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE3E7EE)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF2F6FB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('✎', style: TextStyle(fontSize: 12, color: ColoresAlta.azul)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    TextosHistorialDeLaCasa.notaDeLaVisita,
                    style: TextStyle(
                      fontFamily: 'JetBrainsMono',
                      fontSize: 10,
                      letterSpacing: 1.4,
                      color: ColoresAlta.gris,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    texto,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
