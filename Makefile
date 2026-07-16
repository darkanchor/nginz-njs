.PHONY: clean all nginx nginz-packages

# nginz owns all native source pins. This project deliberately uses nginx's
# standard configure/make flow for njs and QuickJS instead of nginz's monolithic
# Zig-built runtime, then links only the native modules needed by this project.
NGINZ_DIR := submodules/nginz
NGINX_DIR := $(NGINZ_DIR)/submodules/nginx
NJS_DIR := $(NGINZ_DIR)/submodules/njs
QUICKJS_DIR := $(NGINZ_DIR)/submodules/quickjs
NGINX_BIN := $(NGINX_DIR)/objs/nginx
OPTIMIZE ?= ReleaseSmall

# Available packages are emitted under $(NGINZ_DIR)/zig-out/modules/.
NGINZ_MODULES ?= echoz jwt requestid circuit-breaker canary oidc

all: nginx

$(QUICKJS_DIR)/libquickjs.a:
	$(MAKE) -C $(QUICKJS_DIR) CFLAGS='-fPIC' libquickjs.a

nginz-packages:
	cd $(NGINZ_DIR) && zig build package -Doptimize=$(OPTIMIZE)

NGINZ_MODULE_FLAGS = $(foreach m,$(NGINZ_MODULES),--add-module=$(abspath $(NGINZ_DIR)/zig-out/modules/$(m)))

nginx: $(QUICKJS_DIR)/libquickjs.a nginz-packages
	cd $(NGINX_DIR) && ./auto/configure \
		--with-http_ssl_module \
		--with-http_v2_module \
		--with-http_v3_module \
		--with-stream \
		--with-compat \
		--add-module=$(abspath $(NJS_DIR)/nginx) \
		$(NGINZ_MODULE_FLAGS) \
		--with-cc-opt="-I ../quickjs" \
		--with-ld-opt="-L ../quickjs" \
		--with-debug
	$(MAKE) -C $(NGINX_DIR)
	test -x $(NGINX_BIN)

clean:
	rm -rf dist/nginx $(NGINX_DIR)/objs $(QUICKJS_DIR)/libquickjs.a
