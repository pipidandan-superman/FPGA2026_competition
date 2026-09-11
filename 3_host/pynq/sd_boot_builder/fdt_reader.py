import struct

def be(data,offset=0):
    return struct.unpack_from('>I',data,offset)[0]

def parse(data):
    if be(data)!=0xd00dfeed: raise ValueError('Invalid FDT magic')
    total,structure,strings_offset=be(data,4),be(data,8),be(data,12)
    strings=data[strings_offset:strings_offset+be(data,32)]
    end=structure+be(data,36)
    if total>len(data) or end>total: raise ValueError('FDT bounds exceeded')
    nodes={}; stack=[]; p=structure
    while p<end:
        token=be(data,p); p+=4
        if token==1:
            q=data.index(0,p); stack.append(data[p:q].decode()); p=(q+4)&~3
            nodes['/'+'/'.join(stack[1:])]={}
        elif token==2: stack.pop()
        elif token==3:
            size,nameoffset=be(data,p),be(data,p+4); p+=8
            name=strings[nameoffset:strings.index(0,nameoffset)].decode()
            nodes['/'+'/'.join(stack[1:])][name]=data[p:p+size]; p=(p+size+3)&~3
        elif token==4: continue
        elif token==9: return nodes
        else: raise ValueError('Invalid FDT token')
    raise ValueError('FDT END token absent')

def text(data):
    return data.rstrip(b'\0').decode()
