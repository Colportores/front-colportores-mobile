import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../ventas/domain/services/reglas_de_venta.dart';
import '../../domain/entities/cuota.dart';
import '../textos_cuotas.dart';

const _borde = Color(0xFFCFD6E1);
const _verde = Color(0xFF1F6E3A);

const _estiloRotulo = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10.5,
  letterSpacing: 1.6,
  color: ColoresAgenda.gris,
);

/// El rótulo de una sección («CUOTAS · TOCÁ UN MONTO PARA CAMBIARLO»).
class RotuloDeCuotas extends StatelessWidget {
  const RotuloDeCuotas(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Semantics(header: true, child: Text(texto, style: _estiloRotulo)),
  );
}

/// «Cantidad de cuotas · De 2 a 12» con un contador: menos, el número y más (30A-01). Los botones se
/// apagan en los extremos y cada uno mide 48 dp.
class ContadorDeCuotas extends StatelessWidget {
  const ContadorDeCuotas({
    super.key,
    required this.cantidad,
    required this.minimo,
    required this.maximo,
    required this.alCambiar,
    this.habilitado = true,
  });

  final int cantidad;
  final int minimo;
  final int maximo;
  final ValueChanged<int> alCambiar;

  /// `false` mientras se crea el plan: no responde.
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('cuotas_contador'),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borde, width: 1.5),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextosCuotas.cantidad,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                Text(
                  TextosCuotas.cantidadAyuda,
                  style: TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
                ),
              ],
            ),
          ),
          IconButton(
            key: const Key('cuotas_menos'),
            tooltip: 'Una cuota menos',
            onPressed: habilitado && cantidad > minimo ? () => alCambiar(cantidad - 1) : null,
            icon: const Icon(Icons.remove),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
          Semantics(
            liveRegion: true,
            label: '$cantidad cuotas',
            excludeSemantics: true,
            child: Text(
              '$cantidad',
              key: const Key('cuotas_cantidad'),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            key: const Key('cuotas_mas'),
            tooltip: 'Una cuota más',
            onPressed: habilitado && cantidad < maximo ? () => alCambiar(cantidad + 1) : null,
            icon: const Icon(Icons.add),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ],
      ),
    );
  }
}

/// «PRIMERA CUOTA · Sábado 26/10 ›» (30A-01 y 30A-03): abre el calendario.
class CampoDeDiaDeCuota extends StatelessWidget {
  const CampoDeDiaDeCuota({
    super.key,
    required this.rotulo,
    required this.texto,
    required this.alTocar,
    this.error,
  });

  final String rotulo;
  final String texto;

  /// `null` = el campo no responde (se está creando).
  final VoidCallback? alTocar;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final conError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: ExcludeSemantics(child: Text(rotulo, style: _estiloRotulo)),
        ),
        Semantics(
          button: true,
          enabled: alTocar != null,
          label: '$rotulo: $texto',
          excludeSemantics: true,
          onTap: alTocar,
          child: InkWell(
            key: const Key('cuotas_primera'),
            onTap: alTocar,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: conError ? ColoresAgenda.rojo : _borde, width: 1.5),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(texto, style: const TextStyle(fontSize: 16))),
                  const SizedBox(width: 10),
                  const Icon(Icons.chevron_right, color: ColoresAgenda.gris),
                ],
              ),
            ),
          ),
        ),
        if (conError)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error!,
                key: const Key('cuotas_primera_error'),
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

/// Una cuota con su monto editable (30A-01, 30A-02B, 30A-02C y 30A-09): «1 · sáb 26/10» y, al lado,
/// el monto, que se toca para cambiar. Con [cerrada] no se puede cambiar y dice por qué.
class FilaDeCuotaEditable extends StatelessWidget {
  const FilaDeCuotaEditable({
    super.key,
    required this.rotulo,
    this.controlador,
    this.alCambiar,
    this.valorFijo,
    this.ayuda,
    this.error,
    this.cerrada = false,
    this.habilitado = true,
  });

  final String rotulo;

  /// El monto que se escribe; no va con [cerrada].
  final TextEditingController? controlador;
  final ValueChanged<String>? alCambiar;

  /// El monto de una cuota [cerrada], que se muestra sin poder tocarlo.
  final String? valorFijo;

