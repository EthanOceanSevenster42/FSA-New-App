/// Application configuration.
///
/// Deliberately *not* a bag of `const` values the way an older
/// `Constants.cs` was — there, switching environment meant recompiling with
/// `#if` directives and 20-odd duplicate `BaseApiUrl` declarations. Here the
/// values are instance fields, overridable at build time via `--dart-define`
/// or at runtime from a config endpoint, without touching code.
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.apiBaseUrl,
    required this.isTrialVersion,
  });

  /// Reads `--dart-define=API_BASE_URL=...`, falling back to the LAN address of
  /// the development machine so a debug build runs against the local Django
  /// server with no extra flags.
  factory AppConfig.fromEnvironment() => const AppConfig(
        appName: 'Food Safety Agency',
        // Override per build: --dart-define=API_BASE_URL=http://<host>:<port>
        // The default is a dev machine on the LAN, whose address DHCP moves.
        apiBaseUrl: String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://192.168.2.2:8010',
        ),
        isTrialVersion: bool.fromEnvironment('IS_TRIAL'),
      );

  final String appName;
  final String apiBaseUrl;
  final bool isTrialVersion;

  /// True when the API is reached over plaintext HTTP. Only a LAN dev server
  /// should ever be. Cleartext to a public IP is never acceptable.
  bool get isInsecureTransport => apiBaseUrl.startsWith('http://');
}
