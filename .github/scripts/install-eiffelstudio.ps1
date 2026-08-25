$ErrorActionPreference = "Stop"

$installer = Join-Path $env:RUNNER_TEMP "get-eiffelstudio.bat"
curl.exe -fsSL -o $installer https://www.eiffel.org/setup/install.bat
if ($LASTEXITCODE -ne 0) { throw "Cannot download the EiffelStudio installer" }

Push-Location $env:RUNNER_TEMP
try {
    & cmd.exe /d /c "`"$installer`" latest"
    if ($LASTEXITCODE -ne 0) { throw "EiffelStudio installation failed" }
}
finally {
    Pop-Location
}

$compiler = Get-ChildItem -Path $env:RUNNER_TEMP -Recurse -File -Filter ec.exe |
    Where-Object { $_.FullName -match '[\\/]studio[\\/]spec[\\/][^\\/]+[\\/]bin[\\/]ec\.exe$' } |
    Select-Object -First 1
if ($null -eq $compiler) {
    throw "The EiffelStudio installation does not contain ec.exe"
}

$platform = $compiler.Directory.Parent.Name
$root = $compiler.Directory.Parent.Parent.Parent.Parent.FullName
"ISE_EIFFEL=$root" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"ISE_LIBRARY=$root" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"ISE_PLATFORM=$platform" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
$compiler.Directory.FullName | Out-File -FilePath $env:GITHUB_PATH -Encoding utf8 -Append
