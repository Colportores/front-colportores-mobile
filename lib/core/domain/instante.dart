/// El instante [t] en UTC y truncado al milisegundo.
///
/// Es la precisión de la DB local (epoch ms, 08-conceptos-transversales §8.11): sin truncar, la
/// entidad en memoria tendría microsegundos, la fila releída de Drift no, y el payload de sync
/// (`.123999Z`) no coincidiría con ninguna de las dos. Lo aplican en su constructor todas las
/// entidades con instantes —`Auditoria`, `Jornada` y las que vengan—, así que cubre `now()`, la
/// hora elegida a mano y lo que llega del cloud sin que cada caso de uso se acuerde de truncar
/// (decisión de Cristian del 23/09 en #70).
DateTime instanteMs(DateTime t) =>
    DateTime.fromMillisecondsSinceEpoch(t.millisecondsSinceEpoch, isUtc: true);
