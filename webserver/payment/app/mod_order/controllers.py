# -*- coding: utf-8 -*-
import sys
import time
import json
import requests

from flask import Blueprint, request, jsonify, session, g
from flask_sqlalchemy import SQLAlchemy

from .models import Order, OrderStatus
from app.database import db

reload(sys)
sys.setdefaultencoding('utf8')

# Define the blueprint: 'auth', set its url prefix: app.url/auth
order = Blueprint('order', __name__, url_prefix='/starry/order')

CHANNEL_DEFINITION = {
    99:'iOS',
}
CHANNEL_NAME_DEFINITION = dict([(v,k) for k,v in CHANNEL_DEFINITION.items()])

PRODUCTS = {
    101 : 3,
    102 : 6,
    103 : 18,
    104 : 30,
    105 : 68,
    106 : 128,
    107 : 328,
}

PRODUCT_MAP = {
    'starryddz_10007':101,
    'starryddz_10001':102,
    'starryddz_10002':103,
    'starryddz_10003':104,
    'starryddz_10004':105,
    'starryddz_10005':106,
    'starryddz_10006':307,
}

def generate_order_id(uid, channel_id):
    lt = time.localtime()
    return '%02d%02d%02d%02d%02d%02d%02d%010d' % (channel_id, lt.tm_year % 100, lt.tm_mon,
                                                  lt.tm_mday, lt.tm_hour, lt.tm_min, lt.tm_sec, uid)

def make_order():
    req = request.get_json(True)
    product_id = int(req.get('product_id'))
    channel_id = int(req.get('channel_id'))
    uid = int(req.get('uid'))

    if not PRODUCTS.has_key(product_id):
        return jsonify(code=-1, reason='unknown product %d' % product_id)

    channel_name = CHANNEL_DEFINITION.has_key(channel_id)
    if channel_name is None:
        return jsonify(code=-2, reason='unknown channel_id %d' % channel_id)

    order_id = generate_order_id(uid, channel_id)
    curr_time = int(time.time())
    new_order = Order(order_id=order_id, uid=uid, product_id=product_id,
                      create_time=curr_time, channel=channel_name, 
                      status=OrderStatus.ORDER_STATUS_MADE)

    try:
        db.session.add(new_order)
        db.session.commit()
        return jsonify(code=0, order_id=order_id)
    except:
        return jsonify(code=-3, reason='unknown error occurred,please retry again')

IOS_VERIFY_URL = "https://sandbox.itunes.apple.com/verifyReceipt"

def check_payment():
    req = request.get_json(True)
    receipt = req.get('receipt')
    order_id = req.get('order_id')
    if receipt is None:
        return jsonify(code=-1, message='invalid receipt...')

    unity_json = json.loads(receipt)
    payload = unity_json.get('Payload')

    
    proxies = {
        'http': 'http://192.168.0.210:808',
        'https': 'http://192.168.0.210:808',
    }

    payload = json.dumps({'receipt-data':payload})
    r = requests.post(IOS_VERIFY_URL, data=payload, proxies=proxies)
    receipt_rsp = r.json()

    status = receipt_rsp.get('status')
    if status != 0:
        return jsonify(code=-10, message='invalid status %s' % str(status))

    inapp_info = receipt_rsp.get('receipt').get('in_app')[0]
    product_id = inapp_info.get('product_id')
    transaction_id = inapp_info.get('transaction_id')

    amount = PRODUCTS[PRODUCT_MAP[product_id]]
    order = Order.query.filter_by(order_id=order_id).first()
    if order is None:
        return jsonify(code=-11, message='no such order<%s>' % order_id)

    if order.status != OrderStatus.ORDER_STATUS_MADE:
        return jsonify(code=0)
        
    order.status = OrderStatus.ORDER_STATUS_PAID
    order.amount = amount
    order.channel_order = transaction_id
    order.extra = json.dumps(receipt_rsp)

    db.session.add(order)
    db.session.commit()

    return jsonify(code=0)

# URLs
order.add_url_rule('/make_order', 'make_order', make_order, methods=['POST'])
order.add_url_rule('/check_payment', 'check_payment', check_payment, methods=['POST'])
