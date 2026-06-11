#!/bin/bash

set -euo pipefail

run () {
    curl -Ss https://wttr.in/?format=3
}