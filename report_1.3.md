#課題内容  
```
OpenFlow1.3 版スイッチの動作を説明しよう。

スイッチ動作の各ステップについて、trema dump_flows の出力 (マルチプルテーブルの内容) を混じえながら動作を説明すること。  
  
###実行のしかた  
以下のように --openflow13 オプションが必要です。

```$ bundle exec trema run lib/learning_switch13.rb --openflow13 -c trema.conf```
```

##解答
###テーブルの初期化
まず，```$ bundle exec trema run lib/learning_switch13.rb --openflow13 -c trema.conf``` を一方の端末で実行する．このとき， ```learning_switch13.rb``` の ```switch_ready``` ハンドラが呼び出される．以下に ```switch_ready``` ハンドラのコードを示す．
  
```
def switch_ready(datapath_id)
  add_bpdu_drop_flow_entry(datapath_id)
  add_default_broadcast_flow_entry(datapath_id)
  add_default_flooding_flow_entry(datapath_id)
  add_default_forwarding_flow_entry(datapath_id)
end
```  

このハンドラでは，未登録パケットについてのデフォルト処理を，新たに起動したスイッチのフローテーブルに書き込む動作を行う． 
① ```add_bpdu_drop_flow_entry``` メソッドを呼び出し，Table ID:0に，宛先のMACアドレスがマルチキャストアドレスである場合はドロップするという処理を優先度2として登録する．  
② ```add_default_broadcast_flow_entry``` メソッドを呼び出し，Table ID:1に，宛先のMACアドレスがブロードキャストアドレスである場合はフラッディングするという処理を優先度3として登録する．  
③ ```add_default_flooding_flow_entry``` メソッドを呼び出し，Table ID:1に，コントローラにPacket Inする処理を優先度1として登録する．  
④ ```add_default_forwarding_flow_entry``` メソッドを呼び出し，Table ID:0に，Table ID:1にGotoする処理を優先度1として登録する．  

次に，tremaを起動し，コントローラにスイッチが接続された状態，すなわち ```switch_ready``` ハンドラが呼び出された後のスイッチlswのフローテーブルを以下に示す．  
 
```
./bin/trema dump_flows lsw
cookie=0x0, duration=6.529s, table=0, n_packets=0, n_bytes=0, priority=2,dl_dst=01:00:00:00:00:00/ff:00:00:00:00:00 actions=drop
cookie=0x0, duration=6.49s, table=0, n_packets=10, n_bytes=1694, priority=2,dl_dst=33:33:00:00:00:00/ff:ff:00:00:00:00 actions=drop
cookie=0x0, duration=6.49s, table=0, n_packets=1, n_bytes=342, priority=1 actions=goto_table:1
cookie=0x0, duration=6.49s, table=1, n_packets=1, n_bytes=342, priority=3,dl_dst=ff:ff:ff:ff:ff:ff actions=FLOOD
cookie=0x0, duration=6.49s, table=1, n_packets=0, n_bytes=0, priority=1 actions=CONTROLLER:65535
```

上記フローテーブルの各行の意味を順に示す．
1行目：Table ID:0(Filtering Table)において，宛先のMACアドレスがマルチキャストアドレスである場合はドロップする(優先度2)
2行目：Table ID:0(Filtering Table)において，宛先のMACアドレスがIPv6マルチキャストアドレスである場合はドロップする(優先度2)
3行目：Table ID:0(Filtering Table)において，Table ID:1(Forwarding Table)へgotoする(優先度1)
4行目：Table ID:1(Forwarding Table)において，宛先のMACアドレスがブロードキャストアドレスである場合はフラッディングする(優先度3)
5行目：Table ID:1(Forwarding Table)において，コントローラにPacket Inする(優先度1)


###host1からhost2にパケット送信
ここでは，スイッチに接続されたhost1からhost2へパケットを送信した場合のフローテーブルの変化について記述する．  
まず，Packet Inが発生した際に呼び出される ```packet_in``` ハンドラについて説明する．

```
  def packet_in(_datapath_id, packet_in)
    @fdb.learn(packet_in.source_mac, packet_in.in_port)
    add_forwarding_flow_and_packet_out(packet_in)
  end
```

```@fdb.learn(packet_in.source_mac, packet_in.in_port)``` では，Packet Inしたパケットの送信元MACアドレスとIn Portを一組として学習を行う．ここで呼び出される ```add_forwarding_flow_and_packet_out``` メソッドにおいて，学習した組をForwarding Table(Table ID:1)のフローテーブに登録する．  
実際にhost1からhost2へパケットを送信したときのフローテーブルの様子を以下に示す．

```
$ ./bin/trema send_packets --source host1 --dest host2　　
$ ./bin/trema dump_flows lsw
cookie=0x0, duration=13.629s, table=0, n_packets=0, n_bytes=0, priority=2,dl_dst=01:00:00:00:00:00/ff:00:00:00:00:00 actions=drop
cookie=0x0, duration=13.59s, table=0, n_packets=14, n_bytes=2048, priority=2,dl_dst=33:33:00:00:00:00/ff:ff:00:00:00:00 actions=drop
cookie=0x0, duration=13.59s, table=0, n_packets=3, n_bytes=726, priority=1 actions=goto_table:1
cookie=0x0, duration=13.59s, table=1, n_packets=2, n_bytes=684, priority=3,dl_dst=ff:ff:ff:ff:ff:ff actions=FLOOD
cookie=0x0, duration=13.59s, table=1, n_packets=1, n_bytes=42, priority=1 actions=CONTROLLER:65535
```

