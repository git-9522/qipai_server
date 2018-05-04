#define LUA_LIB

#include "skynet_malloc.h"

#include "skynet_socket.h"

#include <lua.h>
#include <lauxlib.h>

#include <assert.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <arpa/inet.h>

#define QUEUESIZE 1024
#define HASHSIZE 4096
#define SMALLSTRING 2048

#define TYPE_DATA 1
#define TYPE_MORE 2
#define TYPE_ERROR 3
#define TYPE_OPEN 4
#define TYPE_CLOSE 5
#define TYPE_WARNING 6
#define TYPE_CONNECTED 7



#define MAX_PROXY_PACK_LENGTH (1024*1024*1024)
/*
	Each package is uint16 + data , uint16 (serialized in big-endian) is the number of bytes comprising the data .
 */

struct netpack {
	int id;
	int size;
	void * buffer;
};

struct uncomplete {
	struct netpack pack;
	struct uncomplete * next;
	int read;
	int header;
};

struct queue {
	int cap;
	int head;
	int tail;
	struct uncomplete * hash[HASHSIZE];
	struct netpack queue[QUEUESIZE];
};

static void
clear_list(struct uncomplete * uc) {
	while (uc) {
		skynet_free(uc->pack.buffer);
		void * tmp = uc;
		uc = uc->next;
		skynet_free(tmp);
	}
}

static int
lclear(lua_State *L) {
	struct queue * q = lua_touserdata(L, 1);
	if (q == NULL) {
		return 0;
	}
	int i;
	for (i=0;i<HASHSIZE;i++) {
		clear_list(q->hash[i]);
		q->hash[i] = NULL;
	}
	if (q->head > q->tail) {
		q->tail += q->cap;
	}
	for (i=q->head;i<q->tail;i++) {
		struct netpack *np = &q->queue[i % q->cap];
		skynet_free(np->buffer);
	}
	q->head = q->tail = 0;

	return 0;
}

static inline int
hash_fd(int fd) {
	int a = fd >> 24;
	int b = fd >> 12;
	int c = fd;
	return (int)(((uint32_t)(a + b + c)) % HASHSIZE);
}

static struct uncomplete *
find_uncomplete(struct queue *q, int fd) {
	if (q == NULL)
		return NULL;
	int h = hash_fd(fd);
	struct uncomplete * uc = q->hash[h];
	if (uc == NULL)
		return NULL;
	if (uc->pack.id == fd) {
		q->hash[h] = uc->next;
		return uc;
	}
	struct uncomplete * last = uc;
	while (last->next) {
		uc = last->next;
		if (uc->pack.id == fd) {
			last->next = uc->next;
			return uc;
		}
		last = uc;
	}
	return NULL;
}

static struct queue *
get_queue(lua_State *L) {
	struct queue *q = lua_touserdata(L,1);
	if (q == NULL) {
		q = lua_newuserdata(L, sizeof(struct queue));
		q->cap = QUEUESIZE;
		q->head = 0;
		q->tail = 0;
		int i;
		for (i=0;i<HASHSIZE;i++) {
			q->hash[i] = NULL;
		}
		lua_replace(L, 1);
	}
	return q;
}

static void
expand_queue(lua_State *L, struct queue *q) {
	struct queue *nq = lua_newuserdata(L, sizeof(struct queue) + q->cap * sizeof(struct netpack));
	nq->cap = q->cap + QUEUESIZE;
	nq->head = 0;
	nq->tail = q->cap;
	memcpy(nq->hash, q->hash, sizeof(nq->hash));
	memset(q->hash, 0, sizeof(q->hash));
	int i;
	for (i=0;i<q->cap;i++) {
		int idx = (q->head + i) % q->cap;
		nq->queue[i] = q->queue[idx];
	}
	q->head = q->tail = 0;
	lua_replace(L,1);
}

static void
push_data(lua_State *L, int fd, void *buffer, int size, int clone) {
	if (clone) {
		void * tmp = skynet_malloc(size);
		memcpy(tmp, buffer, size);
		buffer = tmp;
	}
	struct queue *q = get_queue(L);
	struct netpack *np = &q->queue[q->tail];
	if (++q->tail >= q->cap)
		q->tail -= q->cap;
	np->id = fd;
	np->buffer = buffer;
	np->size = size;
	if (q->head == q->tail) {
		expand_queue(L, q);
	}
}

static struct uncomplete *
save_uncomplete(lua_State *L, int fd) {
	struct queue *q = get_queue(L);
	int h = hash_fd(fd);
	struct uncomplete * uc = skynet_malloc(sizeof(struct uncomplete));
	memset(uc, 0, sizeof(*uc));
	uc->next = q->hash[h];
	uc->pack.id = fd;
	q->hash[h] = uc;

	return uc;
}

