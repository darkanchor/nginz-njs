.PHONY: clean all nginz-packages

# Native modules to compile from the nginz submodule.
# Each name corresponds to a package directory under submodules/nginz/zig-out/modules/.
# Available: echoz jwt hello requestid waf oidc ratelimit healthcheck canary circuit-breaker redis consul pgrest
NGINZ_MODULES ?= echoz jwt requestid circuit-breaker canary oidc

all: nginx

libquickjs.a:
	cd submodules/quickjs && CFLAGS='-fPIC' make libquickjs.a

# Build selected nginz module packages via zig build.
# Produces submodules/nginz/zig-out/modules/<name>/{<name>_module.o,libcjson.a,...,config}
nginz-packages:
	cd submodules/nginz && zig build package -Doptimize=ReleaseSmall

# Compute --add-module flags from NGINZ_MODULES
NGINZ_MODULE_FLAGS = $(foreach m,$(NGINZ_MODULES),--add-module=$(abspath submodules/nginz/zig-out/modules/$(m)))

nginx: libquickjs.a nginz-packages
	cd submodules/nginx && ./auto/configure \
		--with-http_ssl_module \
		--with-http_v2_module \
		--with-http_v3_module \
		--with-stream \
		--add-module=../njs/nginx \
		$(NGINZ_MODULE_FLAGS) \
		--with-cc-opt="-I ../quickjs" \
		--with-ld-opt="-L ../quickjs" \
		--with-debug && make

clean:
	rm -rf dist/nginx submodules/nginx/objs submodules/quickjs/libquickjs.a