  /// «Se ajustó» o «Ya está pagada: no cambia.».
  final String? ayuda;
  final String? error;

  /// La cuota ya está pagada: se muestra pero no se toca.
  final bool cerrada;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    final conError = error != null;
    final editable = habilitado && !cerrada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 8, 4),
          decoration: BoxDecoration(
            color: cerrada ? ColoresAgenda.grisFondo : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: conError ? ColoresAgenda.rojo : _borde, width: 1.5),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  style: const TextStyle(
                    fontFamily: 'JetBrainsMono',
                    fontSize: 13,
                    color: ColoresAgenda.tinta,
                  ),
                ),
              ),
              if (cerrada)
                Semantics(
                  label: 'Monto de la cuota $rotulo: ${valorFijo ?? ''}. ${TextosCuotas.pagada}',
                  excludeSemantics: true,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          valorFijo ?? '',
                          style: const TextStyle(
                            fontFamily: 'JetBrainsMono',
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ColoresAgenda.gris,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.check, size: 16, color: _verde),
                      ],
                    ),
                  ),
                )
              else
                SizedBox(
                  width: 130,
                  child: Semantics(
                    label: 'Monto de la cuota $rotulo',
                    child: TextField(
                      controller: controlador,
                      onChanged: alCambiar,
                      enabled: editable,
                      textAlign: TextAlign.end,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [LengthLimitingTextInputFormatter(14)],
                      style: TextStyle(
                        fontFamily: 'JetBrainsMono',
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: conError ? ColoresAgenda.rojo : ColoresAgenda.tinta,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        constraints: BoxConstraints(minHeight: 48),
                        border: InputBorder.none,
                        suffixIcon: Icon(Icons.edit_outlined, size: 16, color: ColoresAgenda.gris),
                        suffixIconConstraints: BoxConstraints(minWidth: 24, minHeight: 24),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (conError)
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(top: 4, left: 4),
              child: Text(
                error!,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: ColoresAgenda.rojo,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          )
        else if (ayuda != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(ayuda!, style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris)),
          ),
      ],
    );
  }
}

/// Una cuota de la lista (30A-04 y 30A-06): el glifo de cómo está, «CUOTA 2 · 02/11», el monto y una
/// línea de estado.
class TarjetaDeCuota extends StatelessWidget {
  const TarjetaDeCuota({super.key, required this.cuota, required this.ahora});

  final Cuota cuota;
  final DateTime ahora;

