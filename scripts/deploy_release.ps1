# ==============================================================================
# PIPELINE DE PRODUCCION: DEPLOY Y ACTUALIZACION TOTAL DE TECNM MAPAS (NAVIA)
# ==============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$Version = "",

    [Parameter(Mandatory=$false)]
    [int]$BuildNumber = 0,

    [Parameter(Mandatory=$false)]
    [string]$ReleaseNotes = "Mejoras de rendimiento, estabilidad y actualizacion de mapas.",

    [switch]$SkipTests,
    [switch]$SkipBuild,
    [switch]$SkipUpload,
    [switch]$SkipDeviceInstall,
    [switch]$SkipGit
)

$ErrorActionPreference = "Stop"

# Rutas base
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = (Get-Item "$ScriptDir\..").FullName
$AppDir = Join-Path $ProjectRoot "app"
$DistDir = Join-Path $ProjectRoot "dist"
$PubspecPath = Join-Path $AppDir "pubspec.yaml"
$AppVersionDart = Join-Path $AppDir "lib\core\constants\app_version.dart"
$ApkPath = Join-Path $AppDir "build\app\outputs\flutter-apk\app-release.apk"
$DesktopDir = [Environment]::GetFolderPath('Desktop')
$DesktopApk = Join-Path $DesktopDir "TecNM_Mapas.apk"
$DistApk = Join-Path $DistDir "TecNM_Mapas.apk"

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   LANZADOR DE PRODUCCION - TECNM MAPAS / NAVIA" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host ""

# ------------------------------------------------------------------------------
# 1. RESOLVER Y AUMENTAR VERSION
# ------------------------------------------------------------------------------
Write-Host "[1/8] Verificando version actual..." -ForegroundColor Yellow

$pubspecContent = Get-Content $PubspecPath -Raw -Encoding UTF8
if ($pubspecContent -match 'version:\s*([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)') {
    $currentVersion = $Matches[1]
    $currentBuild = [int]$Matches[2]
} else {
    Write-Error "No se pudo leer la version de $PubspecPath"
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $currentVersion
}
if ($BuildNumber -le 0) {
    if ($SkipBuild) {
        $BuildNumber = $currentBuild
    } else {
        $BuildNumber = $currentBuild + 1
    }
}

Write-Host "  -> Version anterior : v$currentVersion+$currentBuild" -ForegroundColor DarkGray
Write-Host "  -> Nueva version    : v$Version+$BuildNumber" -ForegroundColor Green

# Actualizar pubspec.yaml
$updatedPubspec = [regex]::Replace($pubspecContent, 'version:\s*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+', "version: $Version+$BuildNumber")
Set-Content -Path $PubspecPath -Value $updatedPubspec -NoNewline -Encoding UTF8

