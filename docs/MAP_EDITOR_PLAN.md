# 맵 에디터 플랜 v2 (구현 보류 — 설계 문서)

확정 결정: **같은 프로젝트 내 에디터 모드** + **미니멀 v1** + **JSON 포맷**.
편집기와 게임을 "맵 파일"이라는 계약으로 분리한다.

## 0. 가장 큰 설계 포인트 — 멀티플레이 맵 동기화
지오메트리가 정적 씬이 아니라 데이터 기반이 되면, 조인한 클라이언트가 host가 고른 맵
(특히 `user://` 커스텀 맵)을 갖고 있지 않을 수 있다.

- host 권위: host가 맵 JSON을 메모리에 로드.
- 클라 접속 시 서버가 맵 데이터 전체를 해당 클라에 RPC(reliable)로 전송 → 클라가 받은
  데이터로 MapLoader 빌드 → 그 후 플레이어 스폰.
- 빌트인/커스텀 구분 없이 항상 전체 JSON 전송(단순·일관). 큰 맵이면 압축은 후순위.
- 시퀀스: `client connect → server: receive_map.rpc_id(client, json) → client builds → 플레이어 복제`.
- 단일플레이는 로컬 로드만.

## 1. JSON 스키마
```jsonc
{
  "format": 1,                 // 스키마 버전
  "name": "arena1",
  "blocks": [
    { "pos":[x,y,z], "size":[x,y,z], "rot":[x,y,z], "mat":"concrete" }
  ],
  "spawns":  [[x,y,z], ...],   // 비면 [[0,2,0]]
  "targets": [[x,y,z], ...]
}
```
검증(map_loader 진입부): format 미스매치 시 변환/폴백, 누락 필드는 기본값
(size [2,2,2], rot [0,0,0], mat "concrete"), size 각 축 clamp(0.1,500), blocks 최대 2000.
좌표는 `[x,y,z]` 배열 → `Vector3` 변환 헬퍼 한 곳.

## 2. 공유 레지스트리
- `MaterialRegistry` autoload: `MatReg.get_mat(id)`, `MatReg.ids()`.
- v1 id(보유 PBR 4종): floor(PavingStones), wall(Bricks), metal(Metal), concrete(Concrete).
- 미존재 id → concrete 폴백 + 1회 경고.
- 전부 triplanar(월드 스케일) → 블록 크기 달라도 타일 일정, per-block UV 불필요.

## 3. map_builder (편집기·게임 공용 단일 함수)
`MapBuilder.make_block(block) -> StaticBody3D`
```
StaticBody3D (collision_layer=1, position, rotation_degrees)
  ├─ MeshInstance3D  BoxMesh(size), material = MatReg.get_mat(mat)
  └─ CollisionShape3D BoxShape3D(size)
```
편집기는 여기에 선택 하이라이트만 덧입힘. 전체 재빌드는 자식 queue_free 후 재생성.
타겟 = target.tscn 인스턴스(위치만). 스폰 = 게임에선 비가시, 편집기에선 마커.

## 4. 스폰 배정
spawns 비면 [[0,2,0]]. 피어 배정 `spawns[idx % size]` 또는 랜덤. 충돌 회피 v1 비목표.
network_manager 가 맵 spawns 사용(현재 랜덤 ±6 대체).

## 5. 맵 선택 & 전파
```
메뉴: [맵 드롭다운(res://maps + user://maps)] [SINGLE][MULTI][EDIT]
SINGLE     → 로컬 로드 → 빌드 → host(solo)
MULTI/HOST → 로컬 로드 → 빌드 → host (클라 접속 시 JSON 송신)
MULTI/JOIN → 접속 후 host JSON 으로 빌드
EDIT       → map_editor.tscn
```
목록: `map_io.list_maps()` = res://maps/*.json + user://maps/*.json (중복 시 user 우선).

## 6. 편집기 스펙 (미니멀 v1)
- 카메라: 우클릭 홀드 마우스룩 + WASD, 휠=속도.
- 모드: Block / Spawn / Target. 좌클릭 = 추가(그리드 스냅) 또는 선택. Del = 삭제.
- 우측 속성 패널(선택 시): pos·size·rot SpinBox, mat OptionButton → 실시간 반영.
- 하단: 그리드 스냅 토글/간격, 블록 수, 맵 이름.
- 내부 데이터 모델 = `Array[Dictionary]`(파일 스키마와 동일) → 직렬화 변환 0.
- 저장: `user://maps/<name>.json`.
- 상단 툴바: New | Load | Save | Save As | ▶Test | ← 메뉴.

## 7. default.json 변환 (회귀 방지)
현재 main.tscn 의 블록/타겟을 1:1 로 res://maps/default.json 으로 이전.
일회용 변환 스크립트로 main.tscn 파싱(좌표/사이즈/회전/머티리얼 id 매핑) → JSON 출력.
램프 회전 행렬 → 오일러 degrees 역산 필요.

## 8. 단계별 + 검증
- Phase 1 (소비측+멀티동기화): registry/builder/loader/io + default.json + main.tscn 전환
  + host→client 맵 RPC.
  검증: autohost 헤드리스 무에러 / 블록 수 == default / 2-피어로 클라 빌드 / 플레이 동등성.
- Phase 2 (편집기 MVP): map_editor.tscn + EDIT 버튼 + 배치/선택/삭제/속성/스냅/저장·불러오기.
  검증: 에디터 씬 헤드리스 로드 무에러 / 왕복 테스트(생성→save→load→build, 노드수·좌표 assert)
  / 저장 맵이 메뉴에 뜨고 플레이.
- Phase 3 (폴리시, 후순위): 마우스 기즈모, 램프 도구, 복제, 언두, 인-에디터 테스트 플레이, 썸네일.

## 9. 디렉토리
```
scripts/map/{material_registry,map_builder,map_loader,map_io}.gd
scenes/map_editor.tscn, scripts/map/map_editor.gd
scenes/target.tscn
maps/default.json            (res://, 동봉)
user://maps/*.json           (사용자 저장)
```

## 10. 비목표 / 예약
- 비목표(v1): 비박스 메시, 라이트/스카이 편집, 머티리얼 신규 생성, 언두, 메시 임포트.
- 예약 필드(무시하되 보존): props, lights, gametype, skybox.

## 11. 리스크 & 완화
- 시각 검증 불가: 숫자패널 중심 + 헤드리스 왕복 테스트 + 노드수/좌표 assert.
- main.tscn 대수술: 변환 스크립트로 1:1 보장, 변환 후 블록수/바운딩 비교.
- 멀티 동기화 타이밍: 맵 송신을 스폰보다 먼저, 클라 빌드 완료 후 스폰.
- CSG→StaticBody 전환: 콜리전·렌더 동일성(특히 램프 회전)은 MapBuilder 한 곳에서 책임.
