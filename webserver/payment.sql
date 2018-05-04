CREATE TABLE `order` (
  `order_id` varchar(64) NOT NULL,
  `amount` float(11,0) NOT NULL COMMENT '单位为：元',
  `uid` int(10) unsigned NOT NULL,
  `product_id` int(11) NOT NULL COMMENT '所购买产品id',
  `create_time` int(10) unsigned NOT NULL COMMENT '订单创建时间',
  `paid_time` int(10) unsigned NOT NULL COMMENT '订单完成时间',
  `channel_order` varchar(128) NOT NULL COMMENT '渠道订单号',
  `status` int(11) NOT NULL DEFAULT '0' COMMENT '0:已下单，1:已支付未处理，2:已支付已处理完成',
  `channel` varchar(12) NOT NULL COMMENT '渠道',
  `extra` varchar(4096) NOT NULL,
  PRIMARY KEY (`order_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

