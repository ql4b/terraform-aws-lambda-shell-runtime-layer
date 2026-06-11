ARCHS := arm64 amd64

.PHONY: all clean $(ARCHS)

all: $(addsuffix .zip,$(addprefix bootstrap-,$(ARCHS)))

bootstrap-%.zip: %
	@ls -lh $@

$(ARCHS): %:
	CGO_ENABLED=0 GOOS=linux GOARCH=$* go build \
		-ldflags="-s -w" \
		-trimpath \
		-o bootstrap main.go
	zip -j bootstrap-$*.zip bootstrap
	rm -f bootstrap

clean:
	rm -f bootstrap bootstrap-arm64.zip bootstrap-amd64.zip
