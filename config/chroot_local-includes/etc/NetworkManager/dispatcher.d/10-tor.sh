#!/bin/sh

# We don't start Tor automatically so *this* is the time
# when it is supposed to start.

# Run only when the interface is not "lo":
if [ -z "$1" ] || [ "$1" = "lo" ]; then
    exit 0
fi

BASENAME=$(basename "$0")

if [ "$2" = "up" ]; then
    : # go on, that's what this script is for
elif [ "${2}" = "down" ]; then
    echo >&2 "$BASENAME: $1 down: stopping tails-tor-has-bootstrapped.target"
    systemctl --no-block stop tails-tor-has-bootstrapped.target
    exit 0
else
    exit 0
fi

echo >&2 "$BASENAME: $1 up: starting tca.service"
/usr/local/lib/run-with-user-env systemctl --user start tca.service

# that's not what it looks: htpdate will not really be started until Tor has bootstrapped
echo >&2 "$BASENAME: $1 up: restarting htpdate.service"
systemctl --no-block restart htpdate.service

# Wait until the user is done with configuring Tor
echo >&2 "$BASENAME: $1 up: waiting until Tor was configured"
until [ "$(/usr/local/lib/tor_variable get --type=conf DisableNetwork)" = 0 ]; do
    sleep 1
done

echo >&2 "$BASENAME: $1 up: Finished"
