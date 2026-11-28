#!/usr/bin/env bash
# Evidence driver: runs the real firstmate scripts inside the disposable local-CI
# Linux container (fm-ci-entrypoint shell mode, /work holds the commit under test).
# Everything lives under /tmp inside the container, which is discarded on exit.
set -u
HEAD_SHA=7e87e9034284e0b712335b996e76ce248730a3a1
BASE_SHA=f39290fe1779040293e1e1532f74b6b08ee673ed
T=/tmp/ev
mkdir -p "$T"
say() { printf '\n### %s\n' "$*"; }
cmdx() { printf '$ %s\n' "$*"; "$@" 2>&1; printf '(exit %s)\n' "$?"; }
quiet_install() { "$@" 2>&1 | grep -v '^link     [a-z]' ; printf '(exit %s)\n' "${PIPESTATUS[0]}"; }
unset FM_HOME FM_CONFIG_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_PROJECTS_OVERRIDE FM_ROOT_OVERRIDE

git clone -q /work "$T/clone" || exit 1
cd "$T/clone" || exit 1
git config core.autocrlf false

say "A. upgrade: install at base $BASE_SHA, then update the same clone to $HEAD_SHA and re-run"
git checkout -q "$BASE_SHA"
export HOME_UP=$T/up-user
quiet_install env HOME="$HOME_UP" FM_HOME="$T/up-home" bin/fm-install-skills.sh
cmdx ls "$HOME_UP/.claude/agents" "$T/up-home/config"
git checkout -q "$HEAD_SHA"
quiet_install env HOME="$HOME_UP" FM_HOME="$T/up-home" bin/fm-install-skills.sh
cmdx ls -l "$HOME_UP/.claude/agents"
cmdx ls "$T/up-home/config"
[ -e "$HOME_UP/.claude/agents/fm-mechanic.md" ] && echo "fm-mechanic resolves" || echo "fm-mechanic.md is a dangling leftover link (docs say delete it)"

say "B. fresh install on a fresh home"
P=$T/primary
U=$T/user
quiet_install env HOME="$U" FM_HOME="$P" bin/fm-install-skills.sh
cmdx ls "$U/.claude/agents" "$P/config"
cmp "$P/config/crew-dispatch.json" docs/examples/crew-dispatch.pstack.json && echo "crew-dispatch.json byte-identical to template"
cmdx jq . "$P/config/crew-dispatch.json"
say "B2. re-run is silent for config files"
quiet_install env HOME="$U" FM_HOME="$P" bin/fm-install-skills.sh

say "C. adversarial destinations"
for kind in dangling-symlink symlink-to-identical directory; do
  H=$T/adv-$kind; mkdir -p "$H/config"
  d=$H/config/crew-dispatch.json
  case $kind in
    dangling-symlink) ln -s "$H/outside-target.json" "$d" ;;
    symlink-to-identical) cp docs/examples/crew-dispatch.pstack.json "$H/real.json"; ln -s "$H/real.json" "$d" ;;
    directory) mkdir "$d"; echo keep > "$d/keep" ;;
  esac
  echo "--- $kind"
  env HOME="$U" FM_HOME="$H" bin/fm-install-skills.sh 2>&1 | grep -E 'crew-dispatch'; echo "(exit ${PIPESTATUS[0]})"
  ls -ld "$d"; ls -A "$H"
  env HOME="$U" FM_HOME="$H" bin/fm-install-skills.sh --force 2>&1 | grep -E 'crew-dispatch'; echo "(--force exit ${PIPESTATUS[0]})"
  ls -ld "$d"; ls -lR "$H"/config/.pstack-backup-*; ls -A "$H"
done
echo "--- dry run on a home with no config dir writes nothing"
env HOME="$U" FM_HOME="$T/dry-home" bin/fm-install-skills.sh --dry-run 2>&1 | grep -A2 -E '^install '; echo "(exit ${PIPESTATUS[0]})"
[ -e "$T/dry-home" ] && echo "dry-home CREATED (bad)" || echo "dry-home not created"

mkdir -p "$P/state" "$P/data" "$P/projects"
say "D. firstmate bootstrap validates the installed config"
cmdx bash -c "FM_HOME='$P' FM_BOOTSTRAP_VERBOSE_FACTS=1 timeout 120 bin/fm-bootstrap.sh 2>&1 | grep -E 'crew dispatch|CREW_DISPATCH'"
echo "control: same check on a deliberately broken effort value must be reported"
cp "$P/config/crew-dispatch.json" "$T/saved.json"
jq '.default.effort="turbo"' "$T/saved.json" > "$P/config/crew-dispatch.json"
cmdx bash -c "FM_HOME='$P' timeout 120 bin/fm-bootstrap.sh 2>&1 | grep -E 'crew dispatch|CREW_DISPATCH'"
cp "$T/saved.json" "$P/config/crew-dispatch.json"

