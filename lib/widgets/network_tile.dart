import 'package:flutter/material.dart';

import '../models/network_config.dart';
import '../models/network_instance.dart';
import 'status_badge.dart';

class NetworkTile extends StatelessWidget {
  const NetworkTile({
    super.key,
    required this.config,
    required this.running,
    this.instance,
    this.selected = false,
    this.onTap,
  });

  final NetworkConfig config;
  final bool running;
  final NetworkInstance? instance;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = Theme.of(context).textTheme;
    final traffic = _trafficSummary(instance);
    final nodeSummary = running
        ? '${instance?.peerCount ?? 0} nodes'
        : config.virtualIpv4.isNotEmpty
            ? config.virtualIpv4
            : (config.dhcp ? 'DHCP' : 'Idle');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _StatusDot(running: running),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              config.displayName,
                              style: ts.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (config.serviceEnabled ||
                              config.autoStart ||
                              config.acceptDns ||
                              config.enableSocks5 ||
                              config.noTun ||
                              config.useSmoltcp) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (config.serviceEnabled)
                                      const _TinyChip(
                                        label: 'Service',
                                        icon: Icons.miscellaneous_services_outlined,
                                      ),
                                    if (config.autoStart)
                                      const _TinyChip(
                                        label: 'Auto',
                                        icon: Icons.schedule_outlined,
                                      ),
                                    if (config.acceptDns)
                                      const _TinyChip(
                                        label: 'DNS',
                                        icon: Icons.dns_outlined,
                                      ),
                                    if (config.enableSocks5)
                                      _TinyChip(
                                        label: 'S5:${config.socks5Port}',
                                        icon: Icons.route_outlined,
                                      ),
                                    if (config.noTun)
                                      const _TinyChip(
                                        label: 'No TUN',
                                        icon: Icons.link_off_outlined,
                                      ),
                                    if (config.useSmoltcp)
                                      const _TinyChip(
                                        label: 'smoltcp',
                                        icon: Icons.memory_outlined,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 8),
                          StatusBadge(running: running, compact: true),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          if (config.networkName.isNotEmpty)
                            _MetaText(
                              icon: Icons.badge_outlined,
                              text: config.networkName,
                            ),
                          _MetaText(
                            icon: Icons.hub_outlined,
                            text: nodeSummary,
                            mono: !running && config.virtualIpv4.isNotEmpty,
                            color: running ? cs.primary : null,
                          ),
                          if (running)
                            _MetaText(
                              icon: Icons.swap_horiz,
                              text: traffic,
                              color: cs.tertiary,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _trafficSummary(NetworkInstance? instance) {
    if (instance == null) return '0 B / 0 B';
    return '${_formatBytes(instance.totalRxBytes)} / ${_formatBytes(instance.totalTxBytes)}';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _MetaText extends StatelessWidget {
  const _MetaText({
    required this.icon,
    required this.text,
    this.mono = false,
    this.color,
  });

  final IconData icon;
  final String text;
  final bool mono;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.outline;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            color: fg,
            fontFamily: mono ? 'monospace' : null,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _TinyChip extends StatelessWidget {
  const _TinyChip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: cs.outline),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              color: cs.outline,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: running ? Colors.green : Colors.grey.shade400,
        boxShadow: running
            ? [
                BoxShadow(
                  color: Colors.green.withValues(alpha: 0.35),
                  blurRadius: 6,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
    );
  }
}
