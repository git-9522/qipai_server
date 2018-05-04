import json
import socket
import struct
import select
import threading
import sys

SERVER_TYPE_GATEWAY = 1
SERVER_TYPE_PROXY = 2
SERVER_TYPE_TABLESVR = 3
SERVER_TYPE_HALLSVR = 4
SERVER_TYPE_DBSVR = 5
SERVER_TYPE_MATCHSVR = 6
SERVER_TYPE_ACCOUNTSVR = 7

class NetProtocol(object):
    def __str__(self):
        return 'msg[%s]seq:%d,msgid:%d,body_length:%d,msg(%s)' % (self.msg.DESCRIPTOR.full_name,
            self.seq,self.msgid,self.body_length,str(self.msg)
        )

def parse(filename):
    msg_name_map = {}
    msg_id_map = {}
    with open(filename,'rb') as f:
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
MSG_NAME_MAP,MSG_ID_MAP = parse('../proto/src/msgdef.ini')

class Client:
    def __init__(self):
        self.socket = socket.socket(family=socket.AF_INET,type=socket.SOCK_STREAM)
        self.inputs = []
        self.protocols = []
        self.buffer = bytes('')
        self.dest = 4 << 16 | 1

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
            active_clients.remove(self)
        self.buffer += bytes(buffer)
        self._unpack_response()
        for r in self.protocols:
            print(r)
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
        msgid = MSG_NAME_MAP[msg.DESCRIPTOR.full_name]
        print msgid
        b = self.pack(msgid,msg)
        self.socket.send(b)

    def login(self):
        import login_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = login_pb2.REQ_LOGIN()
        self.send(pb)

    def enter(self,table_gid = None):
        import table_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_ENTER()
        pb.table_gid = table_gid or self.table_gid
        self.send(pb)

    def set_dizhu(self,score,is_rob):
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        import ddz_pb2
        pb = ddz_pb2.REQ_ROBDIZHU()
        pb.score = score
        pb.is_rob = is_rob
        self.send(pb)
    def ready(self,ready):
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        import ddz_pb2
        pb = ddz_pb2.REQ_READY()
        pb.ready = ready
        self.send(pb)

    def play(self,cards):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_PLAY()
        for id_ in cards:
            pb.card_suit.append(id_)
        self.send(pb)
    def lplay(self,cards,card_type,key):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_LAIZI_PLAY()
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
        pb.table_type = 10001
        pb.xuezhan_create_conf.total_count = 4
        pb.xuezhan_create_conf.limit_rate = 4
        pb.xuezhan_create_conf.zimo_addition = 1
        pb.xuezhan_create_conf.dianganghua = 1
        pb.xuezhan_create_conf.exchange_three = False
        pb.xuezhan_create_conf.hujiaozhuanyi = True
        pb.xuezhan_create_conf.daiyaojiu = True
        pb.xuezhan_create_conf.duanyaojiu = True
        pb.xuezhan_create_conf.jiangdui = True
        pb.xuezhan_create_conf.mengqing = True
        pb.xuezhan_create_conf.tiandi_hu = True
        pb.xuezhan_create_conf.haidilaoyue = True
        self.send(pb)
        
    def frecord(self,game_type):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_FRECORD_LIST()
        pb.game_type = game_type
        self.send(pb)

    def fpanel(self,game_type):
        import room_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = room_pb2.REQ_FRIEND_TABLE_PANEL()
        pb.game_type = game_type
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
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_CHAT()
        pb.content_id = content_id
        self.send(pb)
    def voice_chat(self,content_id):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_VOICE_CHAT()
        pb.voice_id = "1234"
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
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_LEAVE()
        self.send(pb)

    def gm(self,cmd):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_GM()
        pb.cmd = cmd
        self.send(pb)
    
    def trust(self,trust):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_TRUSTEE()
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
    def peipai(self,game_type,self_cards,cards1,cards2,cards3,laizi):
        import table_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = table_pb2.REQ_CONFIG_CARDS()
        pb.game_type = game_type
        pb.self_cards = self_cards
        pb.cards1 = cards1
        pb.cards2 = cards2
        pb.cards3 = cards3
        pb.laizi_id = laizi
        self.send(pb)
    def jiabei(self,type):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_JIABEI()
        pb.type = type
        self.send(pb)                

    def self_table(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_SELF_TABLE()
        self.send(pb)  
    def diss(self,table_gid):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_DISMISS_TOUPIAO()
        self.send(pb) 
    def tou_piao(self,agree):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_TOUPIAO()
        self.send(pb)                
    def rank(self):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_ROUND_RANK()
        self.send(pb)
    def serial(self):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_ROUND_SERIAL()
        self.send(pb)
    def special(self):
        import daily_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = daily_pb2.REQ_SPECIAL_SIGNAWARD()
        self.send(pb)
   
    def change_name(self,name):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_CHANGE_NAME()
        pb.name = name
        self.send(pb)
           
    def change_sex(self,sex):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_CHANGE_SEX()
        pb.sex = sex
        self.send(pb)
    def player_info(self,uid):
        import ddz_pb2
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_PLAYER_INFO()
        pb.uid = uid
        self.send(pb)
    def player(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_PERSONAL_INFO()
        self.send(pb)
    def shop(self):
        import hall_pb2
        self.dest = SERVER_TYPE_HALLSVR << 16 | 1
        pb = hall_pb2.REQ_SHOP_INFO()
        self.send(pb)
    def mingpai(self,rate):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = ddz_pb2.REQ_MINGPAI()
        pb.rate = rate
        self.send(pb)
    def exchange(self,tile_list):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_HUANSANZHANG()
        for tile in tile_list:
            pb.tile_list.append(tile)
        self.send(pb)
    def dingque(self,flower):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_DINGQUE()
        pb.flower = flower
        self.send(pb)
    def discard(self,tile):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_DISCARD()
        pb.tile = tile
        self.send(pb)
    def peng(self):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_PENG()
        self.send(pb)
    def gang(self,tile):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_GANG()
        pb.tile = tile
        self.send(pb)
    def hu(self):
        import majiang_pb2    
        self.dest = SERVER_TYPE_TABLESVR << 16 | 1
        pb = majiang_pb2.REQ_WIN()
        self.send(pb)
    #response==================
    def account_rsp_verify(self,msg):
        self.login()

    def hall_ntf_match_sucess(self,msg):
        self.dest = msg.dest
        self.table_gid = msg.table_gid


active_clients = []
def thread_select():
    while True:
        result_list = select.select(active_clients,[],[],1)
        if len(result_list[0]) < 1:
            continue
        
        for c in result_list[0]:
            c.read()

def CT(host='localhost',port=8555,auto_add=True):
    c = Client()
    c.connect(host,port)
    if auto_add:
        active_clients.append(c)

    return c


thread= threading.Thread(target=thread_select)
thread.setDaemon(True)
thread.start()


if __name__ == '__main__':
    uid = int(sys.argv[1])
    c = CT()
    c.verify(uid)
