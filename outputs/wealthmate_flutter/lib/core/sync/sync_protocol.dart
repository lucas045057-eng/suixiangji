/// Highest sync wire protocol this build implements.
///
/// This single constant selects the `X-Wealthmate-Sync-Protocol` header and is
/// compared with a 426 `min_protocol` response so a capable client is not
/// blocked by a stale upgrade gate.
const int kSupportedSyncProtocolVersion = 2;