say "E. spawn with the installed config, real tmux, real treehouse, real claude CLI (no login in container)"
bin/fm-install-treehouse.sh "$T/tools" 2>&1 | tail -1
npm install --silent --prefix "$T/claude" @anthropic-ai/claude-code >/dev/null 2>&1; echo "npm exit $?"
export PATH="$T/tools:$T/claude/node_modules/.bin:$PATH"
cmdx claude --version
cmdx treehouse --version
git init -q "$P/projects/demo"
(cd "$P/projects/demo" && echo demo > README.md && git add . && git commit -qm init)
export FM_HOME="$P" HOME="$T/spawn-user"
mkdir -p "$HOME"
git config --global user.name ev; git config --global user.email ev@example.invalid; git config --global --add safe.directory '*'
export TMUX_TMPDIR="$T/tmux"; mkdir -p "$TMUX_TMPDIR"
tmux new-session -d -s primary -x 220 -y 50 -c "$T/clone" || echo "tmux failed"
for spec in "ship-low:sonnet:medium:" "scout-diag:opus:high:--scout"; do
  IFS=: read -r id model effort scout <<<"$spec"
  echo; echo "=== task $id (expect $model/$effort)"
  if [ -n "$scout" ]; then
    cmdx bin/fm-brief.sh "$id" demo --scout
    kindargs=(--scout)
  else
    cmdx bin/fm-brief.sh "$id" demo --mode local-only
    kindargs=(--mode local-only --yolo off)
  fi
  b=$P/data/$id/brief.md
  sed -i "s/{TASK}/Fix a typo in README.md./g; s/{FIRSTMATE_SPEC}/Change the word demo in README.md. Low risk./g" "$b"
  grep -n '{[A-Z_]*}' "$b" | head
  echo "-- no --harness: refused"
  cmdx timeout 60 bin/fm-spawn.sh "$id" "$P/projects/demo" "${kindargs[@]}" --backend tmux
  echo "-- explicit profile, but no dispatch record yet: refused"
  cmdx timeout 60 bin/fm-spawn.sh "$id" "$P/projects/demo" "${kindargs[@]}" --backend tmux --harness claude --model "$model" --effort "$effort"
  echo "-- resolver with no model key"
  cmdx env -u TYPESAFE_API_KEY -u OPENROUTER_API_KEY -u OPENAI_API_KEY bin/fm-dispatch-resolve.sh "$b" --project demo
  cmdx cat "$P/data/$id/dispatch-resolution.json"
  echo; echo "-- spawn with the template tier"
  tmux send-keys -t primary "cd $T/clone && PATH=$PATH FM_HOME=$P HOME=$HOME timeout 180 bin/fm-spawn.sh $id $P/projects/demo ${kindargs[*]} --backend tmux --harness claude --model $model --effort $effort > $T/spawn-$id.log 2>&1; echo \$? > $T/spawn-$id.rc" Enter
  for _ in $(seq 1 200); do [ -f "$T/spawn-$id.rc" ] && break; sleep 1; done
  echo "spawn exit: $(cat "$T/spawn-$id.rc" 2>/dev/null || echo 'still running')"
  tail -15 "$T/spawn-$id.log"
  sleep 5
  echo "-- recorded task metadata"
  grep -E '^(harness|model|effort|kind|window)=' "$P/state/$id.meta" 2>&1
  echo "-- running claude processes"
  ps -eo args | grep -E '(^|/)claude( |$).*--model' | grep -- "/state/$id.inbox" | grep -v grep | head -1 | grep -oE -- "/state/$id.inbox|--(model|effort)[ =]+[^ ]+"
  echo "-- worker pane"
  w=$(sed -n 's/^window=//p' "$P/state/$id.meta" 2>/dev/null)
  [ -n "$w" ] && tmux capture-pane -p -J -t "$w" | grep -v '^[[:space:]]*$' | cut -c1-260 | head -40
done

