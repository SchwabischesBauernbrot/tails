#!/bin/sh

MACSPOOF_SETTING='/var/lib/live/config/tails.macspoof'
NETWORK_SETTING='/var/lib/live/config/tails.network'

_get_tg_setting() {
    if [ -r "${1}" ]; then
        . "${1}"
        eval "echo \${${2}:-}"
    fi
}

mac_spoof_is_enabled() {
    # Only return false when explicitly told so to increase failure
    # safety.
    [ "$(_get_tg_setting "${MACSPOOF_SETTING}" TAILS_MACSPOOF_ENABLED)" != false ]
}

tails_network_enabled() {
    # Only return true when explicitly told so to increase failure
    # safety.
    [ "$(_get_tg_setting "${NETWORK_SETTING}" TAILS_NETWORK)" = true ]
}
