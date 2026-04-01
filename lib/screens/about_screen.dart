import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../providers/app_state.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _RepoLinkTile extends StatelessWidget {
  const _RepoLinkTile({
    required this.name,
    required this.url,
    this.subtitle,
  });

  final String name;
  final String url;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(url);
    final cs = Theme.of(context).colorScheme;

    Future<void> openLink() async {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!context.mounted || ok) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open $url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    Future<void> copyLink() async {
      await Clipboard.setData(ClipboardData(text: url));
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Link copied'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    return Material(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: openLink,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: FaIcon(
                  FontAwesomeIcons.github,
                  size: 20,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle ?? url.replaceFirst('https://', ''),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                onPressed: copyLink,
                icon: const Icon(Icons.copy_outlined, size: 18),
              ),
              IconButton(
                tooltip: 'Open',
                onPressed: openLink,
                icon: const Icon(Icons.open_in_new_rounded, size: 20),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;
  String? _coreVersion;
  String? _corePath;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final state = context.read<AppState>();
    final packageInfo = await PackageInfo.fromPlatform();
    final coreVersion = await state.manager.getCoreVersion();
    if (!mounted) return;
    setState(() {
      _packageInfo = packageInfo;
      _coreVersion = coreVersion;
      _corePath = state.manager.coreBinaryPath;
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final version = _packageInfo == null
        ? 'Loading...'
        : _packageInfo!.buildNumber.isEmpty
            ? _packageInfo!.version
            : '${_packageInfo!.version} (${_packageInfo!.buildNumber})';

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.lan_rounded,
                      color: cs.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'FlEasyTier',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Flutter GUI for EasyTier',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Versions',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  _InfoRow(label: 'FlEasyTier', value: version),
                  _InfoRow(
                    label: 'Core',
                    value: _coreVersion ?? 'Unavailable',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Links',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  _RepoLinkTile(
                    name: 'FlEasyTier',
                    url: 'https://github.com/eWloYW8/FlEasyTier',
                    subtitle: 'github.com/eWloYW8/FlEasyTier',
                  ),
                  const SizedBox(height: 12),
                  _RepoLinkTile(
                    name: 'EasyTier',
                    url: 'https://github.com/EasyTier/EasyTier',
                    subtitle: 'github.com/EasyTier/EasyTier',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  const _LinkRow({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.parse(url);
    final cs = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 13,
            ),
          ),
        ),
        Expanded(
          child: InkWell(
            onTap: () async {
              final ok = await launchUrl(uri);
              if (!context.mounted || ok) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Failed to open $url'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                url,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.primary,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: 'Copy',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Link copied'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
        ),
      ],
    );
  }
}
