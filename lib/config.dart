/// Cloud project for PE Systems (Supabase, Mumbai). The publishable key is
/// meant to be inside the app: what each login may see is enforced by the
/// database's security rules, not by keeping this key secret.
const String kSupabaseUrl = 'https://bqwgdlvvtosfspyoqmal.supabase.co';
const String kSupabaseKey = 'sb_publishable_BAWkjUDeegmjxR6hGmNOAg_k7-8CgHJ';

/// Test-only build with a fake in-memory cloud and no real login
/// (flutter build ... --dart-define=PE_DEMO=true). Never given to users.
const bool kDemoMode = bool.fromEnvironment('PE_DEMO');

/// Shown in Settings; keep the same as `version:` in pubspec.yaml.
const String _version = '2.4.0';

/// Build number (the part after + in pubspec.yaml). Updates compare it.
const int _build = 18;

// Only a demo (test) build may pretend to be another version, to test
// updating; a real build always uses the numbers above.
const String kAppVersion = kDemoMode
    ? String.fromEnvironment('PE_VERSION', defaultValue: _version)
    : _version;
const int kBuildNumber = kDemoMode
    ? int.fromEnvironment('PE_BUILD', defaultValue: _build)
    : _build;

/// The PC website.
const String kWebsiteUrl = 'https://pe-daily-report.daily-report.workers.dev';

/// Where the phone app gets its updates: always the website. Only a demo
/// build with --dart-define=PE_UPDATE_URL=... uses a local test server.
const String _updateTestUrl = String.fromEnvironment('PE_UPDATE_URL');
const bool kUpdateTest = kDemoMode && _updateTestUrl != '';
const String kUpdateUrl = kUpdateTest ? _updateTestUrl : kWebsiteUrl;
