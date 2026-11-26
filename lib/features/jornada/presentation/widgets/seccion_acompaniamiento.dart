import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../domain/entities/acompaniante.dart';
import '../../domain/entities/jornada.dart';
import '../providers/acompaniamiento_providers.dart';
import '../textos_acompaniamiento.dart';
import 'aviso_jornada.dart';
import 'hoja_acompaniantes.dart';

/// «¿Te acompañó alguien?» de la jornada en curso (vista 20, 20J·01 a 20J·07, y vista 21, 21J·01 y 21J·02;
/// HU-JOR-003): el interruptor, la tarjeta de quienes acompañan y la hoja para elegir. Sigue disponible
/// hasta cerrar la jornada: si se olvidó de marcarlo durante el día, lo hace al cerrar (21J·02).
///
/// Todo es local: la lista baja con la sincronización y lo que se anota sube con la jornada, así que no hay
/// aviso de «sin conexión». Los guardados se hacen de a uno y en orden (dos cambios seguidos no se pisan:
/// el último gana); si uno falla queda el aviso con «Reintentar» y lo que estaba guardado no cambia.
class SeccionAcompaniamiento extends ConsumerStatefulWidget {
  const SeccionAcompaniamiento({super.key, required this.colportorId, required this.jornada});

  final String colportorId;
  final Jornada jornada;

  @override
  ConsumerState<SeccionAcompaniamiento> createState() => _SeccionAcompaniamientoState();
}

class _SeccionAcompaniamientoState extends ConsumerState<SeccionAcompaniamiento> {
  /// Los guardados van en fila: cada uno espera al anterior.
  Future<void> _fila = Future.value();

  /// Lo último que se pidió guardar: el aviso de error y «Reintentar» hablan de eso.
  Set<String>? _ultimoPedido;
  int _guardando = 0;
  bool _fallo = false;
  bool _abriendo = false;

  ClaveDeLaLista get _clave => (colportorId: widget.colportorId, inicio: widget.jornada.inicio);

  Future<void> _elegir(List<Acompaniante> actuales) async {
    if (_abriendo) return;
    _abriendo = true;
    try {
      final elegidos = await mostrarHojaAcompaniantes(context, clave: _clave, actuales: actuales);
      if (!mounted || elegidos == null) return;
      final antes = {for (final a in actuales) a.usuarioId};
      // Sin cambios no se guarda ni se vuelve a subir nada.
      if (antes.length == elegidos.length && antes.containsAll(elegidos)) return;
      unawaited(_guardar(elegidos));
    } finally {
      _abriendo = false;
    }
  }

  Future<void> _guardar(Set<String> elegidos) {
    final pedido = Set<String>.of(elegidos);
    _ultimoPedido = pedido;
    setState(() {
      _fallo = false;
      _guardando++;
    });
    final repositorio = ref.read(acompaniamientoRepositoryProvider);
    final turno = _fila.then((_) async {
      final resultado = await repositorio.guardar(
        jornadaId: widget.jornada.id,
        colportorId: widget.colportorId,
        usuarioIds: pedido,
      );
      if (!mounted) return;
      final quienes = resultado.isRight() ? await _quienesSon(pedido) : const <Acompaniante>[];
      if (!mounted) return;
      setState(() {
        _guardando--;
        // El aviso es del último pedido: una falla vieja ya no importa si hay uno más nuevo.
        if (resultado.isLeft()) {
          _fallo = identical(_ultimoPedido, pedido);
        } else if (identical(_ultimoPedido, pedido)) {
          _fallo = false;
        }
      });
      if (resultado.isRight() && identical(_ultimoPedido, pedido)) {
        final mensajes = ScaffoldMessenger.maybeOf(context);
        mensajes?.clearSnackBars();
        mensajes?.showSnackBar(SnackBar(content: Text(TextosAcompaniamiento.anotado(quienes))));
      }
    });
    _fila = turno.catchError((Object _) {});
    return turno;
  }

  /// Los nombres de [ids]: los de la lista de hoy o, si ya no están, los que figuraban.
  Future<List<Acompaniante>> _quienesSon(Set<String> ids) async {
    final conocidos = <String, Acompaniante>{};
    try {
      for (final a in await ref.read(acompaniantesDeLaJornadaProvider(widget.jornada.id).future)) {
        conocidos[a.usuarioId] = a;
      }
    } on Object {
      // Sin nombres: el aviso dice «alguien».
    }
    final lista = ref.read(listaDeAcompanantesProvider(_clave)).value ?? const [];
    for (final c in lista) {
      conocidos[c.usuarioId] = Acompaniante(
        usuarioId: c.usuarioId,
        nombre: c.nombre,
        apellido: c.apellido,
      );
    }
    return [for (final id in ids) conocidos[id] ?? Acompaniante(usuarioId: id)];
  }