# Actualizar lib/core/constants/app_version.dart
$appVersionContent = Get-Content $AppVersionDart -Raw -Encoding UTF8
$appVersionContent = [regex]::Replace($appVersionContent, "static const String version = '[^']+';", "static const String version = '$Version';")
$appVersionContent = [regex]::Replace($appVersionContent, "static const int buildNumber = [0-9]+;", "static const int buildNumber = $BuildNumber;")
Set-Content -Path $AppVersionDart -Value $appVersionContent -NoNewline -Encoding UTF8
Write-Host "  [OK] Archivos de version sincronizados (pubspec.yaml y app_version.dart)" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 2. EJECUTAR PRUEBAS
# ------------------------------------------------------------------------------
if (-not $SkipTests) {
    Write-Host ""
    Write-Host "[2/8] Ejecutando pruebas automatizadas..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        & flutter test
        if ($LASTEXITCODE -ne 0) {
            throw "flutter test retorno codigo $LASTEXITCODE"
        }
        Write-Host "  [OK] Pruebas pasadas exitosamente" -ForegroundColor Green
    } catch {
        Pop-Location
        Write-Error "Fallaron las pruebas unitarias. Abortando publicacion."
        exit 1
    }
    Pop-Location
} else {
    Write-Host ""
    Write-Host "[2/8] Omitiendo pruebas (-SkipTests activado)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 3. COMPILACION DE APK DE PRODUCCION
# ------------------------------------------------------------------------------
if (-not $SkipBuild) {
    Write-Host ""
    Write-Host "[3/8] Compilando APK Release firmado institucionalmente..." -ForegroundColor Yellow
    Push-Location $AppDir
    try {
        & flutter build apk --release
        if ($LASTEXITCODE -ne 0) {
            throw "flutter build fallo con codigo $LASTEXITCODE"
        }
        if (-not (Test-Path $ApkPath)) {
            throw "El APK no fue generado en $ApkPath"
        }
        $apkItem = Get-Item $ApkPath
        $apkSizeMb = [math]::Round($apkItem.Length / 1MB, 2)
        Write-Host "  [OK] APK compilado con exito: $ApkPath ($apkSizeMb MB)" -ForegroundColor Green
    } catch {
        Pop-Location
        Write-Error "Error compilando el APK release: $_"
        exit 1
    }
    Pop-Location
} else {
    Write-Host ""
    Write-Host "[3/8] Omitiendo compilacion (-SkipBuild activado, usando APK existente)" -ForegroundColor DarkGray
}

# Verify the real APK before copying or publishing metadata (also with -SkipBuild).
$adbExecutable = (Get-Command adb -ErrorAction Stop).Source
$sdkDir = Split-Path (Split-Path $adbExecutable -Parent) -Parent
$aapt = Get-ChildItem (Join-Path $sdkDir "build-tools") -Filter aapt.exe -Recurse |
    Sort-Object FullName -Descending | Select-Object -First 1
if (-not $aapt) { throw "No se encontro aapt para verificar el APK" }
$badging = & $aapt.FullName dump badging $ApkPath
if ($LASTEXITCODE -ne 0) { throw "No se pudo inspeccionar el APK" }
$packageLine = $badging | Select-Object -First 1
if ($packageLine -notmatch "name='mx.edu.tecnm.colima.sinait'" -or
    $packageLine -notmatch "versionCode='$BuildNumber'" -or
    $packageLine -notmatch "versionName='$Version'") {
    throw "El APK no coincide con la version anunciada: $packageLine"
}
$versionedApkName = "TecNM_Mapas_v${Version}_b${BuildNumber}.apk"
$versionedApkUrl = "https://storage.googleapis.com/tecnm-mapas-updates/$versionedApkName"

# ------------------------------------------------------------------------------
# 4. DISTRIBUCION LOCAL (ESCRITORIO Y DIST/)
# ------------------------------------------------------------------------------
Write-Host ""
Write-Host "[4/8] Copiando APK a ubicaciones de distribucion local..." -ForegroundColor Yellow

if (-not (Test-Path $DistDir)) {
    New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
}

Copy-Item $ApkPath -Destination $DesktopApk -Force
Copy-Item $ApkPath -Destination $DistApk -Force

Write-Host "  [OK] Copiado al Escritorio : $DesktopApk" -ForegroundColor Green
Write-Host "  [OK] Copiado a dist/       : $DistApk" -ForegroundColor Green

# ------------------------------------------------------------------------------
# 5. SUBIDA A GOOGLE CLOUD STORAGE
# ------------------------------------------------------------------------------
if (-not $SkipUpload) {
    Write-Host ""
    Write-Host "[5/8] Subiendo a Google Cloud Storage (CDN publico)..." -ForegroundColor Yellow

    Write-Host "  -> Subiendo a gs://tecnm-mapas-updates/TecNM_Mapas.apk..." -ForegroundColor DarkCyan
    & gcloud storage cp $DistApk "gs://tecnm-mapas-updates/$versionedApkName"
    if ($LASTEXITCODE -ne 0) { throw "Fallo la subida del APK versionado" }
    & gcloud storage cp "gs://tecnm-mapas-updates/$versionedApkName" gs://tecnm-mapas-updates/TecNM_Mapas.apk --cache-control=no-store
    if ($LASTEXITCODE -ne 0) { throw "Fallo la subida del APK" }

    Write-Host "  -> Subiendo a gs://navia-updates-tecnm/TecNM_Mapas.apk..." -ForegroundColor DarkCyan
    & gcloud storage cp "gs://tecnm-mapas-updates/$versionedApkName" gs://navia-updates-tecnm/TecNM_Mapas.apk --cache-control=no-store
    if ($LASTEXITCODE -ne 0) { throw "Fallo la subida del APK secundario" }

    Write-Host "  [OK] APK disponible publicamente en la nube:" -ForegroundColor Green
    Write-Host "       https://storage.googleapis.com/tecnm-mapas-updates/TecNM_Mapas.apk" -ForegroundColor Cyan
} else {
    Write-Host ""
    Write-Host "[5/8] Omitiendo subida a la nube (-SkipUpload activado)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 6. SINCRONIZAR METADATOS DE ACTUALIZACION EN FIRESTORE
# ------------------------------------------------------------------------------
if (-not $SkipUpload) {
    Write-Host ""
    Write-Host "[6/8] Activando alerta de actualizacion en Firestore (In-App Updater)..." -ForegroundColor Yellow

    $syncScript = Join-Path $ScriptDir "sync_cloud_update.js"
    Push-Location $ProjectRoot
    try {
        & node $syncScript --version $Version --build $BuildNumber --notes $ReleaseNotes --apkUrl $versionedApkUrl --mandatory
        if ($LASTEXITCODE -ne 0) { throw "Fallo la sincronizacion de Firestore" }
        Write-Host "  [OK] Metadatos sincronizados en app_meta/app_update. In-App Updater activado (Obligatorio)." -ForegroundColor Green
    } catch {
        throw "No se pudo actualizar Firestore: $_"
    }
    Pop-Location
} else {
    Write-Host ""
    Write-Host "[6/8] Omitiendo sincronizacion en Firestore (-SkipUpload activado)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 7. INSTALAR EN DISPOSITIVOS CONECTADOS (ADB)
# ------------------------------------------------------------------------------
if (-not $SkipDeviceInstall) {
    Write-Host ""
    Write-Host "[7/8] Buscando dispositivos fisicos conectados por ADB..." -ForegroundColor Yellow

    $adbDevicesOutput = & adb devices
    $deviceMatches = [regex]::Matches($adbDevicesOutput, '(?m)^([a-zA-Z0-9_\-]+)\s+device$')

    if ($deviceMatches.Count -gt 0) {
        foreach ($m in $deviceMatches) {
            $deviceId = $m.Groups[1].Value
            Write-Host "  -> Instalando en dispositivo: $deviceId..." -ForegroundColor DarkCyan
            & adb -s $deviceId install -r $ApkPath
            & adb -s $deviceId shell monkey -p mx.edu.tecnm.colima.sinait -c android.intent.category.LAUNCHER 1 | Out-Null
            Write-Host "  [OK] Instalado y ejecutado en: $deviceId" -ForegroundColor Green
        }
    } else {
        Write-Host "  (No hay dispositivos conectados por USB/WiFi ADB, omitiendo instalacion directa)" -ForegroundColor DarkGray
    }
} else {
    Write-Host ""
    Write-Host "[7/8] Omitiendo instalacion en dispositivo (-SkipDeviceInstall activado)" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# 8. GIT COMMIT Y TAG
# ------------------------------------------------------------------------------
if (-not $SkipGit) {
    Write-Host ""
    Write-Host "[8/8] Registrando release en Git..." -ForegroundColor Yellow
    Push-Location $ProjectRoot
    try {
        & git add -A
        & git commit -m "chore(release): v$Version+$BuildNumber - $ReleaseNotes" --allow-empty
        & git tag -a "v$Version+$BuildNumber" -m "Release v$Version+$BuildNumber" -f
        Write-Host "  [OK] Git commit y tag creados (v$Version+$BuildNumber)" -ForegroundColor Green
    } catch {
        Write-Warning "No se pudo crear commit/tag en Git: $_"
    }
    Pop-Location
} else {
    Write-Host ""
    Write-Host "[8/8] Omitiendo Git (-SkipGit activado)" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "   ACTUALIZACION PUBLICADA Y PROPAGADA EXITOSAMENTE" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  Version final  : v$Version (Build $BuildNumber)"
Write-Host "  Escritorio     : $DesktopApk"
Write-Host "  Dist           : $DistApk"
Write-Host "  Cloud Storage  : https://storage.googleapis.com/tecnm-mapas-updates/TecNM_Mapas.apk"
Write-Host "  In-App Updater : Activo en Firestore para todos los usuarios."
Write-Host ""
