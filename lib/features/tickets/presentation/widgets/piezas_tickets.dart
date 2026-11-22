import 'package:flutter/material.dart';

import '../../../catalogo/presentation/formato_precios.dart' show FormatoPrecios;
import '../../../cuenta/presentation/widgets/piezas_cuenta.dart' show ColoresCuenta;
import '../../../ventas/presentation/widgets/piezas_venta.dart' show ChipDeVenta;
import '../../domain/entities/item_del_historial.dart';
import '../../domain/services/visor_de_fotos.dart';
import '../textos_tickets.dart';

// Las piezas de «Mis tickets» (vista 38B). Todas crecen con el texto (`textScaler` 2.0): nada tiene
// alto fijo salvo el mínimo táctil de 48.

/// Cómo se ve cada estado: glifo, fondo y tinta (38B·01).
({String glifo, Color fondo, Color tinta}) _aspecto(EstadoDelItem estado) => switch (estado) {
  EstadoDelItem.porValidar => (
    glifo: '◷',
    fondo: ColoresCuenta.ambarFondo,
    tinta: ColoresCuenta.ambarTinta,
  ),
  EstadoDelItem.validado => (
    glifo: '✓',
    fondo: ColoresCuenta.verdeFondo,
    tinta: ColoresCuenta.verde,
  ),
  EstadoDelItem.rechazado => (
    glifo: '!',
    fondo: const Color(0xFFFBEDEC),
    tinta: ColoresCuenta.rojo,
  ),
  EstadoDelItem.enCola => (glifo: '⇡', fondo: ColoresCuenta.grisFondo, tinta: ColoresCuenta.gris),
};

/// Los filtros de 38B·01: «Todos», «Por validar», «Rechazados» y «Alquiler».
class FiltrosDeTickets extends StatelessWidget {
  const FiltrosDeTickets({super.key, required this.elegido, required this.alElegir});

  final FiltroDeTickets elegido;
  final ValueChanged<FiltroDeTickets> alElegir;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: TextosTickets.filtrosEtiqueta,
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in FiltroDeTickets.values)
            KeyedSubtree(
              key: Key('tickets_filtro_${f.name}'),
              child: ChipDeVenta(
                texto: TextosTickets.filtro(f),
                elegido: f == elegido,
                alPresionar: () => alElegir(f),
              ),
            ),
        ],
      ),
    );
  }
}

/// Una fila de «Mis tickets» (38B·01): el glifo del estado, «HOY · BANCO», el monto, el detalle, la
/// etiqueta del estado y «›». Se toca y abre el detalle.
class TarjetaDeTicket extends StatelessWidget {
  const TarjetaDeTicket({super.key, required this.item, required this.hoy, required this.alAbrir});

  final ItemDelHistorial item;

  /// El instante de ahora: decide si la fecha dice «HOY».
  final DateTime hoy;
  final VoidCallback alAbrir;

  @override
  Widget build(BuildContext context) {
    final aspecto = _aspecto(item.estado);
    final subtitulo = TextosTickets.subtitulo(item);
    return Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      onTap: alAbrir,
      label: TextosTickets.hablada(item, hoy),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: ColoresCuenta.borde),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: alAbrir,
          child: Container(
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: aspecto.fondo,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    aspecto.glifo,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: aspecto.tinta,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        TextosTickets.lineaDeArriba(item, hoy),
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 10,
                          letterSpacing: 1.4,
                          color: ColoresCuenta.gris,
                        ),
                      ),
                      Text(
                        FormatoPrecios.monto(item.montoCentavos),
                        style: const TextStyle(
                          fontFamily: 'JetBrainsMono',
                          fontSize: 20,
                          fontWeight: FontWeight.w500,
                          color: ColoresCuenta.tinta,
                        ),
                      ),
                      if (subtitulo.isNotEmpty)
                        Text(
                          subtitulo,
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12.5,
                            height: 1.35,
                            color: ColoresCuenta.gris,
                          ),
                        ),
                      const SizedBox(height: 6),
                      EtiquetaDeEstado(estado: item.estado),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '›',
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(fontSize: 22, color: ColoresCuenta.gris),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Por validar», «Validado», «Rechazado» o «En cola», con el color del estado.
class EtiquetaDeEstado extends StatelessWidget {
  const EtiquetaDeEstado({super.key, required this.estado});