  @override
  Widget build(BuildContext context) {
    final situacion = cuota.situacion(ahora);
    final (glifo, fondo, tinta, borde) = switch (situacion) {
      SituacionDeCuota.pagada => (Icons.check, _verde, Colors.white, null),
      SituacionDeCuota.parcial => (
        Icons.timelapse,
        const Color(0xFFE0B43C),
        ColoresAgenda.navy,
        null,
      ),
      SituacionDeCuota.vencida => (
        Icons.priority_high,
        ColoresAgenda.rojo,
        Colors.white,
        ColoresAgenda.rojo,
      ),
      SituacionDeCuota.agendada => (
        Icons.circle_outlined,
        Colors.white,
        const Color(0xFF6B7688),
        const Color(0xFF6B7688),
      ),
    };
    final titulo = situacion == SituacionDeCuota.parcial
        ? TextosCuotas.pagadoDe(cuota.pagadoCentavos, cuota.montoCentavos)
        : TextosCuotas.montoDeCuota(cuota.montoCentavos);
    final linea = switch (situacion) {
      SituacionDeCuota.pagada => TextosCuotas.pagadaEl(
        cuota.cubiertaEl == null ? null : ReglasDeVenta.diaDeMontevideo(cuota.cubiertaEl!),
        cuota.medios,
      ),
      SituacionDeCuota.parcial => TextosCuotas.parcialFaltan(cuota.faltanCentavos),
      SituacionDeCuota.vencida =>
        cuota.pagadoCentavos > 0
            ? TextosCuotas.parcialFaltan(cuota.faltanCentavos)
            : TextosCuotas.agendadaPara(cuota.fecha),
      SituacionDeCuota.agendada => TextosCuotas.agendadaPara(cuota.fecha),
    };
    final etiqueta = switch (situacion) {
      SituacionDeCuota.parcial => TextosCuotas.parcial,
      SituacionDeCuota.vencida => TextosCuotas.vencida,
      _ => null,
    };
    final vencida = situacion == SituacionDeCuota.vencida;
    // Con letra grande la etiqueta no entra al costado sin cortar el texto: baja debajo de la línea.
    final pastillaAbajo = MediaQuery.textScalerOf(context).scale(14) > 14 * 1.3;
    final pastilla = etiqueta == null
        ? null
        : Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: vencida ? Colors.white : ColoresAgenda.ambarFondo,
              borderRadius: BorderRadius.circular(8),
              border: vencida ? Border.all(color: ColoresAgenda.rojo) : null,
            ),
            child: Text(
              etiqueta,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: vencida ? ColoresAgenda.rojo : ColoresAgenda.ambarTinta,
              ),
            ),
          );
    return Semantics(
      container: true,
      label:
          '${TextosCuotas.antetituloDeCuota(cuota)}. $titulo. $linea${etiqueta == null ? '' : '. $etiqueta'}',
      excludeSemantics: true,
      child: Container(
        key: Key('cuota_${cuota.numero}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: situacion == SituacionDeCuota.vencida ? ColoresAgenda.rojo : _borde,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: fondo,
                shape: BoxShape.circle,
                border: borde == null ? null : Border.all(color: borde, width: 2),
              ),
              child: Icon(glifo, size: 18, color: tinta),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(TextosCuotas.antetituloDeCuota(cuota), style: _estiloRotulo),
                  const SizedBox(height: 2),
                  Text(titulo, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(linea, style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris)),
                  if (pastilla != null && pastillaAbajo) ...[const SizedBox(height: 6), pastilla],
                ],
              ),
            ),
            if (pastilla != null && !pastillaAbajo) ...[const SizedBox(width: 8), pastilla],
          ],
        ),
      ),
    );
  }
}

/// Un aviso informativo (30A-05): dice a qué cuota va el pago que se está escribiendo.
class AvisoInformativoDeCuotas extends StatelessWidget {
  const AvisoInformativoDeCuotas({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: ColoresAgenda.azulFondo,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: ColoresAgenda.azul, width: 1.5),
        ),
        child: Text(
          texto,
          style: const TextStyle(fontSize: 13.5, height: 1.35, color: ColoresAgenda.tinta),
        ),
      ),
    );
  }
}

/// El marco de las pantallas de cuotas: cabecera y contenido que se desplazan, y el botón de abajo.
class MarcoDeCuotas extends StatelessWidget {
  const MarcoDeCuotas({
    super.key,
    required this.cabecera,
    required this.hijos,
    this.cta,
    this.scroll,
  });

  final Widget cabecera;
  final List<Widget> hijos;
  final Widget? cta;
  final ScrollController? scroll;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                children: [cabecera, ...hijos],
              ),
            ),
            if (cta != null) Padding(padding: const EdgeInsets.fromLTRB(20, 4, 20, 16), child: cta),
          ],
        ),
      ),
    );
  }
}

/// Las filas grises mientras se leen las cuotas.
class EsqueletoDeCuotas extends StatelessWidget {
  const EsqueletoDeCuotas({super.key});

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
      label: TextosCuotas.cargandoLasCuotas,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('cuotas_cargando'),
          children: [
            bloque(92),
            const SizedBox(height: 10),
            bloque(64),
            const SizedBox(height: 10),
            bloque(64),
            const SizedBox(height: 10),
            bloque(64),
          ],
        ),
      ),
    );
  }
}

/// La venta pagada (30A-07): una marca verde y «No hay saldo para repartir en cuotas.».
class MarcaDeSinSaldo extends StatelessWidget {
  const MarcaDeSinSaldo({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        key: const Key('cuotas_sin_saldo'),
        padding: const EdgeInsets.symmetric(vertical: 30),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: Color(0xFFDDE8D3), shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 32, color: _verde),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              TextosCuotas.ventaPagada,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              TextosCuotas.sinSaldoParaRepartir,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.gris),
            ),
          ],
        ),
      ),
    );
  }
}
