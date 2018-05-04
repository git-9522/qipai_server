from sqlalchemy import Column, Integer, String, Float
from app.database import db

class OrderStatus(object):
    ORDER_STATUS_MADE = 0
    ORDER_STATUS_PAID = 1
    ORDER_STATUS_DEALT = 2

class Order(db.Model):
    __tablename__ = 'order'
    order_id = Column(String(64), primary_key=True)
    amount = Column(Float, nullable=False, default=0.0)
    uid = Column(Integer, nullable=False, default=0)
    product_id = Column(Integer, nullable=False, default=0)
    create_time = Column(Integer, nullable=False, default=0)
    paid_time = Column(Integer, nullable=False, default=0)
    channel_order = Column(String(128), nullable=False, default='')
    status = Column(Integer, nullable=False, default=0)
    channel = Column(String(12), nullable=False, default='')
    extra = Column(String(4096), nullable=False, default='')

    def __repr__(self):
        return '<Order order:%s,uid:%d,product_id:%d>' % (self.order_id,self.uid,self.product_id)