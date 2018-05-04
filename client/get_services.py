import sys
import socket
import StringIO

'''
if len(sys.argv) <= 1:
	print("need imput close server name!!!")
	sys.exit()
'''

def get_service_list(addr,port):
    tmp_socket = socket.socket(family=socket.AF_INET,type=socket.SOCK_STREAM)
    tmp_socket.connect((addr,port))
    tmp_str = 'list' + '\r\n'
    tmp_socket.send(tmp_str)
    recv_str = tmp_socket.recv(4096)
    while not recv_str.find('<CMD OK>') >= 0:
        recv_str += tmp_socket.recv(4096)

    tmp_socket.close()

    si = StringIO.StringIO(recv_str)
    all_lines = si.readlines()
    all_lines = all_lines[1: len(all_lines) -1]
    service_list = []
    for s in all_lines:
        s = s.strip().split()
        addr = s[0]
        name = s[2]
        service_list.append((addr,name))

    return service_list
    
HOST = '127.0.0.1'
PORT = 19322

service_list = get_service_list(HOST,PORT)
def hotfix(service_list,service_name,patch):
    tmp_socket = socket.socket(family=socket.AF_INET,type=socket.SOCK_STREAM)
    tmp_socket.connect((HOST,PORT))

    for addr,name in service_list:
        if name == service_name:
            tmp_socket.send('inject %s %s\r\n' % (addr,patch))

    recv_str = tmp_socket.recv(4096)
    while not recv_str.find('<CMD OK>') >= 0:
        recv_str += tmp_socket.recv(4096)
    print(recv_str)
    tmp_socket.close()

hotfix(service_list,'msg_handler','/tmp/h_msg_handler.lua')
