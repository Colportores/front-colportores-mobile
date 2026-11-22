/// Con cuánta anticipación avisa el recordatorio de una visita (HU-NOT-002):
/// `usuario.notif_anticipacion_minutos`, global para el colportor.
abstract final class AnticipacionRecordatorio {
  /// Lo que vale mientras la persona no lo cambie (la pantalla de preferencias es #155).
  static const int porDefecto = 30;

  /// Lo más corto que se puede elegir (5 minutos).
  static const int minimo = 5;

  /// Lo más largo que se puede elegir (2 horas).
  static const int maximo = 120;

  /// [minutos] dentro de `[minimo, maximo]`. Un valor guardado fuera del rango (un dato viejo o
  /// dañado) no rompe nada: se lleva al extremo más cercano.
  static int acotar(int minutos) => minutos.clamp(minimo, maximo);
}
