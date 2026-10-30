import 'package:flutter/material.dart';

import '../../../agenda/presentation/formato_agendar_visita.dart';
import '../../../agenda/presentation/widgets/piezas_agenda.dart' show ColoresAgenda;
import '../../../ventas/presentation/formato_venta.dart' show FormatoVenta;
import '../textos_cobro.dart';

// Las piezas de la vista 28 (Cobro en efectivo). Todas crecen con el texto (`textScaler` 2.0): nada
// tiene alto fijo salvo el mínimo táctil de 48.

const _borde = Color(0xFFE3E7EE);
const _verdeFondo = Color(0xFFDDE8D3);
const _verdeTinta = Color(0xFF1F6E3A);

const _estiloRotulo = TextStyle(
  fontFamily: 'JetBrainsMono',
  fontSize: 10.5,
  letterSpacing: 1.6,
  color: ColoresAgenda.gris,
);

/// El resumen de la venta que se cobra: «Venta 0042 · 12/10», lo pagado y el saldo.
class ResumenDeLaVenta extends StatelessWidget {
  const ResumenDeLaVenta({
    super.key,
    required this.titulo,
    required this.totalCentavos,
    required this.cobradoCentavos,
    required this.saldoCentavos,
  });

  final String titulo;
  final int totalCentavos;
  final int cobradoCentavos;
  final int saldoCentavos;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('cobro_resumen'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borde),
      ),
      child: Column(
        children: [
          _Fila(clave: 'cobro_total', rotulo: titulo, valor: FormatoVenta.monto(totalCentavos)),
          _Fila(
            clave: 'cobro_pagado',
            rotulo: TextosCobro.pagado,
            valor: FormatoVenta.monto(cobradoCentavos),
          ),
          _Fila(
            clave: 'cobro_saldo',
            rotulo: TextosCobro.saldo,
            valor: FormatoVenta.monto(saldoCentavos),
            fuerte: true,
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.clave,
    required this.rotulo,
    required this.valor,
    this.fuerte = false,
  });

  final String clave;
  final String rotulo;
  final String valor;
  final bool fuerte;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$rotulo: $valor',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text(
                  rotulo,
                  style: TextStyle(
                    fontSize: 14,
                    color: fuerte ? ColoresAgenda.tinta : ColoresAgenda.gris,
                    fontWeight: fuerte ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                valor,
                key: Key(clave),
                style: TextStyle(
                  fontFamily: 'JetBrainsMono',
                  fontSize: fuerte ? 16 : 14,
                  fontWeight: fuerte ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El campo FECHA: el día del cobro y «Cambiar», que abre la hoja «¿Cuándo te pagó?» (28·04).
class CampoDeFechaDelCobro extends StatelessWidget {
  const CampoDeFechaDelCobro({super.key, required this.texto, required this.alCambiar, this.error});

  final String texto;

  /// `null` = el campo no responde (se está registrando).
  final VoidCallback? alCambiar;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final conError = error != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: ExcludeSemantics(child: Text(TextosCobro.fecha, style: _estiloRotulo)),
        ),
        Semantics(
          button: true,
          enabled: alCambiar != null,
          label: '${TextosCobro.fecha}: $texto. ${TextosCobro.cambiar}',
          excludeSemantics: true,
          onTap: alCambiar,
          child: InkWell(
            key: const Key('cobro_fecha'),
            onTap: alCambiar,
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
                  Text(
                    TextosCobro.cambiar,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: alCambiar == null ? ColoresAgenda.gris : ColoresAgenda.azul,
                    ),
                  ),
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
                key: const Key('cobro_fecha_error'),
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

/// El aviso verde de lo que quedó hecho (28·06).
class AvisoDeCobroHecho extends StatelessWidget {
  const AvisoDeCobroHecho({super.key, required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        key: const Key('cobro_aviso_ok'),
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

/// La marca grande de «Venta pagada» (28·07).
class MarcaDeVentaPagada extends StatelessWidget {
  const MarcaDeVentaPagada({super.key, required this.titulo, required this.texto});

  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Padding(
        key: const Key('cobro_venta_pagada'),
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: [
            ExcludeSemantics(
              child: Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: _verdeTinta, shape: BoxShape.circle),
                child: const Text('★', style: TextStyle(fontSize: 28, color: Colors.white)),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              titulo,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: 'SourceSerif4',
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              texto,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, height: 1.4, color: ColoresAgenda.gris),
            ),
          ],
        ),
      ),
    );
  }
}

/// Las filas grises mientras se lee la venta.
class EsqueletoDelCobro extends StatelessWidget {
  const EsqueletoDelCobro({super.key, this.etiqueta = TextosCobro.cargandoLaVenta});

  /// Lo que dice el lector de pantalla mientras carga.
  final String etiqueta;

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
      label: etiqueta,
      child: ExcludeSemantics(
        child: Column(
          key: const Key('cobro_cargando'),
          children: [
            bloque(92),
            const SizedBox(height: 10),
            bloque(56),
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

/// La hoja «¿Cuándo te pagó?» (28·04): Hoy, Ayer, anteayer y «Otro día…», sin días antes de la venta.
/// Devuelve el día elegido al tocar «Listo», o `null` si se la cierra sin confirmar (no cambia nada).
/// [hoy], [diaDeLaVenta] y [elegido] son fechas sin hora (día de Montevideo).
Future<DateTime?> mostrarHojaFechaDelCobro(
  BuildContext context, {
  required DateTime hoy,
  required DateTime diaDeLaVenta,
  required DateTime elegido,
}) => showModalBottomSheet<DateTime>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.white,
  shape: _formaHoja,
  builder: (_) => HojaFechaDelCobro(hoy: hoy, diaDeLaVenta: diaDeLaVenta, elegido: elegido),
);

class HojaFechaDelCobro extends StatefulWidget {
  const HojaFechaDelCobro({
    super.key,
    required this.hoy,
    required this.diaDeLaVenta,
    required this.elegido,
  });

  final DateTime hoy;
  final DateTime diaDeLaVenta;
  final DateTime elegido;

  @override
  State<HojaFechaDelCobro> createState() => _HojaFechaDelCobroState();
}

class _HojaFechaDelCobroState extends State<HojaFechaDelCobro> {
  late DateTime _dia = widget.elegido;
  var _abriendoElCalendario = false;

  bool _sePuede(DateTime d) => !d.isBefore(widget.diaDeLaVenta) && !d.isAfter(widget.hoy);

  Future<void> _otroDia() async {
    if (_abriendoElCalendario) return;
    _abriendoElCalendario = true;
    try {
      final elegido = await showDatePicker(
        context: context,
        initialDate: _sePuede(_dia) ? _dia : widget.hoy,
        firstDate: widget.diaDeLaVenta,
        lastDate: widget.hoy,
      );
      if (elegido != null && mounted) {
        setState(() => _dia = DateTime(elegido.year, elegido.month, elegido.day));
      }
    } finally {
      _abriendoElCalendario = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Hoy (0), ayer (1) y anteayer (2), menos los que quedan antes de la venta.
    final atajos = <({int atras, DateTime dia})>[
      for (var i = 0; i < 3; i++)
        if (_sePuede(FormatoCobro.diasAntes(widget.hoy, i)))
          (atras: i, dia: FormatoCobro.diasAntes(widget.hoy, i)),
    ];
    final hayMas = widget.diaDeLaVenta.isBefore(FormatoCobro.diasAntes(widget.hoy, 2));
    final fueraDeAtajo = !atajos.any((a) => FormatoAgendarVisita.mismoDia(a.dia, _dia));

    Widget chip(String texto, DateTime dia, Key clave) {
      final elegido = FormatoAgendarVisita.mismoDia(dia, _dia);
      return Semantics(
        selected: elegido,
        button: true,
        excludeSemantics: true,
        label: texto,
        onTap: () => setState(() => _dia = dia),
        child: ChoiceChip(
          key: clave,
          label: Text(texto),
          selected: elegido,
          showCheckmark: false,
          selectedColor: ColoresAgenda.navy,
          backgroundColor: Colors.white,
          side: BorderSide(color: elegido ? ColoresAgenda.navy : ColoresAgenda.bordeChip),
          labelStyle: TextStyle(color: elegido ? Colors.white : ColoresAgenda.tinta),
          materialTapTargetSize: MaterialTapTargetSize.padded,
          onSelected: (_) => setState(() => _dia = dia),
        ),
      );
    }

    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: Text(TextosCobro.hojaTitulo, style: Theme.of(context).textTheme.titleLarge),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final a in atajos)
                  chip(
                    switch (a.atras) {
                      0 => TextosCobro.hoy,
                      1 => TextosCobro.ayer,
                      _ => FormatoAgendarVisita.diaCorto(a.dia),
                    },
                    a.dia,
                    Key('cobro_dia_${a.atras}'),
                  ),
                if (fueraDeAtajo)
                  chip(
                    FormatoAgendarVisita.diaCortoYMes(_dia),
                    _dia,
                    const Key('cobro_dia_elegido'),
                  ),
                if (hayMas)
                  ActionChip(
                    key: const Key('cobro_otro_dia'),
                    label: const Text(TextosCobro.otroDia),
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: ColoresAgenda.bordeChip),
                    materialTapTargetSize: MaterialTapTargetSize.padded,
                    onPressed: _otroDia,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              TextosCobro.fechaFueraDeRango(FormatoAgendarVisita.diaYMes(widget.diaDeLaVenta)),
              key: const Key('cobro_rango'),
              style: const TextStyle(fontSize: 12.5, color: ColoresAgenda.gris),
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('cobro_hoja_listo'),
              onPressed: () => Navigator.of(context).pop(_dia),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                backgroundColor: ColoresAgenda.navy,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                TextosCobro.listo,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
