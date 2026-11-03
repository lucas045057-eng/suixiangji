/// Highest sync wire protocol this build implements.
///
/// This single constant selects the `X-Wealthmate-Sync-Protocol` header and is
/// compared with a 426 `min_protocol` response so a capable client is not
/// blocked by a stale upgrade gate.
const int kSupportedSyncProtocolVersion = 2;

/// User-facing explanation for a 426 `upgrade_required`.
///
/// [requiredProtocol] is what the server demanded; null means it answered 426
/// without a parseable version. The text never renders `vnull`, and it keeps
/// "the app must upgrade" distinct from "the server is asking for more than a
/// capable client can do".
String syncUpgradeMessage(int? requiredProtocol) {
  if (requiredProtocol == null) {
    return '客户端需升级：服务端要求更高协议版本（未提供具体版本），请升级客户端';
  }
  if (requiredProtocol > kSupportedSyncProtocolVersion) {
    return '客户端需升级：服务端要求协议 v$requiredProtocol，'
        '当前客户端支持至 v$kSupportedSyncProtocolVersion';
  }
  return '服务端要求更高协议（v$requiredProtocol），客户端已支持 '
      'v$kSupportedSyncProtocolVersion；请稍后重试或联系服务提供方';
}
