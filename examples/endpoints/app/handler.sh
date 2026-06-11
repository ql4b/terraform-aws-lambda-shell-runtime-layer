#!/bin/bash

set -eo pipefail

# Health check
health () {
    cat > /dev/null # drain stdin
    jq -nc '{ status: "ok", ts: (now | todate) }'
}

# Echo request context (method, path, query, source IP)
echo_request () {
    jq '{
        method: .requestContext.http.method,
        path: .rawPath,
        query: .rawQueryString,
        sourceIp: .requestContext.http.sourceIp,
        userAgent: .requestContext.http.userAgent
    }'
}

# Timestamp endpoint
timestamp () {
    cat > /dev/null
    jq -nc '{ time: (now | todate), epoch: (now | floor) }'
}
