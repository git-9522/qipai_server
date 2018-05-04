import os
import sys
import os.path

def parse(filename):
    msg_map = {}
    msg_id_check = {}
    msg_list = []
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

            name_component = msg_name.split('.')
            if len(name_component) != 2:
                print 'invalid message name',msg_name
                return
            
            module = name_component[0]
            msg = name_component[1]

            if msg_map.has_key((module,msg)):
                raise KeyError("duplicated key: [%s.%s]" % (module,msg))

            if msg_id_check.has_key(msg_id):
                raise KeyError("duplicated key: [%s.%s]=>%s" % (module,msg,msg_id))

            msg_map[(module,msg)] = msg_id
            msg_id_check[msg_id] = (module,msg)
            msg_list.append((module,msg,msg_id))

    return msg_list

def to_lua_content(msg_list):
    lua_file_content = ['local NAME_TO_ID = {\n']

    for (module,msg,msg_id) in msg_list:
        lua_file_content.append("\t['%s.%s'] = %s,\n" % (module,msg,msg_id))
    lua_file_content.append('}\n')

    lua_file_content.append('local ID_TO_NAME = {\n')
    for (module,msg,msg_id) in msg_list:
        lua_file_content.append("\t[%s] = {'%s','%s'},\n" % (msg_id,module,msg))
    lua_file_content.append('}\n')

    lua_file_content.append('return {name_to_id = NAME_TO_ID,id_to_name = ID_TO_NAME}')
    return ''.join(lua_file_content)

def collect_proto_dirs(src,result):
    assert os.path.isdir(src), src
    files = os.listdir(src)
    is_proto_dir = False
    for f in files:
        f = os.path.join(src,f)
        if not is_proto_dir and os.path.isfile(f) and f.endswith('.proto'):
            is_proto_dir = True
        elif os.path.isdir(f):
            collect_proto_dirs(f,result)
    if is_proto_dir:
        result.append(src)

def process_dir(dirname):
    subdir = os.path.split(dirname)[1]
    built_dir = os.path.join('built')
    msgdef_dir = os.path.join('lualib')

    if not os.path.exists(built_dir):
        os.makedirs(built_dir)

    if not os.path.exists(msgdef_dir):
        os.makedirs(msgdef_dir)

    srcdir = os.path.join(dirname, 'protos')
    proto_dirs = []
    collect_proto_dirs(srcdir,proto_dirs)

    include_option = ' -I '.join(proto_dirs)
    for proto_dir in proto_dirs:
        for filepath in os.listdir(proto_dir):
            filepath = os.path.join(proto_dir,filepath)
            if filepath.endswith('.proto'):
                target_dir = os.path.join(built_dir,filepath.replace(srcdir + '/',''))
                target_dir = os.path.split(target_dir)[0]
                if not os.path.exists(target_dir):
                    os.makedirs(target_dir)
                filename = os.path.split(filepath)[1]
                target_pb = os.path.join(target_dir,filename[:filename.rfind('.')])
                cmd = "protoc -o %s.pb %s -I %s" % (target_pb, filepath, include_option)
                os.system(cmd)
                print cmd
                
    with open(os.path.join(msgdef_dir,'msgdef.lua'),'wb+') as f:
        f.write(to_lua_content(parse(os.path.join(dirname, 'msgdef.ini'))))


process_dir('src')

