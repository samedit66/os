@echo off

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo Cannot find vswhere.exe
    exit /b 1
)

set "VS_PATH="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS_PATH=%%i"
if not defined VS_PATH (
    echo Cannot find a Visual Studio C++ toolchain
    exit /b 1
)

call "%VS_PATH%\VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 exit /b 1