  final EstadoDelItem estado;

  @override
  Widget build(BuildContext context) {
    final aspecto = _aspecto(estado);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(color: aspecto.fondo, borderRadius: BorderRadius.circular(999)),
      child: Text(
        TextosTickets.estado(estado),
        style: TextStyle(
          fontFamily: 'Inter',
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: aspecto.tinta,
        ),
      ),
    );
  }
}

/// Un aviso del detalle: de error (rojo), de éxito (verde), de información (azul) o de sin conexión
/// (gris). El ícono lo repite en texto (`!`, `✓`, `i`, `✕`): no depende solo del color.
enum TipoDeAviso { error, ok, info, sinConexion }

class AvisoDeTicket extends StatelessWidget {
  const AvisoDeTicket({super.key, required this.texto, required this.tipo});

  final String texto;
  final TipoDeAviso tipo;

  @override
  Widget build(BuildContext context) {
    final (color, glifo) = switch (tipo) {
      TipoDeAviso.error => (ColoresCuenta.rojo, '!'),
      TipoDeAviso.ok => (ColoresCuenta.verde, '✓'),
      TipoDeAviso.info => (ColoresCuenta.azul, 'i'),
      TipoDeAviso.sinConexion => (ColoresCuenta.gris, '✕'),
    };
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ExcludeSemantics(
              child: Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Text(
                  glifo,
                  textScaler: TextScaler.noScaling,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                texto,
                style: const TextStyle(fontFamily: 'Inter', fontSize: 13.5, height: 1.45),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La carga (38B·05): una fila de filtros y dos tarjetas en gris.
class EsqueletoDeTickets extends StatelessWidget {
  const EsqueletoDeTickets({super.key});

  @override
  Widget build(BuildContext context) {
    Widget bloque(double alto) => Container(
      height: alto,
      decoration: BoxDecoration(
        color: ColoresCuenta.esqueleto,
        borderRadius: BorderRadius.circular(14),
      ),
    );
    return Semantics(
      liveRegion: true,
      label: TextosTickets.cargando,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('tickets_cargando'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            bloque(40),
            const SizedBox(height: 8),
            bloque(76),
            const SizedBox(height: 8),
            bloque(76),
          ],
        ),
      ),
    );
  }
}

/// El vacío (38B·04): un glifo, el título y lo que hay que hacer.
class VacioDeTickets extends StatelessWidget {
  const VacioDeTickets({super.key, required this.titulo, this.texto});

  final String titulo;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 12),
      child: Column(
        children: [
          ExcludeSemantics(
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ColoresCuenta.grisFondo,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                '▤',
                textScaler: TextScaler.noScaling,
                style: TextStyle(fontSize: 20, color: ColoresCuenta.gris),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            titulo,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: ColoresCuenta.tinta,
            ),
          ),
          if (texto != null) ...[
            const SizedBox(height: 6),
            Text(
              texto!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 13.5,
                height: 1.45,
                color: ColoresCuenta.gris,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Una fila «Fecha → 20/10» del detalle (38B·02, 38B·03).
class FilaDeDatoDelTicket extends StatelessWidget {
  const FilaDeDatoDelTicket({super.key, required this.rotulo, required this.valor});

  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$rotulo: $valor',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(rotulo, style: const TextStyle(fontSize: 14, color: ColoresCuenta.gris)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                valor,
                textAlign: TextAlign.end,
                style: const TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: ColoresCuenta.tinta,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La foto del ticket en el detalle: la copia del teléfono, la de la nube, o lo que pasa si no hay
/// (cargando, vencida, sin red, todavía sin enviar). [alReintentar] vuelve a pedirla.
class FotoDelDetalle extends StatelessWidget {
  const FotoDelDetalle({
    super.key,
    required this.foto,
    required this.alReintentar,
    this.rechazada = false,
  });

  /// `null` mientras se busca.
  final FotoParaVer? foto;
  final VoidCallback alReintentar;

  /// El servidor rechazó la foto para siempre: no queda nada que mostrar ni que reintentar.
  final bool rechazada;

  @override
  Widget build(BuildContext context) {
    final f = foto;
    final Widget cuerpo;
    switch (f) {
      case null:
        cuerpo = const _CuadroDeFoto(
          clave: Key('ticket_foto_cargando'),
          semantica: TextosTickets.cargandoLaFoto,
          hijo: Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
        );
      case FotoEnElTelefono(:final bytes):
        cuerpo = _CuadroDeFoto(
          clave: const Key('ticket_foto'),
          semantica: TextosTickets.foto,
          hijo: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            // Una copia dañada no tumba el detalle: se dice y se puede volver a pedir.
            errorBuilder: (_, _, _) => _Nota(
              clave: const Key('ticket_foto_error'),
              texto: TextosTickets.fotoNoDisponible,
              alReintentar: alReintentar,
            ),
          ),
        );
      case FotoEnLaNube(:final url):
        cuerpo = _CuadroDeFoto(
          clave: const Key('ticket_foto'),
          semantica: TextosTickets.foto,
          hijo: Image.network(
            url.toString(),
            fit: BoxFit.contain,
            loadingBuilder: (_, hijo, progreso) => progreso == null
                ? hijo
                : const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
            errorBuilder: (_, _, _) => _Nota(
              clave: const Key('ticket_foto_error'),
              texto: TextosTickets.fotoNoDisponible,
              alReintentar: alReintentar,
            ),
          ),
        );
      case FotoVencida():
        cuerpo = const _Nota(clave: Key('ticket_foto_vencida'), texto: TextosTickets.fotoVencida);
      case SinFotoParaVer():
        cuerpo = _Nota(
          clave: const Key('ticket_foto_sin_enviar'),
          texto: rechazada ? TextosTickets.fotoRechazada : TextosTickets.fotoSinEnviar,
        );
      case FotoNoDisponible(:final sinRed):
        cuerpo = _Nota(
          clave: const Key('ticket_foto_error'),
          texto: sinRed ? TextosTickets.fotoSinRed : TextosTickets.fotoNoDisponible,
          alReintentar: alReintentar,
        );
    }
    return cuerpo;
  }
}

/// El marco de la foto: alto 200 (crece con el texto solo en las notas, no acá).
class _CuadroDeFoto extends StatelessWidget {
  const _CuadroDeFoto({required this.clave, required this.semantica, required this.hijo});

  final Key clave;
  final String semantica;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      image: true,
      label: semantica,
      child: Container(
        key: clave,
        height: 200,
        width: double.infinity,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresCuenta.borde, width: 1.5),
        ),
        child: hijo,
      ),
    );
  }
}

/// Lo que se dice en lugar de la foto, con «Reintentar» si volver a pedirla puede servir.
class _Nota extends StatelessWidget {
  const _Nota({required this.clave, required this.texto, this.alReintentar});

  final Key clave;
  final String texto;
  final VoidCallback? alReintentar;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: clave,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
      decoration: BoxDecoration(
        color: ColoresCuenta.grisFondo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            texto,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 13.5,
              height: 1.45,
              color: ColoresCuenta.tinta,
            ),
          ),
          if (alReintentar != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                key: const Key('ticket_foto_reintentar'),
                onPressed: alReintentar,
                style: TextButton.styleFrom(
                  foregroundColor: ColoresCuenta.azul,
                  minimumSize: const Size(48, 48),
                ),
                child: const Text(
                  TextosTickets.reintentar,
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            )
          else
            const SizedBox(height: 6),
        ],
      ),
    );
  }
}
