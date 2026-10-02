import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';
import '../../../auth/domain/entities/resumen_datos_locales.dart';
import '../pages/borrar_datos_locales_page.dart' show TextosBorrado;

/// Primera parte de «Borrar datos locales» (vista 19, artboards 01 a 04): lo que hay en el
/// teléfono, el bloqueo si hay operaciones sin sincronizar (o no se pudieron contar) y las dos
/// casillas. "Continuar" solo se habilita sin pendientes y con las dos casillas marcadas.
class ResumenBorrado extends StatelessWidget {
  const ResumenBorrado({
    super.key,
    required this.resumen,
    required this.soloEsteTelefono,
    required this.irreversible,
    required this.sincronizando,
    required this.recontando,
    required this.avisoSincronizacion,
    required this.onSoloEsteTelefono,
    required this.onIrreversible,
    required this.onSincronizar,
    required this.onReintentarConteo,
    required this.onContinuar,
  });

  final ResumenDatosLocales resumen;
  final bool soloEsteTelefono;
  final bool irreversible;

  /// "Sincronizar ahora" en curso.
  final bool sincronizando;

  /// Volviendo a contar lo pendiente (después de sincronizar o de "Reintentar").
  final bool recontando;

  /// Lo que dejó el último "Sincronizar ahora", para guiar qué hacer. `null` si no hay.
  final String? avisoSincronizacion;

  final ValueChanged<bool> onSoloEsteTelefono;
  final ValueChanged<bool> onIrreversible;
  final VoidCallback onSincronizar;
  final VoidCallback onReintentarConteo;
  final VoidCallback onContinuar;

  /// No se pudo contar lo pendiente: se trata como "posiblemente pendiente" y bloquea.
  bool get _sinConteo => resumen.operacionesSinSincronizar == null;

  int get _pendientes => resumen.operacionesSinSincronizar ?? 0;

  bool get _bloqueado => _sinConteo || _pendientes > 0;

  bool get _casillasMarcadas => soloEsteTelefono && irreversible;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final ocupado = sincronizando || recontando;
    final puedeContinuar = !_bloqueado && _casillasMarcadas && !ocupado;

