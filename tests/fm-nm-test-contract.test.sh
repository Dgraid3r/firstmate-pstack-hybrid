#!/usr/bin/env bash
# Contract: parsed .no-mistakes.yaml routes the gate's lint and test steps
# through the local Docker CI services and declares no_ci, because GitHub
# Actions is disabled for this fork. The Herdr, herdr-core and stock macOS lanes
# are not run in this fork while it is disabled; anyone who needs them runs them
# on a machine that has those tools. The test command must stay the targeted
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
  local prefix='git --exec-path=docker/ci fm-ci '
  [ "$(nm_value 'cmds["lint"]')" = "${prefix}lint" ] || fail "commands.lint must run the lint docker service through the shell-neutral git-fm-ci launcher"
  [ "$(nm_value 'cmds["test"]')" = "${prefix}test-changed" ] || fail "commands.test must run the targeted test-changed docker service through the shell-neutral git-fm-ci launcher"
  [ -x "$ROOT/docker/ci/git-fm-ci" ] || fail "docker/ci/git-fm-ci must exist and be executable"
  pass "no-mistakes lints and tests through the local Docker services"
}

test_nm_runs_local_docker_services
