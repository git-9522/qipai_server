
�5
majiang.protomajiang"�

PlayerInfo
uid (:0
name (	: 
position (:0
coins (:0
icon (	: 
sex (:1
state (:0
	player_ip (	: "/
PengGangInfo
tile (:0
uid (:0"�
PlayerTileInfo
uid (:0

tile_count (:0
	tile_list ((
	peng_list (2.majiang.PengGangInfo(
	gang_list	 (2.majiang.PengGangInfo
angang_list
 (
dingque (:0
discarded_tiles (
win_tile (:0"c
OptionMessage
peng (:false
gang (:false
angang (:false
hu (:false"^
HuansanzhangData
	tile_list (
exchange_end_time (:0
default_tile_list (":
DingqueData
que (:0
dingque_end_time (:0"�
PlayingData
curr_player_uid (:0
curr_player_tile (:0
curr_end_time (:0&
option (2.majiang.OptionMessage"�

GameStatus6
player_tile_info_list (2.majiang.PlayerTileInfo

banker_uid (:0

cur_status (:05
huangsanzhang_data (2.majiang.HuansanzhangData*
dingque_data (2.majiang.DingqueData*
playing_data (2.majiang.PlayingData
die_num (:0
left_tile_count (:0"H
	NTF_START(
game_status (2.majiang.GameStatus
fround (:0"�
	TableConf
creator_uid (:0
total_round (:0

curr_round (:0

limit_rate (:0
password (:0
zimo_addition (:0
dianganghua (:0
exchange_three (:false
hujiaozhuanyi	 (:false
	daiyaojiu
 (:false

duanyaojiu (:false
jiangdui (:false
mengqing (:false
	tiandi_hu (:false
haidilaoyue (:false

base_score (:0"�
	EnterInfo-
player_info_list (2.majiang.PlayerInfo'
ftable_info (2.majiang.TableConf(
game_status (2.majiang.GameStatus"
REQ_DISCARD
tile (:0"1
RSP_DISCARD
result (:0
tile (:0"G
NTF_DISCARD
uid (:0
tile (:0
new_end_time (:0"j
NTF_NEXT_DISCARD_PLAYER
uid (:0
is_draw (:false
op_end_time (:0
tile (:0"`
NTF_DRAW_TILE
tile (:0&
option (2.majiang.OptionMessage
op_end_time (:0"S
NTF_PLAYER_OPTION&
option (2.majiang.OptionMessage
op_end_time (:0"	
REQ_WIN"
RSP_WIN
result (:0"�
AddtionTpye

duanyaojiu (:false
mengqing (:false
haidilaoyue (:false
dianganghua (:false
gangshangpao (:false
zimo_addition (:0
	gen_count (:0
tiandihu (:0
gangshanghua	 (:false
	qianggang
 (:false"w
NTF_WIN
uid (:0
tile (
hu_type (
fangpao_uid (:0%
addtion (2.majiang.AddtionTpye"

REQ_PENG"+
RSP_PENG
result (:0
tile ("?
NTF_PENG
uid (:0
tile (

penged_uid (:0"
REQ_GANG
tile ("X
RSP_GANG
result (:0
	gang_type (:0
tile (

ganged_uid (:0"U
NTF_GANG
uid (:0
	gang_type (:0
tile (

ganged_uid (:0"

REQ_PASS"
RSP_PASS
result (:0"
NTF_PASS
uid (:0"�

CreateConf
total_count (:0

limit_rate (:0
zimo_addition (:0
dianganghua (:0
exchange_three (:false
hujiaozhuanyi (:false
	daiyaojiu (:false

duanyaojiu (:false
jiangdui	 (:false
mengqing
 (:false
	tiandi_hu (:false
haidilaoyue (:false"*
	NTF_EVENT
uid (
state (:0"7
NTF_PLAYER_ENTER#
player (2.majiang.PlayerInfo"
	REQ_READY"
	RSP_READY
result (:0"
	REQ_LEAVE"1
	RSP_LEAVE
result (:0
status (:0"5
NTF_PLAYER_LEAVE
uid (:0
status (:0"j
NTF_EXCHANGE_THREE_START
	tile_list (
exchange_direction (:0
exchange_end_time (:0"%
REQ_HUANSANZHANG
	tile_list ("%
RSP_HUANSANZHANG
result (:0"I
NTF_HUANSANZHANG_TILES
	tile_list (
cardtoon_end_time (:0"0
NTF_DINGQUE_START
dingque_end_time (:0" 
REQ_DINGQUE
flower (:0" 
RSP_DINGQUE
result (:0"2
PlayerDingQue
uid (:0
flower (:0"B
NTF_DINGQUE3
player_dingque_list (2.majiang.PlayerDingQue"�
ScoreDetail
op_type (:0
score (:0
hu_type (:0
uid_list (%
addtion (2.majiang.AddtionTpye
fengding (:false
fan (:0"u
PlayerRecord
uid (
	add_score (:0.
add_score_detail (2.majiang.ScoreDetail
add_fan (:0")
LeftCard
uid (:0
cards ("�
NTF_GAMEOVER1
player_record_list (2.majiang.PlayerRecord0
player_left_card_list (2.majiang.LeftCard
liuju (:false"8
REQ_CHAT

content_id (:0
str_content (	: "K
RSP_CHAT
result (:0

content_id (:0
str_content (	: "H
NTF_CHAT
uid (:0

content_id (:0
str_content (	: "$
REQ_VOICE_CHAT
voice_id (	: "7
RSP_VOICE_CHAT
result (:0
voice_id (	: "4
NTF_VOICE_CHAT
uid (:0
voice_id (	: "!
REQ_PLAYER_INFO
uid (:0"�
RSP_PLAYER_INFO
result (:0
name (	: 
sex (:1
icon (	: 
level (:0
coins (:0
total_count (:0
win_percent (:0
uid	 (:0
	player_ip
 (	: "
REQ_DISMISS_TOUPIAO"(
RSP_DISMISS_TOUPIAO
result (:0"8
NTF_TOUPIAO_PANEL
uid (:0
end_time (:0""
REQ_TOUPIAO
is_agree (:1"5
RSP_TOUPIAO
result (:0
is_agree (:1"2
NTF_TOUPIAO
uid (:0
is_agree (:1"7
NTF_FTABLE_DISS
result (:0
reason (:0"
REQ_TRUSTEE
trust (:0"2
RSP_TRUSTEE
state (:0
result (:0"_
MoneyUpdate
uid (
update_score (:0*
score_detail (2.majiang.ScoreDetail">
NTF_UPDATE_MONEY*
money_update (2.majiang.MoneyUpdate"k
RankInfo
uid (:0
round_times (:0
	win_times (:0
rank (:0
score (:0"5
PlayRoundInfo
uid (:0
	add_score (:0"J
	RoundInfo
round (:0+
player_list (2.majiang.PlayRoundInfo"
REQ_ROUND_INFO"q
RSP_ROUND_INFO
result (:0$
	rank_list (2.majiang.RankInfo&

round_list (2.majiang.RoundInfo"^
NTF_ROUND_OVER$
	rank_list (2.majiang.RankInfo&

round_list (2.majiang.RoundInfo"�
TotalRecord
uid (:0
total_score (:0

zimo_count (:0
jiepao_count (:0
dianpao_count (:0
angang_count (:0

gang_count (:0
dajiao_count (:0"C
NTF_TOTAL_RECORD/
total_record_list (2.majiang.TotalRecord" 
REQ_TEST_DRAW
tile (:0""
RSP_TEST_DRAW
result (:0"+
NTF_YIPAODUOXIANG
dianpao_uid (:0"5
REQ_INTERACT
uid (:0

context_id (:0"M
RSP_INTERACT
result (:0
recv_uid (:0

context_id (:0"O
NTF_INTERACT
send_uid (:0
recv_uid (:0

context_id (:0