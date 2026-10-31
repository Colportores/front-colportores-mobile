import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/sesion.dart';
import '../../domain/usecases/finalizar_jornada_anterior_use_case.dart';
import '../../domain/usecases/jornadas_por_cerrar_use_case.dart';
import '../formato_jornada.dart';
import '../providers/jornada_providers.dart';
import '../providers/jornadas_por_cerrar_providers.dart';
import 'corregir_jornada_page.dart';

/// Los textos de la pantalla de las jornadas que quedaron abiertas con otra después.
abstract final class TextosJornadasPorCerrar {
  static const eyebrow = 'JORNADA SIN CERRAR';
  static const titulo = '¿A qué hora terminaste?';
  static String explicacion(int cantidad) => cantidad == 1
      ? 'Quedó abierta una jornada de antes. Indicá a qué hora terminó; no la cerramos con la '
            'hora de ahora porque las horas se contarían dos veces.'
      : 'Quedaron abiertas $cantidad jornadas de antes. Indicá a qué hora terminó cada una; no '
            'las cerramos con la hora de ahora porque las horas se contarían dos veces.';
  static String jornada(DateTime inicio) =>
      'Empezó el ${diaCorto(inicio)} a las ${horaCorta(inicio)}';
  static const elegir = 'Elegir la hora de fin';
}

/// Después de recuperar los datos de otro teléfono (HU-SYNC-006) puede haber más de una jornada
/// abierta del colportor: cada una que tiene otra después pasa por «¿A qué hora terminaste?»
/// (HU-JOR-002, vista 21) con el inicio de la siguiente como tope. Ninguna se cierra sola ni con
/// la hora de ahora, y no se llega a Hoy hasta cerrarlas todas.
///
/// Abre la pantalla de corregir de la más vieja; al cerrarla, la lista se vuelve a leer y sigue la
/// que queda. Si la persona vuelve atrás sin cerrar (solo es posible cuando el reloj no deja
/// ninguna hora válida), esta pantalla le deja volver a intentar.
class JornadasPorCerrarPage extends ConsumerStatefulWidget {
  const JornadasPorCerrarPage({super.key, required this.sesion, required this.pendientes});

  final Sesion sesion;

  /// Lo que hay por cerrar, la más vieja primero. No vacío.
  final List<JornadaPorCerrar> pendientes;

  @override
  ConsumerState<JornadasPorCerrarPage> createState() => _JornadasPorCerrarPageState();
}

class _JornadasPorCerrarPageState extends ConsumerState<JornadasPorCerrarPage> {
  bool _abierta = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_abrir()));
  }

  @override
  void didUpdateWidget(JornadasPorCerrarPage anterior) {
    super.didUpdateWidget(anterior);
    // La que sigue se abre sola; si la lista es la misma de antes no se vuelve a abrir una pantalla
    // que la persona acaba de dejar.
    if (anterior.pendientes.first.jornada.id != widget.pendientes.first.jornada.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_abrir()));
    }
  }

  Future<void> _abrir() async {
    if (!mounted || _abierta || widget.pendientes.isEmpty) return;
    _abierta = true;
    final por = widget.pendientes.first;
    final colportorId = widget.sesion.usuarioId;
    await Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        builder: (_) => CorregirJornadaPage(
          sesion: widget.sesion,
          inicio: por.jornada.inicio,
          inicioSiguiente: por.inicioSiguiente,
          finalizar: (hora) => ref.read(finalizarJornadaAnteriorUseCaseProvider)(
            FinalizarJornadaAnteriorParams(
              colportorId: colportorId,
              jornadaId: por.jornada.id,
              hora: hora,
            ),
          ),
        ),
      ),
    );
    _abierta = false;
    if (!mounted) return;
    // Cerrada o ya cerrada en otro lado: se relee la lista y sigue la que quede (o Hoy).
    ref.invalidate(jornadasPorCerrarProvider(colportorId));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>() ?? ColoresColportaje.unica;
    final por = widget.pendientes.first;
    return Scaffold(
      key: const Key('jornadas_por_cerrar_pagina'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, restricciones) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(26, 44, 26, 26),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (restricciones.maxHeight - 70).clamp(0, double.infinity),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 12,
                    children: [
                      Text(
                        TextosJornadasPorCerrar.eyebrow,
                        style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
                      ),
                      Semantics(
                        header: true,
                        child: Text(
                          TextosJornadasPorCerrar.titulo,
                          style: theme.textTheme.headlineMedium,
                        ),
                      ),
                      Text(
                        TextosJornadasPorCerrar.explicacion(widget.pendientes.length),
                        key: const Key('jornadas_por_cerrar_explicacion'),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          height: 1.5,
                        ),
                      ),
                      Text(
                        TextosJornadasPorCerrar.jornada(por.jornada.inicio),
                        key: const Key('jornadas_por_cerrar_jornada'),
                        style: theme.textTheme.titleSmall,
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 24),
                    child: FilledButton(
                      key: const Key('jornadas_por_cerrar_elegir'),
                      onPressed: () => unawaited(_abrir()),
                      child: const Text(TextosJornadasPorCerrar.elegir),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
