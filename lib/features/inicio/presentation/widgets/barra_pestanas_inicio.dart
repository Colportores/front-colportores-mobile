import 'package:flutter/material.dart';

/// Las pestañas de la barra inferior, en el orden del diseño (vista 20, #229).
enum PestanaInicio {
  hoy('Hoy', Icons.home_outlined, Icons.home),
  mapa('Mapa', Icons.map_outlined, Icons.map),
  lista('Lista', Icons.format_list_bulleted, Icons.format_list_bulleted),
  agenda('Agenda', Icons.calendar_month_outlined, Icons.calendar_month),
  ventas('Ventas', Icons.payments_outlined, Icons.payments);

  const PestanaInicio(this.etiqueta, this.icono, this.iconoActivo);

  final String etiqueta;
  final IconData icono;
  final IconData iconoActivo;
}

/// Las pestañas que una cuenta pendiente de asignación no puede abrir (todas menos «Hoy»).
const modulosDeCampo = {
  PestanaInicio.mapa,
  PestanaInicio.lista,
  PestanaInicio.agenda,
  PestanaInicio.ventas,
};

/// La barra inferior Hoy · Mapa · Lista · Agenda · Ventas. La arma la pantalla principal (#229) y
/// la reutiliza Configuración (vista 16), donde ninguna pestaña está activa ([seleccionada] `null`).
///
/// Con la cuenta pendiente de asignación (vista 18) los módulos de campo van [bloqueadas]: se ven
/// con un candado y tocarlos le explica al colportor por qué no están disponibles ([onSeleccionar]
/// también se llama con ellas: quien la arma decide qué decir).
class BarraPestanasInicio extends StatelessWidget {
  const BarraPestanasInicio({
    super.key,
    required this.onSeleccionar,
    this.seleccionada,
    this.bloqueadas = const {},
  });

  final PestanaInicio? seleccionada;
  final Set<PestanaInicio> bloqueadas;
  final ValueChanged<PestanaInicio> onSeleccionar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esquema = theme.colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: esquema.surfaceContainerHighest,
        border: Border(top: BorderSide(color: theme.dividerTheme.color ?? esquema.outline)),
      ),
      child: NavigationBar(
        key: const Key('inicio_barra'),
        height: 64,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: (seleccionada ?? PestanaInicio.hoy).index,
        onDestinationSelected: (i) => onSeleccionar(PestanaInicio.values[i]),
        destinations: [
          for (final pestana in PestanaInicio.values)
            NavigationDestination(
              key: Key('inicio_pestana_${pestana.name}'),
              icon: bloqueadas.contains(pestana)
                  ? Semantics(label: 'Bloqueado', child: const Icon(Icons.lock_outline, size: 20))
                  : Icon(pestana.icono),
              selectedIcon: seleccionada == null
                  ? Icon(pestana.icono)
                  : Icon(pestana.iconoActivo, color: esquema.primary),
              label: pestana.etiqueta,
            ),
        ],
      ),
    );
  }
}
