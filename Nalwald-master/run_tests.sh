#!/bin/bash
set -e
nimble install malebolgia@1.3.2
nimble install zippy@0.10.16
nim Nalwald.nims | grep -v "^Hint:" | cut -d' ' -f1 | xargs -I {} nim {} -f Nalwald.nims
find . -name *.nim -print0 | xargs -n 1 -0 nim check $1
nim tests -f --run Nalwald.nims
nim testsDanger -f --run Nalwald.nims
