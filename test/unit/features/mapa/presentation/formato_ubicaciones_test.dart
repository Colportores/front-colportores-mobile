import 'package:colportores_mobile/core/domain/entities/auditoria.dart';
import 'package:colportores_mobile/features/mapa/domain/entities/ubicacion.dart';
import 'package:colportores_mobile/features/mapa/domain/value_objects/coordenadas.dart';
import 'package:colportores_mobile/features/mapa/presentation/formato_ubicaciones.dart';
import 'package:flutter_test/flutter_test.dart';

Ubicacion _u({String? calle, String? numero}) => Ubicacion(
  id: 'u',
  tipo: TipoUbicacion.casa,
  calle: calle,
  numero: numero,
  lat: -34.9,
  lon: -56.1,
  ciudadId: 'c',
  auditoria: Auditoria(createdAt: DateTime.utc(2026), updatedAt: DateTime.utc(2026)),
);

void main() {
  group('distancia', () {
    test('metros redondeados, nunca «0 m»', () {
      expect(FormatoUbicaciones.distancia(12.4), '12 m');
      expect(FormatoUbicaciones.distancia(0.2), '1 m');
      expect(FormatoUbicaciones.distancia(0), '1 m');
    });

    test('desde el kilómetro, en km con coma', () {
      expect(FormatoUbicaciones.distancia(1000), '1,0 km');
      expect(FormatoUbicaciones.distancia(1234), '1,2 km');
    });

    test('un valor que no es una distancia da vacío', () {
      expect(FormatoUbicaciones.distancia(double.nan), '');
      expect(FormatoUbicaciones.distancia(-3), '');
    });
  });

  group('direccion', () {
    test('calle y número', () {
      expect(
        FormatoUbicaciones.direccion(_u(calle: ' Av. Italia ', numero: '1234')),
        'Av. Italia 1234',
      );
    });

    test('solo uno de los dos', () {
      expect(FormatoUbicaciones.direccion(_u(calle: 'Av. Italia')), 'Av. Italia');
      expect(FormatoUbicaciones.direccion(_u(numero: '1234')), '1234');
    });

    test('ninguno o en blanco: «Sin dirección»', () {
      expect(FormatoUbicaciones.direccion(_u()), 'Sin dirección');
      expect(FormatoUbicaciones.direccion(_u(calle: '  ', numero: '')), 'Sin dirección');
    });
  });

  test('coordenadas con 5 decimales', () {
    expect(
      FormatoUbicaciones.coordenadas(const Coordenadas(lat: -34.887612, lon: -56.130244)),
      '-34.88761, -56.13024',
    );
  });

  test('tipo', () {
    expect(FormatoUbicaciones.tipo(TipoUbicacion.negocio), 'Negocio');
    expect(FormatoUbicaciones.tipo(TipoUbicacion.edificio), 'Edificio');
  });

  group('hace', () {
    final ahora = DateTime.utc(2026, 10, 2, 12);

    String hace(Duration d) => FormatoUbicaciones.hace(ahora.subtract(d), ahora);

    test('escalas', () {
      expect(FormatoUbicaciones.hace(ahora, ahora), 'hace un momento');
      expect(hace(const Duration(minutes: 1)), 'hace 1 minuto');
      expect(hace(const Duration(minutes: 45)), 'hace 45 minutos');
      expect(hace(const Duration(hours: 1)), 'hace 1 hora');
      expect(hace(const Duration(hours: 5)), 'hace 5 horas');
      expect(hace(const Duration(days: 1)), 'hace 1 día');
      expect(hace(const Duration(days: 3)), 'hace 3 días');
      expect(hace(const Duration(days: 45)), 'hace 1 mes');
      expect(hace(const Duration(days: 100)), 'hace 3 meses');
      expect(hace(const Duration(days: 400)), 'hace 1 año');
      expect(hace(const Duration(days: 800)), 'hace 2 años');
    });

    test('una fecha futura (reloj corrido) no da un número negativo', () {
      expect(FormatoUbicaciones.hace(ahora.add(const Duration(days: 2)), ahora), 'hace un momento');
    });
  });
}
