#!/bin/sh
# Verifies the signatures a pipeline brings against `.allowed_signers` read from a protected branch,
# never from the change under test, so a merge request cannot trust its own key:
#   a merge request into dev or main: every commit in <target>..HEAD (the source head in a
#   merged-results pipeline), signers from <target>;
#   a pipeline on dev or main, where a project still runs one: every commit on the branch, signers
#   from that branch;
#   a pipeline on a v* tag: the tag and every commit it reaches, signers from main.
# SIGNATURES_SINCE, when set to a commit, starts the history at that commit's children, for a
# project whose earlier history predates signing. Exits 1 naming the first object that fails.
set -eu

fail() { echo "verify-signatures: $*" >&2; exit 1; }

tag=''
if [ -n "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" ]; then
    trusted=$CI_MERGE_REQUEST_TARGET_BRANCH_NAME
    # A merged-results pipeline checks out the service's unsigned merge ref; the request's own
    # commits end at its source head.
    range="refs/remotes/origin/$trusted..${CI_MERGE_REQUEST_SOURCE_BRANCH_SHA:-HEAD}"
elif [ -n "${CI_COMMIT_TAG:-}" ]; then
    trusted=main
    range=HEAD
    tag=$CI_COMMIT_TAG
else
    trusted=${CI_COMMIT_BRANCH:-}
    [ -n "$trusted" ] || fail 'no merge request, branch, or tag to verify'
    range=HEAD
fi

git fetch --quiet origin "+refs/heads/$trusted:refs/remotes/origin/$trusted" \
    || fail "cannot fetch $trusted"
signers=$(mktemp)
trap 'rm -f "$signers"' EXIT
git show "refs/remotes/origin/$trusted:.allowed_signers" > "$signers" 2>/dev/null \
    || fail "$trusted has no .allowed_signers; commit it there first"

verify() { git -c gpg.ssh.allowedSignersFile="$signers" "$@" > /dev/null 2>&1; }

if [ -n "$tag" ]; then
    [ "$(git cat-file -t "refs/tags/$tag" 2>/dev/null)" = tag ] || fail "the tag $tag is lightweight"
    verify verify-tag "$tag" || fail "the tag $tag does not verify"
fi

commits=$(git rev-list "$range" ${SIGNATURES_SINCE:+"^$SIGNATURES_SINCE"}) \
    || fail "cannot list the commits of $range${SIGNATURES_SINCE:+ after $SIGNATURES_SINCE}"
count=0
for commit in $commits; do
    verify verify-commit "$commit" \
        || fail "commit $commit does not verify: $(git log -1 --format=%s "$commit")"
    count=$((count + 1))
done
echo "verify-signatures: $count commit(s)${tag:+ and the tag $tag} verified against $trusted"
