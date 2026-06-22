# build.ps1 - AluxStrike 단일 실행파일 빌드 (Windows / Linux 크로스 익스포트)
# 사용법:  ./build.ps1            -> Windows  (build\AluxStrike.exe)
#          ./build.ps1 linux     -> Linux    (build\AluxStrike.x86_64)
# WSL 불필요: Godot 이 Windows 에서 바로 Linux 바이너리를 뽑습니다.
param([string]$Platform = "windows")

$ErrorActionPreference = "Stop"
$ProjectDir = $PSScriptRoot
$ExeName    = "AluxStrike"
$OutDir     = Join-Path $ProjectDir "build"
$ExportFlag = "--export-release"
if ($Platform -eq "linux") {
    $Preset = "Linux"
    $OutExe = Join-Path $OutDir "$ExeName.x86_64"
} elseif ($Platform -eq "debug") {
    # Debug build: ships the debug template so native crash backtraces resolve
    # to symbols and GDScript runtime errors print a full source:line stack.
    $Preset = "Windows Desktop"
    $OutExe = Join-Path $OutDir "${ExeName}_debug.exe"
    $ExportFlag = "--export-debug"
} else {
    $Preset = "Windows Desktop"
    $OutExe = Join-Path $OutDir "$ExeName.exe"
}

Write-Host "== FPS Game 빌드 ==" -ForegroundColor Cyan

# 1) godot 실행파일 확인
$godot = (Get-Command godot -ErrorAction SilentlyContinue).Source
if (-not $godot) { throw "godot 가 PATH 에 없습니다. Godot 4.x 를 설치하고 PATH 에 추가하세요." }
Write-Host "godot: $godot"

# 2) 버전 -> 템플릿 폴더 이름 (예: 4.6.3.stable)
$verAll = (& godot --version 2>&1 | Out-String)   # 예: 4.6.3.stable.official.xxxxx
$m = [regex]::Match($verAll, '(\d+\.\d+(?:\.\d+)?)\.(stable|beta\d*|rc\d*|dev\d*)')
if (-not $m.Success) { throw "버전 파싱 실패: $verAll" }
$verNum  = $m.Groups[1].Value           # 4.6.3
$verChan = $m.Groups[2].Value           # stable
$tmplVer = "$verNum.$verChan"           # 4.6.3.stable
Write-Host "버전: $tmplVer"

# 3) export_presets.cfg 없으면 생성 (단일 exe: PCK 임베드 + 콘솔래퍼 끔)
$presetFile = Join-Path $ProjectDir "export_presets.cfg"
Write-Host "export_presets.cfg 작성 (단일 exe, BOM 없이)..." -ForegroundColor Yellow
$presetText = @'
[preset.0]
name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.0.options]
binary_format/embed_pck=true
binary_format/architecture="x86_64"
debug/export_console_wrapper=0

[preset.1]
name="Linux"
platform="Linux"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter=""
exclude_filter=""
export_path=""
encryption_include_filters=""
encryption_exclude_filters=""
encrypt_pck=false
encrypt_directory=false

[preset.1.options]
binary_format/embed_pck=true
binary_format/architecture="x86_64"
'@
# PowerShell 5.1 의 Out-File utf8 은 BOM 을 붙여 Godot ConfigFile 파서가 깨지므로 BOM 없이 기록
[System.IO.File]::WriteAllText($presetFile, $presetText, (New-Object System.Text.UTF8Encoding($false)))

# 4) export templates 확인, 없으면 다운로드/설치
$tmplDir = Join-Path $env:APPDATA "Godot\export_templates\$tmplVer"
$needTmpl = -not (Test-Path (Join-Path $tmplDir "windows_release_x86_64.exe"))
if ($needTmpl) {
    Write-Host "export templates 없음 -> 다운로드 시도..." -ForegroundColor Yellow
    $url = "https://github.com/godotengine/godot/releases/download/$verNum-$verChan/Godot_v$verNum-$verChan`_export_templates.tpz"
    $tmp = Join-Path $env:TEMP "godot_tmpl_$tmplVer"
    $tpz = "$tmp.zip"
    try {
        Invoke-WebRequest $url -OutFile $tpz -UserAgent "Mozilla/5.0"
        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        Expand-Archive $tpz -DestinationPath $tmp -Force
        New-Item -ItemType Directory -Force $tmplDir | Out-Null
        Copy-Item (Join-Path $tmp "templates\*") $tmplDir -Recurse -Force
        Remove-Item $tpz,$tmp -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "템플릿 설치 완료: $tmplDir" -ForegroundColor Green
    } catch {
        throw @"
export templates 자동 설치 실패 ($url).
Godot 에디터에서 수동 설치하세요:
  godot -e --path "$ProjectDir"  실행 후
  상단 메뉴 [편집기] > [내보내기 템플릿 관리] > [다운로드 및 설치]
그런 다음 다시 ./build.ps1 실행.
"@
    }
} else {
    Write-Host "export templates OK: $tmplDir"
}

# 5) 빌드
New-Item -ItemType Directory -Force $OutDir | Out-Null
if (Test-Path $OutExe) { Remove-Item $OutExe -Force }
Write-Host "내보내는 중 -> $OutExe" -ForegroundColor Cyan
# godot 진행상황이 stderr 로 나와 Stop 모드에서 종료성 에러로 오인되므로 완화
$ErrorActionPreference = "Continue"
& godot --headless --path $ProjectDir $ExportFlag $Preset $OutExe
Write-Host "godot 종료코드: $LASTEXITCODE"

# 6) 결과 확인
if (Test-Path $OutExe) {
    $mb = [math]::Round((Get-Item $OutExe).Length / 1MB, 1)
    Write-Host "`n완료: $OutExe  ($mb MB)" -ForegroundColor Green
    Write-Host "실행: `"$OutExe`""
    exit 0
} else {
    throw "빌드는 끝났지만 exe 가 생성되지 않았습니다."
}
