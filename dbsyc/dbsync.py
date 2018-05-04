# -*- coding: utf-8 -*-  

import time
import json
import logging
import pymongo
import redis
import ConfigParser
import sys
import logging

config = None

LUA_FETCH_CODE = '''
    local dqk = KEYS[1]
    local dqk_db = ARGV[1]
    redis.call('select',dqk_db)
    if redis.call('hlen',dqk) == 0 then
        return nil
    end 
    return redis.call('hgetall',dqk)
'''

LUA_FETCH_DATA = '''
    local data_db = KEYS[1]
    local prefix = ARGV[1]
    local uid = ARGV[2]
    redis.call('select',data_db)
    return redis.call('get',prefix .. uid)
'''

LUA_POP_CODE = '''
    local dqk = KEYS[1]
    local dqk_db = ARGV[1]
    local uid = ARGV[2]
    local seq = ARGV[3]
    redis.call('select',dqk_db)
    if redis.call('hget',dqk,uid) == seq then
        return redis.call('hdel',dqk,uid)
    end
    return false
'''
def save_data(uid,user_data,client_conn):
    if user_data is None:
        logging.error('invalid user data')
        return False

    user_info = json.loads(user_data)
    if len(user_info) < 1:
        logging.error('invalid user data <%s>', user_data)
        return False
    #save to mongodb
    mongo_table = client_conn[config['mongo_db']][config['mongo_table']]
    mongo_table.update_one({'_id': uid},{'$set':user_info},True)

def handle(redis_conn, client_conn):
    #取出第一个uid
    continuous_failed_times = 0
    seq = 0
    while True:
        try:
            uid_seq_list = redis_conn.eval(LUA_FETCH_CODE,1,config['dirty_key'],config['dirty_db'])
            if uid_seq_list is None:
                logging.info('there is no cache to handle anymore,wait a second')
                time.sleep(5)
                continue

            for i in range(len(uid_seq_list)/2):
                uid = int(uid_seq_list[i*2])
                seq = int(uid_seq_list[i*2 + 1])
                try:
                    user_data = redis_conn.eval(LUA_FETCH_DATA,1,config['data_db'],
                        config['data_prefix'],uid)
                    logging.info('now save <%d> <%s> <%s>', uid, user_data, str(type(user_data)))
                    save_data(uid, user_data, client_conn)
                    continuous_failed_times = 0
                except Exception as e:
                    logging.error(e.message)
                    logging.exception(e)
                    continuous_failed_times += 1
                    
                #pop this uid from dirty queue
                if not redis_conn.eval(LUA_POP_CODE, 1, config['dirty_key'], config['dirty_db'], uid,seq):
                    logging.error('failed to pop uid <%d> seq<%d>', uid,seq)
                    
        except Exception as e:
            logging.error(e.message)
            logging.exception(e)
            continuous_failed_times += 1
            time.sleep(1)

def parse_cfg(cfg_path):
    conf = ConfigParser.ConfigParser()
    conf.read(cfg_path)
    redis_host = conf.get("redis", "host")  
    redis_port = conf.getint("redis", "port")
    dirty_key = conf.get("redis", "dirty_key")
    data_prefix = conf.get("redis", "data_prefix")
    dirty_db = conf.getint("redis", "dirty_db")
    data_db = conf.getint("redis", "data_db")

    mongo_host = conf.get("mongo", "host")
    mongo_port = conf.getint("mongo", "port")
    mongo_db = conf.get("mongo", "db")
    mongo_table = conf.get("mongo", "table")

    return {
        'redis_host':redis_host,
        'redis_port':redis_port,
        'dirty_key':dirty_key,
        'data_prefix':data_prefix,
        'dirty_db':dirty_db,
        'data_db':data_db,

        'mongo_host':mongo_host,
        'mongo_port':mongo_port,
        'mongo_db':mongo_db,
        'mongo_table':mongo_table,
    }

def main():
    logging.basicConfig(level=logging.DEBUG,
        format='%(asctime)s:[line:%(lineno)d] %(message)s',
        datefmt='%a, %d %b %Y %H:%M:%S',
        stream=sys.stdout)
    cfg_path = sys.argv[1]

    global config
    config = parse_cfg(cfg_path)
    #连上redis
    redis_conn = redis.StrictRedis(host=config['redis_host'], port=config['redis_port'], db=0)
    #连上mongo
    client_conn  = pymongo.MongoClient(config['mongo_host'], config['mongo_port'])

    handle(redis_conn, client_conn)
    
if __name__ == '__main__':
    main()