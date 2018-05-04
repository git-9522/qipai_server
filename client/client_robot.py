import json
import socket
import struct
import select
import threading
import time
from datetime import datetime
import logging
import sys
import os
import StringIO

SERVER_TYPE_GATEWAY = 1
SERVER_TYPE_PROXY = 2
SERVER_TYPE_TABLESVR = 3
SERVER_TYPE_HALLSVR = 4
SERVER_TYPE_DBSVR = 5
SERVER_TYPE_MATCHSVR = 6
SERVER_TYPE_ACCOUNTSVR = 7

class NetProtocol(object):
    def __str__(self):
        return 'msgid:%d,body_length:%d, [%s](%s)' % (
           self.msgid,self.body_length,self.msg.DESCRIPTOR.full_name,str(self.msg)
        )

LOG_DIR = 'robots'
try:
    os.mkdir(LOG_DIR)
except:
    pass


active_clients = []

active_lock = threading.Lock()
def add_new_client(c):
    active_lock.acquire()
    active_clients.append(c)
    active_lock.release()

def remove_client(c):
    active_lock.acquire()
    active_clients.remove(c)
    active_lock.release()

content = '''
login.REQ_LOGIN = 10001
login.RSP_LOGIN = 10002
login.NTF_LOGOUT = 10003

hall.PING = 20001
hall.PONG = 20002
hall.REQ_MATCH_PLAYER = 20003
hall.RSP_MATCH_PLAYER = 20010
hall.REQ_BUY = 20012
hall.RSP_BUY = 20013
hall.NTF_CIRCLE_NOTIFICATION = 20014
hall.NTF_USER_MONEY = 20015
hall.REQ_ITEM_LIST = 20016
hall.RSP_ITEM_LIST = 20017
hall.REQ_SELF_TABLE = 20018
hall.RSP_SELF_TABLE = 20019
hall.REQ_CANCEL_MATCH_PLAYER = 20020
hall.RSP_CANCEL_MATCH_PLAYER = 20021
hall.NTF_MATCH_SUCESS = 20022
hall.REQ_GM = 20023
hall.RSP_GM = 20024
hall.NTF_COMPENSATION = 20027
hall.REQ_PERSONAL_INFO = 20028
hall.RSP_PERSONAL_INFO = 20029
hall.REQ_CHANGE_NAME = 20030
hall.RSP_CHANGE_NAME = 20031
hall.REQ_CHANGE_SEX = 20032
hall.RSP_CHANGE_SEX = 20033

room.REQ_ENTER = 20100
room.RSP_ENTER = 20101
room.REQ_CREATE_FRIEND_TABLE = 20102
room.RSP_CREATE_FRIEND_TABLE = 20103
room.REQ_FRIEND_TABLE_INFO = 20104
room.RSP_FRIEND_TABLE_INFO = 20105	
room.REQ_FRIEND_TABLE_PANEL = 20106
room.RSP_FRIEND_TABLE_PANEL = 20107
room.REQ_FRECORD_LIST = 20108
room.RSP_FRECORD_LIST = 20109
room.NTF_FRIEND_TABLE_UPDATE = 20110

table.REQ_ENTER = 30002
table.RSP_ENTER = 30003
table.NTF_EVENT = 30004
table.NTF_START = 30005
table.REQ_PLAY = 30006
table.RSP_PLAY = 30007
table.NTF_PLAY = 30008
table.NTF_GAMEOVER = 30009
table.REQ_ROBDIZHU = 30010
table.RSP_ROBDIZHU = 30001
table.NTF_ROBDIZHU = 30011
table.NTF_SETDIZHU = 30012
table.REQ_READY = 30013
table.RSP_READY = 30014
table.REQ_CARD_NOTE = 30015
table.RSP_CARD_NOTE = 30016
table.REQ_CHAT = 30017
table.RSP_CHAT = 30018
table.NTF_CHAT = 30019
table.NTF_PLAYER_ENTER = 30020
table.REQ_LEAVE = 30021
table.RSP_LEAVE = 30022
table.NTF_PLAYER_LEAVE = 30023
table.REQ_KICK_PLAYER = 30024
table.RSP_KICK_PLAYER = 30025

table.NTF_SCORE_AND_RATE = 30029
table.NTF_FRECORD_ADD  = 30030
table.NTF_PLAY_TIMEOUT  = 30031
table.NTF_BACKTO_MATCH  = 30032
table.NTF_NODIZHU_RESTART  = 30033
table.REQ_TRUSTEE = 30034
table.RSP_TRUSTEE = 30035
table.REQ_PLAYER_INFO = 30036
table.RSP_PLAYER_INFO = 30037
table.REQ_MINGPAI = 30038
table.RSP_MINGPAI = 30039
table.NTF_MINGPAI = 30040
table.REQ_JIABEI = 30041
table.RSP_JIABEI = 30042
table.REQ_CONFIG_CARDS = 30043
table.RSP_CONFIG_CARDS = 30044
table.NTF_MONEY_CHANGE = 30045
table.NTF_SCORE_AND_RATE_DETAIL = 30046
table.NTF_ROUND_OVER = 30047
table.REQ_ROUND_RANK = 30048
table.RSP_ROUND_RANK = 30049
table.REQ_ROUND_SERIAL = 30050
table.RSP_ROUND_SERIAL = 30051
table.REQ_STAND = 30052
table.RSP_STAND = 30053
table.REQ_SITDOWN = 30054
table.RSP_SITDOWN = 30055

daily.REQ_SIGNIN = 30101
daily.RSP_SIGNIN = 30102
daily.REQ_SIGNIN_PANEL = 30103
daily.RSP_SIGNIN_PANEL = 30104
daily.REQ_TAKE_SIGN_AWARD = 30105
daily.RSP_TAKE_SIGN_AWARD = 30106
daily.REQ_CURR_TASK = 30107
daily.RSP_CURR_TASK = 30108
daily.REQ_TAKE_TASK_AWARD = 30109
daily.RSP_TAKE_TASK_AWARD = 30110
daily.NTF_TASK_CHANGE = 30111
daily.REQ_SPECIAL_SIGNAWARD = 30112
daily.RSP_SPECIAL_SIGNAWARD = 30113

mail.REQ_MAIL_LIST = 30201
mail.RSP_MAIL_LIST = 30202
mail.REQ_DEL_MAIL = 30203
mail.RSP_DEL_MAIL = 30204
mail.REQ_TAKE_ATTACH = 30205
mail.RSP_TAKE_ATTACH = 30206
mail.REQ_ALL_MAIL_ATTACH = 30207
mail.RSP_ALL_MAIL_ATTACH = 30208
mail.NTF_NEW_MAIL = 30209

account.REQ_VERIFY = 80000
account.RSP_VERIFY = 80001
account.REQ_REGISTER_TOURIST = 80002
account.RSP_REGISTER_TOURIST = 80003
account.REQ_REGISTER_PHONE = 80004
account.RSP_REGISTER_PHONE = 80005
account.REQ_VERIFY_REGISTER_CODE = 80006
account.RSP_VERIFY_REGISTER_CODE = 80007
account.REQ_GET_LOGIN_CODE = 80008
account.RSP_GET_LOGIN_CODE = 80009
account.REQ_VERIFY_LOGIN_CODE = 80010
account.RSP_VERIFY_LOGIN_CODE = 80011
account.REQ_MAKE_ORDER = 80012
account.RSP_MAKE_ORDER = 80013
account.REQ_CHECK_PAYMENT = 80014
account.RSP_CHECK_PAYMENT = 80015
account.REQ_VERIFY_3RD_LOGIN = 80016
account.RSP_VERIFY_3RD_LOGIN = 80017
'''
def parse(filename):
    msg_name_map = {}
    msg_id_map = {}
    f = StringIO.StringIO(content)
    for l in f.readlines():
        l = l.strip()
        if l == '':
            continue

        if l.startswith('#'):
            #comments
            continue

        params = l.split('=')
        if len(params) != 2:
            print 'invalid message definition',l
            return

        
        msg_name = params[0].strip()
        msg_id = params[1].strip()

        if not msg_id.isdigit():
            print 'invalid message id(%s)'%msg_id
            return

        msg_id = int(msg_id)
        name_component = msg_name.split('.')
        if len(name_component) != 2:
            print 'invalid message name',msg_name
            return

        module = name_component[0]
        msg = name_component[1]

        msg_name_map['%s.%s' % (module,msg)] = msg_id
        msg_id_map[msg_id] = (module,msg)

    return msg_name_map,msg_id_map