  /// Lo que se muestra: lo guardado o, mientras hay un guardado en vuelo, lo que se acaba de pedir. Así un
  /// segundo cambio antes de que termine el primero parte de lo que la colportora ya eligió y no lo pisa.
  List<Acompaniante> _mostrados(List<Acompaniante> guardados, List<CoordinadorDeCampania> lista) {
    final pedido = _ultimoPedido;
    if (_guardando == 0 || pedido == null) return guardados;
    final conocidos = {
      for (final c in lista)
        c.usuarioId: Acompaniante(usuarioId: c.usuarioId, nombre: c.nombre, apellido: c.apellido),
      for (final a in guardados) a.usuarioId: a,
    };
    return [
      for (final a in guardados)
        if (pedido.contains(a.usuarioId)) a,
      for (final id in pedido.toList()..sort())
        if (!guardados.any((a) => a.usuarioId == id)) conocidos[id] ?? Acompaniante(usuarioId: id),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final acompanantes = ref.watch(acompaniantesDeLaJornadaProvider(widget.jornada.id));
    final lista = ref.watch(listaDeAcompanantesProvider(_clave)).value ?? const [];
    final conocida = ref.watch(campaniaDeLaJornadaConocidaProvider(_clave)).value ?? true;

    return acompanantes.when(
      loading: () => const SizedBox.shrink(key: Key('acompaniamiento_cargando')),
      error: (_, _) => Column(
        key: const Key('acompaniamiento_error_lectura'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 8,
        children: [
          const AvisoJornada(
            texto: TextosAcompaniamiento.noPudimosLeerElAcompaniamiento,
            esError: true,
          ),
          OutlinedButton(
            key: const Key('acompaniamiento_releer'),
            onPressed: () => ref.invalidate(acompaniantesDeLaJornadaProvider(widget.jornada.id)),
            child: const Text(TextosAcompaniamiento.reintentar),
          ),
        ],
      ),
      data: (guardados) => _cuerpo(context, _mostrados(guardados, lista), conocida),
    );
  }

  Widget _cuerpo(BuildContext context, List<Acompaniante> actuales, bool conocida) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;
    return Column(
      key: const Key('acompaniamiento'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        if (_fallo)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 8,
            children: [
              const AvisoJornada(
                key: Key('acompaniamiento_error'),
                texto: TextosAcompaniamiento.noPudimosGuardar,
                esError: true,
              ),
              OutlinedButton(
                key: const Key('acompaniamiento_reintentar'),
                onPressed: _guardando > 0 ? null : () => unawaited(_guardar(_ultimoPedido!)),
                child: const Text(TextosAcompaniamiento.reintentar),
              ),
            ],
          ),
        // `Material` propio: el `ListTile` del interruptor pinta su fondo sobre el `Material` más cercano.
        Material(
          color: esquema.surfaceContainerHighest,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: colores.borde),
          ),
          child: actuales.isEmpty
              ? SwitchListTile(
                  key: const Key('acompaniamiento_interruptor'),
                  value: false,
                  onChanged: (prendido) {
                    if (prendido) unawaited(_elegir(actuales));
                  },
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: const Text(TextosAcompaniamiento.pregunta),
                  subtitle: Text(
                    _guardando > 0
                        ? TextosAcompaniamiento.guardando
                        : TextosAcompaniamiento.ayudaDelInterruptor(campaniaConocida: conocida),
                    style: TextStyle(color: colores.gris),
                  ),
                )
              : _TarjetaDeAcompanantes(
                  acompanantes: actuales,
                  campaniaConocida: conocida,
                  guardando: _guardando > 0,
                  alCambiar: () => unawaited(_elegir(actuales)),
                ),
        ),
      ],
    );
  }
}

/// 20J·03: «TE ACOMPAÑA» con una fila por persona y «Cambiar» (que abre la hoja con todos marcados).
class _TarjetaDeAcompanantes extends StatelessWidget {
  const _TarjetaDeAcompanantes({
    required this.acompanantes,
    required this.campaniaConocida,
    required this.guardando,
    required this.alCambiar,
  });

  final List<Acompaniante> acompanantes;
  final bool campaniaConocida;
  final bool guardando;
  final VoidCallback alCambiar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final esquema = theme.colorScheme;

    return Padding(
      key: const Key('acompaniamiento_tarjeta'),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 8,
        children: [
          Text(
            TextosAcompaniamiento.teAcompania(acompanantes.length),
            style: theme.textTheme.labelSmall?.copyWith(color: colores.gris),
          ),
          for (final a in acompanantes)
            Row(
              key: Key('acompaniante_tarjeta_${a.usuarioId}'),
              spacing: 12,
              children: [
                ExcludeSemantics(
                  child: CircleAvatar(
                    radius: 17,
                    backgroundColor: esquema.primary,
                    foregroundColor: esquema.onPrimary,
                    child: Text(_iniciales(a.nombreCompleto), style: const TextStyle(fontSize: 12)),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.nombreCompleto ?? TextosAcompaniamiento.personaSinNombre,
                        style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        TextosAcompaniamiento.rolDeLaLista(campaniaConocida: campaniaConocida),
                        style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              key: const Key('acompaniamiento_cambiar'),
              onPressed: alCambiar,
              child: Text(
                guardando ? TextosAcompaniamiento.guardando : TextosAcompaniamiento.cambiar,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _iniciales(String? nombre) {
    final partes = (nombre ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return '·';
    final primera = partes.first.characters.first;
    final ultima = partes.length > 1 ? partes.last.characters.first : '';
    return '$primera$ultima'.toUpperCase();
  }
}
