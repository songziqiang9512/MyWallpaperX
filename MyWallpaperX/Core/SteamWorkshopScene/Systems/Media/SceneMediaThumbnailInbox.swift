/// Scene author/debug ingress retains its existing per-process store. The
/// main App publisher uses a separate instance of this shared value store.
typealias SceneMediaThumbnailInbox = SystemMediaSnapshotStore
