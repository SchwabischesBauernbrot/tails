#!/usr/bin/env python3

# Read bytes from stdin and check if the input data is random by
# calculating the chi-squared value of the input data.
#
# Exit with 0 if the input data is random, otherwise exit with 1.
#
# Usage example:
#   check-randomness.py < /dev/urandom

import sys

# Based on https://gitlab.tails.boum.org/tails/blueprints/-/wikis/veracrypt/#detection
CHI_SQUARE_LOWER_LIMIT = 136
CHI_SQUARE_UPPER_LIMIT = 426


def chi_squared(data) -> float:
    # This is based on the chi-squared test from libblockdev's
    # bd_crypto_device_seems_encrypted()

    # Initialize the symbols list with 256 zeros
    symbols = [0] * 256
    # Calculate the expected value
    e = len(data) / 256
    # Calculate the chi-squared value
    chi_square = 0
    for i in data:
        symbols[i] += 1
    for i in range(256):
        chi_square += (symbols[i] - e) * (symbols[i] - e)
    chi_square /= e
    return chi_square


def main():
    data = sys.stdin.buffer.read()
    chi_squared_value = chi_squared(data)
    # Check if the input data is random
    if CHI_SQUARE_LOWER_LIMIT < chi_squared_value < CHI_SQUARE_UPPER_LIMIT:
        print(f"The input data is random ({chi_squared_value})")
        sys.exit(0)
    else:
        print(f"The input data is not random ({chi_squared_value})")
        sys.exit(1)


if __name__ == "__main__":
    main()
