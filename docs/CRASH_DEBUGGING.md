# 크래시 디버깅 가이드

게임이 도중에 죽을 때(크래시/프리즈) 원인을 찾는 방법.

## 1. 로그 위치

모든 실행은 자동으로 로그를 남깁니다. (`project.godot [debug] file_logging` + `Crash` 오토로드)

- **에디터/`godot`로 실행**: `%APPDATA%\Godot\app_userdata\AluxStrike\logs\`
- **빌드된 exe로 실행**: `%APPDATA%\AluxStrike\logs\`

폴더에 두 종류가 쌓입니다:

| 파일 | 내용 |
|---|---|
| `crash_<날짜>.log` | 세션 정보(엔진/OS/CPU/GPU), 브레드크럼, `Crash.report()`로 찍은 **GDScript 스택** |
| `godot.log` | 엔진 표준출력 전체 — **GDScript 런타임 에러와 네이티브 크래시 백트레이스**가 여기 들어감 |

크래시 후 **가장 최신 `crash_*.log` 와 `godot.log`** 두 개를 보면 됩니다.

## 2. 심볼(함수 이름)이 보이는 스택을 얻으려면

스택 추적이 `source:line:function`까지 다 보이려면 **디버그 빌드 또는 에디터**로 돌려야 합니다.
릴리즈 빌드는 스택이 비어있게(주소만) 나옵니다.

```powershell
# 심볼 포함 디버그 exe 빌드 -> build\AluxStrike_debug.exe
./build.ps1 debug
```

또는 그냥 에디터/CLI로 실행해도 GDScript 에러는 전체 스택이 찍힙니다:

```powershell
godot --path . --verbose      # 더 자세한 로그를 godot.log 로
```

## 3. 코드에서 직접 찍기

전역 오토로드 `Crash` 를 어디서나 호출할 수 있습니다.

```gdscript
Crash.breadcrumb("3번 방 진입")          # 가벼운 위치 기록(메모리에만, report 때 출력)
Crash.report("적 핸들이 null 임")         # 지금 위치의 전체 스택 + 최근 브레드크럼을 로그에 덤프
```

크래시가 의심되는 지점 앞에 `if 잘못된_상태: Crash.report("설명")` 를 넣으면,
크래시 직전 상태와 호출 경로가 로그에 남습니다.

## 4. 리포트 보낼 때

가장 최신 `crash_*.log` + `godot.log` 를 첨부. (재현 단계도 같이)
