import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/domain/entities/auditoria.dart';
import '../../../agenda/domain/entities/visita.dart' show TipoResultadoVisita;
import '../../domain/entities/ficha_de_persona.dart';
import '../../domain/entities/persona.dart';
import '../../domain/repositories/ficha_persona_repository.dart';
import 'audit_log_table.dart';

/// [FichaPersonaRepository] leído de la DB cifrada: la persona, y sus visitas y ventas a través de
/// todos sus vínculos `espacio_persona` (también los dados de baja: lo que pasó con ella no se pierde
/// porque ya no esté en ese depto).
///
/// Solo lee, salvo la auditoría de las llamadas. `watch` de Drift sobre todas las tablas que la ficha
/// mira: cualquier cambio vuelve a leer todo, que son filas chicas (una visita o una venta pesa pocos
/// bytes) y por eso no se pagina en la consulta sino en la pantalla.
final class FichaPersonaLocalDataSourceDrift {
  FichaPersonaLocalDataSourceDrift(this._db);

  final AppDatabase _db;

  /// Cuántos ids lleva cada consulta: SQLite admite 32.766 variables por sentencia; el tope es solo un
  /// resguardo.
  static const _porConsulta = 500;

  Stream<LecturaDeFicha?> observar(String personaId) {
    final cambios = _db.customSelect(
      'SELECT 1',
      readsFrom: {
        _db.personas,
        _db.espacioPersonas,
        // El lugar (baja o reactivación del depto o de la ubicación) cambia si la ficha es de solo lectura.
        _db.espacios,
        _db.ubicaciones,
        _db.visitas,
        _db.ventas,
        _db.ventaItems,
        _db.productos,
        _db.colecciones,
      },
    );
    return cambios.watch().asyncMap((_) => _leer(personaId));
  }

  Future<LecturaDeFicha?> _leer(String personaId) async {
    final fila = await (_db.select(
      _db.personas,
    )..where((p) => p.id.equals(personaId))).getSingleOrNull();
    if (fila == null) return null;
    final vinculos = [
      for (final v in await (_db.select(
        _db.espacioPersonas,
      )..where((v) => v.personaId.equals(personaId))).get())
        v.id,
    ];
    final movimientos = <MovimientoDeFicha>[...await _visitas(vinculos), ...await _ventas(vinculos)]
      ..sort(_masNuevoPrimero);
    return LecturaDeFicha(persona: _aPersona(fila), historial: List.unmodifiable(movimientos));
  }

  static int _masNuevoPrimero(MovimientoDeFicha a, MovimientoDeFicha b) {
    final porFecha = b.fecha.compareTo(a.fecha);
    return porFecha != 0 ? porFecha : b.id.compareTo(a.id);
  }

  Future<List<MovimientoDeFicha>> _visitas(List<String> vinculos) async {
    final salida = <MovimientoDeFicha>[];
    for (final lote in _lotes(vinculos)) {
      final filas = await (_db.select(
        _db.visitas,
      )..where((v) => v.espacioPersonaId.isIn(lote) & v.deletedAt.isNull())).get();
      for (final f in filas) {
        salida.add(
          VisitaEnFicha(
            id: f.id,
            fecha: f.fecha,
            resultado: TipoResultadoVisita.desdeCodigo(f.tipoResultado),
          ),
        );
      }
    }
    return salida;
  }

  Future<List<MovimientoDeFicha>> _ventas(List<String> vinculos) async {
    final salida = <MovimientoDeFicha>[];
    for (final lote in _lotes(vinculos)) {
      final ventas = await (_db.select(
        _db.ventas,
      )..where((v) => v.espacioPersonaId.isIn(lote) & v.deletedAt.isNull())).get();
      if (ventas.isEmpty) continue;
      final lineasPorVenta = await _lineas([for (final v in ventas) v.id]);
      for (final v in ventas) {
        salida.add(
          VentaEnFicha(
            id: v.id,
            fecha: v.fecha,
            numeroTalonario: v.numeroTalonario,
            montoCentavos: v.montoTotal,
            lineas: lineasPorVenta[v.id] ?? const [],
          ),
        );
      }
    }
    return salida;
  }

  /// Los renglones de cada venta con el nombre del producto o de la colección. Un producto que el
  /// catálogo ya no trae (la réplica es de solo lectura) queda como «Producto»: no se inventa un nombre.
  Future<Map<String, List<LineaDeFicha>>> _lineas(List<String> ventaIds) async {
    final salida = <String, List<LineaDeFicha>>{};
    for (final lote in _lotes(ventaIds)) {
      final items =
          await (_db.select(_db.ventaItems)
                ..where((i) => i.ventaId.isIn(lote) & i.deletedAt.isNull())
                ..orderBy([(i) => OrderingTerm.asc(i.createdAt), (i) => OrderingTerm.asc(i.id)]))
              .get();
      if (items.isEmpty) continue;
      final productos = await _nombresDeProductos([
        for (final i in items)
          if (i.productoId != null) i.productoId!,
      ]);
      final colecciones = await _nombresDeColecciones([
        for (final i in items)
          if (i.coleccionId != null) i.coleccionId!,
      ]);
      for (final i in items) {
        final nombre = i.productoId != null
            ? productos[i.productoId] ?? 'Producto'
            : colecciones[i.coleccionId] ?? 'Colección';
        (salida[i.ventaId] ??= []).add(LineaDeFicha(nombre: nombre, cantidad: i.cantidad));
      }
    }
    return salida;
  }

  Future<Map<String, String>> _nombresDeProductos(List<String> ids) async {
    final salida = <String, String>{};
    for (final lote in _lotes(ids.toSet().toList())) {
      final filas = await (_db.select(_db.productos)..where((p) => p.id.isIn(lote))).get();
      for (final f in filas) {
        salida[f.id] = f.nombre;
      }
    }
    return salida;
  }

  Future<Map<String, String>> _nombresDeColecciones(List<String> ids) async {
    final salida = <String, String>{};
    for (final lote in _lotes(ids.toSet().toList())) {
      final filas = await (_db.select(_db.colecciones)..where((c) => c.id.isIn(lote))).get();
      for (final f in filas) {
        salida[f.id] = f.nombre;
      }
    }
    return salida;
  }

  Iterable<List<String>> _lotes(List<String> ids) sync* {
    for (var desde = 0; desde < ids.length; desde += _porConsulta) {
      yield ids.sublist(desde, (desde + _porConsulta).clamp(0, ids.length));
    }
  }

  /// El evento `click_to_call` con el id de la persona, sin el número ni nada de sus datos.
  Future<void> registrarLlamada({required String personaId, required DateTime ahora}) => _db
      .into(_db.auditLogLocal)
      .insert(
        AuditLogLocalCompanion.insert(
          evento: EventoAuditoriaLocal.clickToCall,
          uuid: personaId,
          creadoEn: ahora,
        ),
      );

  static Persona _aPersona(PersonaFila fila) => Persona(
    id: fila.id,
    nombre: fila.nombre,
    apellido: fila.apellido,
    telefono: fila.telefono,
    notasGlobales: fila.notasGlobales,
    auditoria: Auditoria(
      createdAt: fila.createdAt,
      updatedAt: fila.updatedAt,
      createdBy: fila.createdBy,
      deletedAt: fila.deletedAt,
      syncVersion: fila.syncVersion,
    ),
  );
}
