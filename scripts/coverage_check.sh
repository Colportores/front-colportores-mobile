#!/usr/bin/env bash
# Verifica los umbrales de cobertura de convenciones-desarrollo.md §6.4 sobre coverage/lcov.info:
#   total ≥ 70% (RA-MA02) · dominio (lib/**/domain/**) ≥ 90%
# Excluye código generado (*.g.dart, *.freezed.dart).
set -euo pipefail

ARCHIVO="${1:-coverage/lcov.info}"
UMBRAL_TOTAL="${UMBRAL_TOTAL:-70}"
UMBRAL_DOMINIO="${UMBRAL_DOMINIO:-90}"

[ -f "$ARCHIVO" ] || { echo "no existe $ARCHIVO — correr 'flutter test --coverage' antes" >&2; exit 1; }

lf=0; lh=0; lf_dom=0; lh_dom=0; skip=0; dom=0
while IFS= read -r linea; do
  case "$linea" in
    SF:*)
      f="${linea#SF:}"
      case "$f" in *.g.dart|*.freezed.dart) skip=1 ;; *) skip=0 ;; esac
      case "$f" in */domain/*) dom=1 ;; *) dom=0 ;; esac
      ;;
    LF:*)
      n="${linea#LF:}"
      if [ "$skip" -eq 0 ]; then lf=$((lf + n)); [ "$dom" -eq 1 ] && lf_dom=$((lf_dom + n)); fi
      ;;
    LH:*)
      n="${linea#LH:}"
      if [ "$skip" -eq 0 ]; then lh=$((lh + n)); [ "$dom" -eq 1 ] && lh_dom=$((lh_dom + n)); fi
      ;;
  esac
done < "$ARCHIVO"

pct() { if [ "$2" -eq 0 ]; then echo 0; else echo $(( $1 * 100 / $2 )); fi; }

total=$(pct "$lh" "$lf")
dominio=$(pct "$lh_dom" "$lf_dom")

echo "cobertura total:   $lh/$lf líneas = ${total}%  (umbral ${UMBRAL_TOTAL}%)"
echo "cobertura dominio: $lh_dom/$lf_dom líneas = ${dominio}%  (umbral ${UMBRAL_DOMINIO}%)"

estado=0
[ "$total" -ge "$UMBRAL_TOTAL" ] || { echo "✗ cobertura total por debajo del umbral" >&2; estado=1; }
[ "$dominio" -ge "$UMBRAL_DOMINIO" ] || { echo "✗ cobertura de dominio por debajo del umbral" >&2; estado=1; }
exit $estado