static inline void
write_uncomplete_header(uint8_t* header,int offset,uint8_t *buffer,int size){
	memcpy(header + offset,buffer,size);
}

static void
push_more(lua_State *L, int fd, uint8_t *buffer, int size) {
	if (size < 4) {
		struct uncomplete * uc = save_uncomplete(L, fd);
		uc->read = -size;
		write_uncomplete_header((uint8_t*)&uc->header,0,buffer,size);
		return;
	}
	int pack_size = *(int*)buffer;
	buffer += 4;
	size -= 4;

	if (size < pack_size) {
		struct uncomplete * uc = save_uncomplete(L, fd);
		uc->read = size;	//已读
		uc->pack.size = pack_size; //包体总长度
		uc->pack.buffer = skynet_malloc(pack_size);
		memcpy(uc->pack.buffer, buffer, size);
		return;
	}
	push_data(L, fd, buffer, pack_size, 1);

	buffer += pack_size;
	size -= pack_size;
	if (size > 0) {
		push_more(L, fd, buffer, size);
	}
}

static void
close_uncomplete(lua_State *L, int fd) {
	struct queue *q = lua_touserdata(L,1);
	struct uncomplete * uc = find_uncomplete(q, fd);
	if (uc) {
		skynet_free(uc->pack.buffer);
		skynet_free(uc);
	}
}

static int
filter_data_(lua_State *L, int fd, uint8_t * buffer, int size) {
	struct queue *q = lua_touserdata(L,1);
	struct uncomplete * uc = find_uncomplete(q, fd);
	if (uc) {
		// fill uncomplete
		if (uc->read < 0) {
			int read = -uc->read;
			if(read + size < 4){
				uc->read -= size;
				//依旧未完成,读完该读的，再重新链回去
				write_uncomplete_header((uint8_t*)&uc->header,read,buffer,size);
				int h = hash_fd(fd);
				uc->next = q->hash[h];
				q->hash[h] = uc;
				return 1;
			}

			int tmplen = 4-read;
			write_uncomplete_header((uint8_t*)&uc->header,read,buffer,tmplen);
			// read size
			int pack_size = uc->header;
			buffer += tmplen;
			size -= tmplen;
			uc->pack.size = pack_size;
			uc->pack.buffer = skynet_malloc(pack_size);
			uc->read = 0;
		}
		int need = uc->pack.size - uc->read;
		if (size < need) {
			memcpy(uc->pack.buffer + uc->read, buffer, size);
			uc->read += size;
			int h = hash_fd(fd);
			uc->next = q->hash[h];
			q->hash[h] = uc;
			return 1;
		}
		memcpy(uc->pack.buffer + uc->read, buffer, need);
		buffer += need;
		size -= need;
		if (size == 0) {
			lua_pushvalue(L, lua_upvalueindex(TYPE_DATA));
			lua_pushinteger(L, fd);
			lua_pushlightuserdata(L, uc->pack.buffer);
			lua_pushinteger(L, uc->pack.size);
			skynet_free(uc);
			return 5;
		}
		// more data
		push_data(L, fd, uc->pack.buffer, uc->pack.size, 0);
		skynet_free(uc);
		push_more(L, fd, buffer, size);
		lua_pushvalue(L, lua_upvalueindex(TYPE_MORE));
		return 2;
	} else {
		if (size < 4) {
			struct uncomplete * uc = save_uncomplete(L, fd);
			uc->read = -size;
			write_uncomplete_header((uint8_t*)&uc->header,0,buffer,size);
			return 1;
		}
		int pack_size = 0;
		write_uncomplete_header((uint8_t*)&pack_size,0,buffer,4);
		buffer+=4;
		size-=4;

		if (size < pack_size) {
			struct uncomplete * uc = save_uncomplete(L, fd);
			uc->read = size;
			uc->pack.size = pack_size;
			uc->pack.buffer = skynet_malloc(pack_size);
			memcpy(uc->pack.buffer, buffer, size);
			return 1;
		}
		if (size == pack_size) {
			// just one package
			lua_pushvalue(L, lua_upvalueindex(TYPE_DATA));
			lua_pushinteger(L, fd);
			void * result = skynet_malloc(pack_size);
			memcpy(result, buffer, size);
			lua_pushlightuserdata(L, result);
			lua_pushinteger(L, size);
			return 5;
		}
		// more data
		push_data(L, fd, buffer, pack_size, 1);
		buffer += pack_size;
		size -= pack_size;
		push_more(L, fd, buffer, size);
		lua_pushvalue(L, lua_upvalueindex(TYPE_MORE));
		return 2;
	}
}

static inline int
filter_data(lua_State *L, int fd, uint8_t * buffer, int size) {
	int ret = filter_data_(L, fd, buffer, size);
	// buffer is the data of socket message, it malloc at socket_server.c : function forward_message .
	// it should be free before return,
	skynet_free(buffer);
	return ret;
}

