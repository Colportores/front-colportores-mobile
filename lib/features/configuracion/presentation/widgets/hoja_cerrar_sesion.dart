import 'package:flutter/material.dart';

import '../../../../core/theme/colores_colportaje.dart';

/// Textos de la hoja «¿Cerrar sesión?». Los literales de HU-AUTH-006 van tal cual; «¿Cerrar
/// sesión?» y «Todo sincronizado» son propuesta del diseño (vista 16).
abstract final class TextosCerrarSesion {
  static const titulo = '¿Cerrar sesión?';
  static const todoSincronizado = 'Todo sincronizado';
  static const cerrando = 'Cerrando sesión';
  static const confirmar = 'Cerrar sesión';
  static const confirmarIgual = 'Cerrar sesión igual';
  static const cancelar = 'Cancelar';
  static const reintentar = 'Reintentar';
  static const revisando = 'Revisando…';
  static const sinRevisar =
      'No pudimos revisar si hay algo sin subir. Si cerrás sesión no perdés nada, pero puede '
      'quedar sin sincronizar hasta que vuelvas a iniciar sesión.';
  static const datosGuardados =
      'Tus datos quedan guardados en este teléfono: vas a volver a verlos cuando inicies sesión.';
  static const errorCierre = 'No pudimos cerrar la sesión. Probá de nuevo.';

  static String advertenciaPendientes(int n) => n == 1
      ? 'Tenés 1 operación sin sincronizar. Si cerrás sesión ahora, se subirá cuando vuelvas a '
            'iniciar sesión.'
      : 'Tenés $n operaciones sin sincronizar. Si cerrás sesión ahora, se subirán cuando vuelvas a '
            'iniciar sesión.';
}

/// Abre la hoja de confirmación del cierre de sesión (vista 16, A02 a A06). [cerrar] hace el cierre
/// y dice si salió bien: con `false` la hoja muestra el error con «Reintentar». Con `true` no se
/// cierra sola: quien llamó saca las pantallas de la pila (puede haberlo hecho ya la raíz al
/// mostrar el login). Devuelve `null` si el colportor canceló.
///
/// [pendientes] es `null` si no se pudo contar lo que falta subir: la hoja no afirma «Todo
/// sincronizado», lo dice y ofrece «Reintentar» el conteo con [contar] (decisión de Cristian,
/// 02/10). Sin [contar] el reintento no se ofrece.
Future<bool?> mostrarHojaCerrarSesion(
  BuildContext context, {
  required int? pendientes,
  required Future<bool> Function() cerrar,
  Future<int?> Function()? contar,
}) => showModalBottomSheet<bool>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  enableDrag: false,
  showDragHandle: false,
  backgroundColor: Colors.white,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => HojaCerrarSesion(pendientes: pendientes, cerrar: cerrar, contar: contar),
);

enum _Fase { confirmar, cerrando, error }

/// Hoja inferior «¿Cerrar sesión?». Sin pendientes, «Cerrar sesión» es la acción principal; con
/// pendientes, la acción segura («Cancelar») es la principal y «Cerrar sesión igual» la
/// secundaria; sin poder contarlos ([pendientes] `null`), lo dice y «Reintentar» el conteo es la
/// principal. Mientras cierra no se puede cancelar ni cerrar la hoja; si falla, «Reintentar».
class HojaCerrarSesion extends StatefulWidget {
  const HojaCerrarSesion({super.key, required this.pendientes, required this.cerrar, this.contar});

  final int? pendientes;
  final Future<bool> Function() cerrar;

  /// Vuelve a contar lo que falta subir (`null` si tampoco se pudo).
  final Future<int?> Function()? contar;

  @override
  State<HojaCerrarSesion> createState() => _HojaCerrarSesionState();
}

class _HojaCerrarSesionState extends State<HojaCerrarSesion> {
  _Fase _fase = _Fase.confirmar;

  /// Lo contado; `null` si no se pudo. Arranca con lo que trajo quien abrió la hoja.
  late int? _pendientes = widget.pendientes;

  /// «Reintentar» el conteo en curso.
  bool _contando = false;

  Future<void> _recontar() async {
    final contar = widget.contar;
    if (contar == null || _contando || _fase != _Fase.confirmar) return; // Doble tap.
    setState(() => _contando = true);
    int? n;
    try {
      n = await contar();
    } on Object {
      n = null;
    }
    if (!mounted) return;
    setState(() {
      _contando = false;
      _pendientes = n;
    });
  }

