@echo off
chcp 65001 > nul
title Actualizar TecNM Mapas a Producción
echo ========================================================
echo    ACTUALIZAR TECNM MAPAS (NAVIA) A PRODUCCIÓN
echo ========================================================
echo.
echo Este proceso ejecutara:
echo   1. Pruebas de calidad
echo   2. Compilacion de APK firmado de Produccion
echo   3. Copiado a tu Escritorio
echo   4. Subida a Google Cloud Storage (CDN)
echo   5. Activacion de actualizacion In-App en Firestore
echo   6. Instalacion en tu celular (si esta conectado por USB)
echo.
set /p NOTES="Ingresa las novedades o notas del cambio (o presiona ENTER para usar notas por defecto): "

if "%NOTES%"=="" (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy_release.ps1"
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\deploy_release.ps1" -ReleaseNotes "%NOTES%"
)

echo.
pause
