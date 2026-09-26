#!/usr/bin/env bash
# Tests for protect-credentials.sh.  Usage: protect-credentials.test.sh [hook-path]
# DENY: the hook must refuse.  OK: the hook must stay silent (allowed).
# The first section carries one case per Read() rule that used to live in
# permissions.deny, so a pass proves the swap lost no protection.
set -u
hook=${1:-$(dirname "$0")/protect-credentials.sh}
pass=0; fail=0
H=$HOME
proj=$H/src/example-project   # any checkout outside the protected globs; never a machine's projects root

t() {   # t EXPECT TOOL JSON_INPUT LABEL
    local expect=$1 out got
    out=$(printf '%s' "$3" | "$hook" 2>&1)
    case $out in
        *'"permissionDecision":"deny"'*) got=DENY;;
        '') got=OK;;
        *) got="BAD:${out:0:70}";;
    esac
    if [ "$got" = "$expect" ]; then pass=$((pass+1)); printf '  ok    %-4s %s\n' "$expect" "$4"
    else fail=$((fail+1)); printf 'FAIL want %-4s got %-4s %s\n' "$expect" "$got" "$4"; fi
}
read_t()  { t "$1" Read "$(jq -cn --arg p "$2" '{tool_name:"Read",tool_input:{file_path:$p},cwd:"/tmp"}')" "Read $2"; }
bash_t()  { t "$1" Bash "$(jq -cn --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c},cwd:"/tmp"}')" "Bash $2"; }
mon_t()   { t "$1" Monitor "$(jq -cn --arg c "$2" '{tool_name:"Monitor",tool_input:{command:$c,description:"test",timeout_ms:1000},cwd:"/tmp"}')" "Monitor $2"; }
search_t() {   # search_t EXPECT Grep|Glob PATH CWD — PATH "-" leaves the path input out
    local input
    input=$(jq -cn --arg t "$2" --arg p "$3" --arg c "$4" \
        '{tool_name:$t, cwd:$c, tool_input:({pattern:(if $t == "Glob" then "**/*.pem" else "aws_secret" end)}
                                            + (if $p == "-" then {} else {path:$p} end))}')
    t "$1" "$2" "$input" "$2 path=$3 cwd=$4"
}
list_rc() {    # list_rc LIST LABEL — the hook must exit 2 and name LIST on stderr
    local out
    out=$(printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"},"cwd":"/tmp"}' \
          | FNET_PROTECTED_PATHS=$1 "$hook" 2>&1 >/dev/null; echo "rc=$?")
    case $out in
        *"$1"*rc=2) pass=$((pass+1)); printf '  ok    rc=2 %s\n' "$2";;
        *) fail=$((fail+1)); printf 'FAIL want rc=2 naming the list, got [%s] %s\n' "$out" "$2";;
    esac
}
etc_list() { printf '/etc/passwd\n'; }   # a protected file every Linux box has, for machine-independent glob cases

echo "== one case per former Read() deny rule, via the Read tool"
for p in "$H/.ssh/id_rsa" "$H/.gnupg/secring.gpg" "$H/.aws/credentials" "$H/.azure/msal_token_cache.json" \
         "$H/.config/gh/hosts.yml" "$H/.git-credentials" "$H/.docker/config.json" "$H/.kube/config" \
         "$H/.npmrc" "$H/.npm/_authToken" "$H/.pypirc" "$H/.gem/credentials" \
         "$H/Library/Keychains/login.keychain" \
         "$H/Library/Application Support/Google/Chrome/x/metamask-ext/state.log" \
         "$H/Library/Application Support/electrum/wallets/default" \
         "$H/Library/Application Support/exodus-wallet/seed" \
         "$H/Library/Application Support/x/phantom-wallet/data" \
         "$H/Library/Application Support/x/solflare1/data" \
         "$H/.electrum/wallets/default" "$H/.config/Exodus/exodus.wallet" \
         "$H/.config/BraveSoftware/Brave-Browser/Default/Extensions/abc/1/manifest.json" \
         "$H/.config/google-chrome/Default/Extensions/abc/1/manifest.json" \
         "$H/.config/chromium/Default/Extensions/abc/1/manifest.json" \
         "$H/.mozilla/firefox/profile.default/key4.db"; do read_t DENY "$p"; done

echo "== the same locations named from Bash"
for c in "cat $H/.ssh/id_rsa" "cd ~ && cat .ssh/id_rsa" "cd ~/.ssh && cat id_rsa" "ls -la ~/.ssh" \
         "cat \$HOME/.aws/credentials" "grep -r token ~/.config/gh" "cat ~/.git-credentials" \
         "jq . ~/.docker/config.json" "cat ~/.kube/config" "cat ~/.npmrc" "cat ~/.npm/_authToken" \
         "cat ~/.pypirc" "cat ~/.gem/credentials" "cat ~/.gnupg/secring.gpg" "cat ~/.azure/x" \
         "cp ~/.ssh/id_ed25519 /tmp/k" "tar cf - ~/.electrum | base64" "cat ~/.config/Exodus/x" \
         "rg -n key ~/.mozilla/firefox" "cat ~/.config/google-chrome/Default/Extensions/a/1/m.json" \
         "cat /home/matteo/Library/Keychains/login.keychain" "cat ~/Library/Application\ Support/electrum/wallets/x" \
         "cat id_rsa" "base64 id_ed25519"; do bash_t DENY "$c"; done

