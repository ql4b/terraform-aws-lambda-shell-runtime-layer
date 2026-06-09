#!/bin/bash

set -euo pipefail

# curl only (no layers needed)
weather () {
    curl -Ss "https://wttr.in/?format=3"
}

# jq layer
events () {
    curl -Ss https://api.github.com/events \
    | jq '{
        generated_at: now | todate,
        events: map({
            type,
            repo: .repo.name,
            actor: .actor.login,
            created_at
        })
    }'
}

# uuid + jq layers
id () {
    jq -n --arg id "$(uuidgen)" '{ id: $id }'
}

# htmlq + jq layers
runtimes () {
    curl -sS https://docs.aws.amazon.com/lambda/latest/dg/lambda-runtimes.html \
        | htmlq 'div.table-container' \
        | htmlq --text 'div.table-container:first-of-type tbody code' \
        | jq -R | jq -sc
}

# http-cli + jq layers
status () {
    http-cli --status-codes -o /dev/null https://wttr.in/?format=1 \
    | jq '{ code: .http_cli_status_codes.server }'
}
