import 'package:equatable/equatable.dart';

import '../entities/filtros_agenda.dart';
import '../entities/item_agenda.dart';
import '../entities/tipo_agenda.dart';
import '../entities/vista_agenda.dart';
import 'armador_agenda.dart';

/// Cuántas visitas agendadas hay de cada tipo: los números de la pestaña «Agendados N» y de los chips
/// «Todos N», «Cobranzas N», «Entrevistas N» y «Entregas N» (vista 06, 06C·03). Se cuentan sin el
/// filtro de tipo: el chip dice cuántas va a mostrar si se lo toca.
final class CuentasAgendados extends Equatable {
  const CuentasAgendados({this.porTipo = const {}});

  static const ninguna = CuentasAgendados();

  final Map<TipoAgenda, int> porTipo;

  /// Todas las agendadas («Agendados N», «Todos N»).
  int get todas => porTipo.values.fold(0, (suma, n) => suma + n);

  int de(TipoAgenda tipo) => porTipo[tipo] ?? 0;

  @override
  List<Object?> get props => [porTipo];
}

/// Lo que dibujan la hoja «Agendados» del mapa y el mapa de abajo (06C·03): la lista con el filtro de
/// tipo puesto, las cuentas de los chips y las ubicaciones a las que hay que ir (las que el mapa no
/// atenúa).
final class VistaAgendados extends Equatable {
  const VistaAgendados({required this.vista, required this.cuentas, required this.ubicaciones});

  static const vacia = VistaAgendados(
    vista: VistaAgenda.vacia,
    cuentas: CuentasAgendados.ninguna,
    ubicaciones: {},
  );

  /// Las atrasadas arriba y, debajo, cada día con sus visitas, por hora.
  final VistaAgenda vista;

  final CuentasAgendados cuentas;

  /// Los `id` de las ubicaciones de las visitas que se ven ([ItemAgenda.lugar]: la dirección
  /// alternativa de la cobranza si la tiene; si no, la casa). El mapa atenúa las demás.
  final Set<String> ubicaciones;

  @override
  List<Object?> get props => [vista, cuentas, ubicaciones];
}

/// Arma la hoja «Agendados» del mapa (HU-VIS-002, regla «Vista 06 (mapa)»: «es esta lista sobre el
/// mapa»). Son las mismas visitas que la pestaña Agenda con el estado «Pendientes» —las programadas de
/// hoy y los próximos 7 días, y las atrasadas arriba (23B·02)— ordenadas y agrupadas por
/// [ArmadorAgenda]; la hoja no tiene filtro de estado: lo que no está pendiente ya no es «agendado».
/// Es una función pura: la página la vuelve a correr cada vez que cambia lo leído, el filtro o el día.
abstract final class ArmadorAgendados {
  static VistaAgendados armar(List<ItemAgenda> items, TipoAgenda? tipo, DateTime ahora) {
    final todas = ArmadorAgenda.armar(items, FiltrosAgenda.porDefecto, ahora);
    final porTipo = <TipoAgenda, int>{};
    for (final item in _items(todas)) {
      porTipo.update(item.agenda.tipo, (n) => n + 1, ifAbsent: () => 1);
    }
    final vista = tipo == null
        ? todas
        : ArmadorAgenda.armar(items, FiltrosAgenda(tipo: tipo), ahora);
    return VistaAgendados(
      vista: vista,
      cuentas: CuentasAgendados(porTipo: porTipo),
      ubicaciones: {
        for (final item in _items(vista))
          if (item.lugar case final lugar?) lugar.ubicacionId,
      },
    );
  }

  static Iterable<ItemAgenda> _items(VistaAgenda vista) => [
    ...vista.atrasadas,
    for (final dia in vista.dias) ...dia.items,
  ];
}
