#!/bin/bash

set -euo pipefail

# List S3 buckets (curl only — no extra layers)
buckets () {
    curl -sSf \
        --aws-sigv4 "aws:amz:${AWS_REGION}:s3" \
        --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
        -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
        "https://s3.${AWS_REGION}.amazonaws.com/"
}

# Put item to DynamoDB (uuid + jq)
put_item () {
    local table="${TABLE_NAME}"
    local id
    id="$(uuidgen)"

    curl -sSf \
        --aws-sigv4 "aws:amz:${AWS_REGION}:dynamodb" \
        --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
        -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
        -H "Content-Type: application/x-amz-json-1.0" \
        -H "X-Amz-Target: DynamoDB_20120810.PutItem" \
        -d "$(jq -nc --arg table "$table" --arg id "$id" '{
            TableName: $table,
            Item: {
                id: { S: $id },
                created_at: { S: (now | todate) }
            }
        }')" \
        "https://dynamodb.${AWS_REGION}.amazonaws.com/"

    jq -nc --arg id "$id" '{ id: $id, status: "created" }'
}

# Publish to SNS topic (curl only)
publish () {
    local topic="${TOPIC_ARN}"
    local message="${1:-hello from shell lambda}"

    curl -sSf \
        --aws-sigv4 "aws:amz:${AWS_REGION}:sns" \
        --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
        -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
        -d "Action=Publish" \
        -d "TopicArn=${topic}" \
        -d "Message=${message}" \
        "https://sns.${AWS_REGION}.amazonaws.com/"
}

# Get SSM parameter (jq)
get_param () {
    local name="${1:-${PARAM_NAME}}"

    curl -sSf \
        --aws-sigv4 "aws:amz:${AWS_REGION}:ssm" \
        --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
        -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
        -H "Content-Type: application/x-amz-json-1.1" \
        -H "X-Amz-Target: AmazonSSM.GetParameter" \
        -d "$(jq -nc --arg name "$name" '{ Name: $name }')" \
        "https://ssm.${AWS_REGION}.amazonaws.com/" \
    | jq '.Parameter.Value'
}

# Send SQS message (jq)
send_message () {
    local queue_url="${QUEUE_URL}"
    local body="${1:-$(jq -nc '{ event: "ping", ts: (now | todate) }')}"

    curl -sSf \
        --aws-sigv4 "aws:amz:${AWS_REGION}:sqs" \
        --user "${AWS_ACCESS_KEY_ID}:${AWS_SECRET_ACCESS_KEY}" \
        -H "x-amz-security-token: ${AWS_SESSION_TOKEN}" \
        -H "Content-Type: application/x-amz-json-1.0" \
        -H "X-Amz-Target: AmazonSQS.SendMessage" \
        -d "$(jq -nc --arg url "$queue_url" --arg body "$body" '{
            QueueUrl: $url,
            MessageBody: $body
        }')" \
        "https://sqs.${AWS_REGION}.amazonaws.com/"
}