このとき，フローテーブルのエントリは初期状態のものと比較して変化していない．host1からhost2へ送信されたパケットは上記フローテーブルの優先度3,優先度2の全ての条件とマッチしない．すなわち，パケットはドロップしない．フローテーブルの3行目によりTable ID:1へgotoし，5行目によりコントローラへのPacket Inが発生する．Packet Inを受信したコントローラは，パケットをフラッディングする．また，FDBに送信元のMACアドレスとポート番号を組として登録する．host2はフラッディングされたパケットを受信する．

###host2からhost1にパケット送信
続いて，host2からhost1へパケットを送信したときのフローテーブルを以下に示す．

"""
$ ./bin/trema send_packets --source host2 --dest host1
$ ./bin/trema dump_flows lsw
cookie=0x0, duration=24.463s, table=0, n_packets=0, n_bytes=0, priority=2,dl_dst=01:00:00:00:00:00/ff:00:00:00:00:00 actions=drop
cookie=0x0, duration=24.424s, table=0, n_packets=14, n_bytes=2048, priority=2,dl_dst=33:33:00:00:00:00/ff:ff:00:00:00:00 actions=drop
cookie=0x0, duration=24.424s, table=0, n_packets=6, n_bytes=1452, priority=1 actions=goto_table:1
cookie=0x0, duration=24.424s, table=1, n_packets=4, n_bytes=1368, priority=3,dl_dst=ff:ff:ff:ff:ff:ff actions=FLOOD
cookie=0x0, duration=3.797s, table=1, n_packets=0, n_bytes=0, idle_timeout=180, priority=2,in_port=2,dl_src=55:11:8c:f6:0b:4c,dl_dst=c5:2d:34:22:57:bc actions=output:1
cookie=0x0, duration=24.424s, table=1, n_packets=2, n_bytes=84, priority=1 actions=CONTROLLER:65535
"""

このとき，下記に示すエントリがフローテーブルに追加されたことが確認できる．
```
cookie=0x0, duration=3.797s, table=1, n_packets=0, n_bytes=0, idle_timeout=180, priority=2,in_port=2,dl_src=55:11:8c:f6:0b:4c,dl_dst=c5:2d:34:22:57:bc actions=output:1
```

これは，前述した ```packet_in``` ハンドラ内で呼び出される ```add_forwarding_flow_and_packet_out``` メソッドによってもたらされたと考えられる．

```
def add_forwarding_flow_and_packet_out(packet_in)
  port_no = @fdb.lookup(packet_in.destination_mac)
  add_forwarding_flow_entry(packet_in, port_no) if port_no
  packet_out(packet_in, port_no || :flood)
end

def add_forwarding_flow_entry(packet_in, port_no)
  send_flow_mod_add(
    packet_in.datapath_id,
    table_id: FORWARDING_TABLE_ID,
    idle_timeout: AGING_TIME,
    priority: 2,
    match: Match.new(in_port: packet_in.in_port,
                     destination_mac_address: packet_in.destination_mac,
                     source_mac_address: packet_in.source_mac),
    instructions: Apply.new(SendOutPort.new(port_no))
  )
end
```

このメソッドでは，パケットのMACアドレスが既にFDBに登録されているかをチェックする．先ほど，host1からhost2にパケットが送信され，送信元であるhost1のMACアドレスとポート番号の組が登録された．よって，```add_forwarding_flow_entry``` メソッドが呼び出され，Forwarding Tableにパケットについてのフローエントリを追加する．この処理により，フローテーブルに新たに「送信元ポート番号：2, 送信元MACアドレス(host2), 宛先MACアドレス(host1)」を表す1行が追加された．そして最後にPacket Outを行う．

###再びhost1からhost2にパケット送信
このときの実行結果を以下に示す．

```
$ ./bin/trema send_packets --source host1 --dest host2
$ ./bin/trema dump_flows lsw
cookie=0x0, duration=32.004s, table=0, n_packets=0, n_bytes=0, priority=2,dl_dst=01:00:00:00:00:00/ff:00:00:00:00:00 actions=drop
cookie=0x0, duration=31.965s, table=0, n_packets=14, n_bytes=2048, priority=2,dl_dst=33:33:00:00:00:00/ff:ff:00:00:00:00 actions=drop
cookie=0x0, duration=31.965s, table=0, n_packets=9, n_bytes=2178, priority=1 actions=goto_table:1
cookie=0x0, duration=31.965s, table=1, n_packets=6, n_bytes=2052, priority=3,dl_dst=ff:ff:ff:ff:ff:ff actions=FLOOD
cookie=0x0, duration=11.338s, table=1, n_packets=0, n_bytes=0, idle_timeout=180, priority=2,in_port=2,dl_src=55:11:8c:f6:0b:4c,dl_dst=c5:2d:34:22:57:bc actions=output:1
cookie=0x0, duration=3.457s, table=1, n_packets=0, n_bytes=0, idle_timeout=180, priority=2,in_port=1,dl_src=c5:2d:34:22:57:bc,dl_dst=55:11:8c:f6:0b:4c actions=output:2
cookie=0x0, duration=31.965s, table=1, n_packets=3, n_bytes=126, priority=1 actions=CONTROLLER:65535
```

このとき，以下1行がフローテーブルに追加されたことが確認できる．

```
cookie=0x0, duration=3.457s, table=1, n_packets=0, n_bytes=0, idle_timeout=180, priority=2,in_port=1,dl_src=c5:2d:34:22:57:bc,dl_dst=55:11:8c:f6:0b:4c actions=output:2
```

これは，host2からhost1へパケットを送信したときと同様の処理を行い，「送信元ポート番号：1, 送信元MACアドレス(host1), 宛先MACアドレス(host2)」という情報がフローテーブルに登録されたことがわかる．