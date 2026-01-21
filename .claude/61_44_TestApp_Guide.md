# 61.44MHz Test App 개발 가이드

## 1. 개요

### 1.1 목적
AD9361 RF Transceiver의 61.44MHz 클럭 동작을 검증하기 위한 테스트 앱 개발

### 1.2 시스템 구성
```
┌─────────────────┐      MQTT       ┌─────────────────┐
│   Test App      │◄───────────────►│   Combo FW      │
│   (Windows)     │   TCP:1883      │   (Linux)       │
└─────────────────┘                 └─────────────────┘
        │                                   │
        │ Spectrum/IQ Data Display          │ AD9361 Control
        ▼                                   ▼
   ┌─────────┐                        ┌─────────┐
   │   UI    │                        │ AD9361  │
   └─────────┘                        │ 61.44MHz│
                                      └─────────┘
```

### 1.3 주요 기능
- 61.44MHz 모드 초기화
- 스펙트럼 측정 및 표시 (8192 points)
- IQ 데이터 캡처 및 표시
- 주파수/RBW/MaxHold 설정

---

## 2. MQTT 통신 프로토콜

### 2.1 연결 정보
| 항목 | 값                              |
|------|--------------------------------|
| Broker | Combo 장비 IP (예: 192.168.123.4) |
| Port | 1883                           |
| Command Topic | `pact/command`                 |
| Data Topic | `pact/data1`                   |
| QoS | 0                              |

### 2.2 명령 프로토콜 (App → FW)

#### 2.2.1 모드 초기화
```
Topic: pact/command
Payload: "0x44 0x00"
```
- AD9361을 61.44MHz 샘플링 모드로 초기화
- SA_50M_Filter.ftr 필터 적용
- 최초 1회 또는 모드 변경 시 호출 필요

#### 2.2.2 스펙트럼 측정
```
Topic: pact/command
Payload: "0x44 0x01 <center_freq_khz> <rbw_idx> <maxhold>"
```

| 파라미터 | 타입 | 범위 | 설명 |
|----------|------|------|------|
| center_freq_khz | uint64 | 60000 ~ 6000000 | 중심 주파수 (kHz) |
| rbw_idx | uint32 | 0~3 | RBW 인덱스 |
| maxhold | uint32 | 0, 1 | Max Hold 모드 |

**RBW 인덱스 테이블:**
| Index | RBW |
|-------|-----|
| 0 | 15 kHz |
| 1 | 30 kHz |
| 2 | 60 kHz |
| 3 | 120 kHz |

**예제:**
```
# 2GHz, RBW 60kHz, MaxHold Off
"0x44 0x01 2000000 2 0"

# 3.5GHz, RBW 30kHz, MaxHold On
"0x44 0x01 3500000 1 1"
```

#### 2.2.3 IQ 데이터 캡처
```
Topic: pact/command
Payload: "0x44 0x02 <center_freq_khz> <sample_count>"
```

| 파라미터 | 타입 | 범위 | 설명 |
|----------|------|------|------|
| center_freq_khz | uint64 | 60000 ~ 6000000 | 중심 주파수 (kHz) |
| sample_count | uint32 | 1 ~ 65536 | IQ 샘플 수 |

**예제:**
```
# 2GHz에서 8192 샘플 캡처
"0x44 0x02 2000000 8192"

# 900MHz에서 16384 샘플 캡처
"0x44 0x02 900000 16384"
```

#### 2.2.4 측정 정지
```
Topic: pact/command
Payload: "0x44 0x0F"
```

### 2.3 응답 프로토콜 (FW → App)

#### 2.3.1 응답 헤더 포맷
```
Topic: pact/data1
Payload: "0x45 <type> <status> [params...]"
```

| 필드 | 값 | 설명 |
|------|------|------|
| 0x45 | 고정 | 응답 헤더 |
| type | 0x00~0x0F | 명령 타입 |
| status | 0~3 | 상태 코드 |

**상태 코드:**
| Code | 의미 |
|------|------|
| 0 | OK (성공) |
| 1 | ERROR (오류) |
| 2 | BUSY (측정 중) |
| 3 | NOT_INIT (초기화 안됨) |

#### 2.3.2 초기화 응답
```
"0x45 0x00 0"   # 성공
"0x45 0x00 1"   # 실패
```

#### 2.3.3 스펙트럼 응답
```
# 헤더 메시지
"0x45 0x01 <status> <center_freq_khz> <data_points>"

# 데이터 메시지 (Binary)
<8192 x int32_t spectrum data>
```

