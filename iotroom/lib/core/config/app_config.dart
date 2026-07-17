/// Build-time configuration for the Flutter client.
///
/// Pass real values locally with `--dart-define`; do not commit credentials.
class AppConfig {
  const AppConfig._();

  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8900',
  );

  static const String alarmBaseUrl = String.fromEnvironment(
    'ALARM_BASE_URL',
    defaultValue: 'http://localhost:9090',
  );

  static const String wvpHost = String.fromEnvironment(
    'WVP_HOST',
    defaultValue: 'localhost',
  );
  static const int wvpApiPort = int.fromEnvironment(
    'WVP_API_PORT',
    defaultValue: 8080,
  );
  static const int mediaPort = int.fromEnvironment(
    'MEDIA_PORT',
    defaultValue: 80,
  );
  static const int rtspPort = int.fromEnvironment(
    'RTSP_PORT',
    defaultValue: 554,
  );
  static const int rtmpPort = int.fromEnvironment(
    'RTMP_PORT',
    defaultValue: 1935,
  );

  static const String wvpDeviceId = String.fromEnvironment(
    'WVP_DEVICE_ID',
    defaultValue: 'demo-device',
  );
  static const String wvpChannelId = String.fromEnvironment(
    'WVP_CHANNEL_ID',
    defaultValue: 'demo-channel',
  );
  static const String wvpAlarmChannelId = String.fromEnvironment(
    'WVP_ALARM_CHANNEL_ID',
    defaultValue: 'demo-alarm-channel',
  );

  static const String zlmSecret = String.fromEnvironment('ZLM_SECRET');
  static const String wvpUsername = String.fromEnvironment('WVP_USERNAME');
  static const String wvpPasswordMd5 = String.fromEnvironment(
    'WVP_PASSWORD_MD5',
  );
}
