# shellcheck shell=ash

log(){
  echo "$(date "+%H:%M:%S.%3N") $*"
}
