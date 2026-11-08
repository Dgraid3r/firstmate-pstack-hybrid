#!/usr/bin/env bash
# Contract tests for the GitHub workflow split that keeps private-repo Actions
# spend small: ci-fast.yml and no-mistakes-required.yml are the only automatic
# workflows (seconds-long PR hygiene), while the long lint and behavior lanes in
# ci.yml and the Windows Herdr spike are workflow_dispatch only and run locally
# through Docker (CONTRIBUTING.md "Running CI locally").
#
# Every job still carries a finite hang tripwire drawn from the three-tier
# timeout policy that docs/fm-test-portable-shards.md "Timeouts" owns (fast,
# normal, heavy), and the lint and serial matrices must keep covering the
# executable partitions.
set -u

# shellcheck source=tests/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

CI_WORKFLOW="$ROOT/.github/workflows/ci.yml"
FAST_WORKFLOW="$ROOT/.github/workflows/ci-fast.yml"
WORKFLOW_DIR="$ROOT/.github/workflows"

assert_present "$CI_WORKFLOW" ".github/workflows/ci.yml is missing"
assert_present "$FAST_WORKFLOW" ".github/workflows/ci-fast.yml is missing"
command -v ruby >/dev/null 2>&1   || fail "ruby is required to parse the GitHub workflows as YAML"

job_timeout() {
  ruby -ryaml -e '
puts YAML.load_file(ARGV[0]).fetch("jobs").fetch(ARGV[1]).fetch("timeout-minutes", "none")
' "$CI_WORKFLOW" "$1"
}

# Tier membership is the executable inventory of the timeout policy: a new job
# must join a tier, and a job-level value outside these tiers is exactly the
# one-off number the policy removed.
FAST_TIER_JOBS='tests-timing-aggregate full-suite'
NORMAL_TIER_JOBS='lint tests-portable-parallel-1 tests-portable-parallel-2 tests-portable-serial macos-stock-bash'
HEAVY_TIER_JOBS='tests-herdr tests-hc'

# Print the one timeout every listed job shares; fail on any disagreement.
tier_timeout() {  # <tier> <job>...
  local tier=$1 job first actual
  shift
  first=
  for job in "$@"; do
    actual=$(job_timeout "$job") || fail "could not read the $job timeout"
    case "$actual" in ''|*[!0-9]*) fail "$job ($tier tier) has no integer timeout, got $actual" ;; esac
    if [ -z "$first" ]; then
      first=$actual
    elif [ "$actual" != "$first" ]; then
      fail "$tier tier jobs must share one timeout, got $first and $actual ($job)"
    fi
  done
  printf '%s\n' "$first"
}

# Print every job id in the workflow, one per line.
workflow_jobs() {
  ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("jobs").keys' "$CI_WORKFLOW"
}

# Print the trigger names of one workflow file, sorted. Psych reads the bare key
# `on` as true.
workflow_triggers() {  # <file>
  ruby -ryaml -e '
doc = YAML.load_file(ARGV[0])
on = doc.key?("on") ? doc["on"] : doc[true]
puts(on.is_a?(Hash) ? on.keys.sort : Array(on).sort)
' "$1"
}

test_long_workflows_are_manual_only() {
  local file
  for file in ci.yml windows-herdr-spike.yml; do
    [ "$(workflow_triggers "$WORKFLOW_DIR/$file")" = workflow_dispatch ]       || fail "$file must trigger only on workflow_dispatch, got: $(workflow_triggers "$WORKFLOW_DIR/$file" | tr '
' ' ')"
  done
  pass "ci.yml and windows-herdr-spike.yml start only by hand"
}

