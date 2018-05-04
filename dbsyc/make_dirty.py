import redis
r= redis.Redis(db=1)
d = redis.Redis(db=7)

l = r.keys("data_*")
u = [v.replace("data_","") for v in l]
[d.rpush('writable_uid_queue',v) for v in u]
