param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','logs','url','install','build','rebuild','update','autostart','unautostart')]
    [string]$Action='start',
    [string]$RuntimeDirectory=$env:DSH_MANAGER_HOME,
    [switch]$DirectNetwork
)
$ErrorActionPreference='Stop'
$ProjectDirectory=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (!$RuntimeDirectory) { $RuntimeDirectory=Join-Path $ProjectDirectory '.dsh-manager' }
$RuntimeDirectory=[IO.Path]::GetFullPath($RuntimeDirectory)
[void](New-Item -ItemType Directory -Path $RuntimeDirectory -Force)
$PidFile=Join-Path $RuntimeDirectory 'service.pid'
$LogFile=Join-Path $RuntimeDirectory 'service.log'
$Entry=Join-Path $ProjectDirectory 'apps\cli\lib\bin.js'
$Node=(Get-Command node -ErrorAction Stop).Source

function Invoke-Pnpm([string[]]$Arguments) {
    $command=(Get-Command pnpm.cmd -ErrorAction Stop).Source
    & $command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "pnpm failed ($LASTEXITCODE): $Arguments" }
}
function Get-ServiceProcess {
    # Match the exact checkout before stopping a PID that Windows may reuse.
    @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains($Entry)
    })
}
function Stop-ServiceProcess {
    foreach($serviceProcess in @(Get-ServiceProcess)) {
        Stop-Process -Id $serviceProcess.ProcessId -ErrorAction Stop
    }
    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}
function Start-ServiceProcess {
    if (@(Get-ServiceProcess).Count) { Write-Host 'DSH is already running.'; return }
    if (!(Test-Path -LiteralPath $Entry)) { throw 'Build output missing. Run dsh.bat rebuild first.' }
    $saved=@{}
    $changes=@{}
    if (!$env:DSH_HOME) { $changes.DSH_HOME=Join-Path ([Environment]::GetFolderPath('UserProfile')) '.dsh' }
    if($DirectNetwork) {
        foreach($name in @('HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','NODE_USE_ENV_PROXY')) { $changes[$name]=$null }
        $changes.NO_PROXY='*'
    }
    try {
        foreach($name in $changes.Keys) {
            $saved[$name]=[Environment]::GetEnvironmentVariable($name,'Process')
            [Environment]::SetEnvironmentVariable($name,$changes[$name],'Process')
        }
        $service=Start-Process -FilePath $Node -ArgumentList @(('"'+$Entry+'"'),'web','--no-open') -WorkingDirectory $ProjectDirectory -WindowStyle Hidden -RedirectStandardOutput $LogFile -RedirectStandardError "$LogFile.err" -PassThru
    } finally {
        foreach($name in $saved.Keys) { [Environment]::SetEnvironmentVariable($name,$saved[$name],'Process') }
    }
    Set-Content -LiteralPath $PidFile -Value $service.Id -Encoding ascii
    $deadline=(Get-Date).AddSeconds(30)
    do {
        Start-Sleep -Seconds 1
        $service.Refresh()
        if($service.HasExited) { throw "DSH exited. See $LogFile.err" }
        $startup=Select-String -LiteralPath $LogFile -Pattern 'https?://\S+' -ErrorAction SilentlyContinue | Select-Object -Last 1
        if($startup) { Write-Host $startup.Line; return }
    } while((Get-Date) -lt $deadline)
    throw "DSH has not reported readiness. Inspect $LogFile and $LogFile.err"
}
function Install-Dependencies {
    $savedPurge=$env:npm_config_confirm_modules_purge
    try {
        $env:npm_config_confirm_modules_purge='false'
        Invoke-Pnpm @('install','--frozen-lockfile','--store-dir',(Join-Path $RuntimeDirectory 'pnpm-store'))
    } finally { $env:npm_config_confirm_modules_purge=$savedPurge }
}
Push-Location $ProjectDirectory
try {
    switch($Action) {
        start { Start-ServiceProcess }
        stop { Stop-ServiceProcess }
        restart { Stop-ServiceProcess; Start-ServiceProcess }
        install { Install-Dependencies }
        build { Install-Dependencies; Invoke-Pnpm @('run','build') }
        rebuild { Stop-ServiceProcess; Install-Dependencies; Invoke-Pnpm @('run','clean'); Invoke-Pnpm @('run','build'); Start-ServiceProcess }
        update {
            & git pull --ff-only
            if($LASTEXITCODE -ne 0) { throw 'git pull failed' }
            Install-Dependencies
            Invoke-Pnpm @('run','build')
            Stop-ServiceProcess
            Start-ServiceProcess
        }
        status { $processes=@(Get-ServiceProcess); if($processes.Count){$processes | Select-Object ProcessId,CreationDate}else{Write-Host 'DSH is stopped.'} }
        logs { foreach($file in @($LogFile,"$LogFile.err")){if(Test-Path $file){Get-Content -LiteralPath $file -Tail 40}} }
        url { if(Test-Path $LogFile){Select-String -LiteralPath $LogFile -Pattern 'https?://\S+' | Select-Object -Last 1 | ForEach-Object {$_.Line}} }
        autostart {
            $shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web.lnk'
            $shortcut=(New-Object -ComObject WScript.Shell).CreateShortcut($shortcutPath)
            $shortcut.TargetPath=Join-Path $PSHOME 'powershell.exe'
            $shortcut.Arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$PSCommandPath+'" start -RuntimeDirectory "'+$RuntimeDirectory+'"'
            if($DirectNetwork){$shortcut.Arguments+=' -DirectNetwork'}
            $shortcut.WorkingDirectory=$ProjectDirectory
            $shortcut.WindowStyle=7
            $shortcut.Save()
            Write-Host "Installed login startup: $shortcutPath"
        }
        unautostart { $shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web.lnk'; if(Test-Path $shortcutPath){Remove-Item -LiteralPath $shortcutPath} }
    }
} finally { Pop-Location }
