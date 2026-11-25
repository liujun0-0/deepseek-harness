param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','logs','url','install','build','rebuild','update','autostart','unautostart')]
    [string]$Action='start',
    [string]$RuntimeDirectory=$env:DSH_MANAGER_HOME,
    [switch]$DirectNetwork,
    [switch]$Menu,
    [switch]$Supervised
)
$ErrorActionPreference='Stop'
if ($Menu) {
    $menuActions=@('start','stop','restart','status','logs','url','install','build','rebuild','update','autostart','unautostart')
    $menuLabels=@('启动 DSH','停止 DSH','重启 DSH','查看运行状态','查看最近日志','查看访问地址','安装项目依赖','构建项目（不重启）','重新构建并启动','拉取代码、构建并重启','设置登录后自动启动','取消自动启动')
    while ($true) {
        Write-Host "`n========== DSH 管理菜单 =========="
        for ($i=0; $i -lt $menuActions.Count; $i++) {
            Write-Host ('{0,3}. {1}' -f ($i+1),$menuLabels[$i])
        }
        Write-Host '  0. 退出'
        $selection=Read-Host '请输入编号（0-12）'
        if ($null -eq $selection -or $selection.Trim() -eq '0') { return }
        $number=0
        if (![int]::TryParse($selection.Trim(),[ref]$number) -or $number -lt 1 -or $number -gt $menuActions.Count) {
            Write-Host '无效选项，请输入 0 到 12 之间的编号。' -ForegroundColor Yellow
            continue
        }
        try {
            & $PSCommandPath -Action $menuActions[$number-1] -RuntimeDirectory $RuntimeDirectory -DirectNetwork:$DirectNetwork | Out-Host
            Write-Host '操作完成。' -ForegroundColor Green
        } catch {
            Write-Host ('操作失败：'+$_.Exception.Message) -ForegroundColor Red
        }
        Read-Host '按回车返回菜单' | Out-Null
    }
}
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
    $commandLog=Join-Path $RuntimeDirectory 'build.log'
    & $Node (Join-Path $PSScriptRoot 'run-command.mjs') $commandLog $command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "pnpm failed ($LASTEXITCODE): $Arguments" }
}
function Get-ServiceProcess {
    # Match the exact checkout before stopping a PID that Windows may reuse.
    @(Get-CimInstance Win32_Process -Filter "Name='node.exe'" | Where-Object {
        $_.CommandLine -and $_.CommandLine.Contains($Entry)
    })
}
function Stop-ServiceProcess {
    Set-Content -LiteralPath (Join-Path $RuntimeDirectory 'service.paused') -Value 'paused'
    foreach($serviceProcess in @(Get-ServiceProcess)) {
        Stop-Process -Id $serviceProcess.ProcessId -ErrorAction Stop
    }
    Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
}
function Start-ServiceProcess {
    $pauseFile=Join-Path $RuntimeDirectory 'service.paused'
    if ($Supervised -and (Test-Path -LiteralPath $pauseFile)) { return }
    if (!$Supervised) { Remove-Item -LiteralPath $pauseFile -ErrorAction SilentlyContinue }
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
    Write-Host '[依赖] 安装锁定依赖，详细日志：' (Join-Path $RuntimeDirectory 'build.log')
    $installArgs=@('install','--frozen-lockfile','--engine-strict','--yes','--reporter=append-only')
    # Keep the existing dependency store instead of forcing a different store on every checkout.
    $modulesFile=Join-Path $ProjectDirectory 'node_modules\.modules.yaml'
    if (Test-Path -LiteralPath $modulesFile) {
        $metadata=Get-Content -LiteralPath $modulesFile -Raw
        $store=$null
        if ($metadata.TrimStart().StartsWith('{')) {
            $store=($metadata | ConvertFrom-Json).storeDir
        } elseif ($metadata -match '(?m)^storeDir:\s*(.+)$') {
            $store=$Matches[1].Trim().Trim([char]39,[char]34)
        }
        if ($store) {
            if ((Split-Path $store -Leaf) -match '^v[0-9]+$') { $store=Split-Path $store -Parent }
            Write-Host ('[依赖] 复用现有缓存：'+$store)
            $installArgs+=@('--store-dir',$store)
        }
    }
    Invoke-Pnpm $installArgs
}
$lockName='Local\DSH-manager-'+[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($ProjectDirectory)).Replace('/','_')
$managerLock=New-Object Threading.Mutex($false,$lockName)
$ownsLock=$false
Push-Location $ProjectDirectory
try {
    try { $ownsLock=$managerLock.WaitOne(60000) } catch [Threading.AbandonedMutexException] { $ownsLock=$true }
    if (!$ownsLock) { throw 'Another DSH manager operation is still running.' }
    switch($Action) {
        start { Start-ServiceProcess }
        stop { Stop-ServiceProcess }
        restart { Stop-ServiceProcess; Start-ServiceProcess }
        install { Install-Dependencies }
        build { Install-Dependencies; Invoke-Pnpm @('run','build') }
        rebuild {
            Write-Host '[1/5] 停止 DSH，暂停守护恢复...'
            Stop-ServiceProcess
            Write-Host '[2/5] 安装依赖...'
            Install-Dependencies
            Write-Host '[3/5] 清理构建产物...'
            Invoke-Pnpm @('run','clean')
            Write-Host '[4/5] 构建项目并检查...'
            Invoke-Pnpm @('run','build')
            Write-Host '[5/5] 启动 DSH...'
            Start-ServiceProcess
            Write-Host 'Rebuild 完成。'
        }
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
            $shortcut.TargetPath=$Node
            $watchdog=Join-Path $PSScriptRoot 'watchdog.mjs'
            $shortcut.Arguments='"'+$watchdog+'" "'+$RuntimeDirectory+'"'
            if($DirectNetwork){$shortcut.Arguments+=' --direct-network'}
            $shortcut.WorkingDirectory=$ProjectDirectory
            $shortcut.WindowStyle=7
            $shortcut.Save()
            Remove-Item -LiteralPath (Join-Path $RuntimeDirectory 'watchdog.disabled') -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath (Join-Path $RuntimeDirectory 'service.paused') -ErrorAction SilentlyContinue
            Start-Process -FilePath $Node -ArgumentList $shortcut.Arguments -WorkingDirectory $ProjectDirectory -WindowStyle Hidden | Out-Null
            Write-Host "Installed login startup: $shortcutPath"
        }
        unautostart { Set-Content -LiteralPath (Join-Path $RuntimeDirectory 'watchdog.disabled') -Value 'disabled'; $shortcutPath=Join-Path ([Environment]::GetFolderPath('Startup')) 'DSH Web.lnk'; if(Test-Path $shortcutPath){Remove-Item -LiteralPath $shortcutPath} }
    }
} finally { if($ownsLock){$managerLock.ReleaseMutex()}; $managerLock.Dispose(); Pop-Location }