**데이터 구조:**
- 데이터 타입: int32_t (32-bit signed integer)
- 데이터 개수: 8192 points
- 단위: dBm * 100 (예: -5000 = -50.00 dBm)
- 바이트 순서: Little Endian
- 총 크기: 8192 * 4 = 32,768 bytes

#### 2.3.4 IQ 캡처 응답
```
# 헤더 메시지
"0x45 0x02 <status> <center_freq_khz> <sample_count>"

# 데이터 메시지 (Binary)
<sample_count x (I16, Q16) IQ pairs>
```

**IQ 데이터 구조:**
```c
struct IQ_Sample {
    int16_t I;  // In-phase (16-bit signed)
    int16_t Q;  // Quadrature (16-bit signed)
};
```
- 샘플당 크기: 4 bytes (I: 2bytes + Q: 2bytes)
- 바이트 순서: Little Endian
- 총 크기: sample_count * 4 bytes

#### 2.3.5 정지 응답
```
"0x45 0x0F 0"   # 정지 완료
```

---

## 3. 통신 시퀀스

### 3.1 기본 측정 흐름
```
App                                    FW
 │                                      │
 │──── "0x44 0x00" (초기화) ───────────►│
 │                                      │ AD9361 61.44MHz 설정
 │◄──── "0x45 0x00 0" (OK) ────────────│
 │                                      │
 │──── "0x44 0x01 2000000 2 0" ───────►│
 │           (스펙트럼 요청)             │ 캡처 수행
 │                                      │
 │◄──── "0x45 0x01 0 2000000 8192" ────│
 │◄──── <32KB Spectrum Binary> ────────│
 │                                      │
```

### 3.2 연속 측정 (MaxHold)
```
App                                    FW
 │                                      │
 │──── "0x44 0x01 2000000 2 1" ───────►│
 │           (MaxHold On)               │
 │                                      │
 │◄──── "0x45 0x01 0 ..." + data ──────│ (반복)
 │◄──── "0x45 0x01 0 ..." + data ──────│
 │◄──── "0x45 0x01 0 ..." + data ──────│
 │                                      │
 │──── "0x44 0x0F" (정지) ─────────────►│
 │◄──── "0x45 0x0F 0" ─────────────────│
 │                                      │
```

---

## 4. 앱 기능 요구사항

### 4.1 필수 기능

#### 4.1.1 연결 관리
- MQTT Broker 연결/해제
- 연결 상태 표시 (Connected/Disconnected)
- IP 주소 설정

#### 4.1.2 모드 제어
- 61.44MHz 모드 초기화 버튼
- 초기화 상태 표시

#### 4.1.3 스펙트럼 뷰
- 8192 포인트 스펙트럼 그래프 표시
- X축: 주파수 (Center ± Span/2)
- Y축: 전력 (dBm)
- 주파수 설정 (60MHz ~ 6GHz)
- RBW 선택 (15/30/60/120 kHz)
- MaxHold On/Off
- Single/Continuous 측정 모드

#### 4.1.4 IQ 뷰
- I/Q 시간 영역 그래프
- Constellation 다이어그램 (옵션)
- 샘플 수 설정
- 캡처 버튼

### 4.2 권장 기능

#### 4.2.1 데이터 저장
- 스펙트럼 데이터 CSV 저장
- IQ 데이터 바이너리/CSV 저장
- 스크린샷 저장

#### 4.2.2 마커 기능
- 피크 검색
- 마커 위치/레벨 표시

#### 4.2.3 설정
- 스펙트럼 Y축 범위 설정
- 그래프 색상 설정
- 업데이트 주기 설정

---

## 5. UI 구성 제안

