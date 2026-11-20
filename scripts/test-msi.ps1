# Smoke test for a Windows installer built by `gradlew msi`.
# Usage: powershell -File scripts\test-msi.ps1 build\distributions\dotify-studio-<version>-windows-x64.msi
#
# Installs the package silently, checks the installed files, starts the app with the bundled
# runtime and through the installed dotify-studio.exe, then uninstalls it again.
# Needs an administrator prompt (as on GitHub's Windows runners).
param(
	[Parameter(Mandatory = $true)][string]$Msi,
	[int]$Timeout = 120
)
$ErrorActionPreference = 'Stop'

function Fail([string]$message) {
	Write-Host "FAIL: $message"
	exit 1
}

function Wait-For([scriptblock]$condition, [int]$seconds) {
	for ($i = 0; $i -lt $seconds; $i++) {
		if (& $condition) { return $true }
		Start-Sleep -Seconds 1
	}
	return $false
}

$msiPath = (Resolve-Path $Msi).Path
$work = Join-Path ([IO.Path]::GetTempPath()) ("dotify-test-" + [guid]::NewGuid())
New-Item -ItemType Directory $work | Out-Null
Write-Host "== $msiPath"

# Install
$installLog = Join-Path $work 'install.log'
$p = Start-Process msiexec.exe -ArgumentList "/i `"$msiPath`" /qn /norestart /l*v `"$installLog`"" -Wait -PassThru
if ($p.ExitCode -ne 0) {
	Get-Content $installLog -Tail 60
	Fail "install failed with exit code $($p.ExitCode)"
}

$exe = Get-ChildItem -Path $env:ProgramFiles, ${env:ProgramFiles(x86)}, (Join-Path $env:LOCALAPPDATA 'Programs') `
	-Filter 'dotify-studio.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $exe) { Fail 'dotify-studio.exe not found after installing' }
$dir = $exe.DirectoryName
Write-Host "installed in $dir"

$java = Join-Path $dir 'jre\bin\java.exe'
if (-not (Test-Path $java)) { Fail "bundled runtime not found at $java" }
$version = cmd /c "`"$java`" -version 2>&1" | Select-Object -First 1
Write-Host "runtime: $version"
if ($version -notmatch '"21\.') { Fail "expected a Java 21 runtime, got: $version" }
if (-not (Test-Path (Join-Path $dir 'jre\lib\javafx.properties'))) { Fail 'bundled runtime does not include JavaFX' }
if (-not (Get-ChildItem (Join-Path $dir 'lib\plugins') -Filter '*.jar' -ErrorAction SilentlyContinue)) { Fail 'no plugins installed' }
$jar = Get-ChildItem (Join-Path $dir 'lib') -Filter 'dotify-studio-*.jar' | Select-Object -First 1
if (-not $jar) { Fail 'dotify-studio jar not found' }

# 1. Start with the bundled runtime directly, which shows the app's log.
$out = Join-Path $work 'app.out'
$err = Join-Path $work 'app.err'
$app = Start-Process $java -ArgumentList '-jar', "`"$($jar.FullName)`"" -WorkingDirectory $dir `
	-RedirectStandardOutput $out -RedirectStandardError $err -PassThru
$started = Wait-For { (Test-Path $err) -and (Select-String -Path $err -Pattern 'Found jars' -Quiet) -or $app.HasExited } $Timeout
if ($app.HasExited -or -not $started) {
	Get-Content $out, $err -ErrorAction SilentlyContinue
	Fail 'app did not start with the bundled runtime'
}
Start-Sleep -Seconds 3
if ($app.HasExited) { Get-Content $out, $err; Fail 'app exited after starting' }
if (Select-String -Path $out, $err -Pattern 'Exception' -Quiet) { Get-Content $out, $err; Fail 'errors in app output' }
Stop-Process -Id $app.Id -Force
Write-Host 'started with the bundled runtime'

# 2. Start through the installed launcher, as the Start menu shortcut does.
$launcher = Start-Process $exe.FullName -WorkingDirectory $dir -PassThru
$jreDir = Join-Path $dir 'jre'
$running = { Get-Process javaw, java -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "$jreDir*" } }
if (-not (Wait-For { & $running } $Timeout)) {
	# launch4j shows a message box and keeps running when it can't start Java.
	if (-not $launcher.HasExited) { Stop-Process -Id $launcher.Id -Force }
	Fail 'dotify-studio.exe did not start the bundled runtime'
}
Start-Sleep -Seconds 15
$jvm = & $running | Select-Object -First 1
if (-not $jvm) { Fail 'app started from dotify-studio.exe exited' }
$title = (Get-Process -Id $jvm.Id).MainWindowTitle
if ($title) { Write-Host "window: $title" } else { Write-Host 'window: (none reported; normal without an interactive desktop)' }
& $running | Stop-Process -Force
if (-not $launcher.HasExited) { Stop-Process -Id $launcher.Id -Force -ErrorAction SilentlyContinue }
Write-Host 'started with dotify-studio.exe'

# Uninstall
$uninstallLog = Join-Path $work 'uninstall.log'
$p = Start-Process msiexec.exe -ArgumentList "/x `"$msiPath`" /qn /norestart /l*v `"$uninstallLog`"" -Wait -PassThru
if ($p.ExitCode -ne 0) { Get-Content $uninstallLog -Tail 60; Fail "uninstall failed with exit code $($p.ExitCode)" }
if (Test-Path $exe.FullName) { Fail 'dotify-studio.exe is still there after uninstalling' }

Write-Host 'PASS: installed, started and uninstalled'
