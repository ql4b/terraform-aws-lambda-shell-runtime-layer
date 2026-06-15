FROM public.ecr.aws/lambda/provided:al2023 AS build

ARG ARCH=arm64

RUN microdnf install -y unzip && microdnf clean all

# Runtime
COPY runtime/ /tmp/runtime/
RUN unzip /tmp/runtime/bootstrap-${ARCH}.zip -d /var/runtime && chmod +x /var/runtime/bootstrap

FROM public.ecr.aws/lambda/provided:al2023

COPY --from=build /var/runtime/bootstrap /var/runtime/bootstrap

COPY examples/basic/app/ /var/task/

ENV PATH="/opt/bin:${PATH}"

CMD ["handler.run"]
