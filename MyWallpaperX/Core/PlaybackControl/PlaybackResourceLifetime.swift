/// Opaque in-process ownership token for file-backed playback inputs.
///
/// The producer owns the retention policy. Playback and import consumers only
/// keep this object alive for exactly as long as they may still read the
/// corresponding files; it never carries product state or crosses IPC.
protocol PlaybackResourceLifetime: AnyObject {}
