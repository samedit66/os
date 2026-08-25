@echo off
setlocal

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH exit /b 1

call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1

if not exist build\native mkdir build\native
if "%~1"=="msvc" (
    cl /nologo /std:c11 /W4 /WX /I c /c c\subprocess_windows.c /Fobuild\native\subprocess.obj
) else if "%~1"=="clang-cl" (
    clang-cl /nologo /std:c11 /W4 /WX /I c /c c\subprocess_windows.c /Fobuild\native\subprocess.obj
) else (
    echo Unknown compiler: %~1
    exit /b 2
)
if errorlevel 1 exit /b 1

if "%~2"=="library" (
    lib /nologo /out:build\native\os_process.lib build\native\subprocess.obj
    if errorlevel 1 exit /b 1
)