MSG_NAME_MAP,MSG_ID_MAP = parse('msgdef.ini')

def _cmp(x,y):
    if x[0] > y[0]:
        return -1
    elif x[0] < y[0]:
        return 1
    else:
        return 0

class Timer(object):
    def __init__(self):
        self.tasks = []
    
    def add_task(self,seconds,f):
        self.tasks.insert(0,(seconds + time.time(), f))
    
    def update(self):
        if len(self.tasks) < 1:
            return

        self.tasks.sort(_cmp)
        now = time.time()

        i = len(self.tasks)
        while i > 0:
            if self.tasks[i - 1][0] > now:
                break
            task = self.tasks.pop()
            task[1]()
            i = len(self.tasks)
        
global_timer = Timer()

class Client(object):
    def __init__(self,uid):
        self.socket = socket.socket(family=socket.AF_INET,type=socket.SOCK_STREAM)
        self.inputs = []
        self.protocols = []
        self.buffer = bytes('')
        self.dest = 4 << 16 | 1
        self.uid = uid

        ppath = os.path.join(LOG_DIR,'p%d.log' % self.uid)
        self.f = open(ppath,'ab+')

    def fileno(self):
        return self.socket.fileno()
        
    def connect(self,addr,port):
        self.socket.connect((addr,port))
        
    def _unpack_response(self):
        bytes_length = len(self.buffer)

        curr_cursor = 0
        while bytes_length - curr_cursor >= 10:
            cursor = curr_cursor
            length,seq,msgid = struct.unpack_from(">HII",self.buffer,cursor)
            body_length = length - 8
            cursor += 10

            if bytes_length - cursor < body_length:
                break

            body = ''
            if body_length > 0:
                body = struct.unpack_from("%ds" % body_length,self.buffer,cursor)
                body = body[0]
            cursor += body_length

            r = MSG_ID_MAP[msgid]
            module = __import__(r[0] + '_pb2')
            msg = getattr(module,r[1])()
            msg.ParseFromString(body)

            protocol = NetProtocol()
            protocol.seq = seq
            protocol.msgid = msgid
            protocol.body_length = body_length
            protocol.msg = msg
            protocol.handler_name = '_'.join(r).lower()

            self.protocols.append(protocol)

            curr_cursor = cursor
        
        self.buffer = self.buffer[curr_cursor:]

        return True
        
    def read(self):
        buffer = self.socket.recv(4096)
        if len(buffer) == 0:
            remove_client(self)
        self.buffer += bytes(buffer)
        self._unpack_response()
        for r in self.protocols:
            self.log(str(r))

            if hasattr(self,r.handler_name):
                getattr(self,r.handler_name)(r.msg)
        self.protocols = []

    def pack(self,msgid,pb):
        s = pb.SerializeToString()
        real_length = len(s) + 8
        f = '>HII%ds' % len(s)
        b = struct.pack(f,real_length,self.dest,msgid,s)
        return b

    def send(self,msg):
        self.log('now send [%s][%s]' % (msg.DESCRIPTOR.full_name, str(msg)))
        msgid = MSG_NAME_MAP[msg.DESCRIPTOR.full_name]
        b = self.pack(msgid,msg)
        self.socket.send(b)

    def log(self,msg):
        now = datetime.now()
        f = self.f
        f.write('[%d_%02d_%02d-%02d:%02d:%02d.%6d]' % (
            now.year,now.month,now.day,now.hour,now.minute,now.second,now.microsecond
        ))
        f.write(msg)
        f.write("\n")
        f.flush()
        
    def login(self):
        import login_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = login_pb2.REQ_LOGIN()
        self.send(pb)

    def enter(self):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_ENTER()
        pb.table_gid = self.table_gid
        self.send(pb)

    def set_dizhu(self,score,is_rob):
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        import table_pb2
        pb = table_pb2.REQ_ROBDIZHU()
        pb.score = score
        pb.is_rob = is_rob
        self.send(pb)
    def ready(self,ready):
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        import table_pb2
        pb = table_pb2.REQ_READY()
        pb.ready = ready
        self.send(pb)

    def play(self,cards):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_PLAY()
        for id_ in cards:
            pb.card_suit.append(id_)
        self.send(pb)
    def lplay(self,cards,card_type,key):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_LAIZI_PLAY()
        for id_ in cards:
            pb.card_suit.append(id_)
        pb.card_suit_type = card_type
        pb.card_suit_key = key 
        self.send(pb)
    def sign(self):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_SIGNIN()
        self.send(pb)    
    def signpanel(self):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_SIGNIN_PANEL()
        self.send(pb)
    def takesign(self,type):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_TAKE_SIGN_AWARD()
        pb.type = type
        self.send(pb)
    def task(self):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_CURR_TASK()
        self.send(pb)
    def match(self,table_type):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_MATCH_PLAYER()
        pb.table_type = table_type
        self.send(pb)
    def cancel_match(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_CANCEL_MATCH_PLAYER()
        self.send(pb)   
        
    def create(self):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_CREATE_FRIEND_TABLE()
        pb.table_type = 202
        pb.set_dizhu_way = 1
        pb.max_dizhu_rate = 32
        pb.count = 6
        pb.can_watch = 1
        self.send(pb)
        
    def frecord(self):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_FRECORD_LIST()
        self.send(pb)

    def fpanel(self):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_FRIEND_TABLE_PANEL()
        self.send(pb)

    def password(self,password):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_FRIEND_TABLE_INFO()
        pb.password = password
        self.send(pb)
    def takeaward(self,task_id):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_TAKE_TASK_AWARD()
        pb.task_id = task_id
        self.send(pb)
    def mail(self):
        import mail_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = mail_pb2.REQ_MAIL_LIST()
        self.send(pb)
    def delmail(self,mail_seq):
        import mail_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = mail_pb2.REQ_DEL_MAIL()
        pb.mail_seq = mail_seq
        self.send(pb)    
    def attach(self,mail_seq):
        import mail_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = mail_pb2.REQ_TAKE_ATTACH()
        pb.mail_seq = mail_seq
        self.send(pb)
    def attachall(self):
        import mail_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = mail_pb2.REQ_ALL_MAIL_ATTACH()
        self.send(pb)                        

    def verify(self,uid,token=''):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_VERIFY()
        pb.uid = uid
        pb.key_token = token
        self.send(pb)

    def chat(self,content_id):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_CHAT()
        pb.content_id = content_id
        self.send(pb)
    
    def register_tourist(self,seed_token):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_REGISTER_TOURIST()
        pb.seed_token = seed_token
        self.send(pb)
    
    def register_phone(self,phone_number,tourist_key_token):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_REGISTER_PHONE()
        pb.phone_number = phone_number
        pb.tourist_key_token = tourist_key_token
        self.send(pb)

    def verify_register_code(self,phone_number,code):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_VERIFY_REGISTER_CODE()
        pb.phone_number = phone_number
        pb.code = code
        self.send(pb)

    def buy(self,goods_id):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_BUY()
        pb.goods_id = goods_id
        self.send(pb)
            
    def get_login_code(self,phone_number):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_GET_LOGIN_CODE()
        pb.phone_number = phone_number
        self.send(pb)

    def verify_login_code(self,phone_number,code):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_VERIFY_LOGIN_CODE()
        pb.phone_number = phone_number
        pb.code = code
        self.send(pb)

    def make_order(self,product_id,channel_id,uid):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_MAKE_ORDER()
        pb.product_id = product_id
        pb.channel_id = channel_id
        pb.uid = uid
        self.send(pb)
        
    def check_payment(self,receipt,order_id):
        import account_pb2
        self.dest = SERVER_TYPE_ACCOUNTSVR << 16 | 1
        pb = account_pb2.REQ_CHECK_PAYMENT()
        pb.receipt = receipt
        pb.order_id = order_id
        self.send(pb)

    def item(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_ITEM_LIST()
        self.send(pb)

    def leave(self):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_LEAVE()
        self.send(pb)

    def gm(self,cmd):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_GM()
        pb.cmd = cmd
        self.send(pb)
    
    def trust(self,trust):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_TRUSTEE()
        pb.trust = trust
        self.send(pb)
    def personal(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_PERSONAL_INFO()
        self.send(pb)
    def enterroom(self,table_type):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_ENTER()
        pb.table_type = table_type
        self.send(pb)
    def peipai(self,self_cards,cards1,cards2,laizi):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_CONFIG_CARDS()
        pb.self_cards = self_cards
        pb.cards1 = cards1
        pb.cards2 = cards2
        pb.laizi_id = laizi
        self.send(pb)
    def jiabei(self,type):
        import table_pb2
        #self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_JIABEI()
        pb.type = type
        self.send(pb)                

    def self_table(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_SELF_TABLE()
        self.send(pb)                

    def ping(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.PING()
        self.send(pb)

    #response==================

    def account_rsp_verify(self,msg):
        assert msg.result == 0
        self.uid = msg.uid
        self.login()

    def login_rsp_login(self,msg):
        self.log('rsp_login now match')
        self.match(1)
        #self.routinely_ping()

    def hall_ntf_match_sucess(self,msg):
        self.dest = msg.dest
        self.table_gid = msg.table_gid
        self.enter()
    
    def table_rsp_enter(self,msg):
        assert msg.result == 0
    
    def table_ntf_gameover(self,msg):
        self.log('table_ntf_gameover...send ready')
        def f():
            self.ready(1)
        global_timer.add_task(3,f)

    def table_ntf_start(self,msg):
        self.log('not start...send trustee')
        self.trust(1)

    def table_ntf_robdizhu(self,msg):
        self.log('now rob dizhu...')
        if msg.set_dizhu_status.uid == self.uid:
            self.set_dizhu(0,1)
    
    def table_ntf_play(self,msg):
        self.log('table_ntf_play...')
        self.trust(1)
    
    def routinely_ping(self):
        def f():
            self.ping()
            global_timer.add_task(20,f)
        global_timer.add_task(20,f)

def thread_select():
    while True:
        result_list = select.select(active_clients,[],[],1)
        if len(result_list[0]) < 1:
            continue
        
        for c in result_list[0]:
            c.read()
            
        global_timer.update()    

def CT(uid,host='localhost',port=8555,auto_add=True):
    c = Client(uid)
    c.connect(host,port)
    if auto_add:
        add_new_client(c)

    return c


# def start_select():
#     thread= threading.Thread(target=thread_select)
#     thread.setDaemon(True)
#     thread.start()
#     return thread

def main(from_uid,to_uid):
    import sys
    # logging.basicConfig(level=logging.DEBUG,
    #                 format='%(asctime)s:[line:%(lineno)d] %(message)s',
    #                 datefmt='%a, %d %b %Y %H:%M:%S',
    #                 #stream=sys.stdout)
    #                 filename = 'robots.log',
    #                 filemode='a+')
    assert from_uid <= to_uid
    for uid in xrange(from_uid,to_uid + 1):
        c = CT(uid,'192.168.0.232')
        c.verify(uid)

    thread_select()

if __name__ == '__main__':
    from_uid = int(sys.argv[1])
    to_uid = int(sys.argv[2])
    main(from_uid, to_uid)
