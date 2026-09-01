@echo off
setlocal enabledelayedexpansion
title JoErl Dashboard - Build
cd /d "%~dp0"

set "APP_NAME=JoErl Dashboard"

echo ================================
echo   JoErl Dashboard Build Script
echo ================================
echo.

REM --- 0. Check Flutter is on PATH ---
where flutter >nul 2>nul
if errorlevel 1 (
    echo [ERROR] Flutter SDK was not found on PATH.
    echo         Install Flutter and re-run this script.
    pause
    exit /b 1
)

REM --- 1. Scaffold the windows\ runner if this is a fresh checkout ---
if not exist "windows\" (
    echo [1/7] No windows\ runner folder found - generating it...
    flutter create . --platforms=windows
    if errorlevel 1 (
        echo [ERROR] "flutter create" failed.
        pause
        exit /b 1
    )
) else (
    echo [1/7] windows\ runner already present - skipping scaffold.
)
echo.

REM --- 2. Force the output exe to be named "JoErl Dashboard.exe" instead of
REM     the default "joerl_dashboard.exe". IMPORTANT: this does NOT rename
REM     BINARY_NAME itself, because CMake target names can't contain spaces
REM     (BINARY_NAME is used as the actual CMake target identifier in
REM     runner\CMakeLists.txt, not just the output filename - giving it a
REM     space breaks target_compile_definitions/target_link_libraries with
REM     "not built by this project" errors). Instead this sets the target's
REM     OUTPUT_NAME property, which only affects the produced .exe name.
REM     Generates a small temp .ps1 (far more reliable than trying to
REM     escape a multi-line PowerShell one-liner inside a .bat file).
REM     Idempotent, and self-heals BINARY_NAME back to a safe id if an
REM     earlier version of this script broke it.
echo [2/7] Setting output exe name to "%APP_NAME%.exe"...
set "RENAME_PS1=%TEMP%\joerl_dashboard_rename.ps1"
if exist "%RENAME_PS1%" del "%RENAME_PS1%"
echo $appName = '%APP_NAME%' >> "%RENAME_PS1%"
echo $safeId = 'joerl_dashboard' >> "%RENAME_PS1%"
echo $q = [char]34 >> "%RENAME_PS1%"
echo $needsClean = $false >> "%RENAME_PS1%"
echo $f1 = 'windows\CMakeLists.txt' >> "%RENAME_PS1%"
echo if (-not (Test-Path $f1)) { exit 1 } >> "%RENAME_PS1%"
echo $c = Get-Content $f1 -Raw >> "%RENAME_PS1%"
echo $pattern = 'set\(BINARY_NAME ' + $q + '.*?' + $q + '\)' >> "%RENAME_PS1%"
echo $repl = 'set(BINARY_NAME ' + $q + $safeId + $q + ')' >> "%RENAME_PS1%"
echo $c2 = [regex]::Replace($c, $pattern, $repl) >> "%RENAME_PS1%"
echo if ($c2 -ne $c) { Set-Content -Path $f1 -Value $c2 -NoNewline; $needsClean = $true } >> "%RENAME_PS1%"
echo $f2 = 'windows\runner\main.cpp' >> "%RENAME_PS1%"
echo if (Test-Path $f2) { >> "%RENAME_PS1%"
echo   $c = Get-Content $f2 -Raw >> "%RENAME_PS1%"
echo   $pattern2 = 'window\.Create\(L' + $q + '.*?' + $q >> "%RENAME_PS1%"
echo   $repl2 = 'window.Create(L' + $q + $appName + $q >> "%RENAME_PS1%"
echo   $c2 = [regex]::Replace($c, $pattern2, $repl2) >> "%RENAME_PS1%"
echo   if ($c2 -ne $c) { Set-Content -Path $f2 -Value $c2 -NoNewline } >> "%RENAME_PS1%"
echo } >> "%RENAME_PS1%"
echo $f3 = 'windows\runner\CMakeLists.txt' >> "%RENAME_PS1%"
echo if (Test-Path $f3) { >> "%RENAME_PS1%"
echo   $c = Get-Content $f3 -Raw >> "%RENAME_PS1%"
echo   if (-not $c.Contains('OUTPUT_NAME')) { >> "%RENAME_PS1%"
echo     $nl = [Environment]::NewLine >> "%RENAME_PS1%"
echo     $insertLine = 'set_target_properties(${BINARY_NAME} PROPERTIES OUTPUT_NAME ' + $q + $appName + $q + ')' >> "%RENAME_PS1%"
echo     $marker = 'apply_standard_settings(${BINARY_NAME})' >> "%RENAME_PS1%"
echo     if ($c.Contains($marker)) { >> "%RENAME_PS1%"
echo       $c2 = $c.Replace($marker, $marker + $nl + $insertLine) >> "%RENAME_PS1%"
echo     } else { >> "%RENAME_PS1%"
echo       $c2 = $c + $nl + $insertLine + $nl >> "%RENAME_PS1%"
echo     } >> "%RENAME_PS1%"
echo     Set-Content -Path $f3 -Value $c2 -NoNewline >> "%RENAME_PS1%"
echo     $needsClean = $true >> "%RENAME_PS1%"
echo   } >> "%RENAME_PS1%"
echo } >> "%RENAME_PS1%"
echo if ($needsClean) { exit 2 } else { exit 0 } >> "%RENAME_PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%RENAME_PS1%"
set "RENAME_RC=%ERRORLEVEL%"
set "FORCE_CLEAN="
if "%RENAME_RC%"=="1" (
    echo   [WARN] Rename step could not find windows\CMakeLists.txt - exe may keep its default name.
) else if "%RENAME_RC%"=="2" (
    echo   Applied - build\ will be cleaned so it takes effect.
    set "FORCE_CLEAN=1"
) else (
    echo   Already up to date.
)
del "%RENAME_PS1%" >nul 2>nul
echo.