static void
pushstring(lua_State *L, const char * msg, int size) {
	if (msg) {
		lua_pushlstring(L, msg, size);
	} else {
		lua_pushliteral(L, "");
	}
}

/*
	userdata queue
	lightuserdata msg
	integer size
	return
		userdata queue
		integer type
		integer fd
		string msg | lightuserdata/integer
 */
static int
lfilter(lua_State *L) {
	struct skynet_socket_message *message = lua_touserdata(L,2);
	int size = luaL_checkinteger(L,3);
	char * buffer = message->buffer;
	if (buffer == NULL) {
		buffer = (char *)(message+1);
		size -= sizeof(*message);
	} else {
		size = -1;
	}

	lua_settop(L, 1);

	switch(message->type) {
	case SKYNET_SOCKET_TYPE_DATA:
		// ignore listen id (message->id)
		assert(size == -1);	// never padding string
		return filter_data(L, message->id, (uint8_t *)buffer, message->ud);
	case SKYNET_SOCKET_TYPE_CONNECT:
		// ignore listen fd connect
        lua_pushvalue(L, lua_upvalueindex(TYPE_CONNECTED));
        lua_pushinteger(L, message->id);
		return 3;
	case SKYNET_SOCKET_TYPE_CLOSE:
		// no more data in fd (message->id)
		close_uncomplete(L, message->id);
		lua_pushvalue(L, lua_upvalueindex(TYPE_CLOSE));
		lua_pushinteger(L, message->id);
		return 3;
	case SKYNET_SOCKET_TYPE_ACCEPT:
		lua_pushvalue(L, lua_upvalueindex(TYPE_OPEN));
		// ignore listen id (message->id);
		lua_pushinteger(L, message->ud);
		pushstring(L, buffer, size);
		return 4;
	case SKYNET_SOCKET_TYPE_ERROR:
		// no more data in fd (message->id)
		close_uncomplete(L, message->id);
		lua_pushvalue(L, lua_upvalueindex(TYPE_ERROR));
		lua_pushinteger(L, message->id);
		pushstring(L, buffer, size);
		return 4;
	case SKYNET_SOCKET_TYPE_WARNING:
		lua_pushvalue(L, lua_upvalueindex(TYPE_WARNING));
		lua_pushinteger(L, message->id);
		lua_pushinteger(L, message->ud);
		return 4;
	default:
		// never get here
		return 1;
	}
}

/*
	userdata queue
	return
		integer fd
		lightuserdata msg
		integer size
 */
static int
lpop(lua_State *L) {
	struct queue * q = lua_touserdata(L, 1);
	if (q == NULL || q->head == q->tail)
		return 0;
	struct netpack *np = &q->queue[q->head];
	if (++q->head >= q->cap) {
		q->head = 0;
	}
	lua_pushinteger(L, np->id);
	lua_pushlightuserdata(L, np->buffer);
	lua_pushinteger(L, np->size);

	return 3;
}

/*
	string msg | lightuserdata/integer

	lightuserdata/integer
 */

static const char *
tolstring(lua_State *L, size_t *sz, int index) {
	const char * ptr;
	if (lua_isuserdata(L,index)) {
		ptr = (const char *)lua_touserdata(L,index);
		*sz = (size_t)luaL_checkinteger(L, index+1);
	} else {
		ptr = luaL_checklstring(L, index, sz);
	}
	return ptr;
}

static int
lpack_raw(lua_State *L) {
	size_t len;
	const char * ptr = tolstring(L, &len, 1);
	if (len >= MAX_PROXY_PACK_LENGTH) {
		return luaL_error(L, "Invalid size (too long) of data : %d", (int)len);
	}

	uint8_t * buffer = skynet_malloc(len);
	memcpy(buffer, ptr, len);

	lua_pushlightuserdata(L, buffer);
	lua_pushinteger(L, len);

	return 2;
}



static int
ltostring(lua_State *L) {
	void * ptr = lua_touserdata(L, 1);
	int size = luaL_checkinteger(L, 2);
	if (ptr == NULL) {
		lua_pushliteral(L, "");
	} else {
		lua_pushlstring(L, (const char *)ptr, size);
		skynet_free(ptr);
	}
	return 1;
}

static const void *
getbuffer(lua_State *L, int index, size_t *sz) {
	const void * buffer = NULL;
	int t = lua_type(L, index);
	if (t == LUA_TSTRING) {
		buffer = lua_tolstring(L, index, sz);
	} else {
		if (t != LUA_TUSERDATA && t != LUA_TLIGHTUSERDATA) {
			luaL_argerror(L, index, "Need a string or userdata");
			return NULL;
		}
		buffer = lua_touserdata(L, index);
		*sz = luaL_checkinteger(L, index+1);
	}
	return buffer;
}

