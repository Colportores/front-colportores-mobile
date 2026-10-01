// El nombre del usuario en la sesión (#243): dato personal, nunca en `toString` ni en logs.
import 'package:colportores_mobile/features/auth/data/models/sesion_model.dart';
import 'package:colportores_mobile/features/auth/domain/entities/sesion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final expira = DateTime.utc(2026, 10, 30);

  Sesion sesion({String? nombre}) => Sesion(
    usuarioId: 'u-1',
    email: 'ana@example.com',
    accessToken: 'jwt-secreto',
    expiraEn: expira,
    nombre: nombre,
  );

  test('dado un nombre, cuando se imprime la sesión, el nombre no aparece', () {
    final texto = sesion(nombre: 'Lucía Silva').toString();

    expect(texto, isNot(contains('Lucía')));
    expect(texto, isNot(contains('Silva')));
    expect(texto, isNot(contains('jwt-secreto')));
    expect('${SesionModel.fromEntity(sesion(nombre: 'Lucía'))}', isNot(contains('Lucía')));
  });

  test('dos sesiones que solo difieren en el nombre no son iguales', () {
    expect(sesion(nombre: 'Lucía'), isNot(sesion(nombre: 'Ana')));
    expect(sesion(nombre: 'Lucía'), sesion(nombre: 'Lucía'));
  });

  test('el nombre viaja en el modelo: ida y vuelta por JSON y a la entidad', () {
    final modelo = SesionModel.fromEntity(sesion(nombre: 'Lucía'));

    final vuelta = SesionModel.fromJson(modelo.toJson());

    expect(vuelta.nombre, 'Lucía');
    expect(vuelta.toEntity(), sesion(nombre: 'Lucía'));
  });

  test('una sesión guardada antes de #243 no trae nombre y se lee sin él', () {
    final json = SesionModel.fromEntity(sesion()).toJson()..remove('nombre');

    expect(SesionModel.fromJson(json).nombre, isNull);
  });
}
