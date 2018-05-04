import sys
import socket
import StringIO

if len(sys.argv) <= 1:
	print("need imput close server name!!!")
	sys.exit()

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

def close_on_server(addr,port,server_addr):
	tmp_socket = socket.socket(family=socket.AF_INET,type=socket.SOCK_STREAM)
	tmp_socket.connect((addr,port))
	tmp_str = 'call ' + server_addr + ' \'close_server\'' + '\r\n'
	tmp_socket.send(tmp_str)
	recv_str = tmp_socket.recv(4096)
	print(recv_str)
	tmp_socket.close()

def close_by_name(host,port):
	service_list = get_service_list(host,port)
	for addr,name in service_list:
		if name == 'msg_handler': 
			close_on_server(host,port,addr)


TABLE_HOST = '127.0.0.1'
TABLE_PORT = 18581

HALL_HOST = '127.0.0.1'
HALL_PORT = 19322

if sys.argv[1] == "table_server":
	close_by_name(TABLE_HOST,TABLE_PORT)
elif sys.argv[1] == "hall_server":
	close_by_name(HALL_HOST,HALL_PORT)
elif sys.argv[1] == "all":
	close_by_name(TABLE_HOST,TABLE_PORT)
	close_by_name(HALL_HOST,HALL_PORT)
else:
	print("input server name error!!!!")

