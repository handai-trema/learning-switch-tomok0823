$LOAD_PATH.unshift __dir__

require 'fdb'

# An OpenFlow controller that emulates a layer-2 switch.
class LearningSwitch < Trema::Controller
  timer_event :age_fdb, interval: 5.sec

  def start(_argv)
    @fdb = FDB.new
  end

  def packet_in(_datapath_id, message)
    return if message.destination_mac.reserved?
    @fdb.learn message.source_mac, message.in_port
    flow_mod_and_packet_out message
  end

  def age_fdb
    @fdb.age
  end

  private

  def flow_mod_and_packet_out(message)
    port_no = @fdb.lookup(message.destination_mac)
    if port_no
      flow_mod message, port_no
      packet_out message, port_no
    else
      flood message
    end
  end

  def flow_mod(message, port_no)
    send_flow_mod_add(
      message.datapath_id,
      match: ExactMatch.new(message),
      actions: SendOutPort.new(port_no)
    )
  end

  def packet_out(message, port_no)
    send_packet_out(
      message.datapath_id,
      packet_in: message,
      actions: SendOutPort.new(port_no)
    )
  end

  def flood(message)
    packet_out message, :flood
  end
end
