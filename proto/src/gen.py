import os
import sys
import os.path

def parse(filename):
    msg_map = {}
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

            msg_map[(module,msg)] = msg_id

    return msg_map

def to_lua_content(msg_map):
    lua_file_content = ['local NAME_TO_ID = {\n']

    for (module,msg),msg_id in msg_map.items():
        lua_file_content.append("\t['%s.%s'] = %s,\n" % (module,msg,msg_id))
    lua_file_content.append('}\n')

    lua_file_content.append('local ID_TO_NAME = {\n')
    for (module,msg),msg_id in msg_map.items():
        lua_file_content.append("\t[%s] = {'%s','%s'},\n" % (msg_id,module,msg))
    lua_file_content.append('}\n')

    lua_file_content.append('return {name_to_id = NAME_TO_ID,id_to_name = ID_TO_NAME}')
    return ''.join(lua_file_content)

def process_dir(dirname):
    msgdef_path = dirname
    if not os.path.exists(msgdef_path):
        os.makedirs(msgdef_path)
    with open(os.path.join(msgdef_path,'msgdef.lua'),'wb+') as f:
        f.write(to_lua_content(parse(os.path.join(dirname, 'msgdef.ini'))))


process_dir('.')

