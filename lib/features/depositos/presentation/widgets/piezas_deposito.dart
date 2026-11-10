import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../textos_deposito.dart';

// Las piezas de «Registrar depósito» (vista 33 D) y de la foto del ticket (vista 38 A). Todas crecen
// con el texto (`textScaler` 2.0): nada tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFCFD6E1);

/// La foto del ticket del depósito (38A): «+ Sacar foto del ticket» sin foto, la foto con «tocá para
/// cambiarla» cuando ya está, y «Preparando la foto…» mientras se achica. Con [error] el borde va en
/// rojo y dice qué pasó.
class FotoDelTicketDeDeposito extends StatelessWidget {
  const FotoDelTicketDeDeposito({
    super.key,
    required this.foto,
    required this.preparando,
    required this.alTocar,
    this.error,
    this.marcarFalta = false,
  });

  /// La foto ya achicada; `null` si todavía no hay.
  final Uint8List? foto;

  /// Se está achicando la foto recién sacada.
  final bool preparando;

  /// `null` = no responde (se está registrando o preparando la foto).
  final VoidCallback? alTocar;

  /// Lo que salió mal con la última foto (permiso, foto ilegible).
  final String? error;

  /// Falta la foto para poder registrar (38A-04): el borde va en rojo.
  final bool marcarFalta;

  @override
  Widget build(BuildContext context) {
    final conFoto = foto != null;
    final rojo = error != null || (marcarFalta && !conFoto);
    final Widget contenido;
    if (preparando) {
      contenido = const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: ColoresAgenda.azul),
          ),
          SizedBox(width: 10),
          Flexible(child: Text(TextosDeposito.preparandoFoto, style: TextStyle(fontSize: 14))),
        ],
      );
    } else if (conFoto) {
      contenido = Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.memory(
              foto!,
              key: const Key('deposito_foto_miniatura'),
              width: 72,
              height: 72,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              excludeFromSemantics: true,
              errorBuilder: (_, _, _) => Container(
                width: 72,
                height: 72,
                color: ColoresAgenda.grisFondo,
                alignment: Alignment.center,
                child: const Icon(Icons.receipt_long, color: ColoresAgenda.gris),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              TextosDeposito.fotoCargada,
              style: TextStyle(fontSize: 14, color: ColoresAgenda.tinta),
            ),
          ),
        ],
      );
    } else {
      contenido = const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_a_photo_outlined, color: ColoresAgenda.azul),
          SizedBox(width: 10),
          Flexible(
            child: Text(
              TextosDeposito.sacarFotoDelTicket,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: ColoresAgenda.azul,
              ),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          enabled: alTocar != null,
          label: preparando
              ? TextosDeposito.preparandoFoto
              : conFoto
              ? TextosDeposito.fotoCargadaEtiqueta
              : TextosDeposito.sacarFotoDelTicket,
          excludeSemantics: true,
          onTap: alTocar,
          child: InkWell(
            key: const Key('deposito_foto'),
            onTap: alTocar,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              constraints: const BoxConstraints(minHeight: 96),
              padding: const EdgeInsets.all(12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: rojo ? ColoresAgenda.rojo : _borde, width: 1.5),
              ),
              child: contenido,
            ),
          ),
        ),
        if (error != null)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                key: const Key('deposito_foto_error'),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ColoresAgenda.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// De dónde sale la foto del ticket.
enum OrigenDeLaFoto { camara, galeria }

/// La hoja «Sacar foto» / «Elegir de la galería». Devuelve el origen elegido, o `null` si se cierra.
Future<OrigenDeLaFoto?> mostrarHojaOrigenDeLaFoto(BuildContext context) =>
    showModalBottomSheet<OrigenDeLaFoto>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  TextosDeposito.deDondeLaFoto,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              const SizedBox(height: 12),
              _OpcionDeOrigen(
                clave: const Key('deposito_foto_camara'),
                icono: Icons.photo_camera_outlined,
                texto: TextosDeposito.sacarFoto,
                alTocar: () => Navigator.of(context).pop(OrigenDeLaFoto.camara),
              ),
              _OpcionDeOrigen(
                clave: const Key('deposito_foto_galeria'),
                icono: Icons.photo_library_outlined,
                texto: TextosDeposito.elegirDeLaGaleria,
                alTocar: () => Navigator.of(context).pop(OrigenDeLaFoto.galeria),
              ),
            ],
          ),
        ),
      ),
    );

class _OpcionDeOrigen extends StatelessWidget {
  const _OpcionDeOrigen({
    required this.clave,
    required this.icono,
    required this.texto,
    required this.alTocar,
  });

  final Key clave;
  final IconData icono;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: clave,
      onTap: alTocar,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              Icon(icono, color: ColoresAgenda.azul),
              const SizedBox(width: 14),
              Expanded(child: Text(texto, style: const TextStyle(fontSize: 16))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Una fila de 33D-04: «En mano   $ 2.400 → $ 600». Con el texto grande, el monto pasa abajo.
class FilaAntesYDespues extends StatelessWidget {
  const FilaAntesYDespues({
    super.key,
    required this.rotulo,
    required this.antes,
    required this.despues,
  });

  final String rotulo;
  final int antes;
  final int despues;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: TextosDeposito.antesYDespuesEtiqueta(rotulo, antes, despues),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 2,
          children: [
            Text(rotulo, style: const TextStyle(fontSize: 14, color: ColoresAgenda.gris)),
            Text(
              TextosDeposito.antesYDespues(antes, despues),
              style: const TextStyle(
                fontFamily: 'JetBrainsMono',
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: ColoresAgenda.tinta,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// El recuadro de las filas de 33D-04.
class CuadroAntesYDespues extends StatelessWidget {
  const CuadroAntesYDespues({super.key, required this.filas});

  final List<Widget> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('deposito_antes_y_despues'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE3E7EE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < filas.length; i++) ...[
            if (i > 0) const Divider(height: 1, color: Color(0xFFE3E7EE)),
            filas[i],
          ],
        ],
      ),
    );
  }
}

/// Una línea de ayuda gris bajo un control («El retiro no lleva foto…»).
class AyudaDeDeposito extends StatelessWidget {
  const AyudaDeDeposito({super.key, required this.texto, this.error = false});

  final String texto;

  /// En rojo: algo impide registrar (sin campaña para el alquiler, sin cámara).
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: error,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          texto,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.35,
            color: error ? ColoresAgenda.rojo : ColoresAgenda.gris,
            fontWeight: error ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
