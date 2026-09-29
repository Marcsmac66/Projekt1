#!/bin/bash
# Verbindet jede neue Sitzung mit Atlas: sucht den API-Schlüssel in der
# Umgebung, stellt ATLAS_API_KEY/ATLAS_BASE_URL bereit und lädt den
# Mitglieder-Bootstrap (GET /api/me/bootstrap) als Sitzungskontext.
# Der Schlüssel selbst wird nie ausgegeben.
set -uo pipefail

ATLAS_BASE_URL="${ATLAS_BASE_URL:-https://sharify-media-fzco-atlas.s2.sac.run/api}"

# Schlüssel finden: bevorzugte Namen, sonst jede Variable mit Wert atl_...
key=""
for name in ATLAS_API_KEY ATLAS_KEY ATLAS_TOKEN ATLAS_API_TOKEN; do
  if [ -n "${!name:-}" ]; then key="${!name}"; break; fi
done
if [ -z "$key" ]; then
  key="$(env | sed -n 's/^[A-Za-z_][A-Za-z0-9_]*=\(atl_[A-Za-z0-9_-]\{20,\}\)$/\1/p' | head -n1)"
fi

if [ -z "$key" ]; then
  echo "Atlas: Kein API-Schlüssel in der Umgebung gefunden (erwartet ATLAS_API_KEY). Bitte im Cloud-Environment hinterlegen und eine neue Sitzung starten."
  exit 0
fi

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    printf 'export ATLAS_API_KEY=%q\n' "$key"
    printf 'export ATLAS_BASE_URL=%q\n' "$ATLAS_BASE_URL"
  } >> "$CLAUDE_ENV_FILE"
fi

source_arg="$(cat 2>/dev/null | sed -n 's/.*"source"[[:space:]]*:[[:space:]]*"\([a-z]*\)".*/\1/p' | head -n1)"
case "$source_arg" in startup|resume|compact) ;; *) source_arg="startup" ;; esac

tmp="$(mktemp)"
code="$(curl -sS --max-time 20 -o "$tmp" -w '%{http_code}' \
  -H "Authorization: Bearer $key" \
  "$ATLAS_BASE_URL/me/bootstrap?format=json&source=$source_arg" 2>/dev/null || echo 000)"

if [ "$code" != "200" ]; then
  echo "Atlas: Bootstrap fehlgeschlagen (HTTP $code). Schlüssel in ATLAS_API_KEY prüfen."
  rm -f "$tmp"; exit 0
fi

echo "# Atlas verbunden"
echo "API: \$ATLAS_BASE_URL ($ATLAS_BASE_URL), Header: Authorization: Bearer \$ATLAS_API_KEY. Schlüssel nie ausgeben oder committen."
echo "Regeln: Envelope { data, meta?, error? }, Listen per cursor+limit; kein Hard-Delete (archivedAt bzw. /archive); Kontakte unter /api/companies/contacts; Aufgaben immer mit assigneeIds und definitionOfDone anlegen. Unbekannte Endpunkte: GET /api/<bereich>/info."
echo
python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["data"]["text"])' "$tmp" 2>/dev/null \
  || echo "(Bootstrap geladen, Text nicht lesbar)"
rm -f "$tmp"
exit 0
