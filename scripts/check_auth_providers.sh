#!/usr/bin/env bash
# Smoke test de la configuración de Supabase Auth (HU-AUTH-003, #22): consulta el endpoint
# público /auth/v1/settings y verifica que los proveedores estén como los espera la app:
#   email = true · google = true · apple = false (iOS desactivado en esta etapa)
# Sin SUPABASE_URL / SUPABASE_ANON_KEY sale 0 con aviso: no bloquea a quien no tiene proyecto.
#
# Uso: SUPABASE_URL=https://xxx.supabase.co SUPABASE_ANON_KEY=... bash scripts/check_auth_providers.sh
set -euo pipefail

if [ -z "${SUPABASE_URL:-}" ] || [ -z "${SUPABASE_ANON_KEY:-}" ]; then
  echo "▷ check_auth_providers omitido: faltan SUPABASE_URL y/o SUPABASE_ANON_KEY"
  exit 0
fi

settings="$(curl -sS --fail --max-time 20 "${SUPABASE_URL%/}/auth/v1/settings" -H "apikey: $SUPABASE_ANON_KEY")" \
  || { echo "✗ no se pudo leer $SUPABASE_URL/auth/v1/settings" >&2; exit 1; }

# `jq` si está en la imagen; si no, grep sobre el JSON compacto que devuelve GoTrue.
leer() { # $1 = proveedor → imprime true/false
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$settings" | jq -r ".external.$1"
  else
    printf '%s' "$settings" | grep -o "\"$1\":[a-z]*" | head -n 1 | cut -d: -f2
  fi
}

estado=0
verificar() { # $1 = proveedor, $2 = valor esperado
  local real; real="$(leer "$1")"
  if [ "$real" = "$2" ]; then
    echo "✓ external.$1 = $2"
  else
    echo "✗ external.$1 = '${real:-?}' (esperado $2) — Supabase → Authentication → Providers" >&2
    estado=1
  fi
}

verificar email true
verificar google true
verificar apple false
exit "$estado"
