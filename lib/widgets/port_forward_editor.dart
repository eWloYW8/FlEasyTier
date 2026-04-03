import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/app_localizations.dart';
import '../models/network_config.dart';

class PortForwardEditor extends StatelessWidget {
  const PortForwardEditor({
    super.key,
    required this.items,
    required this.onChanged,
  });

  final List<PortForwardConfig> items;
  final ValueChanged<List<PortForwardConfig>> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l10n.t('port_forwards.title'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: cs.onSurface,
              ),
            ),
            const Spacer(),
            IconButton.filledTonal(
              icon: const Icon(Icons.add, size: 20),
              tooltip: l10n.t('port_forwards.add_rule'),
              onPressed: () => _showAddDialog(context),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...List.generate(items.length, (i) {
            final pf = items[i];
            return Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                dense: true,
                leading: Icon(
                  pf.proto == 'udp' ? Icons.swap_horiz : Icons.sync_alt,
                  size: 20,
                  color: cs.primary,
                ),
                title: Text(
                  pf.displayText,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
                trailing: IconButton(
                  icon: Icon(Icons.close, size: 18, color: cs.error),
                  onPressed: () {
                    final updated = [...items]..removeAt(i);
                    onChanged(updated);
                  },
                ),
              ),
            );
          }),
        ],
      ],
    );
  }

  void _showAddDialog(BuildContext context) {
    final l10n = context.l10n;
    final bindIpCtrl = TextEditingController(text: '0.0.0.0');
    final bindPortCtrl = TextEditingController();
    final dstIpCtrl = TextEditingController();
    final dstPortCtrl = TextEditingController();
    String proto = 'tcp';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.t('port_forwards.add_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                      value: 'tcp',
                      label: Text(l10n.t('port_forwards.protocol_tcp')),
                    ),
                    ButtonSegment(
                      value: 'udp',
                      label: Text(l10n.t('port_forwards.protocol_udp')),
                    ),
                  ],
                  selected: {proto},
                  onSelectionChanged: (s) =>
                      setDialogState(() => proto = s.first),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: bindIpCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.t('port_forwards.bind_ip'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: bindPortCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.t('port_forwards.bind_port'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Icon(Icons.arrow_downward, color: Colors.grey),
                ),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: dstIpCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.t('port_forwards.dest_ip'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: dstPortCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.t('port_forwards.dest_port'),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.t('common.cancel')),
            ),
            FilledButton(
              onPressed: () {
                final bindPort = int.tryParse(bindPortCtrl.text) ?? 0;
                final dstPort = int.tryParse(dstPortCtrl.text) ?? 0;
                if (bindPort > 0 &&
                    dstPort > 0 &&
                    dstIpCtrl.text.trim().isNotEmpty) {
                  onChanged([
                    ...items,
                    PortForwardConfig(
                      bindIp: bindIpCtrl.text.trim(),
                      bindPort: bindPort,
                      dstIp: dstIpCtrl.text.trim(),
                      dstPort: dstPort,
                      proto: proto,
                    ),
                  ]);
                  Navigator.pop(ctx);
                }
              },
              child: Text(l10n.t('common.add')),
            ),
          ],
        ),
      ),
    );
  }
}
