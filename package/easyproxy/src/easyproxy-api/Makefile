BIN     := easyproxy-api
OUT     := ../../files/usr/bin/$(BIN)
GO      ?= go
LDFLAGS := -s -w
TAGS    := -trimpath

.PHONY: all build cross clean test

all: build

build:
	CGO_ENABLED=0 $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o $(OUT) ./cmd/easyproxy-api

# 交叉编译：路由器常见架构（amd64 供 .13 与 x86 软路由）
cross: amd64 mips mipsel arm64 arm

amd64:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o $(OUT) ./cmd/easyproxy-api

mips:
	CGO_ENABLED=0 GOOS=linux GOARCH=mips GOMIPS=softfloat $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o dist/$(BIN)-mips ./cmd/easyproxy-api

mipsel:
	CGO_ENABLED=0 GOOS=linux GOARCH=mipsle GOMIPS=softfloat $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o dist/$(BIN)-mipsel ./cmd/easyproxy-api

arm64:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o dist/$(BIN)-arm64 ./cmd/easyproxy-api

arm:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm GOARM=7 $(GO) build $(TAGS) -ldflags "$(LDFLAGS)" -o dist/$(BIN)-arm ./cmd/easyproxy-api

test:
	$(GO) vet ./...

clean:
	rm -f $(OUT) dist/$(BIN)-*
