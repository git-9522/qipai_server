CREATE TABLE `opration_message` (
  `id` int(10) NOT NULL AUTO_INCREMENT,
  `begine_time` int(10) unsigned NOT NULL COMMENT '开始时间',
  `end_time` int(10) unsigned NOT NULL COMMENT '结束时间',
  `interval` int(10) unsigned NOT NULL COMMENT '间隔时间',
  `message` varchar(256) NOT NULL COMMENT '消息',
  `status` int(11) NOT NULL DEFAULT '0' COMMENT '0:未处理，1:已经处理',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=19 DEFAULT CHARSET=utf8;


CREATE TABLE `platform_mail` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT,
  `title` varchar(32) NOT NULL,
  `content` varchar(255) NOT NULL,
  `send_time` int(11) NOT NULL,
  `mail_type` tinyint(1) NOT NULL DEFAULT '1' COMMENT '1：全服,2：指定玩家',
  `range` varchar(255) NOT NULL COMMENT '当type为2时,uid的集合，以“，”隔开,如:"7777,8888"',
  `attach_list` varchar(255) NOT NULL COMMENT '奖励列表,存储结构为：[{"id":1001,"count":100},{"id":1002,"count":200}]',
  `status` tinyint(1) NOT NULL DEFAULT '0' COMMENT '发送状态，0未发送，1已发送',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=2000000015 DEFAULT CHARSET=utf8;

-- ----------------------------
CREATE TABLE `platform_operation` (
  `id` bigint(20) NOT NULL AUTO_INCREMENT COMMENT '序号',
  `uid` bigint(20) NOT NULL,
  `cmd` int(3) NOT NULL COMMENT 'GM命令:1增加，2减少',
  `item_id` int(10) NOT NULL DEFAULT '0' COMMENT '物品id',
  `params` varchar(255) NOT NULL DEFAULT '0' COMMENT '命令参数，多个参数由逗号隔开',
  `operate_time` int(11) unsigned NOT NULL DEFAULT '0' COMMENT '操作时间',
  `status` int(1) unsigned NOT NULL DEFAULT '0' COMMENT '0:未发送1：已发送',
  `reason` varchar(255) DEFAULT NULL COMMENT '操作原因',
  `adminId` int(10) unsigned DEFAULT '0' COMMENT '管理员id',
  PRIMARY KEY (`id`)
) ENGINE=InnoDB AUTO_INCREMENT=1 DEFAULT CHARSET=utf8;