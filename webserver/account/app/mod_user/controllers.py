# -*- coding: utf-8 -*-
import sys
import time
import json
import random
import alimessage
from flask import Blueprint, request, jsonify, session, g, current_app
from flask_sqlalchemy import SQLAlchemy
import third_login


from .models import User
from app.database import db
import common

reload(sys)
sys.setdefaultencoding('utf8')

# Define the blueprint: 'auth', set its url prefix: app.url/auth
userbp = Blueprint('user', __name__, url_prefix='/starry/user')

VERIFYING_RAND_CODE_LIVE_TIME  = 60

##############################################################

def create_and_send_rand_code(phone_number):
    rand_code = '%06d' % random.randint(1,999999)
    #send message
    if current_app.config.get('SEND_MSG'):
        alimessage.send_message(phone_number,rand_code)
        
    return rand_code

##############################################################
# def register_tourist():
#     req = request.get_json(True)
    
#     seed_token = req.get('seed_token')
#     if seed_token is None:
#         current_app.logger.debug('invalid seed token')
#         return jsonify(code=common.ERROR_INVALID_SEED_TOKEN, message='')
    
#     seed_token = '%s.%f.%d' % (seed_token, time.time(), random.randint(1,100000000))
#     new_token = common.get_hash(seed_token)
        
#     global_id = common.make_tourist_id(new_token)
#     user = User.query.filter_by(global_id=global_id).first()
#     if user is not None:
#         return jsonify(code=common.ERROR_REG_FAILED_TO_EXISTING, message='')

#     #register now.
#     user = User(global_id=global_id,register_time=int(time.time()))
#     db.session.add(user)
#     db.session.commit()

#     new_uid = user.uid
#     key_token = common.create_wrapper_token(third_login.CHANNEL_TOURIST, global_id, new_uid)

#     current_app.logger.debug('new tourist <%s>' % global_id)
#     return jsonify(code=0, uid=new_uid, key_token=key_token)

def register_tourist():
    req = request.get_json(True)
    
    seed_token = req.get('seed_token')
    if seed_token is None:
        current_app.logger.debug('invalid seed token')
        return jsonify(code=common.ERROR_INVALID_SEED_TOKEN, message='')
    
    new_token = common.get_hash(seed_token)
    
    is_new_user = False
    global_id = common.make_tourist_id(new_token)
    user = User.query.filter_by(global_id=global_id).first()
    if user is None:
        user = User(global_id=global_id,register_time=int(time.time()))
        db.session.add(user)
        db.session.commit()
        is_new_user = True

    uid = user.uid
    key_token = common.create_wrapper_token(third_login.CHANNEL_TOURIST, global_id, uid)

    current_app.logger.debug('new tourist <%s>, new user<%s>' % (global_id, str(is_new_user)))
    return jsonify(code=0, uid=uid, key_token=key_token)
################################################################

