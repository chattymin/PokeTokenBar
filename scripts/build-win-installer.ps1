# Build the Windows installer (Setup.exe) for PokeTokenBar from the current release build.
#
#   pwsh scripts/build-win-installer.ps1 -Version 2.4.5.7 -OutDir out
#
# Prerequisites:
#   * `swift build -c release` already run in the Swift-for-Windows environment (produces the exe).
#   * Inno Setup installed:  winget install JRSoftware.InnoSetup
#
# It assembles the portable folder (release exe + Swift runtime DLLs + VC++ runtime) and compiles
# installer/PokeTokenBar.iss into PokeTokenBar-Setup-<Version>.exe (per-user AppData installer).
param(
  [Parameter(Mandatory)][string]$Version,
  [string]$OutDir = "."
)
$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $root ".build\x86_64-unknown-windows-msvc\release\PokeTokenBar.exe"
if (-not (Test-Path $exe)) { throw "Release exe not found - run 'swift build -c release' first: $exe" }

# Guard: the built exe's baked version MUST match -Version. Forgetting `swift build -c release` after
# bumping the version silently ships a stale exe (e.g. Setup-2.4.5.13 containing a 2.4.5.12 binary =>
# an endless update loop). Verify before packaging.
$baked = (& $exe --update-check 2>&1 | Select-String 'current baked version:\s*([\d.]+)').Matches.Groups[1].Value
if ($baked -ne $Version) {
  throw "Release exe is v$baked but you asked for v$Version. Run 'swift build -c release' after bumping WindowsUpdate.currentVersion, then retry."
}

# Swift runtime (redistributable DLLs) + toolchain bin (BlocksRuntime/dispatch).
$rt = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Runtimes" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName + "\usr\bin"
$tc = (Get-ChildItem "$env:LOCALAPPDATA\Programs\Swift\Toolchains" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName + "\usr\bin"

$stage = Join-Path $env:TEMP "ptb-portable-$Version"
if (Test-Path $stage) { Get-ChildItem $stage | Remove-Item -Recurse -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
Copy-Item $exe $stage
Copy-Item (Join-Path $rt "*.dll") $stage -Force
foreach ($d in "BlocksRuntime.dll", "dispatch.dll") { $s = Join-Path $tc $d; if (Test-Path $s) { Copy-Item $s $stage -Force } }
foreach ($d in "VCRUNTIME140.dll", "VCRUNTIME140_1.dll", "msvcp140.dll") { $s = "C:\Windows\System32\$d"; if (Test-Path $s) { Copy-Item $s $stage -Force } }

$iscc = Get-ChildItem "$env:LOCALAPPDATA\Programs\Inno Setup 6", "${env:ProgramFiles(x86)}\Inno Setup 6", "$env:ProgramFiles\Inno Setup 6" -Filter ISCC.exe -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName
if (-not $iscc) { throw "ISCC.exe (Inno Setup) not found. Install: winget install JRSoftware.InnoSetup" }
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
& $iscc "/DSrcDir=$stage" "/DAppVer=$Version" "/DOutDir=$OutDir" (Join-Path $root "installer\PokeTokenBar.iss")
Write-Host "Installer: $(Resolve-Path (Join-Path $OutDir "PokeTokenBar-Setup-$Version.exe"))"
