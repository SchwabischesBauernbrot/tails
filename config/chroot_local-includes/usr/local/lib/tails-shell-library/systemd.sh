#!/bin/sh

tor_has_bootstrapped() {
	[ -f /run/tor-has-bootstrapped/done ]
}
