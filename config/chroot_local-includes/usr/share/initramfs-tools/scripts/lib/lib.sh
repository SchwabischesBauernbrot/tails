# shellcheck shell=ash

PREREQS=""

prereqs() { echo "$PREREQS"; }

case "${1:-}" in
prereqs)
    prereqs
    exit 0
    ;;
esac

log() {
    echo "$(date "+%H:%M:%S.%3N") $*"
}