    return Column(
      key: const Key('borrar_datos_resumen'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(TextosBorrado.explicacion, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 20),
        Text(TextosBorrado.encabezadoResumen, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: colores.borde),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              _Fila(
                icono: Icons.people_outline,
                titulo: 'Personas registradas en este teléfono',
                valor: _sinConteo ? '—' : '${resumen.personas}',
                valorKey: const Key('borrar_datos_personas'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.event_note_outlined,
                titulo: 'Visitas registradas en este teléfono',
                valor: _sinConteo ? '—' : '${resumen.visitas}',
                valorKey: const Key('borrar_datos_visitas'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.cloud_upload_outlined,
                titulo: 'Operaciones sin sincronizar',
                valor: _sinConteo ? '— ${TextosBorrado.noSePudieronContar}' : '$_pendientes',
                valorKey: const Key('borrar_datos_pendientes'),
              ),
              const Divider(),
              _Fila(
                icono: Icons.cloud_outlined,
                titulo: 'Backup en Drive',
                valor: resumen.hayBackupEnDrive ? 'Sí, vas a elegir si se borra' : 'No hay',
                valorKey: const Key('borrar_datos_backup'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_sinConteo)
          _BloqueoSinConteo(recontando: recontando, onReintentar: onReintentarConteo)
        else if (_pendientes > 0)
          _BloqueoPendientes(
            pendientes: _pendientes,
            sincronizando: sincronizando,
            recontando: recontando,
            aviso: avisoSincronizacion,
            onSincronizar: onSincronizar,
          ),
        if (!_sinConteo && _pendientes > 0) ...[
          const SizedBox(height: 12),
          Text(
            TextosBorrado.leyendaBloqueo,
            key: const Key('borrar_datos_leyenda_bloqueo'),
            style: theme.textTheme.bodySmall?.copyWith(color: colores.gris),
          ),
        ],
        const SizedBox(height: 12),
        const _Aviso(icono: Icons.info_outline, texto: TextosBorrado.datosDelSistema),
        const SizedBox(height: 8),
        const _Aviso(icono: Icons.lock_outline, texto: TextosBorrado.limiteBorrado),
        const SizedBox(height: 12),
        CheckboxListTile(
          key: const Key('borrar_datos_checkbox'),
          value: soloEsteTelefono,
          onChanged: ocupado ? null : (v) => onSoloEsteTelefono(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(TextosBorrado.casillaSoloEsteTelefono),
        ),
        CheckboxListTile(
          key: const Key('borrar_datos_checkbox_irreversible'),
          value: irreversible,
          onChanged: ocupado ? null : (v) => onIrreversible(v ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(TextosBorrado.casillaIrreversible),
        ),
        if (!_bloqueado && !_casillasMarcadas) ...[
          const SizedBox(height: 4),
          Text(
            TextosBorrado.faltanCasillas,
            key: const Key('borrar_datos_faltan_casillas'),
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
          ),
        ],
        const SizedBox(height: 12),
        FilledButton(
          key: const Key('borrar_datos_continuar'),
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
            minimumSize: const Size.fromHeight(48),
          ),
          onPressed: puedeContinuar ? onContinuar : null,
          child: const Text('Continuar'),
        ),
      ],
    );
  }
}

/// Artboard 02: hay operaciones sin subir. Se sincroniza antes de borrar; las que no se pueden
/// subir (`INVALID`) piden corregirlas.
class _BloqueoPendientes extends StatelessWidget {
  const _BloqueoPendientes({
    required this.pendientes,
    required this.sincronizando,
    required this.recontando,
    required this.aviso,
    required this.onSincronizar,
  });

  final int pendientes;
  final bool sincronizando;
  final bool recontando;
  final String? aviso;
  final VoidCallback onSincronizar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          key: const Key('borrar_datos_aviso_pendientes'),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    TextosBorrado.pendientes(pendientes),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (aviso != null) ...[
          const SizedBox(height: 8),
          Text(
            aviso!,
            key: const Key('borrar_datos_aviso_sync'),
            style: theme.textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('borrar_datos_sincronizar'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: sincronizando || recontando ? null : onSincronizar,
          child: sincronizando || recontando
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                        key: Key('borrar_datos_sincronizando'),
                        strokeWidth: 2.5,
                        semanticsLabel: 'Sincronizando',
                      ),
                    ),
                    SizedBox(width: 10),
                    Flexible(child: Text('Sincronizando…')),
                  ],
                )
              : const Text('Sincronizar ahora'),
        ),
      ],
    );
  }
}

/// Artboard 03: no se pudo contar lo pendiente. Decisión de Cristian (29/09): también bloquea.
class _BloqueoSinConteo extends StatelessWidget {
  const _BloqueoSinConteo({required this.recontando, required this.onReintentar});

  final bool recontando;
  final VoidCallback onReintentar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const Key('borrar_datos_sin_conteo'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(
                  child: Icon(Icons.help_outline, color: theme.colorScheme.onErrorContainer),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${TextosBorrado.noSePudieronContar}. ${TextosBorrado.reintentarConteo}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('borrar_datos_reintentar_conteo'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          onPressed: recontando ? null : onReintentar,
          child: recontando
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    key: Key('borrar_datos_recontando'),
                    strokeWidth: 2.5,
                    semanticsLabel: 'Contando',
                  ),
                )
              : const Text('Reintentar'),
        ),
      ],
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.icono,
    required this.titulo,
    required this.valor,
    required this.valorKey,
  });

  final IconData icono;
  final String titulo;
  final String valor;
  final Key valorKey;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icono),
    title: Text(titulo),
    subtitle: Text(valor, key: valorKey, style: Theme.of(context).textTheme.titleMedium),
  );
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Icon(icono, size: 20)),
        const SizedBox(width: 10),
        Expanded(child: Text(texto, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
