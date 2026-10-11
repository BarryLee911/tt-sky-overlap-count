import json,sys
a=json.load(open(sys.argv[1]));b=json.load(open(sys.argv[2]))
keys=sorted(set(a['groups'])|set(b['groups']),key=lambda k:-max(a['groups'].get(k,0),b['groups'].get(k,0)))
for k in keys[:int(sys.argv[3]) if len(sys.argv)>3 else 22]: print(f"{k:28s} v6={a['groups'].get(k,float('nan')):7.3f}  new={b['groups'].get(k,float('nan')):7.3f}")
