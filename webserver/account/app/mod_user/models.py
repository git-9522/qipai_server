from sqlalchemy import Column, Integer, String
from app.database import db

class User(db.Model):
    __tablename__ = 'user'
    uid = Column(Integer, primary_key=True)
    global_id = Column(String(128), nullable=False, default='')
    phone = Column(String(32), nullable=False, default='')
    email = Column(String(64), nullable=False, default='')
    register_time = Column(Integer, nullable=False, default=0)

    def __repr__(self):
        return '<User uid:%s,global_id:%s,phone:%s,register_time:%d>' % (self.uid, self.global_id, self.phone, self.register_time)