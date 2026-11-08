#!/usr/bin/env bash
# Contract: parsed .no-mistakes.yaml routes the gate's lint and test steps
# through the local Docker CI services and declares no_ci, because the long
# GitHub lanes are manual-only. The test command must stay the targeted
# changed-tests service, never the full suite.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NM="$ROOT/.no-mistakes.yaml"

nm_value() {  # <ruby expression over doc>
  command -v ruby >/dev/null 2>&1     || fail "ruby is required to parse .no-mistakes.yaml for this contract"
  ruby -ryaml -e '
doc = YAML.load_file(ARGV[0]) || {}
cmds = doc["commands"].is_a?(Hash) ? doc["commands"] : {}
puts eval(ARGV[1])
' "$NM" "$1" || fail "failed to parse .no-mistakes.yaml as YAML"
}

test_nm_runs_local_docker_services() {
  [ "$(nm_value 'doc["no_ci"].inspect')" = true ] || fail "no_ci must be true"
  case "$(nm_value 'cmds["lint"]')" in
    *"docker-compose.ci.yml run --rm --build lint"*) ;;
    *) fail "commands.lint must run the lint docker service" ;;
  esac
  [ "$(nm_value 'cmds["test"]')" = "docker compose -f docker-compose.ci.yml run --rm --build test-changed" ]     || fail "commands.test must be the targeted test-changed docker service"
  pass "no-mistakes lints and tests through the local Docker services"
}

test_nm_runs_local_docker_services
