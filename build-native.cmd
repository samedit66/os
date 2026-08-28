@echo off
setlocal

set "OS_NATIVE_COMPILER=%~1"
if not defined OS_NATIVE_COMPILER set "OS_NATIVE_COMPILER=msvc"

call "%~dp0.github\scripts\setup-msvc.cmd"
if errorlevel 1 exit /b 1

if not exist "%~dp0build\native" mkdir "%~dp0build\native"
if "%OS_NATIVE_COMPILER%"=="msvc" (
    cl /nologo /std:c11 /W4 /WX /I "%~dp0c" /c "%~dp0c\subprocess_windows.c" /Fo"%~dp0build\native\subprocess.obj"
    if errorlevel 1 exit /b 1
    cl /nologo /std:c11 /W4 /WX /I "%~dp0c" /c "%~dp0c\file_path_windows.c" /Fo"%~dp0build\native\file_path.obj"
) else if "%OS_NATIVE_COMPILER%"=="clang-cl" (
    clang-cl /nologo /std:c11 /W4 /WX /I "%~dp0c" /c "%~dp0c\subprocess_windows.c" /Fo"%~dp0build\native\subprocess.obj"
    if errorlevel 1 exit /b 1
    clang-cl /nologo /std:c11 /W4 /WX /I "%~dp0c" /c "%~dp0c\file_path_windows.c" /Fo"%~dp0build\native\file_path.obj"
) else (
    echo Unknown compiler: %OS_NATIVE_COMPILER%
    exit /b 2
)
if errorlevel 1 exit /b 1

lib /nologo /out:"%~dp0build\native\os_native.lib" "%~dp0build\native\subprocess.obj" "%~dp0build\native\file_path.obj"
if errorlevel 1 exit /b 1
