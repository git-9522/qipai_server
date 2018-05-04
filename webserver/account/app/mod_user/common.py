# -*- coding: utf-8 -*-

import redis
from Crypto.Cipher import AES
from binascii import b2a_hex, a2b_hex
from flask import g, current_app
import hashlib
import time

#####################error code definition###################
ERROR_EXPIRED_LOGIN = -100      #登录状态失效
ERROR_UNEXPECTED_VERIFYING = -101
ERROR_UNEXPECTED_CHECKING = -102
ERROR_TOURIST_NO_FOUND = -103   #没有这个游客
ERROR_UNMATCHED_GID = -104      #GID不匹配
ERROR_UNMATCHED_UID = -105      #UID不匹配
ERROR_EXPIRED_RANDCODE = -106   #验证码过期
ERROR_INVALID_SEED_TOKEN = -107   #无效seed token
ERROR_REG_FAILED_TO_EXISTING = -108   #注册失败，账号已经存在
ERROR_REG_FAILED_TO_INVALID_PHONE = -109   #无效的电话号码
ERROR_REG_FAILED_TO_BIND_NOT_TOURIST = -110   #绑定非游客的账号
ERROR_REG_FAILED_TO_PHONE_EXISTING = -111   #手机已存在
ERROR_RANDCODE_BEEN_SENT = -112   #验证码已经发送
ERROR_RANDCODE_BEEN_EXPIRED = -113   #验证码已过期
ERROR_RANDCODE_UNMATCHED = -114   #验证码不正确
ERROR_RANDCODE_EXCEPTION = -115   #验证码异常
ERROR_PHONE_BEEN_EXISTING = -116   #手机已存在

ERROR_UNKNOWN_EXCEPTION = -999   #未知错误，请重新尝试

#####################error code definition###################

AES_SECRET_KEY = 'bc26c1b55e9250ac'
AES_SECRET_IV = '5298343f8c9e658b'

class AES_ENCRYPT(object):
    def __init__(self):
        self.key = AES_SECRET_KEY
        self.mode = AES.MODE_CBC
     
    def encrypt(self, text):
        cryptor = AES.new(self.key, self.mode, AES_SECRET_IV)
        length = 16
        count = len(text)
        add = length - (count % length)
        text = text + ('\0' * add)
        self.ciphertext = cryptor.encrypt(text)
        return b2a_hex(self.ciphertext)
     
    def decrypt(self, text):
        cryptor = AES.new(self.key, self.mode, AES_SECRET_IV)
        plain_text = cryptor.decrypt(a2b_hex(text))
        return plain_text.rstrip('\0')

def make_tourist_id(global_id):
    return 'TOURIST_%s' % global_id

def is_tourist_id(global_id):
    return global_id.startswith('TOURIST_')

def make_phone_number_id(phone_number):
    return 'PHONE_%s' % phone_number

def make_3rd_global_id(channel, id):
    return '%s_%s' % (channel, id)

def make_register_cached_key(phone_number):
    return 'register_%s' % phone_number

def make_login_cached_key(phone_number):
    return 'login_%s' % phone_number

def wrap_token(channel, token):
    return '%s.%s' % (channel, token)

def get_channel_from_token(token):
    return token.split('.')[0]

def create_login_token(global_id, uid):    
    return ('A0' + AES_ENCRYPT().encrypt(global_id)).upper()

def get_tourist_id_from_token(key_token):
    raw_token = key_token.split('.')[1]
    return AES_ENCRYPT().decrypt(raw_token[2:].lower())

def create_wrapper_token(channel, global_id, uid):
    raw_token = create_login_token(global_id, uid)
    return wrap_token(channel,raw_token)

def get_hash(key):
    sh = hashlib.sha256() 
    sh.update(key)
    return sh.hexdigest()

SALT = 'b8a7c29c59b6735fc442d04c7feaf35b'
def create_raw_key(global_id):
    return get_hash('%s_%s_%f' % (global_id, SALT, time.time()))


def connect_to_redis():
    host = current_app.config['REDIS_IP']
    port = current_app.config['REDIS_PORT']
    return redis.Redis(host=host, port=port)

def get_redis_conn():
    if not hasattr(g, 'redis_conn'):
        g.redis_conn = connect_to_redis()
    return g.redis_conn

THIRD_CHANNELS_VERIFYING = {}
def register_channel_verifying(channel,f):
    THIRD_CHANNELS_VERIFYING[channel] = f

THIRD_CHANNELS_CHECKING = {}
def register_channel_checking(channel,f):
    THIRD_CHANNELS_CHECKING[channel] = f

def get_channel_verifying(channel):
    return THIRD_CHANNELS_VERIFYING[channel]
    
def get_channel_checking(channel):
    return THIRD_CHANNELS_CHECKING[channel]


def make_user_info_key(uid):
    return 'user_info_%d' % uid