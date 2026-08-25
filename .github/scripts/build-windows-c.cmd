@echo off
setlocal

call "%~dp0setup-msvc.cmd"
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