REM --- 3. Fetch packages ---
echo [3/7] Running flutter pub get...
call flutter pub get
if errorlevel 1 (
    echo [ERROR] "flutter pub get" failed.
    pause
    exit /b 1
)
echo.

REM --- 4. Sanity-check apps.json is valid before we bundle it ---
echo [4/7] Validating assets\apps.json...
powershell -NoProfile -Command "try { Get-Content 'assets\apps.json' -Raw | ConvertFrom-Json | Out-Null; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
if errorlevel 1 (
    echo [ERROR] assets\apps.json is not valid JSON - fix it before building.
    pause
    exit /b 1
)
echo   apps.json OK.
echo.

REM --- 5. Detect a stale CMake cache - either from a previous folder
REM     location, or because step 2 just edited CMakeLists.txt - and force
REM     a clean reconfigure so those changes actually take effect.
set "CACHE_FILE=build\windows\x64\CMakeCache.txt"
set "HERE=%CD%"
set "HERE=%HERE:\=/%"
set "NEEDS_CLEAN="
if defined FORCE_CLEAN set "NEEDS_CLEAN=1"
if exist "%CACHE_FILE%" (
    findstr /C:"%HERE%" "%CACHE_FILE%" >nul
    if errorlevel 1 set "NEEDS_CLEAN=1"
)
if defined NEEDS_CLEAN (
    echo [5/7] Cleaning build\ for a fresh reconfigure...
    rmdir /s /q build
) else (
    echo [5/7] Build cache OK, or nothing to clean.
)
echo.

REM --- 6. Build the release exe ---
echo [6/7] Building release exe (this can take a minute)...
call flutter build windows --release
if errorlevel 1 (
    echo   Build failed - retrying once with a full "flutter clean"...
    call flutter clean
    call flutter pub get
    call flutter build windows --release
    if errorlevel 1 (
        echo [ERROR] "flutter build windows" failed twice. See the log above for the real error.
        pause
        exit /b 1
    )
)
echo.

REM --- 7. Drop a live copy of apps.json next to the built exe ---
set "OUT_DIR=build\windows\x64\runner\Release"
echo [7/7] Copying apps.json next to the built exe...
copy /y "assets\apps.json" "%OUT_DIR%\apps.json" >nul

if not exist "%OUT_DIR%\%APP_NAME%.exe" (
    echo.
    echo [WARN] Expected "%OUT_DIR%\%APP_NAME%.exe" but didn't find it.
    echo        Contents of %OUT_DIR%:
    dir /b "%OUT_DIR%\*.exe"
)

echo.
echo ================================
echo   Build complete!
echo   Exe: %OUT_DIR%\%APP_NAME%.exe
echo ================================
echo.
echo Tip: edit "%OUT_DIR%\apps.json" any time to add or fix an app entry -
echo      the dashboard reads that copy at runtime, no rebuild needed.
echo.
pause