test_fast_workflow_is_automatic_and_small() {
  local triggers jobs
  triggers=$(workflow_triggers "$FAST_WORKFLOW" | tr '
' ' ')
  [ "$triggers" = "pull_request push " ]     || fail "ci-fast.yml must run on push and pull_request, got: $triggers"
  jobs=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("jobs").keys.sort' "$FAST_WORKFLOW" | tr '
' ' ')
  [ "$jobs" = "invariants test-coverage " ]     || fail "ci-fast.yml must hold only the seconds-long hygiene jobs, got: $jobs"
  pass "ci-fast.yml runs the coverage guard and invariants automatically"
}

test_manual_jobs_only_wait_on_manual_jobs() {
  ruby -ryaml - "$CI_WORKFLOW" <<'RUBY' || fail "ci.yml needs a job outside ci.yml"
jobs = YAML.load_file(ARGV[0]).fetch("jobs")
jobs.each do |name, job|
  Array(job["needs"]).each do |dep|
    raise "#{name} needs #{dep}, which is not a ci.yml job" unless jobs.key?(dep)
  end
end
RUBY
  pass "every ci.yml dependency is a ci.yml job"
}

test_fast_workflow_jobs_share_the_fast_tier() {
  local value job
  for job in test-coverage invariants; do
    value=$(ruby -ryaml -e 'puts YAML.load_file(ARGV[0]).fetch("jobs").fetch(ARGV[1]).fetch("timeout-minutes", "none")' "$FAST_WORKFLOW" "$job")
    [ "$value" = "$(job_timeout tests-timing-aggregate)" ]       || fail "ci-fast.yml $job must share the fast tier timeout, got $value"
  done
  pass "ci-fast.yml jobs share the fast tier timeout"
}

test_every_job_has_a_finite_timeout() {
  local reported
  reported=$(ruby -ryaml -e '
YAML.load_file(ARGV[0]).fetch("jobs").each do |name, job|
  timeout = job["timeout-minutes"]
  next if timeout.is_a?(Integer) && timeout > 0
  puts "#{name}: #{timeout.inspect}"
end
' "$CI_WORKFLOW") || fail "could not read job timeouts from ci.yml"
  [ -z "$reported" ] || fail "these CI jobs have no finite hang tripwire:"$'\n'"$reported"
  pass "every ci.yml job carries a finite timeout"
}

# Every job sits in exactly one tier, and the workflow carries exactly three
# distinct job-level timeouts: one per tier, no one-off numbers.
test_every_job_belongs_to_exactly_one_timeout_tier() {
  local expected actual distinct
  # shellcheck disable=SC2086
  expected=$(printf '%s\n' $FAST_TIER_JOBS $NORMAL_TIER_JOBS $HEAVY_TIER_JOBS | LC_ALL=C sort)
  [ "$(printf '%s\n' "$expected" | LC_ALL=C sort -u)" = "$expected" ] \
    || fail "a job is listed in more than one timeout tier:"$'\n'"$expected"
  actual=$(workflow_jobs | LC_ALL=C sort) || fail "could not list ci.yml jobs"
  [ "$actual" = "$expected" ] \
    || fail "ci.yml jobs and the timeout tiers disagree; every job must join one tier"$'\n'"workflow: $(printf '%s' "$actual" | tr '\n' ' ')"$'\n'"tiers: $(printf '%s' "$expected" | tr '\n' ' ')"
  distinct=$(for job in $expected; do job_timeout "$job"; done | LC_ALL=C sort -u | wc -l | tr -d ' ')
  [ "$distinct" = 3 ] \
    || fail "ci.yml must carry exactly three distinct job timeouts (fast, normal, heavy), got $distinct"
  pass "every ci.yml job belongs to one of the three timeout tiers"
}

# Fast tier: seconds-long checks share one short tripwire in the 5-10 minute band.
test_fast_tier_shares_one_short_tripwire() {
  local fast
  # shellcheck disable=SC2086
  fast=$(tier_timeout fast $FAST_TIER_JOBS) || exit 1
  [ "$fast" -ge 5 ] && [ "$fast" -le 10 ] \
    || fail "fast tier must be a 5-10 minute hang tripwire, got $fast"
  pass "fast tier jobs share one $fast minute tripwire"
}

# Normal tier: every test or lint lane shares ONE fixed 30-minute budget,
# above the fast tier. That budget is a hang tripwire, not a packing estimate.
test_normal_tier_shares_one_budget() {
  local fast normal
  # shellcheck disable=SC2086
  fast=$(tier_timeout fast $FAST_TIER_JOBS) || exit 1
  # shellcheck disable=SC2086
  normal=$(tier_timeout normal $NORMAL_TIER_JOBS) || exit 1
  [ "$normal" -gt "$fast" ] \
    || fail "normal tier ($normal) must exceed the fast tier ($fast)"
  [ "$normal" = 30 ] \
    || fail "normal tier must be the single 30-minute shared budget, got $normal"
  pass "normal tier jobs share one $normal minute budget"
}

# Heavy tier: Herdr alone carries a job-level last-resort backstop above the
# normal tier, while its family-run step owns a tighter tripwire so the
# always() cleanup and timing upload still run after a hang.
test_heavy_tier_keeps_a_step_tripwire_under_a_job_backstop() {
  local normal heavy step
  # shellcheck disable=SC2086
  normal=$(tier_timeout normal $NORMAL_TIER_JOBS) || exit 1
  # shellcheck disable=SC2086
  heavy=$(tier_timeout heavy $HEAVY_TIER_JOBS) || exit 1
  [ "$heavy" -gt "$normal" ] \
    || fail "heavy tier backstop ($heavy) must exceed the normal tier ($normal)"
  [ "$heavy" -ge 60 ] && [ "$heavy" -le 75 ] \
    || fail "heavy tier backstop must stay a 60-75 minute last resort, got $heavy"
  # Each heavy lane's family-run step owns the same 20-minute tripwire shape:
  # its own timeout, an always() cleanup step that must come after it, and a
  # bound below the shared job backstop.
  while read -r lane run_step cleanup_step; do
    step=$(ruby -ryaml -e '
steps = YAML.load_file(ARGV[0]).fetch("jobs").fetch(ARGV[1]).fetch("steps")
index = steps.index { |s| s["id"] == ARGV[2] }
raise "no #{ARGV[2]} step" unless index
teardown = steps.index { |s| s["id"] == ARGV[3] }
raise "no #{ARGV[3]} step" unless teardown
raise "teardown must follow the family-run step" unless teardown > index
raise "teardown must run under always()" unless steps[teardown]["if"].to_s.strip == "always()"
puts steps[index].fetch("timeout-minutes", "none")
' "$CI_WORKFLOW" "$lane" "$run_step" "$cleanup_step") || fail "could not read the $lane family-run step"
    case "$step" in ''|*[!0-9]*) fail "the $lane family-run step needs its own timeout-minutes, got $step" ;; esac
    [ "$step" = 20 ] \
      || fail "the $lane family-run step must be the 20-minute tripwire, got $step"
    [ "$step" -lt "$heavy" ] \
      || fail "the $lane step tripwire ($step) must stay below the job backstop ($heavy)"
  done <<'LANES'
tests-herdr run-real-herdr-family cleanup-herdr-lab-sessions
tests-hc run-real-hc-family cleanup-hc-lab-sessions
LANES
  pass "each heavy lane keeps a 20 minute step tripwire under a $heavy minute job backstop"
}

# The fork opt-out is opt-in: with neither variable set every job runs on both
# events, FM_CI_SKIP_PUSH=1 empties only the push run, and FM_CI_SKIP_MACOS=1

test_ci_matrices_match_executable_partitions() {
  ruby -ryaml -ropen3 - "$CI_WORKFLOW" "$ROOT" <<'RUBY' || fail "CI partition contract"
jobs = YAML.load_file(ARGV[0]).fetch("jobs")
root = ARGV[1]
serial = jobs.fetch("tests-portable-serial").fetch("strategy")
raise "serial failures must not cancel other shards" unless serial.fetch("fail-fast") == false
matrix = serial.fetch("matrix")
raise "unexpected serial dimensions" unless matrix.keys == ["shard"]
shards = matrix.fetch("shard")
lanes, status = Open3.capture2(File.join(root, "bin/fm-test-run.sh"), "--list-lanes")
raise "cannot list runner lanes" unless status.success?
actual = lanes.lines.map(&:strip).select { |l| l.match?(/\Aportable-serial-\d+of\d+\z/) }
expected = shards.map { |s| "portable-serial-#{s}of#{shards.length}" }
raise "CI matrix and runner disagree" unless actual.sort == expected.sort
lint = jobs.fetch("lint").fetch("strategy")
raise "lint failures must not cancel another partition" unless lint.fetch("fail-fast") == false
matrix = lint.fetch("matrix")
raise "unexpected lint dimensions" unless matrix.keys == ["partition"]
parts = matrix.fetch("partition")
roots = parts.flat_map do |p|
  output, result = Open3.capture2(File.join(root, "bin/fm-lint.sh"), "--partition", "#{p}of#{parts.length}", "--list-files")
  raise "unsupported lint partition" unless result.success?
  output.lines.map(&:strip)
end
canonical, result = Open3.capture2({"CI" => "true"}, File.join(root, "bin/fm-lint.sh"), "--list-files")
raise "lint matrix loses or duplicates canonical roots" unless result.success? && roots.sort == canonical.lines.map(&:strip).sort
RUBY
  pass "CI matrices cover every executable serial lane and canonical lint root exactly once"
}

test_long_workflows_are_manual_only
test_fast_workflow_is_automatic_and_small
test_manual_jobs_only_wait_on_manual_jobs
test_fast_workflow_jobs_share_the_fast_tier
test_ci_matrices_match_executable_partitions
test_every_job_has_a_finite_timeout
test_every_job_belongs_to_exactly_one_timeout_tier
test_fast_tier_shares_one_short_tripwire
test_normal_tier_shares_one_budget
test_heavy_tier_keeps_a_step_tripwire_under_a_job_backstop
