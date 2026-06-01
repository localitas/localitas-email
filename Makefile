.PHONY: build test run dev stop lint release-build release

APP_NAME := email
BINARY := $(APP_NAME)-server
VERSION := $(shell git describe --tags --always --dirty 2>/dev/null || echo "dev")
COMMIT := $(shell git rev-parse --short HEAD 2>/dev/null || echo "unknown")
LDFLAGS := -s -w -X main.version=$(VERSION) -X main.commit=$(COMMIT)

PORT ?= 9208
CORE_URL ?= http://localhost:8090
BASE_PATH ?= /apps/ext/$(APP_NAME)/
DEV_USER_EMAIL ?= didipk@gmail.com
DEV_USER_NAME ?= Didip Kerabat
DEV_USER_ID ?= 2b9af8b9-856a-4710-9ab6-58fe4eccdf24
DEV_TOKEN := $(shell echo '{"email":"$(DEV_USER_EMAIL)","name":"$(DEV_USER_NAME)","user_id":"$(DEV_USER_ID)"}' | base64)
PID_FILE := bin/$(BINARY).pid
LOG_FILE := bin/$(BINARY).log

BIN_DIR := bin

build:
	@mkdir -p $(BIN_DIR)
	go build -ldflags "$(LDFLAGS)" -o $(BIN_DIR)/$(BINARY) ./cmd/$(BINARY)

test:
	go test -v ./...

dev: build stop
	@echo "Starting $(BINARY) on port $(PORT)..."
	@mkdir -p $(BIN_DIR)
	@nohup ./$(BIN_DIR)/$(BINARY) \
		--listen :$(PORT) \
		--core-url $(CORE_URL) \
		--base-path $(BASE_PATH) \
		--token $(DEV_TOKEN) \
		> $(LOG_FILE) 2>&1 &
	@echo $$! > $(PID_FILE)
	@echo "$(BINARY) running on port $(PORT) (pid $$(cat $(PID_FILE)))"

run: build
	./$(BIN_DIR)/$(BINARY) --listen :0 --core-url $(CORE_URL) --base-path / --token $(DEV_TOKEN)

stop:
	@if [ -f $(PID_FILE) ]; then \
		kill $$(cat $(PID_FILE)) 2>/dev/null || true; \
		rm -f $(PID_FILE); \
	fi
	@-lsof -ti:$(PORT) | xargs kill -9 2>/dev/null || true
	@echo "$(BINARY) stopped"

lint:
	gofmt -w .
	go vet ./...

release-build:
	@echo "Building $(BINARY) $(VERSION) (commit: $(COMMIT))..."
	@mkdir -p $(BIN_DIR)
	@echo "  darwin/arm64..."
	@GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -trimpath \
		-o $(BIN_DIR)/$(BINARY)-darwin-arm64 ./cmd/$(BINARY)
	@echo "  linux/amd64..."
	@GOOS=linux GOARCH=amd64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -trimpath \
		-o $(BIN_DIR)/$(BINARY)-linux-amd64 ./cmd/$(BINARY)
	@echo "  linux/arm64..."
	@GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags "$(LDFLAGS)" -trimpath \
		-o $(BIN_DIR)/$(BINARY)-linux-arm64 ./cmd/$(BINARY)
	@echo "All binaries built:"
	@ls -lh $(BIN_DIR)/$(BINARY)-*

release: release-build
	@if ! gh auth status >/dev/null 2>&1; then \
		echo "Not authenticated with GitHub. Run: gh auth login"; \
		exit 1; \
	fi
	@TAG=$(VERSION) && \
		echo "Creating release $$TAG..." && \
		gh release create $$TAG \
			$(BIN_DIR)/$(BINARY)-darwin-arm64 \
			$(BIN_DIR)/$(BINARY)-linux-amd64 \
			$(BIN_DIR)/$(BINARY)-linux-arm64 \
			--title "$$TAG" \
			--generate-notes && \
		echo "Release $$TAG published"
