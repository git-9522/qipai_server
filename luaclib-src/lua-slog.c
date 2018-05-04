#include <lua.h>
#include <lauxlib.h>
#include <syslog.h>
#include <string.h>

static const char *g_ident = NULL;
static int 
lopenlog(lua_State *L){
    const char* ident = luaL_checkstring(L,1);
    int option = luaL_checkinteger(L,2);
    int facility = luaL_checkinteger(L,3);

    g_ident = strdup(ident);
    //tood openlog有可能会缓存着new_ident,因此这里必须重新new一份
    openlog(g_ident,option,facility);

    lua_pushboolean(L,1);
    return 1;
}

static int 
lsyslog(lua_State *L){
    int priority = luaL_checkinteger(L,1);
    const char* content = luaL_checkstring(L,2);

    syslog(priority,"%s",content);

    lua_pushboolean(L,1);
    return 1;
}

struct lib_constant{
    const char* name;
    int value;
};
#define DEFINE_CONSTANT(v) {#v,v}

LUAMOD_API int
luaopen_slog(lua_State *L){
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "openlog", lopenlog },
		{ "syslog", lsyslog },
		{ NULL, NULL },
	};
	luaL_newlib(L,l);

    struct lib_constant option[] = {
            DEFINE_CONSTANT(LOG_CONS),
            DEFINE_CONSTANT(LOG_NDELAY),
            DEFINE_CONSTANT(LOG_NOWAIT),
            DEFINE_CONSTANT(LOG_ODELAY),
            DEFINE_CONSTANT(LOG_PERROR),
            DEFINE_CONSTANT(LOG_PID),
    };
    struct lib_constant facility[] = {
            DEFINE_CONSTANT(LOG_AUTH),
            DEFINE_CONSTANT(LOG_AUTHPRIV),
            DEFINE_CONSTANT(LOG_CRON),
            DEFINE_CONSTANT(LOG_DAEMON),
            DEFINE_CONSTANT(LOG_FTP),
            DEFINE_CONSTANT(LOG_KERN),
            DEFINE_CONSTANT(LOG_LOCAL0),
            DEFINE_CONSTANT(LOG_LOCAL1),
            DEFINE_CONSTANT(LOG_LOCAL2),
            DEFINE_CONSTANT(LOG_LOCAL3),
            DEFINE_CONSTANT(LOG_LOCAL4),
            DEFINE_CONSTANT(LOG_LOCAL5),
            DEFINE_CONSTANT(LOG_LOCAL6),
            DEFINE_CONSTANT(LOG_LOCAL7),
            DEFINE_CONSTANT(LOG_LPR),
            DEFINE_CONSTANT(LOG_MAIL),
            DEFINE_CONSTANT(LOG_NEWS),
            DEFINE_CONSTANT(LOG_SYSLOG),
            DEFINE_CONSTANT(LOG_USER),
            DEFINE_CONSTANT(LOG_UUCP),
    };
    struct lib_constant level[] = {
            DEFINE_CONSTANT(LOG_EMERG),
            DEFINE_CONSTANT(LOG_ALERT),
            DEFINE_CONSTANT(LOG_CRIT),
            DEFINE_CONSTANT(LOG_ERR),
            DEFINE_CONSTANT(LOG_WARNING),
            DEFINE_CONSTANT(LOG_NOTICE),
            DEFINE_CONSTANT(LOG_INFO),
            DEFINE_CONSTANT(LOG_DEBUG),
    };

    int i = 0;
#define REGISTER_CONSTANT(v)    \
    lua_pushstring(L,#v);    \
    lua_newtable(L);            \
    for(i = 0;i < sizeof(v) / sizeof((v)[0]); ++i){ \
        lua_pushstring(L,(v)[i].name);  \
        lua_pushinteger(L,(v)[i].value);    \
        lua_rawset(L,-3);\
    }                   \
    lua_rawset(L,-3);   \

    //option.....
    REGISTER_CONSTANT(option);
    REGISTER_CONSTANT(facility);
    REGISTER_CONSTANT(level);

#undef REGISTER_CONSTANT

	return 1;
}