def register_phone_number():
    req = request.get_json(True)
    phone_number = str(req.get('phone_number') or '')
    tourist_key_token = req.get('tourist_key_token')
    
    tourist_id = None
    if len(phone_number) < 3:
        current_app.logger.error('invalid phone number <%s>' % phone_number)
        return jsonify(code=common.ERROR_REG_FAILED_TO_INVALID_PHONE)
    if tourist_key_token is not None:
        tourist_id = common.get_tourist_id_from_token(tourist_key_token)
        if not common.is_tourist_id(tourist_id):
            current_app.logger.error('invalid tourist_id <%s>' % tourist_id)
            return jsonify(code=common.ERROR_REG_FAILED_TO_BIND_NOT_TOURIST)
        tourist_user = User.query.filter_by(global_id=tourist_id).first()
        if tourist_user is None:
            current_app.logger.error('no such tourist user <%s>' % tourist_id)
            return jsonify(code=common.ERROR_TOURIST_NO_FOUND)
            
    #check if this phone number has already been used or send a code to user's phone
    phone_number_id = common.make_phone_number_id(phone_number)
    record = User.query.filter_by(global_id=phone_number_id).first()
    if record is not None:
        return jsonify(code=common.ERROR_REG_FAILED_TO_PHONE_EXISTING)
    
    r = common.get_redis_conn()
    #check if that phone is already in checking
    cached_key = common.make_register_cached_key(phone_number)
    if r.get(cached_key):
        return jsonify(code=common.ERROR_RANDCODE_BEEN_SENT)

    r.delete(cached_key)
    #ok,send a random code in text message to user's phone
    rand_code = create_and_send_rand_code(phone_number)
    
    phone_number_id = common.make_phone_number_id(phone_number)
    cached_info = {
        'phone_number' : phone_number,
        'rand_code' : rand_code,
        'phone_number_id': phone_number_id,
        'tourist_key_token' : tourist_key_token
    }
    if tourist_id is not None:
        cached_info['tourist_id'] = tourist_id
    #cache it
    r.setex(cached_key,json.dumps(cached_info),VERIFYING_RAND_CODE_LIVE_TIME)
    return jsonify(code = 0, message = 'please check your text message')

################################################################
LUA_CODE_FETCH_AND_DELETE = '''
    local k = KEYS[1]
    local v = redis.call('get',k)
    return v
'''
def verify_register_rand_code():
    req = request.get_json(True)
    phone_number = str(req.get('phone_number') or '')
    rand_code = str(req.get('code') or '')
    
    r = common.get_redis_conn()
    cached_key = common.make_register_cached_key(phone_number)
    cached_str = r.eval(LUA_CODE_FETCH_AND_DELETE,1, cached_key)
    if cached_str is None:
        return jsonify(code=common.ERROR_RANDCODE_BEEN_EXPIRED)
    
    r.delete(cached_key)
    cached_info = json.loads(cached_str)
    phone_number_id = cached_info.get('phone_number_id')
    
    if rand_code != cached_info.get('rand_code'):
        return jsonify(code=common.ERROR_RANDCODE_UNMATCHED) 
    
    if phone_number != cached_info.get('phone_number'):
        return jsonify(code=common.ERROR_RANDCODE_EXCEPTION) 

    #now insert of update the phone number
    tourist_id = cached_info.get('tourist_id')
    
    uid = None
    if tourist_id is not None:
        #update ...
        tourist_user = User.query.filter_by(global_id=tourist_id).first()
        if tourist_user is None:
            return jsonify(code=common.ERROR_TOURIST_NO_FOUND)
        tourist_user.global_id = phone_number_id
        db.session.add(tourist_user)
        db.session.commit()
        uid = tourist_user.uid
    else:
        #register now.
        user = User(global_id=phone_number_id, phone=phone_number, register_time=int(time.time()))
        db.session.add(user)
        db.session.commit()
        uid = user.uid

    key_token = third_login.create_phone_key_token(phone_number_id, uid)
    tourist_key_token = cached_info.get('tourist_key_token') or ''
    return jsonify(code = 0, uid = uid, key_token = key_token, tourist_key_token=tourist_key_token)

################################################################
def get_login_rand_code():
    req = request.get_json(True)
    phone_number = str(req.get('phone_number') or '')
    
    if len(phone_number) < 3:
        current_app.logger.debug('invalid phone number <%s>' % phone_number)
        return jsonify(code=common.ERROR_REG_FAILED_TO_INVALID_PHONE)
            
    #check if this phone number has already been used or send a code to user's phone
    phone_number_id = common.make_phone_number_id(phone_number)
    user = User.query.filter_by(global_id=phone_number_id).first()
    if user is None:
        return jsonify(code=common.ERROR_PHONE_BEEN_EXISTING)

    uid = user.uid
    r = common.get_redis_conn()
    #check if that phone is already in checking
    cached_key = common.make_login_cached_key(phone_number)
    if r.get(cached_key):
        return jsonify(code=common.ERROR_RANDCODE_BEEN_SENT)
        
    #ok,send a random code in text message to user's phone
    rand_code = create_and_send_rand_code(phone_number)
    
    phone_number_id = common.make_phone_number_id(phone_number)
    cached_info = {
        'phone_number' : phone_number,
        'rand_code' : rand_code,
        'phone_number_id': phone_number_id,
        'uid' : uid,
    }
    #cache it
    r.setex(cached_key,json.dumps(cached_info),VERIFYING_RAND_CODE_LIVE_TIME)
    return jsonify(code = 0, message = 'please check your text message')

