# Flutter 테스트 가이드

## 테스트 구조

```
test/
├── helpers/
│   └── test_data_generator.dart    # 더미 데이터 생성기
├── models/
│   ├── spectrum_data_test.dart     # SpectrumData 모델 테스트
│   └── iq_data_test.dart           # IqData 모델 테스트
├── services/
│   └── mqtt_service_test.dart      # MQTT 서비스 테스트
├── integration/
│   └── message_flow_test.dart      # 메시지 흐름 통합 테스트
└── widget_test.dart                # 위젯 테스트 (기본)
```

## 테스트 실행 방법

### 1. 의존성 설치

```bash
cd /mnt/d/project_temp/flutter/timing_module_testtool
flutter pub get
```

### 2. 전체 테스트 실행

```bash
flutter test
```

### 3. 특정 테스트 파일 실행

```bash
# 모델 테스트만 실행
flutter test test/models/

# Spectrum 데이터 테스트만
flutter test test/models/spectrum_data_test.dart

# IQ 데이터 테스트만
flutter test test/models/iq_data_test.dart

# MQTT 서비스 테스트만
flutter test test/services/mqtt_service_test.dart

# 통합 테스트만
flutter test test/integration/message_flow_test.dart
```

### 4. 상세 출력으로 테스트 실행

```bash
flutter test --reporter expanded
```

### 5. 특정 테스트 그룹/케이스만 실행

```bash
# 특정 테스트 이름으로 필터링
flutter test --name "should parse binary data correctly"

# 정규식으로 필터링
flutter test --name ".*Spectrum.*"
```

### 6. 커버리지 리포트 생성

```bash
flutter test --coverage
# 결과: coverage/lcov.info

# HTML 리포트 생성 (genhtml 필요)
genhtml coverage/lcov.info -o coverage/html
```

## 테스트 내용 설명

### `test_data_generator.dart`

더미 데이터 생성을 위한 유틸리티 클래스:

- `generateSpectrumData()`: 8192 포인트 스펙트럼 바이너리 데이터 생성
- `generateIqData()`: I/Q 샘플 바이너리 데이터 생성
- `generateMultiPeakSpectrumData()`: 다중 피크 스펙트럼 데이터
- `generateMultiToneIqData()`: 다중 주파수 성분 IQ 데이터
- `createInitResponse()`: Init 응답 문자열 생성
- `createSpectrumHeaderResponse()`: 스펙트럼 헤더 응답 생성
- `createIqHeaderResponse()`: IQ 헤더 응답 생성

### `spectrum_data_test.dart`

SpectrumData 모델 테스트:

- 바이너리 데이터 파싱 검증
- 주파수 축 계산 검증
- 피크 검출 검증
- CSV 출력 형식 검증

### `iq_data_test.dart`

IqData 모델 테스트:

- I/Q 채널 바이너리 파싱 검증
- 정규화 값 계산 검증
- 크기(magnitude) 계산 검증
- 다양한 샘플 수 처리 검증

### `mqtt_service_test.dart`

MQTT 서비스 관련 테스트:

- MqttLogEntry 생성 및 포맷 검증
- MqttResponse 상태 판별 검증
- 프로토콜 상수 검증
- 명령 문자열 형식 검증

### `message_flow_test.dart`

통합 테스트 (메시지 흐름 시뮬레이션):

- Init → Spectrum → IQ → Stop 전체 흐름
- 연속 측정 시나리오
- 응답 파싱 검증

## IDE에서 테스트 실행

### VS Code

1. Flutter 확장 설치
2. 테스트 파일 열기
3. `main()` 함수 위의 "Run" 또는 "Debug" 클릭

### Android Studio / IntelliJ

1. 테스트 파일 열기
2. 테스트 함수 옆의 녹색 화살표 클릭
3. 또는 파일 우클릭 → "Run Tests"

## 테스트 작성 팁

### 새 테스트 추가 시

```dart
import 'package:flutter_test/flutter_test.dart';
import '../helpers/test_data_generator.dart';

void main() {
  group('MyFeature', () {
    test('should do something', () {
      // Arrange
      final data = TestDataGenerator.generateSpectrumData();

      // Act
      final result = processData(data);

      // Assert
      expect(result, expectedValue);
    });
  });
}
```

### 비동기 테스트

```dart
test('should handle async operation', () async {
  // Arrange
  final completer = Completer<String>();

  // Act
  final result = await someAsyncFunction();

  // Assert
  expect(result, isNotNull);
});
```

### Stream 테스트

```dart
test('should emit values on stream', () async {
  // Arrange
  final receivedValues = <int>[];

  stream.listen((value) {
    receivedValues.add(value);
  });

  // Act
  await triggerStreamEmission();
  await Future.delayed(Duration(milliseconds: 100));

  // Assert
  expect(receivedValues, [1, 2, 3]);
});
```

## 문제 해결

### 테스트 실패 시

1. 에러 메시지 확인
2. `flutter clean && flutter pub get` 실행
3. `--reporter expanded` 옵션으로 상세 로그 확인

### 타임아웃 발생 시

```dart
test('long running test', () async {
  // 기본 타임아웃: 30초
  // 타임아웃 연장 필요시:
}, timeout: Timeout(Duration(minutes: 2)));
```

### 비동기 테스트 대기

```dart
// 충분한 대기 시간 확보
await Future.delayed(Duration(milliseconds: 100));

// 또는 expectLater 사용
await expectLater(stream, emits(expectedValue));
```
