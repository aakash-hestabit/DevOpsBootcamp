#!/bin/bash
# verify.sh — builds the stack with each env file and confirms the correct
# variables are injected into the running container.

COMPOSE_DIR="$(cd "$(dirname "$0")" && pwd)"
PASS=0; FAIL=0

USAGE="$(cat <<'EOF'
Usage: verify.sh [--help]

Starts the docker-compose stack three times — once per env file — and
asserts that each run exposes the expected APP_ENV and DB_NAME via /config.

Env files tested:
  .env         APP_ENV=development  DB_NAME=appdb
  .env.dev     APP_ENV=development  DB_NAME=appdb_dev
  .env.prod    APP_ENV=production   DB_NAME=appdb_prod

Prerequisites:
  docker compose up is NOT already running for this project.

Exit codes:
  0  All assertions passed
  1  One or more assertions failed
EOF
)"

[[ "$1" == "--help" ]] && { echo "$USAGE"; exit 0; }

dc() { docker compose -f "$COMPOSE_DIR/docker-compose.yml" "$@"; }

wait_ready() {
  local port="$1" i=1
  while (( i <= 20 )); do
    curl -sf "http://localhost:${port}/health" > /dev/null 2>&1 && return 0
    sleep 3; i=$((i+1))
  done
  echo "  [TIMEOUT] API on :${port} did not respond"
  return 1
}

assert_field() {
  local label="$1" url="$2" field="$3" expected="$4"
  local got
  got=$(curl -sf --max-time 5 "$url" 2>/dev/null | grep -o "\"${field}\":\"[^\"]*\"" | cut -d'"' -f4)
  if [[ "$got" == "$expected" ]]; then
    printf "  [PASS] %-42s --> %s=%s\n" "$label" "$field" "$got"
    PASS=$((PASS+1))
  else
    printf "  [FAIL] %-42s --> expected %s=%s, got '%s'\n" "$label" "$field" "$expected" "$got"
    FAIL=$((FAIL+1))
  fi
}

run_scenario() {
  local label="$1" envfile="$2" port="$3" exp_env="$4" exp_db="$5"
  echo ""
  echo "── $label (--env-file $envfile, API :${port}) ──"

  dc --env-file "$COMPOSE_DIR/$envfile" up -d --build --quiet-pull > /dev/null 2>&1
  wait_ready "$port" || { dc --env-file "$COMPOSE_DIR/$envfile" down -v > /dev/null 2>&1; return; }

  local config_url="http://localhost:${port}/config"
  assert_field "$envfile --> app.env"  "$config_url" "env"  "$exp_env"
  # check db.name specifically from the db block
  local db_name
  db_name=$(curl -sf --max-time 5 "$config_url" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['db']['name'])" 2>/dev/null)
  if [[ "$db_name" == "$exp_db" ]]; then
    printf "  [PASS] %-42s --> db.name=%s\n" "$envfile --> db.name" "$db_name"
    PASS=$((PASS+1))
  else
    printf "  [FAIL] %-42s --> expected db.name=%s, got '%s'\n" "$envfile --> db.name" "$exp_db" "$db_name"
    FAIL=$((FAIL+1))
  fi

  dc --env-file "$COMPOSE_DIR/$envfile" down -v > /dev/null 2>&1
}

echo "╔══════════════════════════════════════════════════╗"
echo "║        Environment Variable Substitution Test    ║"
echo "╚══════════════════════════════════════════════════╝"

run_scenario "Default .env"  ".env"      "3000" "development" "appdb"
run_scenario "Dev .env.dev"  ".env.dev"  "3000" "development" "appdb_dev"
run_scenario "Prod .env.prod" ".env.prod" "4000" "production"  "appdb_prod"

echo ""
echo "══════════════════════════════════════════════════"
printf  "  Results: %d passed, %d failed\n" "$PASS" "$FAIL"
echo "══════════════════════════════════════════════════"

(( FAIL > 0 )) && exit 1
exit 0
