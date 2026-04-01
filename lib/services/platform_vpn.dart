/// Platform-specific VPN service integration.
///
/// - **Windows**: Requires admin elevation (manifest) + wintun.dll
/// - **Android**: Uses VpnService via platform channel
/// - **macOS**: Requires network entitlements
/// - **Linux**: Requires root or CAP_NET_ADMIN
library;

import 'dart:io';

import 'package:flutter/services.dart';

class PlatformVpn {
  static const _channel = MethodChannel('com.ewloyw8.fleasytier/vpn');

  /// Whether the current platform requires a system VPN API
  /// (as opposed to the core creating TUN directly).
  static bool get needsSystemVpn => Platform.isAndroid;

  // ── Android VPN ──

  /// Request VPN permission from the user (Android only).
  /// Returns true if permission granted.
  static Future<bool> prepareVpn() async {
    if (!Platform.isAndroid) return true;
    final result = await _channel.invokeMethod<bool>('prepareVpn');
    return result ?? false;
  }

  /// Start the Android VPN service.
  static Future<void> startVpn({
    required String ipv4,
    int cidr = 24,
    int mtu = 1300,
    List<String> routes = const ['0.0.0.0/0'],
    String? dns,
  }) async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('startVpn', {
      'ipv4': ipv4,
      'cidr': cidr,
      'mtu': mtu,
      'routes': routes,
      'dns': dns,
    });
  }

  /// Stop the Android VPN service.
  static Future<void> stopVpn() async {
    if (!Platform.isAndroid) return;
    await _channel.invokeMethod('stopVpn');
  }

  /// Get current VPN status (Android only).
  static Future<({bool running, int fd})> getVpnStatus() async {
    if (!Platform.isAndroid) return (running: false, fd: -1);
    final result =
        await _channel.invokeMapMethod<String, dynamic>('getVpnStatus');
    return (
      running: result?['running'] as bool? ?? false,
      fd: result?['fd'] as int? ?? -1,
    );
  }

  // ── Platform requirements info ──

  /// Returns a human-readable message about what the current platform
  /// requires for TUN device creation.
  static String get platformRequirements {
    if (Platform.isWindows) {
      return 'Windows requires:\n'
          '  1. wintun.dll next to easytier-core.exe\n'
          '     Download from https://www.wintun.net/\n'
          '  2. easytier-core runs with admin privileges\n'
          '     Run FlEasyTier as Administrator when TUN mode is enabled\n'
          '  3. Or enable No TUN / Use smoltcp for user-space mode';
    }
    if (Platform.isAndroid) {
      return 'Android uses the system VPN API.\n'
          'VPN permission will be requested when starting a network.';
    }
    if (Platform.isMacOS) {
      return 'macOS requires:\n'
          '  1. Network Extension entitlements (for App Store)\n'
          '  2. Or run easytier-core with sudo for development';
    }
    if (Platform.isLinux) {
      return 'Linux requires one of:\n'
          '  1. Run as root: sudo ./FlEasyTier\n'
          '  2. Set capability: sudo setcap cap_net_admin+ep easytier-core\n'
          '  3. Ensure /dev/net/tun exists:\n'
          '     sudo mkdir -p /dev/net && sudo mknod /dev/net/tun c 10 200';
    }
    return 'Unknown platform';
  }

  /// Whether wintun.dll is present (Windows only).
  static Future<bool> checkWintun() async {
    if (!Platform.isWindows) return true;
    final exe = Platform.resolvedExecutable;
    final dir = exe.substring(0, exe.lastIndexOf('\\'));
    return File('$dir\\wintun.dll').exists();
  }
}
