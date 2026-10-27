/// Phone app: it is already installed, so there is nothing to offer.
/// (These are only used on the website.)
bool canOfferInstall() => false;

Future<bool> offerInstall() async => false;

bool runningAsInstalledApp() => false;

Future<String> downloadAndroidAppImpl(String? token, String fileName) async =>
    'unsupported';
