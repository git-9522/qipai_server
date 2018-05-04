DEPS_DIR=../deps
SKYNET_SRC_PATH = $(DEPS_DIR)/skynet
PBC_SRC_PATH=$(DEPS_DIR)/pbc

PBC_LIB=$(PBC_SRC_PATH)/build/libpbc.a

include $(SKYNET_SRC_PATH)/platform.mk

LUA_CLIB_PATH ?= luaclib

#CFLAGS = -g -O2 -Wall -I$(LUA_INC) $(MYCFLAGS)
CFLAGS = -g -Wall -I$(LUA_INC) $(MYCFLAGS)

LUA_INC ?= $(SKYNET_SRC_PATH)/3rd/lua


CSERVICE = 
LUA_CLIB = proxypack protobuf cjson fs util slog textfilter

linux freebsd macosx: \
  $(SKYNET_SRC_PATH)/skynet \
  $(foreach v, $(LUA_CLIB), $(LUA_CLIB_PATH)/$(v).so) 

$(SKYNET_SRC_PATH)/skynet :
	cd $(SKYNET_SRC_PATH) && $(MAKE) $(MAKECMDGOALS)

$(PBC_LIB):
	cd $(PBC_SRC_PATH) && $(MAKE)

$(LUA_CLIB_PATH) :
	mkdir $(LUA_CLIB_PATH)

$(LUA_CLIB_PATH)/proxypack.so : luaclib-src/lua-proxypack.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) -I$(SKYNET_SRC_PATH)/skynet-src $^ -o $@	

$(LUA_CLIB_PATH)/cjson.so : luaclib-src/lua-cjson.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@	

$(LUA_CLIB_PATH)/protobuf.so : luaclib-src/lua-pbc.c $(PBC_LIB) | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@ -I$(PBC_SRC_PATH)  -L$(PBC_SRC_PATH)/build -lpbc

$(LUA_CLIB_PATH)/fs.so : luaclib-src/lua-fs.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@	

$(LUA_CLIB_PATH)/util.so : luaclib-src/lua-util.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@	

$(LUA_CLIB_PATH)/slog.so : luaclib-src/lua-slog.c | $(LUA_CLIB_PATH)
	$(CC) $(CFLAGS) $(SHARED) $^ -o $@	

$(LUA_CLIB_PATH)/textfilter.so : luaclib-src/lua-textfilter.cc | $(LUA_CLIB_PATH)
	$(CXX) $(CFLAGS) $(SHARED) $^ -o $@	

clean :
	rm -f $(LUA_CLIB_PATH)/*.so