  Future<void> _cerrar() async {
    if (_fase == _Fase.cerrando) return; // Doble tap / reintento encimado: una sola vez.
    setState(() => _fase = _Fase.cerrando);
    var ok = false;
    try {
      ok = await widget.cerrar();
    } on Object {
      ok = false;
    }
    if (!mounted) return;
    // Con éxito la hoja queda en «Cerrando sesión» hasta que se la saque de la pila.
    if (!ok) setState(() => _fase = _Fase.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colores = theme.extension<ColoresColportaje>()!;
    final cerrando = _fase == _Fase.cerrando;
    final pendientes = _pendientes;
    final sinRevisar = pendientes == null && _fase != _Fase.error;
    final hayPendientes = pendientes != null && pendientes > 0 && _fase != _Fase.error;

    final cancelar = _Boton(
      clave: const Key('configuracion_dialogo_cancelar'),
      texto: TextosCerrarSesion.cancelar,
      principal: hayPendientes,
      onPressed: cerrando ? null : () => Navigator.of(context).pop(),
    );
    final reintentarConteo = _Boton(
      clave: const Key('configuracion_reintentar_conteo'),
      texto: _contando ? TextosCerrarSesion.revisando : TextosCerrarSesion.reintentar,
      principal: true,
      cargando: _contando,
      onPressed: _contando || cerrando ? null : _recontar,
    );
    final cierre = switch (_fase) {
      _Fase.error => _Boton(
        clave: const Key('configuracion_reintentar'),
        texto: TextosCerrarSesion.reintentar,
        principal: true,
        onPressed: _cerrar,
      ),
      _Fase.cerrando => const _Boton(
        clave: Key('configuracion_dialogo_confirmar'),
        texto: TextosCerrarSesion.cerrando,
        principal: true,
        cargando: true,
        onPressed: null,
      ),
      _Fase.confirmar => _Boton(
        clave: const Key('configuracion_dialogo_confirmar'),
        texto: hayPendientes || sinRevisar
            ? TextosCerrarSesion.confirmarIgual
            : TextosCerrarSesion.confirmar,
        principal: !hayPendientes && !sinRevisar,
        onPressed: _contando ? null : _cerrar,
      ),
    };

    return PopScope(
      canPop: !cerrando,
      child: SingleChildScrollView(
        child: Padding(
          key: const Key('configuracion_dialogo_cierre'),
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
              Semantics(
                header: true,
                child: Text(TextosCerrarSesion.titulo, style: theme.textTheme.headlineSmall),
              ),
              if (_fase == _Fase.error)
                _Aviso(
                  key: const Key('configuracion_error_cierre'),
                  color: theme.colorScheme.error,
                  marca: '!',
                  texto: TextosCerrarSesion.errorCierre,
                )
              else if (sinRevisar)
                const _Aviso(
                  key: Key('configuracion_aviso_sin_revisar'),
                  color: Color(0xFF8A6A22),
                  marca: '?',
                  texto: TextosCerrarSesion.sinRevisar,
                )
              else if (pendientes != null && pendientes > 0)
                _Aviso(
                  key: const Key('configuracion_aviso_pendientes'),
                  color: const Color(0xFF8A6A22),
                  marca: '$pendientes',
                  texto: TextosCerrarSesion.advertenciaPendientes(pendientes),
                )
              else ...[
                Text(
                  TextosCerrarSesion.datosGuardados,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                ),
                if (!cerrando) const _TodoSincronizado(),
              ],
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: 10,
                children: sinRevisar && widget.contar != null
                    ? [reintentarConteo, cierre, cancelar]
                    : hayPendientes
                    ? [cancelar, cierre]
                    : [cierre, cancelar],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TodoSincronizado extends StatelessWidget {
  const _TodoSincronizado();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      key: const Key('configuracion_todo_sincronizado'),
      spacing: 8,
      children: [
        ExcludeSemantics(child: Icon(Icons.check_circle_outline, color: theme.colorScheme.primary)),
        Flexible(
          child: Text(
            TextosCerrarSesion.todoSincronizado,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Aviso con marca (número de pendientes o «!») y borde del color del aviso.
class _Aviso extends StatelessWidget {
  const _Aviso({super.key, required this.color, required this.marca, required this.texto});

  final Color color;
  final String marca;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 12,
          children: [
            ExcludeSemantics(
              child: Container(
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
                child: Text(
                  marca,
                  style: theme.textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
            ),
            Expanded(child: Text(texto, style: theme.textTheme.bodyMedium?.copyWith(height: 1.45))),
          ],
        ),
      ),
    );
  }
}

class _Boton extends StatelessWidget {
  const _Boton({
    this.clave,
    required this.texto,
    required this.principal,
    required this.onPressed,
    this.cargando = false,
  });

  final Key? clave;
  final String texto;
  final bool principal;
  final bool cargando;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final escala = MediaQuery.textScalerOf(context).scale(15);
    final forma = escala > 20
        ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        : const StadiumBorder();
    const minimo = Size.fromHeight(52);
    final contenido = cargando
        ? Row(
            mainAxisAlignment: MainAxisAlignment.center,
            spacing: 10,
            children: [
              const SizedBox.square(
                dimension: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              ),
              Flexible(child: Text(texto, textAlign: TextAlign.center)),
            ],
          )
        : Text(texto, textAlign: TextAlign.center);
    final tema = Theme.of(context);
    return principal
        ? FilledButton(
            key: clave,
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              minimumSize: minimo,
              shape: forma,
              disabledBackgroundColor: tema.colorScheme.primary.withValues(alpha: .85),
              disabledForegroundColor: Colors.white,
            ),
            child: contenido,
          )
        : OutlinedButton(
            key: clave,
            onPressed: onPressed,
            style: OutlinedButton.styleFrom(
              minimumSize: minimo,
              shape: forma,
              side: BorderSide(color: tema.extension<ColoresColportaje>()!.bordeInput),
            ),
            child: contenido,
          );
  }
}
