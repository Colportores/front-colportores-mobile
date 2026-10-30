import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../textos_ticket.dart';

// Las piezas de la vista 29 C (foto del ticket de tarjeta). Todas crecen con el texto (`textScaler`
// 2.0): nada tiene alto fijo salvo el mínimo táctil de 48 y el marco de la foto.

const _borde = Color(0xFFE3E7EE);

/// El marco donde se encuadra el ticket (29C-01): oscuro, con borde blanco y la indicación.
class MarcoDeEncuadre extends StatelessWidget {
  const MarcoDeEncuadre({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: TextosTicket.encuadra,
      child: ExcludeSemantics(
        child: Container(
          key: const Key('ticket_marco'),
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 360),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1B2430),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.crop_landscape, size: 48, color: Colors.white70),
              SizedBox(height: 12),
              Text(
                TextosTicket.encuadra,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La foto del ticket (29C-02, 03 y 06) tal como se va a subir, a tamaño real. Si los bytes no se
/// pueden dibujar, el marco queda con el rótulo en vez de romper la pantalla.
class FotoDelTicket extends StatelessWidget {
  const FotoDelTicket({super.key, required this.bytes, this.alto = 360, this.alTocar});

  final Uint8List bytes;
  final double alto;

  /// «Tocá para cambiarla» (paso de datos); `null` = no responde.
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    final foto = Container(
      key: const Key('ticket_foto'),
      height: alto,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ColoresAgenda.bordeChip, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.memory(
        bytes,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(TextosTicket.vistaPrevia, textAlign: TextAlign.center),
          ),
        ),
      ),
    );
    return Semantics(
      image: true,
      button: alTocar != null,
      label: alTocar == null ? TextosTicket.vistaPrevia : TextosTicket.fotoDelTicket,
      onTap: alTocar,
      excludeSemantics: true,
      child: alTocar == null
          ? foto
          : InkWell(
              key: const Key('ticket_foto_cambiar'),
              borderRadius: BorderRadius.circular(16),
              onTap: alTocar,
              child: foto,
            ),
    );
  }
}

/// El círculo con el símbolo y el mensaje grande de una pantalla de resultado (29C-04).
class MensajeDeResultado extends StatelessWidget {
  const MensajeDeResultado({super.key, required this.titulo, this.texto});

  final String titulo;
  final String? texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: Color(0xFFDDE8D3), shape: BoxShape.circle),
            child: const ExcludeSemantics(
              child: Icon(Icons.check, size: 32, color: Color(0xFF1F6E3A)),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            liveRegion: true,
            child: Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
          if (texto != null) ...[
            const SizedBox(height: 6),
            Text(
              texto!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13.5, color: ColoresAgenda.gris, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}

/// Una tarjeta de la pantalla de resultado: la copia en el teléfono (29C-04, con «Borrar») o el
/// ticket que espera en la cola (29C-05, con su etiqueta «En cola»).
class TarjetaDeTicket extends StatelessWidget {
  const TarjetaDeTicket({
    super.key,
    required this.titulo,
    required this.detalle,
    this.etiqueta,
    this.accion,
    this.alAccion,
  });

  final String titulo;
  final String detalle;

  /// La etiqueta de estado a la derecha («En cola»).
  final String? etiqueta;

  /// El texto de la acción a la derecha («Borrar»); sin [alAccion] no responde.
  final String? accion;
  final VoidCallback? alAccion;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde, width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: ColoresAgenda.grisFondo,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const ExcludeSemantics(child: Icon(Icons.receipt_long, size: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                Text(detalle, style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris)),
              ],
            ),
          ),
          if (etiqueta != null)
            Container(
              margin: const EdgeInsets.only(left: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: ColoresAgenda.ambarFondo,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                etiqueta!,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: ColoresAgenda.ambarTinta,
                ),
              ),
            ),
          if (accion != null)
            TextButton(
              key: const Key('ticket_borrar_copia'),
              onPressed: alAccion,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(
                accion!,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: alAccion == null ? ColoresAgenda.gris : ColoresAgenda.rojo,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Un botón de texto de 48 de alto («Sacar otra», «Después», «Elegir de la galería»).
class BotonSecundarioDeTicket extends StatelessWidget {
  const BotonSecundarioDeTicket({super.key, required this.texto, required this.alPresionar});

  final String texto;

  /// `null` = no responde (hay algo en curso).
  final VoidCallback? alPresionar;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: alPresionar,
      style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      child: Text(
        texto,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: alPresionar == null ? ColoresAgenda.gris : ColoresAgenda.azul,
        ),
      ),
    );
  }
}

const _formaHoja = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
);

/// La hoja «¿Borrar la copia de este teléfono?» (29C-08). Devuelve `true` con «Borrar copia»; `false`
/// o `null` (cerrada) no borra nada.
Future<bool?> mostrarHojaBorrarCopia(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (_) => const HojaBorrarCopia(),
);

class HojaBorrarCopia extends StatefulWidget {
  const HojaBorrarCopia({super.key});

  @override
  State<HojaBorrarCopia> createState() => _HojaBorrarCopiaState();
}

class _HojaBorrarCopiaState extends State<HojaBorrarCopia> {
  var _respondio = false;

  void _responder(bool borrar) {
    // Un doble toque no cierra dos veces ni devuelve dos respuestas.
    if (_respondio) return;
    _respondio = true;
    Navigator.of(context).pop(borrar);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text(
                TextosTicket.borrarCopiaTitulo,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              TextosTicket.borrarCopiaTexto,
              style: TextStyle(fontSize: 14, color: ColoresAgenda.gris, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('ticket_confirmar_borrar'),
              onPressed: () => _responder(true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.rojo,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosTicket.borrarCopia,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            TextButton(
              key: const Key('ticket_cancelar_borrar'),
              onPressed: () => _responder(false),
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(
                TextosTicket.cancelar,
                style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La pantalla mientras se achica la foto o se lee el ticket guardado.
class CargandoDelTicket extends StatelessWidget {
  const CargandoDelTicket({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: texto,
      child: ExcludeSemantics(
        child: Padding(
          key: const Key('ticket_cargando'),
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Column(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(texto, style: const TextStyle(color: ColoresAgenda.gris)),
            ],
          ),
        ),
      ),
    );
  }
}
