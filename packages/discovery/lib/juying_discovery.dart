/// Network Service Discovery Abstraction for JuYing.
///
/// **What**: Manages SSDP M-SEARCH multicast, mDNS service queries, and network
/// interface selection for multi-homed desktop and mobile systems (Section 3.2).
///
/// **Why**: VPNs, virtual machines (WSL/Hyper-V), and Wi-Fi hot spots cause SSDP/mDNS
/// to select incorrect network interfaces.
library;

/// Discovered network endpoint.
class DiscoveredEndpoint {
  const DiscoveredEndpoint({
    required this.serviceType,
    required this.location,
    required this.host,
    required this.port,
  });

  final String serviceType;
  final String location;
  final String host;
  final int port;
}
