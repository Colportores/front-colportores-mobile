import 'package:flutter/material.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../formato_entrega_diferida.dart';

// Las piezas de la entrega diferida (vista 27, grupo C). Crecen con el texto (`textScaler` 2.0): nada
// tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);

TextStyle _estiloRotulo() => const TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10.5,
  letterSpacing: 1.6,
  color: ColoresAgenda.gris,
);

/// Una fila de «Qué entregás» de 27C·01: todo lo que se vendió va a esa fecha, así que no se tilda ni
/// se destilda. Lleva el ✓ del canvas como adorno; el lector dice qué es y para cuándo.
class FilaDeLoQueSeEntrega extends StatelessWidget {
  const FilaDeLoQueSeEntrega({super.key, required this.titulo, this.detalle});

  final String titulo;
  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: [titulo, ?detalle].join('. '),
      child: ExcludeSemantics(
        child: Container(
          key: const Key('otro_dia_fila'),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F6FB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: ColoresAgenda.navy, width: 2),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                    if (detalle != null)
                      Text(
                        detalle!,
                        style: const TextStyle(fontSize: 12, color: ColoresAgenda.gris),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ColoresAgenda.navy,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.check, size: 16, color: Colors.white),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El campo de fecha de 27C·01 («FECHA PREVISTA») y 27C·04 («NUEVA FECHA»): el valor o el texto de
/// ayuda, y «›». Al tocarlo se abre la hoja «Día y hora».
class CampoDeFechaDeEntrega extends StatelessWidget {
  const CampoDeFechaDeEntrega({
    super.key,
    required this.rotulo,
    required this.valor,
    required this.alTocar,
    this.conValor = true,
  });

  final String rotulo;

  /// La fecha elegida, o el texto de ayuda si todavía no hay ([conValor] `false`).
  final String valor;
  final bool conValor;
  final VoidCallback? alTocar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text(rotulo, style: _estiloRotulo())),
        const SizedBox(height: 6),
        Semantics(
          button: true,
          enabled: alTocar != null,
          label: TextosEntregaDiferida.lectorCampo(rotulo, valor),
          excludeSemantics: true,
          onTap: alTocar,
          child: Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: ColoresAgenda.bordeChip, width: 1.5),
            ),
            child: InkWell(
              key: const Key('entrega_campo_fecha'),
              onTap: alTocar,
              customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          valor,
                          style: TextStyle(
                            fontSize: 16,
                            color: conValor ? ColoresAgenda.tinta : ColoresAgenda.gris,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const ExcludeSemantics(
                        child: Text('›', style: TextStyle(fontSize: 22, color: ColoresAgenda.gris)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// El tono de una tarjeta de «Entregas pendientes».
enum TonoDeEntrega { atrasada, proxima, sinFecha }

/// Una tarjeta de 27C·02: el día, quién, dónde y qué. Tocarla abre «Marcar entregado»; la que no tiene
/// fecha lleva además «Poner fecha».
class TarjetaDeEntregaPendiente extends StatelessWidget {
  const TarjetaDeEntregaPendiente({
    super.key,
    required this.tono,
    required this.persona,
    required this.detalle,
    required this.alAbrir,
    this.dia,
    this.alPonerFecha,
  });

  final TonoDeEntrega tono;

  /// «LUN 21/10 · 16:30»; `null` en las que no tienen fecha.
  final String? dia;
  final String persona;
  final String detalle;
  final VoidCallback? alAbrir;
  final VoidCallback? alPonerFecha;

  @override
  Widget build(BuildContext context) {
    final atrasada = tono == TonoDeEntrega.atrasada;
    final etiqueta = [
      if (atrasada) 'Atrasada',
      ?dia,
      persona,
      detalle,
    ].where((t) => t.isNotEmpty).join('. ');
    // Con el texto muy grande «Poner fecha» no entra al lado: pasa debajo, alineado a la derecha.
    final apilado = alPonerFecha != null && MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final cuerpo = Semantics(
      // Su propio nodo: sin esto el rótulo del grupo («ATRASADAS») se fusiona con la tarjeta.
      container: true,
      button: true,
      label: etiqueta,
      onTap: alAbrir,
      child: ExcludeSemantics(
        child: InkWell(
          onTap: alAbrir,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: atrasada ? ColoresAgenda.rojo : ColoresAgenda.grisFondo,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    atrasada ? '!' : '⇢',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: atrasada ? Colors.white : ColoresAgenda.gris,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (dia != null)
                        Text(
                          dia!,
                          style: TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 11,
                            letterSpacing: 1,
                            color: atrasada ? ColoresAgenda.rojo : ColoresAgenda.gris,
                          ),
                        ),
                      Text(
                        persona,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        detalle,
                        style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
                      ),
                    ],
                  ),
                ),
                if (alPonerFecha == null)
                  const Text('›', style: TextStyle(fontSize: 22, color: ColoresAgenda.gris)),
              ],
            ),
          ),
        ),
      ),
    );
    final ponerFecha = alPonerFecha == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(right: 6),
            child: TextButton(
              key: const Key('entrega_poner_fecha'),
              onPressed: alPonerFecha,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: const Text(
                TextosEntregaDiferida.ponerFecha,
                style: TextStyle(fontWeight: FontWeight.w600, color: ColoresAgenda.azul),
              ),
            ),
          );
    return Container(
      constraints: const BoxConstraints(minHeight: 70),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: apilado
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cuerpo,
                Align(alignment: Alignment.centerRight, child: ponerFecha),
              ],
            )
          : Row(
              children: [
                Expanded(child: cuerpo),
                ?ponerFecha,
              ],
            ),
    );
  }
}

/// El esqueleto de 27C·06: un rótulo y dos tarjetas.
class EsqueletoDeEntregas extends StatelessWidget {
  const EsqueletoDeEntregas({super.key});

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
      label: TextosEntregaDiferida.cargandoPendientes,
      child: ExcludeSemantics(
        child: Padding(
          key: const Key('entregas_cargando'),
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
          child: Column(
            children: [
              bloque(20),
              const SizedBox(height: 10),
              bloque(70),
              const SizedBox(height: 10),
              bloque(70),
            ],
          ),
        ),
      ),
    );
  }
}
