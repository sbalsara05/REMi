#!/usr/bin/env bash
# Seed REMi test agents + skills on a LibreChat account (idempotent).
# Usage:
#   ./scripts/seed-remi-test-data.sh
#   REMI_SEED_EMAIL=you@example.com REMI_SEED_PASSWORD=secret ./scripts/seed-remi-test-data.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/load-env.sh
source "$ROOT/scripts/load-env.sh"

BASE="${REMI_SEED_BASE_URL:-http://localhost:${PORT:-3080}}"
EMAIL="${REMI_SEED_EMAIL:-shourya0523@gmail.com}"
PASSWORD="${REMI_SEED_PASSWORD:-12345678}"
UA="${REMI_SEED_USER_AGENT:-Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36}"

TOKEN=$(curl -sf -X POST "$BASE/api/auth/login" \
  -H "Content-Type: application/json" -H "User-Agent: $UA" \
  -d "{\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")

auth=(-H "Authorization: Bearer $TOKEN" -H "User-Agent: $UA" -H "Content-Type: application/json")

agent_exists() {
  local name="$1"
  curl -sf "$BASE/api/agents?limit=50" "${auth[@]}" \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(any(a.get('name')=='''$name''' for a in d.get('data',[])))"
}

skill_exists() {
  local name="$1"
  curl -sf "$BASE/api/skills?limit=50" "${auth[@]}" \
    | python3 -c "
import sys,json
d=json.load(sys.stdin)
skills=d.get('skills', d.get('data', []))
print(any(s.get('name')=='''$name''' for s in skills))
"
}

create_agent() {
  local name="$1" desc="$2" instr="$3" model="$4"
  if [[ "$(agent_exists "$name")" == "True" ]]; then
    echo "  agent exists: $name"
    return 0
  fi
  curl -sf -X POST "$BASE/api/agents" "${auth[@]}" -d "$(python3 -c "
import json
print(json.dumps({
  'name': '''$name''',
  'description': '''$desc''',
  'instructions': '''$instr''',
  'provider': 'OpenRouter',
  'model': '''$model''',
  'tools': [],
}))
")" | python3 -c "import sys,json; d=json.load(sys.stdin); print('  created agent:', d.get('id', d))"
}

create_skill() {
  local name="$1" title="$2" desc="$3" body="$4"
  if [[ "$(skill_exists "$name")" == "True" ]]; then
    echo "  skill exists: $name"
    return 0
  fi
  curl -sf -X POST "$BASE/api/skills" "${auth[@]}" -d "$(python3 -c "
import json
print(json.dumps({
  'name': '''$name''',
  'displayTitle': '''$title''',
  'description': '''$desc''',
  'body': '''$body''',
}))
")" | python3 -c "import sys,json; d=json.load(sys.stdin); print('  created skill:', d.get('name', d))"
}

echo "Seeding REMi test data on $EMAIL @ $BASE"

echo "Agents..."
create_agent "Remi Helper" \
  "General REMi overlay test agent." \
  "You are Remi Helper. Be concise." \
  "anthropic/claude-sonnet-4"
create_agent "Code Reviewer" \
  "Reviews code snippets from screen captures." \
  "You review code for bugs, style, and security. Use bullet points." \
  "openai/gpt-4o-mini"
create_agent "Summarizer" \
  "Summarizes long text from hover context." \
  "Summarize clearly in 3-5 bullets. Preserve key facts." \
  "google/gemini-2.5-flash-preview"

echo "Skills..."
create_skill "summarize" "Summarize" \
  "Use when the user wants a short summary of text or screen context." \
  $'# Summarize\n\nProduce a tight summary of the provided content.\n\n## Output\n- 3-5 bullets\n- One-line takeaway at the end'
create_skill "explain-like-im-five" "Explain Like I'm 5" \
  "Use when the user asks for a simple explanation of a complex topic or jargon-heavy text." \
  $'# ELI5\n\nExplain using everyday analogies. Avoid jargon unless you define it in one sentence.'
create_skill "draft-reply" "Draft Reply" \
  "Use when the user needs help writing an email or message reply." \
  $'# Draft Reply\n\nWrite a polite, professional reply. Match the user tone. Offer 2 variants if useful.'
create_skill "debug-hint" "Debug Hint" \
  "Use when the user is stuck on a coding error and wants the next debugging step." \
  $'# Debug Hint\n\nDo not rewrite the whole program. Give the next 1-3 concrete steps to try.'

echo ""
echo "Catalog:"
curl -sf "$BASE/api/remi/catalog" "${auth[@]}" | python3 -m json.tool

DEFAULT_AGENT=$(curl -sf "$BASE/api/agents?limit=50" "${auth[@]}" \
  | python3 -c "import sys,json; d=json.load(sys.stdin); print(next((a['id'] for a in d.get('data',[]) if a.get('name')=='Remi Helper'), ''))")

if [[ -n "$DEFAULT_AGENT" ]]; then
  echo ""
  echo "Set in env.local: REMI_DEFAULT_AGENT_ID=$DEFAULT_AGENT"
fi