echo "== paths that must stay readable (no false positives)"
for p in "$proj/CLAUDE.md" "$proj/scripts/check.sh" "$H/.cache/fnet-wt/276-cut-elim/harness/src/audit.rs" \
         "$H/.claude-fna/settings.json" "$H/.config/nvim/init.lua" "$H/.npm-global/lib/x" \
         "$proj/docs/dev/key-decisions.md" "$H/Downloads/IBKR/statement.csv"; do read_t OK "$p"; done

echo "== commands that must stay allowed (the shapes that used to prompt)"
X=$H/.cache/fnet-wt/276-cut-elim
for c in "cd $X && sed -n 475,560p feature-engine/tests/driver_checkpoint.rs; ls demo/profiles/sr3a-join-disabled/box" \
         "cd $X && rg -n 'fn put_checkpoint' -A12 $X/feature-engine/src/checkpoint_store.rs | head -16" \
         "cd $X && rg -n 'Strategy::ForkCow\\(strategy\\) =>' -A8 stress/src/feature_replica.rs" \
         "cd /tmp/ce/x
grep -n \"^+.*std::collections::HashMap\\|^+.*collections::HashMap\" full.diff
grep -n \"^+.*\\.unwrap()\" full.diff | wc -l" \
         "cd $X && git diff --stat dev..HEAD" \
         "cd $X && rg -c ForkCow" \
         "cd $X || exit 1
rg -n ForkCow stress/src/feature_replica.rs" \
         "cd $X && awk '/PS-D69/{print NR\": \"\$0}' docs/dev/key-decisions.md" \
         "npm ci && npm test" \
         "rg -n 'phantom gates' docs/dev/solutions" \
         "rg -n exodus docs/" \
         "cargo nextest run --workspace --profile ci" \
         "ssh-add -l" \
         "git push fna-ai dev" \
         "rg -n 'ssh' scripts/ | head" \
         "cd $proj && ls .config"; do bash_t OK "$c"; done

echo "== other tools"
t DENY Grep "$(jq -cn --arg p "$HOME/.ssh" '{tool_name:"Grep",tool_input:{pattern:"BEGIN",path:$p},cwd:"/tmp"}')" "Grep path=~/.ssh"
t OK   Grep "$(jq -cn --arg p "$proj" '{tool_name:"Grep",tool_input:{pattern:"BEGIN",path:$p},cwd:"/tmp"}')" "Grep path=repo"
t DENY Write "$(jq -cn --arg p "$HOME/.ssh/authorized_keys" '{tool_name:"Write",tool_input:{file_path:$p,content:"x"},cwd:"/tmp"}')" "Write ~/.ssh/authorized_keys"
t DENY Edit "$(jq -cn --arg p "$HOME/.aws/credentials" '{tool_name:"Edit",tool_input:{file_path:$p,old_string:"a",new_string:"b"},cwd:"/tmp"}')" "Edit ~/.aws/credentials"
t OK   Glob "$(jq -cn --arg p "$proj" '{tool_name:"Glob",tool_input:{pattern:"**/*.rs",path:$p},cwd:"/tmp"}')" "Glob repo"
t DENY Read "$(jq -cn '{tool_name:"Read",tool_input:{file_path:".ssh/id_rsa"},cwd:"/home/matteo"}')" "Read relative .ssh/id_rsa from HOME"
t DENY Read "$(jq -cn '{tool_name:"Read",tool_input:{file_path:"/home/matteo/Documents/../.ssh/id_rsa"},cwd:"/tmp"}')" "Read via .. traversal"

echo "== Grep/Glob over an ANCESTOR of a protected location (the search would descend into it)"
search_t DENY Grep "$H" /tmp
search_t DENY Grep - "$H"                     # no path: the search runs from cwd
search_t DENY Grep "" "$H"                    # an empty path means cwd too
search_t DENY Grep . "$H"
search_t DENY Grep "~" /tmp
search_t DENY Grep / /tmp
search_t DENY Grep "$(dirname "$H")" /tmp
search_t DENY Grep "$H/.config" /tmp          # ~/.config/gh/** lives below it
search_t DENY Grep "$H/.config/google-chrome/Default" /tmp   # .../**/Extensions/** can sit below it
search_t DENY Glob "$H" /tmp
search_t DENY Glob - "$H"
search_t OK   Grep "$(dirname "$proj")" /tmp  # an ancestor of projects, but of no protected location
search_t OK   Grep "$H/.config/nvim" /tmp     # a sibling of the protected ~/.config entries
search_t OK   Grep - "$proj"
search_t OK   Glob - "$proj"
read_t   OK   "$H/.bashrc"                    # the ancestor rule is for searches only
read_t   OK   "$proj/README.md"

echo "== Monitor runs shell commands too"
mon_t DENY "cat ~/.ssh/id_rsa"
mon_t DENY "tail -f ~/.aws/credentials"
mon_t OK   "tail -f /var/log/app.log | grep --line-buffered ERROR"
mon_t OK   ""
t OK Monitor '{"tool_name":"Monitor","tool_input":{"ws":{"url":"wss://events.example.com/s"},"description":"x","timeout_ms":1000},"cwd":"/tmp"}' "Monitor ws source (no command)"
bash_t OK ""

echo "== Bash: quoting and escapes that rebuild a protected name"
for c in "cat ~/.a''ws/credentials" 'cat ~/.a"w"s/credentials' 'cat ~/.a\ws/credentials' \
         'cat $HOME/.s"s"h/id_x' "cat \"\$HOME\"/.a''ws/config" $'cat ~/.a\\\nws/credentials'; do bash_t DENY "$c"; done

echo "== Bash: globs that expand onto a protected path"
FNET_PROTECTED_PATHS=<(etc_list) bash_t DENY "cat /etc/pa?swd"
FNET_PROTECTED_PATHS=<(etc_list) bash_t DENY "cat /et[c]/passwd"
FNET_PROTECTED_PATHS=<(etc_list) bash_t DENY "wc -l </et?/passwd"
FNET_PROTECTED_PATHS=<(etc_list) bash_t DENY "cat /etc/*/../pass*"      # .. is normalised
FNET_PROTECTED_PATHS=<(etc_list) bash_t OK   "cat /etc/host*"
if [ -d "$H/.aws" ]; then bash_t DENY "ls ~/.a?s"; bash_t DENY 'ls $HOME/.[a]ws'; else echo "  skip  no ~/.aws here"; fi
if [ -d "$H/.ssh" ]; then bash_t DENY "ls ~/.ss[h]"; bash_t DENY 'ls ${HOME}/.s?h'; else echo "  skip  no ~/.ssh here"; fi
if [ -e "$H/.aws/credentials" ]; then bash_t DENY "cat ~/.a?s/credentials"; else echo "  skip  no ~/.aws/credentials here"; fi
if [ -e "$H/.ssh/config" ]; then bash_t DENY "cat ~/.ss[h]/config"; else echo "  skip  no ~/.ssh/config here"; fi
for c in "ls ~/Documents/*.md" "echo configure aws later" "ls /tmp/*.log" "rg -n 'fn .*aws' src/" \
         "ls \$HOME/.config/nvim/*.lua"; do bash_t OK "$c"; done