################################################################
def verify_login_rand_code():
    req = request.get_json(True)
    phone_number = str(req.get('phone_number') or '')
    rand_code = str(req.get('code') or '')
    
    r = common.get_redis_conn()
    cached_key = common.make_login_cached_key(phone_number)
    cached_str = r.eval(LUA_CODE_FETCH_AND_DELETE,1, cached_key)
    if cached_str is None:
        return jsonify(code = common.ERROR_EXPIRED_LOGIN, message = 'expiry')
    
    cached_info = json.loads(cached_str)
    phone_number_id = cached_info.get('phone_number_id')
    uid = cached_info['uid']
    
    if rand_code != cached_info.get('rand_code'):
        current_app.logger.debug('unmatched rand code<%s,%s>' % \
            (rand_code, cached_info.get('rand_code')))
        return jsonify(code=common.ERROR_RANDCODE_UNMATCHED) 
    
    if phone_number != cached_info.get('phone_number'):
        current_app.logger.error('unmatched phone number<%s> <%s>' % \
            (str(phone_number),cached_info.get('phone_number')))
        return jsonify(code=common.ERROR_RANDCODE_EXCEPTION)
    
    if not isinstance(uid,(int,long)):
        current_app.logger.error('invalid uid<%s>' % str(uid))
        return jsonify(code=common.ERROR_UNKNOWN_EXCEPTION)

    key_token = third_login.create_phone_key_token(phone_number_id, uid)
    return jsonify(code = 0, uid = uid, key_token = key_token)

################################################################
def verify_3rd_login():
    req = request.get_json(True)
    code = req.get('code')
    channel = req.get('channel')
    uid = req.get('uid')

    f = common.get_channel_verifying(channel)
    result = f(uid, code)

    return jsonify(**result)

################################################################
def check_token():
    req = request.get_json(True)
    key_token = req.get('key_token')
    uid = int(req.get('uid'))

    channel = common.get_channel_from_token(key_token)
    f = common.get_channel_checking(channel)
    result = f(uid,key_token)
    
    result['channel'] = channel
    current_app.logger.debug('got result <%s>' % str(result))
    return jsonify(**result)


################################################################
def get_user_info():
    req = request.get_json(True)
    uid = int(req.get('uid'))
    user_info_key = common.make_user_info_key(uid)

    r = common.get_redis_conn()
    data = r.get(user_info_key) or '{}'
    return data
################################################################

# URLs
userbp.add_url_rule('/register_tourist', 'register_tourist', register_tourist, methods=['POST'])
userbp.add_url_rule('/register_phone_number', 'register_phone_number', register_phone_number, methods=['POST'])
userbp.add_url_rule('/verify_register_rand_code', 'verify_register_rand_code', verify_register_rand_code, methods=['POST'])
userbp.add_url_rule('/get_login_rand_code', 'get_login_rand_code', get_login_rand_code, methods=['POST'])
userbp.add_url_rule('/verify_login_rand_code', 'verify_login_rand_code', verify_login_rand_code, methods=['POST'])
userbp.add_url_rule('/verify_3rd_login', 'verify_3rd_login', verify_3rd_login, methods=['POST'])
userbp.add_url_rule('/check_token', 'check_token', check_token, methods=['POST'])
userbp.add_url_rule('/get_user_info', 'get_user_info', get_user_info, methods=['POST'])