static int 
lpack_proxy_message(lua_State *L){
	if(lua_gettop(L) < 1){
		return 0;
	}

	//由外部传进来的buffer由该接口释放，该接口会返回一个指针与一个长度
	void *buffer = lua_touserdata(L, 1);
	size_t sz = luaL_checkinteger(L, 2);

	if(buffer == NULL){
		return 0;
	}
	
    uint32_t packet_length = sz;
    size_t length = packet_length + sizeof(packet_length);
    void *start = skynet_malloc(length);
    uint8_t *cursor = start;

	*(uint32_t*)cursor = packet_length;
	cursor += sizeof(packet_length);

	memcpy(cursor,buffer,packet_length);
	skynet_free(buffer);
	buffer = NULL;
	
	lua_pushlightuserdata(L,start);
	lua_pushinteger(L,length);

	return 2;
}

static int 
lpack_client_message(lua_State *L){
	if(lua_gettop(L) < 3){
		return 0;
	}

	uint32_t dest = luaL_checkinteger(L,1);
	uint32_t msgid = luaL_checkinteger(L,2);

	size_t sz = 0;
	const void *buffer = getbuffer(L,3,&sz);
	if(buffer == NULL){
		return 0;
	}
	
	uint16_t content_length = sizeof(uint32_t) + sizeof(uint32_t) + sz;
	size_t length = sizeof(content_length) + content_length;
	void* start = skynet_malloc(length);
	uint8_t* cursor = start;

	*(uint16_t*)cursor = htons(content_length);
	cursor += sizeof(content_length);

	*(uint32_t*)cursor = htonl(dest);
	cursor += sizeof(dest);

	*(uint32_t*)cursor = htonl(msgid);
	cursor += sizeof(msgid);

	memcpy(cursor,buffer,sz);

	lua_pushlstring(L,start,length);

	skynet_free(start);
	return 1;
}

static int 
lunpack_client_message(lua_State *L){
	void* ptr = lua_touserdata(L, 1);
	int size = luaL_checkinteger(L, 2);
	if (ptr == NULL) {
		return 0;
	}

	if(size < sizeof(uint32_t) + sizeof(uint32_t)){
		return 0;
	}

	uint8_t* p = (uint8_t*)ptr;
	uint32_t dest = ntohl(*(uint32_t*)p);
	p += sizeof(uint32_t);

	uint32_t msgid = ntohl(*(uint32_t*)p);
	p += sizeof(uint32_t);

	lua_pushinteger(L,dest);
	lua_pushinteger(L,msgid);
	lua_pushlightuserdata(L,p);
	lua_pushinteger(L,size - (p - (uint8_t*)ptr));
	return 4;
}

static int 
lpeek_client_message(lua_State *L){
	size_t size = 0;
	const void* ptr = getbuffer(L,1,&size);
	if (ptr == NULL) {
		return 0;
	}

	if(size < sizeof(uint32_t) + sizeof(uint32_t)){
		return 0;
	}

	const uint8_t* p = (const uint8_t*)ptr;
	uint32_t dest = ntohl(*(uint32_t*)p);
	p += sizeof(uint32_t);

	uint32_t msgid = ntohl(*(uint32_t*)p);
	p += sizeof(uint32_t);

	lua_pushinteger(L,dest);
	lua_pushinteger(L,msgid);

	return 2;
}

static int 
lmodify_dest_to_uid(lua_State *L){
	uint32_t uid = luaL_checkinteger(L,1);
	void* ptr = lua_touserdata(L, 2);
	int size = luaL_checkinteger(L, 3);
	if (ptr == NULL) {
		return 0;
	}

	if(size < sizeof(uint32_t)){
		return 0;
	}

	*(uint32_t*)ptr = htonl(uid);

	lua_pushboolean(L,1);
	return 1;
}

LUAMOD_API int
luaopen_proxypack(lua_State *L) {
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "pop", lpop },
		{ "clear", lclear },
		{ "pack_raw", lpack_raw },
		{ "tostring", ltostring },
		{ "pack_proxy_message", lpack_proxy_message },
		{ "pack_client_message", lpack_client_message },
		{ "unpack_client_message", lunpack_client_message },
		{ "peek_client_message", lpeek_client_message },
		{ "modify_dest_to_uid", lmodify_dest_to_uid },
		{ NULL, NULL },
	};
	luaL_newlib(L,l);

	// the order is same with macros : TYPE_* (defined top)
	lua_pushliteral(L, "data");
	lua_pushliteral(L, "more");
	lua_pushliteral(L, "error");
	lua_pushliteral(L, "open");
	lua_pushliteral(L, "close");
	lua_pushliteral(L, "warning");
	lua_pushliteral(L, "connected");

	lua_pushcclosure(L, lfilter, 7);
	lua_setfield(L, -2, "filter");

	return 1;
}