### 5.1 메인 화면 레이아웃
```
┌─────────────────────────────────────────────────────────────┐
│ [Connection]  IP: [192.168.123.4] [Connect] Status: ● Online│
├─────────────────────────────────────────────────────────────┤
│ [Mode]  [Initialize 61.44MHz]  Status: Initialized          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                                                     │   │
│  │              Spectrum Graph (8192 pts)              │   │
│  │                                                     │   │
│  │                     ~~~~                            │   │
│  │                    /    \                           │   │
│  │  ─────────────────/      \──────────────────────   │   │
│  │                                                     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  Center: [2000.000] MHz   RBW: [60 kHz ▼]   [MaxHold ☐]    │
│                                                             │
│  [Single] [Continuous] [Stop]              [Save CSV]       │
├─────────────────────────────────────────────────────────────┤
│ [IQ Capture]  Samples: [8192]  [Capture]   [Save IQ]        │
│  ┌────────────────────────┐ ┌────────────────────────┐     │
│  │    I Channel           │ │    Q Channel           │     │
│  │    ~~~~~~~~~~~~        │ │    ~~~~~~~~~~~~        │     │
│  └────────────────────────┘ └────────────────────────┘     │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 컨트롤 상세

#### 주파수 입력
- 범위: 60 ~ 6000 MHz
- 단위: MHz
- 소수점 3자리 (kHz 정밀도)

#### RBW 선택
- ComboBox/Dropdown
- 옵션: 15 kHz, 30 kHz, 60 kHz, 120 kHz

#### MaxHold
- CheckBox 또는 Toggle Switch

---

## 6. 구현 참고사항

### 6.1 MQTT 라이브러리 (언어별)

| 언어 | 라이브러리 |
|------|------------|
| C# | MQTTnet, M2Mqtt |
| Python | paho-mqtt |
| C++ | Eclipse Paho C++ |
| JavaScript | mqtt.js |

### 6.2 바이너리 데이터 파싱

#### C# 예제
```csharp
// 스펙트럼 데이터 파싱 (8192 x int32)
byte[] binaryData = mqttMessage.Payload;
int[] spectrumData = new int[8192];
for (int i = 0; i < 8192; i++)
{
    spectrumData[i] = BitConverter.ToInt32(binaryData, i * 4);
}

// dBm 변환
double[] spectrumDbm = spectrumData.Select(x => x / 100.0).ToArray();
```

#### Python 예제
```python
import struct

# 스펙트럼 데이터 파싱
spectrum_data = struct.unpack('<8192i', binary_data)  # Little Endian int32
spectrum_dbm = [x / 100.0 for x in spectrum_data]

# IQ 데이터 파싱
iq_data = struct.unpack(f'<{sample_count*2}h', binary_data)  # int16
i_data = iq_data[0::2]
q_data = iq_data[1::2]
```

### 6.3 주파수 축 계산

```python
# 61.44MHz 샘플레이트 기준
sample_rate = 61.44e6  # Hz
num_points = 8192
center_freq = 2000e6   # Hz (예: 2GHz)

# 주파수 축 생성
freq_resolution = sample_rate / num_points  # 7.5 kHz
freq_axis = [center_freq + (i - num_points/2) * freq_resolution
             for i in range(num_points)]
```

### 6.4 에러 처리

| 상황 | 처리 방법 |
|------|-----------|
| 연결 끊김 | 자동 재연결 시도 + 사용자 알림 |
| 타임아웃 | 3초 후 타임아웃 처리 |
| NOT_INIT 응답 | 자동 초기화 시도 |
| BUSY 응답 | 이전 측정 완료 대기 |

### 6.5 성능 최적화

- 스펙트럼 그래프: 매 프레임 전체 redraw 대신 데이터만 업데이트
- 대용량 IQ 데이터: 화면 표시용 다운샘플링 적용
- MQTT Keep-Alive: 60초 권장

---

## 7. 테스트 시나리오

### 7.1 기본 동작 테스트
1. MQTT 연결
2. 61.44MHz 모드 초기화 (0x44 0x00)
3. 응답 확인 (0x45 0x00 0)
4. 스펙트럼 측정 요청 (0x44 0x01 2000000 2 0)
5. 스펙트럼 데이터 수신 및 표시 확인
6. IQ 캡처 요청 (0x44 0x02 2000000 8192)
7. IQ 데이터 수신 및 표시 확인

### 7.2 주파수 범위 테스트
- 최소: 60 MHz
- 중간: 2000 MHz
- 최대: 6000 MHz

### 7.3 연속 측정 테스트
1. MaxHold 모드 시작
2. 10회 이상 연속 데이터 수신 확인
3. 정지 명령 후 데이터 수신 중단 확인

---

## 8. 관련 파일 참조

| 파일 | 위치 | 설명 |
|------|------|------|
| command.h | src/command/command.h | CMD 정의 |
| test_6144.h | src/command/test_6144.h | 프로토콜 헤더 |
| test_6144.c | src/command/test_6144.c | 핸들러 구현 |
| mqtt_mgmt.c | src/command/MQTT/mqtt_mgmt.c | MQTT 처리 |
| ad9361_manager.c | src/HW/ad9361/ad9361_manager.c | AD9361 제어 (meas_type==8) |
| SA_50M_Filter.ftr | ad936x/SA/SA_50M_Filter.ftr | 61.44MHz 필터 파일 |

---

## 변경 이력

| 버전 | 날짜 | 내용 |
|------|------|------|
| 1.0 | 2026-01-12 | 초기 작성 |
