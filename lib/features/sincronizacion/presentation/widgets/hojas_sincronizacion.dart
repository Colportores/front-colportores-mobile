import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/estado_sincronizacion.dart';
import '../formato_sincronizacion.dart';
import '../textos_sincronizacion.dart';
import 'componentes_sincronizacion.dart';

/// Abre «¿Actualizar con datos móviles?» (25-09). Devuelve `true` si la persona eligió «Actualizar
/// igual», `false` con «Esperar al Wi-Fi» y `null` si la cerró sin elegir (atrás o tocando afuera):
/// quien llama trata `null` como «esperar», nunca como «actualizar».
Future<bool?> mostrarHojaActualizarConDatos(BuildContext context) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => const _HojaActualizarConDatos(),
);

/// Abre el detalle de una operación que el servidor rechazó (25-07). Devuelve `true` si la persona
/// tocó «Reintentar» y `null`/`false` si la cerró.
Future<bool?> mostrarHojaDetalleOperacion(BuildContext context, OperacionFallida operacion) =>
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _HojaDetalleOperacion(operacion: operacion),
    );

class _Marco extends StatelessWidget {
  const _Marco({
    required this.clave,
    required this.titulo,
    required this.texto,
    required this.hijos,
    required this.botones,
  });

  final Key clave;
  final String titulo;
  final String texto;
  final List<Widget> hijos;
  final List<Widget> botones;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    return SingleChildScrollView(
      child: Padding(
        key: clave,
        padding: const EdgeInsets.fromLTRB(22, 10, 22, 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: 16,
          children: [
            Align(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colores.bordeInput,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 6,
              children: [
                Semantics(header: true, child: Text(titulo, style: theme.textTheme.headlineSmall)),
                Text(
                  texto,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
              ],
            ),
            ...hijos,
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, spacing: 10, children: botones),
          ],
        ),
      ),
    );
  }
}

class _BotonSecundario extends StatelessWidget {
  const _BotonSecundario({required this.clave, required this.texto, required this.alTocar});

  final Key clave;
  final String texto;
  final VoidCallback alTocar;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      key: clave,
      onPressed: alTocar,
      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
      child: Text(texto, textAlign: TextAlign.center),
    );
  }
}

class _HojaActualizarConDatos extends StatelessWidget {
  const _HojaActualizarConDatos();

  @override
  Widget build(BuildContext context) {
    return _Marco(
      clave: const Key('sincronizacion_hoja_datos'),
      titulo: TextosSincronizacion.datosTitulo,
      texto: TextosSincronizacion.datosTexto,
      hijos: const [],
      botones: [
        FilledButton(
          key: const Key('sincronizacion_datos_actualizar_igual'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text(TextosSincronizacion.datosActualizarIgual, textAlign: TextAlign.center),
        ),
        _BotonSecundario(
          clave: const Key('sincronizacion_datos_esperar'),
          texto: TextosSincronizacion.datosEsperarWifi,
          alTocar: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}

class _HojaDetalleOperacion extends StatelessWidget {
  const _HojaDetalleOperacion({required this.operacion});

  final OperacionFallida operacion;

  @override
  Widget build(BuildContext context) {
    final titulo = TextosSincronizacion.tituloOperacion(
      operacion,
      FormatoSincronizacion.dia(operacion.fecha),
    );
    return _Marco(
      clave: const Key('sincronizacion_hoja_detalle'),
      titulo: titulo,
      texto: TextosSincronizacion.detalleTexto(operacion.error),
      hijos: [
        FilasDeCifras(
          filas: [
            FilaDeCifras(
              rotulo: TextosSincronizacion.filaTipo,
              valor: TextosSincronizacion.tipo(operacion.tipo),
              clave: const Key('sincronizacion_detalle_tipo'),
            ),
            FilaDeCifras(
              rotulo: TextosSincronizacion.filaFecha,
              valor: FormatoSincronizacion.diaYHora(operacion.fecha),
              clave: const Key('sincronizacion_detalle_fecha'),
            ),
            if (operacion.codigo.isNotEmpty)
              FilaDeCifras(
                rotulo: TextosSincronizacion.filaCodigo,
                valor: operacion.codigo,
                clave: const Key('sincronizacion_detalle_codigo'),
                numero: true,
              ),
          ],
        ),
      ],
      botones: [
        FilledButton(
          key: const Key('sincronizacion_detalle_reintentar'),
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          child: const Text(TextosSincronizacion.detalleReintentar, textAlign: TextAlign.center),
        ),
        _BotonSecundario(
          clave: const Key('sincronizacion_detalle_cerrar'),
          texto: TextosSincronizacion.detalleCerrar,
          alTocar: () => Navigator.of(context).pop(false),
        ),
      ],
    );
  }
}
