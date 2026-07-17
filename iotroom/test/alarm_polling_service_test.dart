import 'package:flutter_test/flutter_test.dart';
import 'package:iotroom/services/alarm_polling_service.dart';

void main() {
  test('parses a fire alarm payload', () {
    final alarm = NewAlarmData.fromJson({
      'id': 'demo-alarm-1',
      'eventType': 'fireSmartFireDetect',
      'eventDescription': 'Demo fire alarm',
      'dateTime': '2026-01-01T12:00:00Z',
      'deviceID': 'demo-device',
      'channelName': 'demo-channel',
      'imageUrl': '/images/demo.jpg',
    });

    expect(alarm.isFireAlarm, isTrue);
    expect(alarm.isRecovery, isFalse);
    expect(alarm.notificationTitle, contains('火灾'));
    expect(alarm.deviceID, 'demo-device');
  });

  test('recognizes an alarm recovery payload', () {
    final alarm = NewAlarmData.fromJson({
      'eventType': 'FirePointAlarmRecovery',
    });

    expect(alarm.isFireAlarm, isFalse);
    expect(alarm.isRecovery, isTrue);
  });
}

