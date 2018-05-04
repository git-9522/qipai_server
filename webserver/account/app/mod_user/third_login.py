# -*- coding: utf-8 -*-
import sys
import os
import requests
import json
import time
from .models import User
from app.database import db
import common
from flask import current_app

reload(sys)
sys.setdefaultencoding('utf8')

CHANNEL_WECHAT = 'wx'
CHANNEL_PHONE = 'phone'
CHANNEL_TOURIST = 'tourist'

SESSION_ALIVE_TIME = 15 * 86400
def create_or_fetch_user(global_id):
    user = User.query.filter_by(global_id=global_id).first()
    if user is None:
        #does not exist,create it
        user = User(global_id=global_id, register_time=int(time.time()))
        db.session.add(user)
        db.session.commit()
    uid = user.uid

    return uid

    
def get_proxies():
    proxies = {} 
    if current_app.config.has_key('HTTP_PROXY'):
        proxies['http'] = current_app.config.get('HTTP_PROXY')
        proxies['https'] = current_app.config.get('HTTP_PROXY')
    return proxies
###############################################wechat##############################
WECHAT_APP_ID = 'wxbf694361cca67b76'
WECHAT_APP_SECRET = 'b5ce44568da3a27a6934486c30876f34'

WECHAT_USERINFO_URL = "https://api.weixin.qq.com/sns/userinfo?access_token=%s&openid=%s"
def update_wechat_user_info(access_token, open_id):
    URL = WECHAT_USERINFO_URL % (access_token, open_id)
    
    r = requests.get(URL, proxies=get_proxies(), verify=False)
    r.encoding = 'utf-8'
    rsp = r.json()
    
    user_info = {}
    user_info['name'] = rsp.get('nickname') or ''

    #1为男性，2为女性
    user_info['sex'] = rsp.get('sex') or 1
    icon = rsp.get('headimgurl') or ''
    if icon.endswith('/0'):
        icon = icon[:len(icon) - 1] + '64'
    user_info['icon'] = rsp.get('headimgurl') or ''
    user_info['channel'] = CHANNEL_WECHAT

    return user_info

LUA_CODE_UPDATE_SESSION_AND_INFO = '''
    local session_key = KEYS[1]
    local session_value = ARGV[1]
    local user_info_key = KEYS[2]
    local user_info_value = ARGV[2]
    local expiry_in = tonumber(ARGV[3])
    redis.call('setex',session_key,expiry_in,session_value)
    redis.call('setex',user_info_key,expiry_in,user_info_value)
'''

WECHAT_LOGIN_URL = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=%s&secret=%s&code=%s&grant_type=authorization_code"
def verify_wechat(uid, code):
    current_app.logger.debug('verify_wechat=======<%d><%s>',uid,code)
    URL = WECHAT_LOGIN_URL % (WECHAT_APP_ID, WECHAT_APP_SECRET, code)

    current_app.logger.debug('before verify=======<%d><%s>,URL<%s>,<%s>',uid,code,URL,get_proxies())
    r = requests.get(URL, proxies=get_proxies(), verify=False)
    r.encoding = 'utf-8'
    current_app.logger.debug('after verify=======<%d><%s>',uid,code)
    rsp = r.json()
    
    if rsp.has_key('errcode'):
        current_app.logger.error('got an error[%d] while checking code <%s>', (rsp.get('errcode'), code))
        return {'code':common.ERROR_UNEXPECTED_VERIFYING, 'message':'failed to check'}
    access_token = rsp.get('access_token')
    refresh_token = rsp.get('refresh_token')
    open_id = rsp.get('openid')
    expires_in = rsp.get('expires_in')

    global_id = common.make_3rd_global_id(CHANNEL_WECHAT, open_id)
    new_uid = create_or_fetch_user(global_id)

    raw_key = common.create_raw_key(global_id)
    cached_key = common.wrap_token(CHANNEL_WECHAT, raw_key)

    cached_value = {
        'access_token' : access_token,
        'refresh_token' : refresh_token,
        'global_id' : global_id,
        'uid' : new_uid,
        'expires_at' : int(time.time()) + expires_in,
        'open_id': open_id,
    }

    user_info_key = common.make_user_info_key(new_uid)
    user_info = {}
    try:
        user_info = update_wechat_user_info(access_token, open_id)
    except Exception as e:
        current_app.logger.error('failed to get user_info access_token<%s>, openid<%s>', access_token, open_id)
        current_app.logger.exception(e)

    r = common.get_redis_conn()
    r.eval(LUA_CODE_UPDATE_SESSION_AND_INFO, 2, cached_key, user_info_key, 
           json.dumps(cached_value), json.dumps(user_info), SESSION_ALIVE_TIME)

    return {'code':0, 'uid':new_uid, 'key_token' : cached_key}

