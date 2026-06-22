# 무기 시스템 / 무기 추가 가이드

## 현재 아세널 (`scripts/weapon/weapon.gd` 의 `_defs` 배열)

인덱스 0~9 = 숫자키 1~9,0. 10~ 은 픽업 전용. F 무기휠로는 미니건 제외 전부 선택.

| # | 이름 | 모델 | 특징 |
|---|------|------|------|
| 0 | Pistol | q_pistol | 기본 사이드암 |
| 1 | SMG | q_smg | 빠른 연사, 낮은 데미지, 큰 탄퍼짐 |
| 2 | Rifle | q_rifle | 밸런스형 자동소총 |
| 3 | Carbine | q_bullpup | 정확도 높음(AUG형 불펍) |
| 4 | LMG | q_lmg | 대용량 탄창, 높은 반동 |
| 5 | Shotgun | shotgun | 근접 고화력 |
| 6 | Sniper | q_sniper | 스코프, 초고데미지 |
| 7 | Magnum | q_revolver | 핸드캐논(리볼버) |
| 8 | Rocket | q_rocket | 폭발 투사체(AoE) |
| 9 | Laser | q_laser | 즉시 명중 빔 |
| 10 | Knife | knife | 근접 |
| 11 | Grenade | grenade_held | 투척(휠로만 선택) |
| 12 | Minigun | rifle(어둡게) | 픽업 전용, 200발 무재장전 |

모델 출처: Quaternius "Ultimate Guns Pack"(CC0) + RPG Launcher/Scifi Sniper(poly.pizza). `assets/weapons/CREDITS.md` 참조.

## 무기 한 자루 추가하는 법

1. **모델 준비**: `.glb` 를 `assets/weapons/real/` 에 넣는다. (poly.pizza 직링크 `https://static.poly.pizza/<uuid>.glb` 를 curl)
2. **AABB 측정**(선택): 가장 긴 축 = 총열 방향. Quaternius 계열은 +X 라 `GUN_ORIENT` 그대로. 다른 축이면 `"orient"` 에 보정 Basis 지정(예: 로켓의 `ROCKET_ORIENT`).
3. **`weapon.gd` 상단에 preload 상수 추가**, `_defs` 에 항목 추가:
   ```gdscript
   {"name": "AK47", "scene": Q_AK, "damage": 30, "cooldown": 0.11, "mag": 30,
    "reserve": 120, "scale": 0.29, "pos": Vector3(0.24,-0.31,-0.55), "spread": 0.04},
   ```
   - `scale` = 목표 화면길이 / 모델 AABB 최장축 (라이플 기준 화면길이 ≈ 1.5)
   - 특수 플래그: `scope`/`ads_fov`, `melee`/`range`, `throwable`, `rocket`, `laser`, `no_reload`, `tint`, `orient`
4. **숫자키/휠 노출**: 인덱스 < `MINIGUN_INDEX` 면 휠에 자동 노출. 숫자키는 `player.gd` `_unhandled_input` 의 `KEY_*` 매핑에 추가(현재 0~9까지).
5. 검증: `godot --headless --import` 후 게임 실행.

## 발사 동작 분기 (`weapon.gd` `fire()`)
- 일반 히트스캔: 탄퍼짐 콘 레이캐스트 → 첫 충돌에 데미지
- `throwable`: 수류탄 로브
- `rocket`: `rocket.tscn` 직진 폭발 투사체
- `laser`: 즉시 명중 + 글로우 빔(`_spawn_beam`)
- `melee`: 정면 짧은 레이

## 업그레이드(보스헤드식)
- 좀비 처치 +15 포인트. `weapon.gd` 의 `_dmg_lv/_rate_lv/_mag_lv`(무기별, 최대 5).
- 키: J=데미지(+25%/lv), K=연사(×0.85 쿨다운/lv), L=탄창(+30%/lv). 비용 120.
- 효과 스탯: `_eff_damage/_eff_cooldown/_eff_mag`.

## 배치물
- 지뢰(Z, 40p): `mine.tscn`, 좀비 접근 시 폭발 AoE
- 바리케이드(X, 80p): `barricade.tscn`, 솔리드 블로커. 인접 좀비가 HP를 깎음. H로 내구(최대 HP) 업글, 신규 설치분에 적용.

## 향후 추가 아이디어 (TODO)
- 실제 AK47/AUG/P90/M4 정밀 모델로 교체(현재는 근사 CC0 모델)
- 화염방사기 / 테슬라 / 터렛(보스헤드 mounted gun)
- 무기별 고유 머즐 플래시·사운드
- 멀티플레이에서 투사체/배치물 복제(현재 배치는 호스트 기준 로컬)