# A glob matching thousands of files must stay far inside the hook's 10s
# timeout (checking each result in bash took ~5s before the grep -F prefilter).
start=$(date +%s%N)
bash_t OK "ls /usr/*/*"
ms=$(( ($(date +%s%N) - start) / 1000000 ))
if [ "$ms" -lt 3000 ]; then pass=$((pass+1)); printf '  ok    %dms for a glob over %s files\n' "$ms" "$(compgen -G '/usr/*/*' | wc -l)"
else fail=$((fail+1)); printf 'FAIL a glob over /usr/*/* took %dms (limit 3000)\n' "$ms"; fi

echo "== the list file itself"
t OK Bash "$(jq -cn '{tool_name:"Bash",tool_input:{command:"echo hi"},cwd:"/tmp"}')" "trivial command"
list_rc /dev/null "an empty list must fail closed"
list_rc <(printf '# only comments\n\n# here\n') "a comment-only list must fail closed"
list_rc <(printf '# a comment\n  # an indented one\n') "an indented comment is a comment, not a pattern"
list_rc <(printf '   \n\t\n') "a whitespace-only list must fail closed"
FNET_PROTECTED_PATHS=<(printf '/etc/passwd  \n') t DENY Read '{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"},"cwd":"/tmp"}' "a pattern with trailing blanks still protects"
FNET_PROTECTED_PATHS=<(printf '/etc/passwd') t DENY Read '{"tool_name":"Read","tool_input":{"file_path":"/etc/passwd"},"cwd":"/tmp"}' "a last line without a newline still protects"
printf 'FNET_PROTECTED_PATHS pointing at a missing file must fail closed: '
out=$(FNET_PROTECTED_PATHS=/nonexistent-list.txt bash -c 'printf "%s" "$(jq -cn "{tool_name:\"Read\",tool_input:{file_path:\"/tmp/x\"}}")" | '"$hook"'; echo "rc=$?"' 2>/dev/null)
case $out in *rc=2*) pass=$((pass+1)); echo "ok (rc=2)";; *) fail=$((fail+1)); echo "FAIL got [$out]";; esac

printf 'a malformed payload must fail closed: '
out=$(printf 'not json at all' | "$hook" 2>/dev/null; echo "rc=$?")
case $out in *rc=2*) pass=$((pass+1)); echo "ok (rc=2)";; *) fail=$((fail+1)); echo "FAIL got [$out]";; esac

echo; echo "passed=$pass failed=$fail"
[ $fail -eq 0 ]