WECHAT_REFRESH_URL = "https://api.weixin.qq.com/sns/oauth2/refresh_token?appid=%s&grant_type=refresh_token&refresh_token=%s"
def check_wechat(uid, token):
    r = common.get_redis_conn()
    v = r.get(token)
    if v == None:
        return {'code':common.ERROR_EXPIRED_LOGIN, 'message':'relogin please'}
    cached_value = json.loads(v)
    access_token = cached_value.get('access_token')
    refresh_token = cached_value.get('refresh_token')
    global_id = cached_value.get('global_id')
    uid = cached_value.get('uid')
    expires_at = cached_value.get('expires_at')
    open_id = cached_value.get('open_id')

    if int(time.time()) < expires_at:
        return {'code':0, 'uid':uid, 'key_token':token}

    URL = WECHAT_REFRESH_URL % (WECHAT_APP_ID, refresh_token)

    #remote check or refresh the token...
    r = requests.get(URL ,proxies=get_proxies(), verify=False)
    r.encoding = 'utf-8'
    rsp = r.json()

    if rsp.has_key('errcode'):
        current_app.logger.error('got an error[%d] while checking token <%s>', (rsp.get('errcode'), token))
        return {'code':common.ERROR_UNEXPECTED_VERIFYING, 'message':'failed to refresh'}

    new_access_token = rsp.get('access_token')
    new_refresh_token = rsp.get('refresh_token')
    expires_in = rsp.get('expires_in')
    new_openid = rsp.get('openid')

    new_global_id = common.make_3rd_global_id(CHANNEL_WECHAT, new_openid)
    if new_global_id != global_id:
        return {'code':common.ERROR_UNMATCHED_GID, 'message':'failed to refresh'}

    cached_value['access_token'] = new_access_token
    cached_value['refresh_token'] = new_refresh_token
    cached_value['expires_at'] = int(time.time()) + expires_in

    user_info_key = common.make_user_info_key(uid)
    user_info = {}
    try:
        user_info = update_wechat_user_info(access_token, open_id)
    except Exception as e:
        current_app.logger.error('failed to get user_info access_token<%s>, openid<%s>', access_token, open_id)
        current_app.logger.exception(e)

    r = common.get_redis_conn()
    r.eval(LUA_CODE_UPDATE_SESSION_AND_INFO, 2, token, user_info_key, 
           json.dumps(cached_value), json.dumps(user_info), SESSION_ALIVE_TIME)

    return {'code':0, 'uid':uid, 'key_token':token}

#######################################phone####################################
def create_phone_key_token(global_id, uid):
    r = common.get_redis_conn()
    raw_key = common.create_raw_key(global_id)
    cached_key = common.wrap_token(CHANNEL_PHONE, raw_key)

    cached_value = {
        'uid':uid,
        'global_id':global_id
    }

    r.setex(cached_key, json.dumps(cached_value), SESSION_ALIVE_TIME)
    return cached_key

def check_phone(uid, token):
    r = common.get_redis_conn()
    v = r.get(token)
    if v == None:
        return {'code':common.ERROR_EXPIRED_LOGIN, 'message':'relogin please'}

    cached_value = json.loads(v)
    if uid != cached_value.get('uid'):
        return {'code':common.ERROR_UNMATCHED_UID, 'message':'relogin please'}
    
    r.expire(token, SESSION_ALIVE_TIME)
    return {'code':0, 'uid':uid, 'key_token':token}

#######################################tourist####################################
def check_tourist(uid, token):
    tourist_id = common.get_tourist_id_from_token(token)
    cached_key = common.wrap_token(CHANNEL_TOURIST, tourist_id)
    r = common.get_redis_conn()
    real_uid = r.get(cached_key)
    if real_uid is None:
        user = User.query.filter_by(global_id=tourist_id).first()
        if user is None:
            return {'code':common.ERROR_TOURIST_NO_FOUND, 'message':'no such tourist'}
        real_uid = user.uid
        r.setex(cached_key, real_uid, SESSION_ALIVE_TIME)
    else:
        real_uid = int(real_uid)

    if uid != real_uid:
        return {'code':common.ERROR_UNMATCHED_UID, 'message':'unmatched uid'}
    
    return {'code':0, 'uid':uid, 'key_token':token}


##############register#################
common.register_channel_verifying(CHANNEL_WECHAT,verify_wechat)


##############register#################
common.register_channel_checking(CHANNEL_WECHAT,check_wechat)
common.register_channel_checking(CHANNEL_PHONE, check_phone)
common.register_channel_checking(CHANNEL_TOURIST, check_tourist)
