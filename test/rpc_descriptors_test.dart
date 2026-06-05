import 'package:fleasytier/rpc/rpc_types.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('PeerManageRpc descriptors match EasyTier api_instance.proto order', () {
    expect(EtRpc.listPeer.methodIndex, 1);
    expect(EtRpc.listPublicIpv6Info.methodIndex, 2);
    expect(EtRpc.listRoute.methodIndex, 3);
    expect(EtRpc.dumpRoute.methodIndex, 4);
    expect(EtRpc.listForeignNetwork.methodIndex, 5);
    expect(EtRpc.listGlobalForeignNetwork.methodIndex, 6);
    expect(EtRpc.showNodeInfo.methodIndex, 7);
    expect(EtRpc.getForeignNetworkSummary.methodIndex, 8);
  });
}