say "F. resolver reads the installed rules with a local stand-in model endpoint (rule-to-profile mapping only; the stand-in picks the rule, no real model is consulted)"
cat > "$T/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
class H(BaseHTTPRequestHandler):
    def do_POST(self):
        req = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        qid, q = next(iter(req['questions'].items()))
        pick = open('/tmp/ev/pick').read().strip()
        opts = list(q['criteria'])
        probs = {o: (0.97 if o == pick else round(0.03 / (len(opts) - 1), 4)) for o in opts}
        json.dump(req, open('/tmp/ev/request-%s.json' % pick, 'w'), indent=1)
        body = json.dumps({"model": "stub", "answers": {qid: {"answer": pick, "choice": pick, "confidence": 0.97, "probabilities": probs}}, "usage": {"input_tokens": 1, "output_tokens": 1}}).encode()
        self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
HTTPServer(('127.0.0.1', 8765), H).serve_forever()
PY
python3 -I "$T/stub.py" & stub=$!
sleep 1
# shared_quota is the documented opt-out that skips quota-axi; rules and default stay exactly as installed.
jq '. + {shared_quota: true}' "$T/saved.json" > "$P/config/crew-dispatch.json"
for pick in default rule_1 rule_2; do
  echo "$pick" > "$T/pick"
  echo "--- stand-in answers $pick"
  FM_DISPATCH_PROVIDER=systemone FM_DISPATCH_MODEL=stub FM_DISPATCH_BASE_URL=http://127.0.0.1:8765 \
    bin/fm-dispatch-resolve.sh "$P/data/ship-low/brief.md" --project demo 2>&1
done
echo "--- criteria the resolver sent"
jq '.questions[] | .criteria' "$T/request-default.json" 2>&1
kill "$stub" 2>/dev/null
cp "$T/saved.json" "$P/config/crew-dispatch.json"

say "G. secondmate home: installer writes the template, config push replaces it with the primary's rules"
S=$T/second
git -C "$T/clone" worktree add -q --detach "$S" "$HEAD_SHA" || echo "worktree add failed"
echo sm1 > "$S/.fm-secondmate-home"
mkdir -p "$S/config" "$S/state" "$S/data"
quiet_install env HOME="$U" FM_HOME="$S" bin/fm-install-skills.sh | grep -E 'crew-dispatch|brief-include|exit'
jq '.default.model="haiku" | .default.effort="low"' "$T/saved.json" > "$P/config/crew-dispatch.json"
echo "primary edits default tier to haiku/low; secondmate still has the template:"
jq -c .default "$S/config/crew-dispatch.json"
printf 'window=primary:0\nkind=secondmate\nhome=%s\nharness=claude\nbackend=tmux\n' "$S" > "$P/state/sm1.meta"
cmdx bash -c "FM_HOME='$P' timeout 120 bin/fm-config-push.sh 2>&1 | grep -E 'config-push|secondmate|crew-dispatch'"
echo "secondmate default now:"; jq -c .default "$S/config/crew-dispatch.json"
echo "--- installer run on the secondmate afterwards reports a conflict and leaves the inherited file"
env HOME="$U" FM_HOME="$S" bin/fm-install-skills.sh 2>&1 | grep -E 'crew-dispatch'; echo "(exit ${PIPESTATUS[0]})"
jq -c .default "$S/config/crew-dispatch.json"
echo "--- installer re-run on the edited primary: conflict, edit preserved"
env HOME="$U" FM_HOME="$P" bin/fm-install-skills.sh 2>&1 | grep -E 'crew-dispatch'; echo "(exit ${PIPESTATUS[0]})"
jq -c .default "$P/config/crew-dispatch.json"

say "H. changed-test selection for the dispatch template"
cd "$T/clone" || exit 1
git checkout -q "$HEAD_SHA"
printf '\n' >> docs/examples/crew-dispatch.pstack.json
echo "--- template edited"; cmdx bin/fm-test-run.sh --list --changed --base HEAD
git checkout -q docs/examples/crew-dispatch.pstack.json
git mv docs/examples/crew-dispatch.pstack.json docs/examples/renamed.json
echo "--- template renamed"; cmdx bin/fm-test-run.sh --list --changed --base HEAD
git mv docs/examples/renamed.json docs/examples/crew-dispatch.pstack.json
git rm -q docs/examples/crew-dispatch.pstack.json
echo "--- template deleted"; cmdx bin/fm-test-run.sh --list --changed --base HEAD
git checkout -q HEAD -- docs/examples/crew-dispatch.pstack.json

tmux kill-server 2>/dev/null
echo DONE
