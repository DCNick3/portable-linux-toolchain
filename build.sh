
set -uexo pipefail

# note: printf is used instead of echo to avoid backslash
# processing and to properly handle values that begin with a '-'.

log() { printf '%s\n' "$*"; }
error() { log "ERROR: $*" >&2; }
fatal() { error "$@"; exit 1; }

# appends a command to a trap
#
# - 1st arg:  code to add
# - remaining args:  names of traps to modify
#
trap_add() {
    trap_add_cmd=$1; shift || fatal "${FUNCNAME} usage error"
    for trap_add_name in "$@"; do
        trap -- "$(
            # print the new trap command
            printf '%s\n' "${trap_add_cmd}"
            # helper fn to get existing trap command from output
            # of trap -p
            extract_trap_cmd() { printf '%s\n' "$3"; }
            # print existing trap command with newline
            eval "extract_trap_cmd $(trap -p "${trap_add_name}")"
        )" "${trap_add_name}" \
            || fatal "unable to add to trap ${trap_add_name}"
    done
}
# set the trace attribute for the above function.  this is
# required to modify DEBUG or RETURN traps because functions don't
# inherit them unless the trace attribute is set
declare -f -t trap_add

trap ':' EXIT

TMPDIR="$(mktemp -d)"
trap_add 'rm -rf -- "$TMPDIR"' EXIT

IIDFILE="$TMPDIR/iid"

docker build . --iidfile "$IIDFILE"
#trap_add 'docker rmi "$(cat -- "$IIDFILE")"' EXIT

CID="$(docker create "$(cat -- "$IIDFILE")" entrypoint)"
trap_add 'docker rm "$CID"' EXIT

docker export "$CID" | tar --delete .dockerenv dev etc proc sys | gzip > toolchain-real.tar.gz
