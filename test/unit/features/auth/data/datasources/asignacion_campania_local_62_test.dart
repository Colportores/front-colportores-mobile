// De dónde sale la campaña y la zona de «Ya te asignaron» (vista 18, 18-A07, #62): de las réplicas
// locales del pull, sin red y sin inventar nada.
import 'package:colportores_mobile/features/auth/data/datasources/asignacion_campania_data_source.dart';
import 'package:colportores_mobile/features/auth/data/datasources/fakes/campanias_inscriptas_en_memoria.dart';
import 'package:colportores_mobile/features/auth/domain/entities/asignacion_campania.dart';
import 'package:colportores_mobile/features/auth/domain/entities/campania_inscripta.dart';
import 'package:flutter_test/flutter_test.dart';

/// Viernes 20/11/2026, 12:00 en Montevideo.
final _ahora = DateTime.utc(2026, 11, 20, 15);

CampaniaInscripta _campania(
  String id, {
  String inicio = '2026-10-01',
  String? fin = '2027-02-28',
  String? zona,
  String? ciudad,
}) => CampaniaInscripta(
  campaniaId: id,
  nombre: 'Campaña $id',
  fechaInicio: inicio,
  fechaFin: fin,
  zona: zona,
  ciudad: ciudad,
);

void main() {
  late CampaniasInscriptasEnMemoria campanias;
  String? usuario = 'col-1';

  AsignacionCampaniaLocal fuente() =>
      AsignacionCampaniaLocal(campanias, usuarioId: () => usuario, ahora: () => _ahora);

  setUp(() {
    campanias = CampaniasInscriptasEnMemoria();
    usuario = 'col-1';
  });

  test('la campaña en curso con su zona y su ciudad', () async {
    campanias.publicar([_campania('a', zona: 'Centro', ciudad: 'Montevideo')]);

    expect(
      await fuente().consultar(),
      const AsignacionCampania(campania: 'Campaña a', zona: 'Centro', ciudad: 'Montevideo'),
    );
  });

  test('el nombre de la zona sin el prefijo «Zona» (la pantalla lo pone)', () async {
    campanias.publicar([_campania('a', zona: 'Zona Centro', ciudad: 'Montevideo')]);

    expect((await fuente().consultar())?.zona, 'Centro');
  });

  test('una zona que se llama solo «Zona» queda como se llama', () async {
    campanias.publicar([_campania('a', zona: 'Zona', ciudad: 'Montevideo')]);

    expect((await fuente().consultar())?.zona, 'Zona');
  });

  test('inscripto «sin zona»: solo la campaña, sin zona ni ciudad inventadas', () async {
    campanias.publicar([_campania('a')]);

    expect(await fuente().consultar(), const AsignacionCampania(campania: 'Campaña a'));
  });

  test('la inscripta en una campaña por empezar: esa (Agustín, la del 1/12)', () async {
    campanias.publicar([
      _campania('a', inicio: '2026-12-01', zona: 'Centro', ciudad: 'Montevideo'),
    ]);

    expect((await fuente().consultar())?.campania, 'Campaña a');
  });

  test('con una en curso y otra por empezar, la que está en curso', () async {
    campanias.publicar([_campania('proxima', inicio: '2026-12-01'), _campania('en-curso')]);

    expect((await fuente().consultar())?.campania, 'Campaña en-curso');
  });

  test('sin inscripciones: null (la pantalla sale sin los renglones)', () async {
    campanias.publicar(const []);

    expect(await fuente().consultar(), isNull);
  });

  test('la que ya terminó no cuenta: null', () async {
    campanias.publicar([_campania('a', inicio: '2026-01-01', fin: '2026-02-28')]);

    expect(await fuente().consultar(), isNull);
  });

  test('todavía no se sabe (el pull no trajo la campaña): null, nunca un dato inventado', () async {
    campanias.publicar(null);

    expect(await fuente().consultar(), isNull);
  });

  test('sin sesión: null y ni siquiera lee', () async {
    usuario = null;
    campanias.publicar([_campania('a')]);

    expect(await fuente().consultar(), isNull);
    expect(campanias.suscripciones, 0);
  });

  test('si la lectura falla, la falla llega a quien la pidió (la pantalla sale igual)', () async {
    campanias.falla = StateError('falló la lectura');

    await expectLater(fuente().consultar(), throwsStateError);
  });
}
