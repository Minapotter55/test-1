/// Google Drive setup — see README (قسم "ربط Google Drive").
///
/// The *Web* OAuth client ID from Google Cloud Console. Android needs it to
/// sign in; leave empty to hide Drive sync until it is configured.
const googleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '');

/// The *iOS* OAuth client ID. Also put it (reversed) in ios/Runner/Info.plist.
const googleIosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID', defaultValue: '');

/// Name of the folder the app creates in the user's Google Drive.
const driveFolderName = 'ClientPro';
const driveExportsFolderName = 'تقارير شهرية';
const driveSyncFileName = 'clientpro_sync.json';
