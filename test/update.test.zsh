#!/usr/bin/env zsh -f
# apathy-update against a fake curl that plays jsDelivr's API and CDN.
emulate -R zsh

root=${0:A:h:h}
sandbox=$(mktemp -d)
trap '/bin/rm -rf $sandbox' EXIT
mkdir -p $sandbox/bin $sandbox/home/.apathy
cur=$(<$root/.github/release/version.txt)
installed=$sandbox/home/.apathy/apathy.zsh

# FAKE_LATEST is the latest release; FAKE_FAIL makes every request fail, and
# FAKE_BROKEN serves a release that doesn't parse.
cat > $sandbox/bin/curl <<EOF
#!/bin/zsh -f
print -r -- \${@[-1]} >> $sandbox/urls
[[ -n \$FAKE_FAIL ]] && exit 22
case \${@[-1]} in
  (https://data.jsdelivr.com/*) print -r -- '{"type": "gh", "version": "'\$FAKE_LATEST'"}' ;;
  (https://cdn.jsdelivr.net/*)
    out=\${@[\${@[(i)-o]}+1]}
    if [[ -n \$FAKE_BROKEN ]]; then print 'if then' > \$out
    else sed "s/^typeset -g APATHY_VERSION=.*/typeset -g APATHY_VERSION=\$FAKE_LATEST/" ${(q)root}/.github/release/apathy.zsh > \$out
    fi ;;
esac
EOF
chmod +x $sandbox/bin/curl

typeset -i pass=0 fail=0
# run <plugin> <env...>: a fresh install of apathy.zsh, then apathy-update.
# REPLY is its output and the version loaded afterwards.
run() {
  local plugin=$1
  shift
  cp $root/.github/release/apathy.zsh $installed
  /bin/rm -f $sandbox/urls
  REPLY=$(/usr/bin/env -i PATH=$sandbox/bin:/usr/bin:/bin HOME=$sandbox/home "$@" \
    zsh -fc 'source $1; apathy-update; print -r -- "status=$? version=$APATHY_VERSION"' _ $plugin 2>&1)
}
check() {
  [[ $REPLY == "$1" ]] && (( ++pass )) || { (( ++fail )); print -r -- "FAIL: $2"$'\n'"want: $1"$'\n'"got:  $REPLY" }
}
installed-version() {
  REPLY=$(zsh -fc 'source $1; print -r -- $APATHY_VERSION' _ $installed)
}

run $installed FAKE_LATEST=$cur
check "apathy: $cur is the latest"$'\n'"status=0 version=$cur" 'already up to date'

run $installed FAKE_LATEST=9.9.9
check "apathy: $cur -> 9.9.9"$'\n'"status=0 version=9.9.9" 'updates and reloads in this shell'
installed-version
check 9.9.9 'the file is replaced'
REPLY=$(<$sandbox/urls)
check $'https://data.jsdelivr.com/v1/packages/gh/sifex/apathy/resolved?specifier=latest\nhttps://cdn.jsdelivr.net/gh/sifex/apathy@9.9.9/.github/release/apathy.zsh' 'an exact version is downloaded'

run $installed FAKE_LATEST=9.9.9 FAKE_FAIL=1
check "apathy: can't look up the latest version"$'\n'"status=1 version=$cur" 'offline'

run $installed FAKE_LATEST=9.9.9 FAKE_BROKEN=1
check "apathy: download of 9.9.9 failed"$'\n'"status=1 version=$cur" 'a broken download'
installed-version
check $cur 'a broken download leaves the install alone'
left=($sandbox/home/.apathy/*.new(N))
REPLY=$left
check '' 'and cleans up'

for plugin in $root/apathy.plugin.zsh $root/.github/release/apathy.zsh; do
  run $plugin FAKE_LATEST=9.9.9
  check "apathy: not a downloaded apathy.zsh; update with git pull or your plugin manager"$'\n'"status=1 version=$cur" "${plugin:t} in the source tree"
done

print "update: $pass passed, $fail failed"
(( fail == 0 ))
