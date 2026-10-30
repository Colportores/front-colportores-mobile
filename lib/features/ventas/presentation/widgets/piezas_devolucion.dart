import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../domain/entities/devolucion.dart';
import '../textos_devolucion.dart';
import 'piezas_venta.dart';

// Las piezas de la vista 31 (Devolución). Todas crecen con el texto (`textScaler` 2.0): nada tiene
// alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);
const _verdeFondo = Color(0xFFDDE8D3);
const _verdeTinta = Color(0xFF1F6E3A);

/// Una fila de [TarjetaDeDatos]: lo que se cuenta y su valor.
class DatoDeDevolucion {
  const DatoDeDevolucion(this.rotulo, this.valor, {this.fuerte = false, this.alerta = false});

  final String rotulo;
  final String valor;

  /// El dato que importa de la tarjeta (el saldo, lo que pagó de más): va en negrita.
  final bool fuerte;

  /// Va en rojo: lo que la colportora le debe al cliente.
  final bool alerta;
}

/// La tarjeta de cuentas del canvas (`kv`): «Se queda con», «Ya pagó», «Pagó de más»…
class TarjetaDeDatos extends StatelessWidget {
  const TarjetaDeDatos({super.key, required this.datos});

  final List<DatoDeDevolucion> datos;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        children: [
          for (final dato in datos)
            Semantics(
              container: true,
              label: '${dato.rotulo}: ${dato.valor.replaceAll('\n', ', ')}',
              child: ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          dato.rotulo,
                          style: TextStyle(
                            fontSize: 14,
                            color: dato.fuerte ? ColoresAgenda.tinta : ColoresAgenda.gris,
                            fontWeight: dato.fuerte ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          dato.valor,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: dato.fuerte ? 16 : 14,
                            fontWeight: dato.fuerte || dato.alerta
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: dato.alerta ? ColoresAgenda.rojo : ColoresAgenda.tinta,
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

/// «¿QUÉ HACÉS CON $ 1.900?» y las tres salidas (31-02 a 31-04). Primero va «Lo retengo», la que no
/// devuelve plata, y viene elegida; «Se lo devuelvo ahora» y «Se lo devuelvo después» quedan a mano
/// debajo (decisión de Cristian, 23/10, «Debo cliente»: la devolución de plata es opcional y no se
/// propone primero).
class OpcionesDeLaDiferencia extends StatelessWidget {
  const OpcionesDeLaDiferencia({
    super.key,
    required this.rotulo,
    required this.elegida,
    required this.alElegir,
  });

  final String rotulo;
  final QueHacerConLaDiferencia? elegida;
  final ValueChanged<QueHacerConLaDiferencia>? alElegir;

  /// El orden en pantalla: la salida que no devuelve plata va primera.
  static const _orden = [
    QueHacerConLaDiferencia.retener,
    QueHacerConLaDiferencia.devolverAhora,
    QueHacerConLaDiferencia.devolverDespues,
  ];

  static const _textos = {
    QueHacerConLaDiferencia.devolverAhora: (TextosDevolucion.ahora, TextosDevolucion.ahoraSub),
    QueHacerConLaDiferencia.retener: (TextosDevolucion.retengo, TextosDevolucion.retengoSub),
    QueHacerConLaDiferencia.devolverDespues: (
      TextosDevolucion.despues,
      TextosDevolucion.despuesSub,
    ),
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const Key('devolucion_opciones'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RotuloDeSeccion(rotulo),
        const SizedBox(height: 8),
        for (final opcion in _orden) ...[
          FilaElegible(
            key: Key('devolucion_opcion_${opcion.name}'),
            titulo: _textos[opcion]!.$1,
            detalle: _textos[opcion]!.$2,
            elegida: elegida == opcion,
            alPresionar: () => alElegir?.call(opcion),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// El aviso verde de lo que quedó hecho (31-05).
class AvisoDeDevolucionHecha extends StatelessWidget {
  const AvisoDeDevolucionHecha({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('devolucion_aviso_ok'),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: _verdeFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _verdeTinta, width: 1.5),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 13.5, height: 1.35, color: _verdeTinta),
        ),
      ),
    );
  }
}

/// Las filas grises mientras se lee la venta.
class EsqueletoDeDevolucion extends StatelessWidget {
  const EsqueletoDeDevolucion({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: ColoresAgenda.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosDevolucion.cargandoLaVenta,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('devolucion_cargando'),
          children: [
            bloque(64),
            const SizedBox(height: 10),
            bloque(64),
            const SizedBox(height: 10),
            bloque(56),
          ],
        ),
      ),
    );
  }
}

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// La hoja «¿Registrar la devolución?» (31-04): lo que se va a registrar y los dos botones. Devuelve
/// `true` al tocar «Registrar devolución» y `false` o `null` si se la cierra o se toca «Volver».
Future<bool?> mostrarHojaConfirmarDevolucion(
  BuildContext context, {
  required List<DatoDeDevolucion> datos,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (_) => HojaConfirmarDevolucion(datos: datos),
);

class HojaConfirmarDevolucion extends StatefulWidget {
  const HojaConfirmarDevolucion({super.key, required this.datos});

  final List<DatoDeDevolucion> datos;

  @override
  State<HojaConfirmarDevolucion> createState() => _HojaConfirmarDevolucionState();
}

class _HojaConfirmarDevolucionState extends State<HojaConfirmarDevolucion> {
  /// La hoja ya se está cerrando: un segundo toque no vuelve a hacer `pop`.
  var _cerrando = false;

  void _cerrar(bool registrar) {
    if (_cerrando) return;
    _cerrando = true;
    Navigator.of(context).pop(registrar);
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        key: const Key('devolucion_hoja'),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: const Text(
                TextosDevolucion.hojaTitulo,
                style: TextStyle(
                  fontFamily: 'SourceSerif4',
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            TarjetaDeDatos(datos: widget.datos),
            const SizedBox(height: 12),
            const Text(
              TextosDevolucion.laVentaNoSeBorra,
              style: TextStyle(fontSize: 13.5, height: 1.4, color: ColoresAgenda.gris),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('devolucion_hoja_registrar'),
              onPressed: () => _cerrar(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosDevolucion.registrarDevolucion,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const Key('devolucion_hoja_volver'),
              onPressed: () => _cerrar(false),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(
                TextosDevolucion.volver,
                style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
