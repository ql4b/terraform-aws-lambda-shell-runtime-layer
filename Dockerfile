FROM public.ecr.aws/lambda/provided:al2023 AS build

ARG LAYERS_VERSION=v0.0.4
ARG ARCH=arm64

RUN microdnf install -y unzip && microdnf clean all

# Runtime
COPY runtime/ /tmp/runtime/
RUN unzip /tmp/runtime/bootstrap-${ARCH}.zip -d /var/runtime && chmod +x /var/runtime/bootstrap

# Tool layers from GitHub releases
RUN curl -sSL -o /tmp/jq.zip "https://github.com/ql4b/lambda-shell-layers/releases/download/${LAYERS_VERSION}/jq-${ARCH}-layer.zip" \
    && curl -sSL -o /tmp/uuid.zip "https://github.com/ql4b/lambda-shell-layers/releases/download/${LAYERS_VERSION}/uuid-${ARCH}-layer.zip" \
    && curl -sSL -o /tmp/htmlq.zip "https://github.com/ql4b/lambda-shell-layers/releases/download/${LAYERS_VERSION}/htmlq-${ARCH}-layer.zip" \
    && curl -sSL -o /tmp/qrencode.zip "https://github.com/ql4b/lambda-shell-layers/releases/download/${LAYERS_VERSION}/qrencode-${ARCH}-layer.zip" \
    && for zip in /tmp/*.zip; do unzip -o "$zip" -d /opt; done


FROM public.ecr.aws/lambda/provided:al2023

COPY --from=build /var/runtime/bootstrap /var/runtime/bootstrap
COPY --from=build /opt/bin/ /opt/bin/

COPY examples/complete/app/ /var/task/

ENV PATH="/opt/bin:${PATH}"

CMD ["handler.weather"]
