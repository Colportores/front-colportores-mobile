import 'dart:async';

import 'package:colportores_mobile/core/error/failure.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/catalogo_local.dart';
import 'package:colportores_mobile/features/catalogo/domain/entities/ciudad_consultable.dart';
import 'package:colportores_mobile/features/catalogo/domain/repositories/consulta_de_precios_repository.dart';
import 'package:colportores_mobile/features/catalogo/domain/repositories/fecha_de_los_precios.dart';
import 'package:colportores_mobile/features/catalogo/domain/repositories/fuente_de_ciudades_para_precios.dart';
import 'package:dartz/dartz.dart';

/// Las ciudades de las campañas de la colportora de los tests (coinciden con `montevideo` y
/// `canelones` de `alta_ubicacion_falsos.dart`, que usa el GPS falso).
const cMontevideo = CiudadConsultable(
  campaniaCiudadId: 'cc-mvd',
  ciudadId: 'ciu-mvd',
  nombre: 'Montevideo',
  campaniaNombre: 'Primavera 2026',
);
const cCanelones = CiudadConsultable(
  campaniaCiudadId: 'cc-can',
  ciudadId: 'ciu-can',
  nombre: 'Canelones',
  campaniaNombre: 'Primavera 2026',
);

/// Un catálogo chico con todo lo que muestran los artboards de la vista 26.
CatalogoLocal catalogoDeLaVista26() => const CatalogoLocal(
  productos: [
    ProductoDelCatalogo(
      id: 'p-deseado',
      nombre: 'El Deseado de Todas las Gentes',
      tipo: TipoDeProducto.libro,
      esBonificable: true,
      codigoEditor: 'ACES-0214',
    ),
    ProductoDelCatalogo(
      id: 'p-camino',
      nombre: 'El Camino a Cristo',
      tipo: TipoDeProducto.libro,
      esBonificable: true,
    ),
    ProductoDelCatalogo(
      id: 'p-misionero',
      nombre: 'Misionero Esperanza',
      tipo: TipoDeProducto.misionero,
      esMisionero: true,
    ),
    ProductoDelCatalogo(
      id: 'p-revista',
      nombre: 'Revista Vida y Salud',
      tipo: TipoDeProducto.revista,
    ),
    ProductoDelCatalogo(id: 'p-sin-precio', nombre: 'Libro sin precio', tipo: TipoDeProducto.libro),
    ProductoDelCatalogo(
      id: 'p-material',
      nombre: 'Folleto de la casa',
      tipo: TipoDeProducto.material,
    ),
  ],
  combos: [
    ComboDelCatalogo(
      id: 'k-2',
      nombre: 'Colección de 2 libros',
      librosAElegir: 2,
      componentes: [
        ComponenteDelCombo(productoId: 'p-misionero'),
        ComponenteDelCombo(productoId: 'p-revista'),
      ],
    ),
    ComboDelCatalogo(
      id: 'k-fijo',
      nombre: 'Pack Familia',
      componentes: [ComponenteDelCombo(productoId: 'p-camino', cantidad: 2)],
    ),
  ],
  excepciones: [
    PrecioDelCatalogo(
      id: 'e-deseado',
      productoId: 'p-deseado',
      centavos: 480000,
      validoDesde: '2026-01-01',
    ),
    PrecioDelCatalogo(id: 'e-k2', comboId: 'k-2', centavos: 890000, validoDesde: '2026-01-01'),
  ],
  generales: [
    PrecioDelCatalogo(
      id: 'g-deseado',
      productoId: 'p-deseado',
      centavos: 500000,
      validoDesde: '2026-01-01',
    ),
    PrecioDelCatalogo(
      id: 'g-camino',
      productoId: 'p-camino',
      centavos: 120000,
      validoDesde: '2026-01-01',
    ),
    PrecioDelCatalogo(
      id: 'g-misionero',
      productoId: 'p-misionero',
      centavos: 45000,
      validoDesde: '2026-01-01',
    ),
    PrecioDelCatalogo(
      id: 'g-revista',
      productoId: 'p-revista',
      centavos: 25000,
      validoDesde: '2026-01-01',
    ),
    PrecioDelCatalogo(
      id: 'g-k-fijo',
      comboId: 'k-fijo',
      centavos: 300000,
      validoDesde: '2026-01-01',
    ),
  ],
);

/// Un catálogo de [n] libros, cada uno con su precio general: para las listas largas.
CatalogoLocal catalogoLargo(int n, {String prefijo = 'Libro'}) => CatalogoLocal(
  productos: [
    for (var i = 0; i < n; i++)
      ProductoDelCatalogo(
        id: 'p$i',
        nombre: '$prefijo ${i.toString().padLeft(4, '0')}',
        tipo: TipoDeProducto.libro,
      ),
  ],
  generales: [
    for (var i = 0; i < n; i++)
      PrecioDelCatalogo(
        id: 'g$i',
        productoId: 'p$i',
        centavos: 10000 + i,
        validoDesde: '2026-01-01',
      ),
  ],
);

/// La réplica del catálogo, que el test controla: qué devuelve para cada ciudad, cuánto tarda y si
/// falla.
final class ConsultaDePreciosFalsa implements ConsultaDePreciosRepository {
  ConsultaDePreciosFalsa([CatalogoLocal? catalogo]) : catalogo = catalogo ?? catalogoDeLaVista26();

  /// Lo que devuelve para cualquier ciudad que no esté en [porCiudad].
  CatalogoLocal catalogo;
  final porCiudad = <String, CatalogoLocal>{};

  /// Si no es `null`, la lectura espera a que se complete.
  Completer<void>? bloqueo;

  /// Cuántas lecturas fallan antes de que una salga bien.
  var fallas = 0;
  final pedidos = <String>[];

  @override
  Stream<CatalogoLocal> observar(String campaniaCiudadId) async* {
    pedidos.add(campaniaCiudadId);
    final espera = bloqueo;
    if (espera != null) await espera.future;
    if (fallas > 0) {
      fallas--;
      throw const FailurePreciosNoDisponibles();
    }
    yield porCiudad[campaniaCiudadId] ?? catalogo;
  }
}

/// Las ciudades de la colportora, que el test controla.
final class FuenteDeCiudadesFalsa implements FuenteDeCiudadesParaPrecios {
  FuenteDeCiudadesFalsa([ContextoDeCiudades? contexto])
    : respuesta = Right(
        contexto ??
            const ContextoDeCiudades(
              ciudades: [cMontevideo, cCanelones],
              ciudadDeMiZonaId: 'ciu-mvd',
            ),
      );

  Either<Failure, ContextoDeCiudades> respuesta;

  /// Cuántas lecturas fallan antes de que una salga bien.
  var fallas = 0;
  var lecturas = 0;
  Completer<void>? bloqueo;

  @override
  Future<Either<Failure, ContextoDeCiudades>> leer(String colportorId) async {
    lecturas++;
    final espera = bloqueo;
    if (espera != null) await espera.future;
    if (fallas > 0) {
      fallas--;
      return const Left(FailurePreciosNoDisponibles());
    }
    return respuesta;
  }
}

/// La fecha de la última bajada de precios.
final class FechaDeLosPreciosFalsa implements FechaDeLosPrecios {
  FechaDeLosPreciosFalsa(this.fecha);

  DateTime? fecha;

  @override
  Future<DateTime?> ultimaBajada() async => fecha;
}

/// Los N días del aviso fuerte.
final class DiasFalsos implements DiasDeAntiguedadDePrecios {
  DiasFalsos(this.valor);

  int valor;

  @override
  Future<int> dias() async => valor;
}
