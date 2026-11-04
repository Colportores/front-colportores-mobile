import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../cobranzas/data/datasources/cobranza_local_data_source_drift.dart';
import '../../../cobranzas/data/datasources/cobro_valido.dart';
import '../../domain/entities/detalle_de_mi_plata.dart';

/// Lee de las tablas `venta`, `cobranza`, `devolucion` y `persona` de la DB cifrada el detalle de «Mi
/// plata» (HU-CTA-003): qué clientes, en qué fecha y por cuánto hay detrás de En mano y Por cobrar.
///
/// Las cifras salen de las mismas cuentas que las de Mi Cuenta ([ResumenDeCuentaLocalDataSourceDrift]
/// y [CobranzaLocalDataSourceDrift]), así que cada lista suma lo que dice su tarjeta. Cada `Stream`
/// emite el valor de ahora al suscribirse y uno nuevo **solo si cambió**.
final class DetalleDeMiPlataLocalDataSourceDrift {
  /// [_cobranzas] se pasa como `cobranzas:`.
  DetalleDeMiPlataLocalDataSourceDrift(this._db, {required this._cobranzas});

  final AppDatabase _db;
  final CobranzaLocalDataSourceDrift _cobranzas;

  /// Cuando falta el nombre de la persona (todavía no bajó por el pull).
  static const clienteSinNombre = 'Cliente sin nombre';

  Set<ResultSetImplementation<dynamic, dynamic>> get _tablas => {
    _db.ventas,
    _db.cobranzas,
    _db.devoluciones,
    _db.espacioPersonas,
    _db.espacios,
    _db.ventaItems,
    _db.personas,
  };

  /// El detalle del colportor [colportorId], de nuevo cada vez que cambia algo que lo afecta.
  Stream<DetalleDeMiPlata> observar(String colportorId) => _db
      .customSelect('SELECT 1', readsFrom: _tablas)
      .watch()
      .asyncMap((_) => leer(colportorId))
      .distinct();

  /// El detalle de ahora.
  Future<DetalleDeMiPlata> leer(String colportorId) async {
    final clientes = await _clientesDe(colportorId);
    String nombreDe(String espacioPersonaId) =>
        clientes[espacioPersonaId]?.nombre ?? clienteSinNombre;

    // En mano: los cobros en efectivo vivos. Una venta dada de baja no resta: el efectivo que se cobró
    // sigue en la mano. Las devoluciones no tocan «En mano»: nunca queda plata a favor del cliente
    // (decisión de Cristian, 03/11, «Devol. saldo»).
    final cobros = await _db
        .customSelect(
          'SELECT c.monto AS monto, c.fecha AS fecha, v.espacio_persona_id AS ep FROM cobranza c '
          'JOIN venta v ON v.id = c.venta_id '
          "WHERE v.colportor_id = ? AND c.medio = 'EFECTIVO' AND ${CobroValido.sql} "
          'ORDER BY c.fecha, c.id',
          variables: [Variable<String>(colportorId)],
        )
        .get();
    final movimientos = [
      for (final f in cobros)
        MovimientoEnMano(
          cliente: nombreDe(f.read<String>('ep')),
          fecha: _fecha(f.read<int>('fecha')),
          centavos: f.read<int>('monto'),
        ),
    ]..sort((a, b) => a.fecha.compareTo(b.fecha));
    final sumaEnMano = movimientos.fold<int>(0, (suma, m) => suma + m.centavos);

    // Por cobrar: las cuentas de cada venta viva, sumadas por cliente.
    final ventas = await _cobranzas.cuentasDeLasVentasDe(colportorId);
    final porCobrar = <String, _Acumulado>{};
    for (final venta in ventas) {
      final saldo = venta.cuenta.saldoCentavos;
      if (saldo > 0) {
        (porCobrar[venta.espacioPersonaId] ??= _Acumulado()).sumar(saldo, venta.fecha);
      }
    }
    final saldosPorCobrar = _porCliente(porCobrar, clientes);

    return DetalleDeMiPlata(
      enManoCentavos: sumaEnMano,
      enMano: movimientos,
      porCobrarCentavos: saldosPorCobrar.fold<int>(0, (suma, s) => suma + s.centavos),
      porCobrar: saldosPorCobrar,
    );
  }

  /// Junta lo acumulado por vínculo en una fila por persona (un cliente puede tener más de un
  /// vínculo con un espacio), la deuda más vieja primero.
  List<SaldoDeCliente> _porCliente(
    Map<String, _Acumulado> porVinculo,
    Map<String, _Cliente> clientes,
  ) {
    final nombres = <String, String>{};
    final porPersona = <String, _Acumulado>{};
    for (final MapEntry(:key, :value) in porVinculo.entries) {
      final cliente = clientes[key];
      final personaId = cliente?.id ?? key;
      nombres[personaId] = cliente?.nombre ?? clienteSinNombre;
      (porPersona[personaId] ??= _Acumulado()).sumar(value.centavos, value.desde);
    }
    return [
      for (final MapEntry(:key, :value) in porPersona.entries)
        SaldoDeCliente(cliente: nombres[key]!, desde: value.desde, centavos: value.centavos),
    ]..sort((a, b) {
      final porFecha = a.desde.compareTo(b.desde);
      return porFecha != 0 ? porFecha : a.cliente.compareTo(b.cliente);
    });
  }

  /// El nombre de la persona de cada vínculo (`espacio_persona`) de las ventas del colportor,
  /// también si el vínculo o la persona se dieron de baja: la deuda sigue siendo suya (32D·03).
  Future<Map<String, _Cliente>> _clientesDe(String colportorId) async {
    final filas = await _db
        .customSelect(
          'SELECT DISTINCT ep.id AS ep, p.id AS persona, p.nombre AS nombre, p.apellido AS apellido '
          'FROM venta v JOIN espacio_persona ep ON ep.id = v.espacio_persona_id '
          'JOIN persona p ON p.id = ep.persona_id WHERE v.colportor_id = ?',
          variables: [Variable<String>(colportorId)],
        )
        .get();
    return {
      for (final f in filas)
        f.read<String>('ep'): _Cliente(
          id: f.read<String>('persona'),
          nombre: _nombreDe(f.read<String>('nombre'), f.read<String>('apellido')),
        ),
    };
  }

  /// Nombre y apellido juntos; «Cliente sin nombre» si los dos están en blanco.
  static String _nombreDe(String nombre, String apellido) {
    final completo = [nombre, apellido].where((p) => p.trim().isNotEmpty).join(' ');
    return completo.isEmpty ? clienteSinNombre : completo;
  }

  DateTime _fecha(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
}

/// Una persona a la que se le vendió.
final class _Cliente {
  const _Cliente({required this.id, required this.nombre});

  final String id;
  final String nombre;
}

/// Lo que se va sumando de un cliente: el total y la fecha más vieja.
final class _Acumulado {
  var centavos = 0;
  DateTime? _desde;

  DateTime get desde => _desde!;

  void sumar(int monto, DateTime fecha) {
    centavos += monto;
    if (_desde == null || fecha.isBefore(_desde!)) _desde = fecha;
  }
}
