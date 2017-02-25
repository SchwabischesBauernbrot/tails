require 'packetfu'

# Returns the unique edges (based on protocol, source/destination
# address/port) in the graph of all network flows.
def pcap_connections_helper(pcap_file, opts = {})
  opts[:ignore_dhcp] = true unless opts.has_key?(:ignore_dhcp)
  connections = Array.new
  packets = PacketFu::PcapFile.new.file_to_array(:filename => pcap_file)
  packets.each do |p|
    if PacketFu::EthPacket.can_parse?(p)
      eth_packet = PacketFu::EthPacket.parse(p)
    else
      raise 'Found something that is not an ethernet packet'
    end
    sport = nil
    dport = nil
    if PacketFu::TCPPacket.can_parse?(p)
      ip_packet = PacketFu::TCPPacket.parse(p)
      protocol = 'tcp'
      sport = ip_packet.tcp_sport
      dport = ip_packet.tcp_dport
    elsif PacketFu::UDPPacket.can_parse?(p)
      ip_packet = PacketFu::UDPPacket.parse(p)
      protocol = 'udp'
      sport = ip_packet.udp_sport
      dport = ip_packet.udp_dport
    elsif PacketFu::ICMPPacket.can_parse?(p)
      ip_packet = PacketFu::ICMPPacket.parse(p)
      protocol = 'icmp'
    elsif PacketFu::IPPacket.can_parse?(p)
      ip_packet = PacketFu::IPPacket.parse(p)
      protocol = 'ip'
    elsif PacketFu::IPv6Packet.can_parse?(p)
      ip_packet = PacketFu::IPv6Packet.parse(p)
      protocol = 'ipv6'
    else
      raise "Found something that cannot be parsed"
    end

    if protocol == "udp" and
       sport == 68 and
       dport == 67 and
       eth_packet.eth_daddr == "ff:ff:ff:ff:ff:ff" and
       ip_packet.ip_daddr == "255.255.255.255"
      next if opts[:ignore_dhcp]
    end

    packet_info = {
      mac_saddr: eth_packet.eth_saddr,
      mac_daddr: eth_packet.eth_daddr,
      protocol: protocol,
      sport: sport,
      dport: dport,
    }
    # It seems *Packet.parse can return nil despite *Packet.can_parse?
    # returning true.
    if ip_packet
      packet_info[:saddr] = ip_packet.ip_saddr
      packet_info[:daddr] = ip_packet.ip_daddr
    else
      puts "We were hit by #11508. PacketFu bug? Packet info: #{packet_info}"
    end
    connections << packet_info
  end
  connections.uniq.map { |p| OpenStruct.new(p) }
end

class FirewallAssertionFailedError < Test::Unit::AssertionFailedError
end

# These assertions are made from the perspective of the system under
# testing when it comes to the concepts of "source" and "destination".
def assert_all_connections(pcap_file, opts = {}, &block)
  all = pcap_connections_helper(pcap_file, opts)
  good = all.find_all(&block)
  bad = all - good
  unless bad.empty?
    raise FirewallAssertionFailedError.new(
            "Unexpected connections were made:\n" +
            bad.map { |e| "  #{e}" } .join("\n"))
  end
end

def assert_no_connections(pcap_file, opts = {}, &block)
  assert_all_connections(pcap_file, opts) { |*args| not(block.call(*args)) }
end
