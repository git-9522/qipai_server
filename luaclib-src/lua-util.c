#include <lua.h>
#include <lauxlib.h>
#include <time.h>
#include <sys/time.h>
#include <stdlib.h>

static int 
is_same_day_by_lags(time_t t1, time_t t2, int hour, int gmt_zone){
	/************************************************************************/
	/* GMT时间，中国是东八区+8，timestamp为0的时候，中国是8点，如果是5点算跨天的话，利用当前时间戳加上 (8 - 5) x 3600
	再mod 86400得到今天超过5点的秒数
	之所以加上 （8-5）x3600是因为当中国时间为5点的时候，实际上时间戳对应的的GMT时间是21点（保持8个小时的差距），
	我们希望在中国时间的5点前后，除以86400后分别算出来的是不同天，具体表现在它除以86400的商是否增加1，于是我们得补上3个小时（8-5），
	我们希望对于GMT时间来说，21点前后就已经是不同天了，如果希望通过除法算出来，就只能自己做补差,经过我们补差后，那么在21点的时候，
	它的值被强制加上了3 * 3600，再除以86400刚好是整除，于是这算是第二天了
	这样我们可以知道它跨天了
	*/
	/************************************************************************/
	int diff = gmt_zone * 3600 - hour * 3600;
	t1 += diff;
	t2 += diff;
	return t1 / 86400 == t2 / 86400;
}

static int
lis_same_sunup_day(lua_State *L){
    time_t t1 = luaL_checkinteger(L,1);
    time_t t2 = luaL_checkinteger(L,2);

    int lags = 6;
    int gmt_zone = 8;
    if(lua_gettop(L) > 2){
        lags = luaL_checkinteger(L,3);
        if(lua_gettop(L) > 3){
            gmt_zone = luaL_checkinteger(L,4);
        }
    }

    lua_pushboolean(L,is_same_day_by_lags(t1,t2,lags,gmt_zone));
    return 1;
}

static int 
lget_sunup_time(lua_State *L){
    time_t curr_time = luaL_checkinteger(L,1);
    int lags = 6;
    int gmt_zone = 8;
    if(lua_gettop(L) > 1){
        lags = luaL_checkinteger(L,2);
        if(lua_gettop(L) > 2){
            gmt_zone = luaL_checkinteger(L,3);
        }
    }

	int diff_time = (gmt_zone - lags) * 3600;
	curr_time += diff_time;
	int brim = curr_time % 86400;
	lua_pushinteger(L,curr_time - brim - diff_time);
    return 1;
}

static int 
lis_same_week(lua_State *L){
    struct tm tm1, tm2;
    time_t t1 = luaL_checkinteger(L,1);
    time_t t2 = luaL_checkinteger(L,2);

	localtime_r(&t1, &tm1);
	localtime_r(&t2, &tm2);

	if (tm2.tm_wday != tm1.tm_wday){
		int day1 = tm1.tm_wday;
		int day2 = tm2.tm_wday;

		if (day1 == 0){
			day1 = 7;
		}

		if (day2 == 0){
			day2 = 7;
		}

		time_t curr_day = (day1 - day2) * 86400 + t2;// 24 * 3600;
		localtime_r(&curr_day, &tm2);
	}

	int ret = (tm2.tm_year == tm1.tm_year && 
            tm2.tm_mon == tm1.tm_mon && 
            tm2.tm_mday == tm1.tm_mday);
    lua_pushboolean(L,ret);
    return 1;
}

static int 
lis_same_month(lua_State *L){
    struct tm tm1, tm2;
    time_t t1 = luaL_checkinteger(L,1);
    time_t t2 = luaL_checkinteger(L,2);

	localtime_r(&t1, &tm1);
	localtime_r(&t2, &tm2);

	int ret = (tm2.tm_year == tm1.tm_year && 
            tm2.tm_mon == tm1.tm_mon);
    lua_pushboolean(L,ret);
    return 1;
}

static int
lis_same_day(lua_State *L){
    struct tm tm1, tm2;
    time_t t1 = luaL_checkinteger(L,1);
    time_t t2 = luaL_checkinteger(L,2);

	localtime_r(&t1, &tm1);
	localtime_r(&t2, &tm2);

	int ret = (tm2.tm_year == tm1.tm_year && 
            tm2.tm_mon == tm1.tm_mon &&
            tm2.tm_yday == tm1.tm_yday);
    lua_pushboolean(L,ret);
    return 1;
}

static int
lget_now_time(lua_State *L){
    struct timeval tv;
	gettimeofday(&tv,NULL);
	lua_pushinteger(L,tv.tv_sec);
    lua_pushinteger(L,tv.tv_usec);
    return 2;
}


static unsigned int random_seed = 0;
static int 
lrandint(lua_State *L)
{
	int floor_var = luaL_checkinteger(L,1);
	int ceil_var = luaL_checkinteger(L,2);
	if (floor_var > ceil_var){
		return 0;
	}

	++random_seed;
	unsigned int real_seed = (random_seed << 8 | random_seed << 16) + random_seed + time(NULL);
	int gap = ceil_var - floor_var + 1;
	int result = rand_r(&real_seed) % gap + floor_var;
	lua_pushinteger(L, result);
	return 1;
}


LUAMOD_API int
luaopen_util(lua_State *L){
	luaL_checkversion(L);
	luaL_Reg l[] = {
		{ "is_same_sunup_day", lis_same_sunup_day },
		{ "get_sunup_time", lget_sunup_time },
		{ "is_same_week", lis_same_week },
		{ "is_same_month", lis_same_month },
		{ "is_same_day", lis_same_day },
		{ "get_now_time", lget_now_time },
		{ "randint", lrandint },
		{ NULL, NULL },
	};
	luaL_newlib(L,l);

	return 1;
}