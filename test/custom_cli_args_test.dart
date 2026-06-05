import 'package:fleasytier/models/network_config.dart';
import 'package:fleasytier/services/easytier_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats and parses generated CLI args with spaces', () {
    final args = [
      '-c',
      '/Users/example/FlEasyTier configs/network.toml',
      '--rpc-portal',
      '127.0.0.1:15888',
    ];

    final text = EasyTierManager.formatCliArgs(args);

    expect(text, contains("'/Users/example/FlEasyTier configs/network.toml'"));
    expect(EasyTierManager.parseCliArgs(text), args);
  });

  test('parses quoted custom CLI args', () {
    final parsed = EasyTierManager.parseCliArgs(
      'easytier-core -c "/tmp/config file.toml" --rpc-portal 127.0.0.1:15888',
    );

    expect(parsed, [
      'easytier-core',
      '-c',
      '/tmp/config file.toml',
      '--rpc-portal',
      '127.0.0.1:15888',
    ]);
  });

  test('preserves custom CLI args in config JSON', () {
    final config = NetworkConfig(
      customCliArgsEnabled: true,
      customCliArgs: '-c /tmp/fleasytier.toml --rpc-portal 127.0.0.1:15999',
      rpcPort: 15999,
    );

    final copied = NetworkConfig.fromJson(config.toJson());

    expect(copied.customCliArgsEnabled, isTrue);
    expect(copied.customCliArgs, config.customCliArgs);
    expect(copied.rpcPort, 15999);
  });
}
