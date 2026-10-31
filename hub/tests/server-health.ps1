$ErrorActionPreference='Stop'
$hubRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $hubRoot 'server-health.ps1')
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('hub-health-'+[Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testDir | Out-Null
$fixture=Join-Path $testDir 'server.cjs'
$listener=New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback,0)
$listener.Start();$port=$listener.LocalEndpoint.Port;$listener.Stop()
$serverRoot='C:\test\Tools Hub';$root=$serverRoot;$serverService='tools-hub-picker'
@'
const http = require('node:http');
let ready = false;
let identity = false;
http.createServer((req, res) => {
  if (req.url === '/api/root') return res.end(JSON.stringify({root:'C:\\test\\Tools Hub', ...(identity ? {service:'tools-hub-picker',protocol:1} : {})}));
  if (req.url === '/enable') { ready = true; return res.end('ok'); }
  if (req.url === '/identify') { identity = true; return res.end('ok'); }
  if (ready && req.url === '/') return res.end('<!doctype html><title>Tools Hub</title>');
  res.writeHead(404); res.end();
}).listen(Number(process.argv[2]), '127.0.0.1');
'@ | Set-Content -LiteralPath $fixture -Encoding UTF8
$child=$null
try {
    $child=Start-Process node -WindowStyle Hidden -PassThru -ArgumentList @(('"'+$fixture+'"'),$port)
    for($i=0;$i -lt 30;$i++){try{[void](Get-HubHttpText "http://127.0.0.1:$port/api/root");break}catch{Start-Sleep -Milliseconds 100}}
    if(Test-HubServer){throw 'Legacy API-only server was accepted.'}
    [void](Get-HubHttpText "http://127.0.0.1:$port/enable")
    if(Test-HubServer){throw 'Unidentified server with HTML was accepted.'}
    [void](Get-HubHttpText "http://127.0.0.1:$port/identify")
    if(-not (Test-HubServer)){throw 'Ready menu server was rejected.'}
    $addressFile=Join-Path $testDir 'address.json'
    @{root=$serverRoot;service=$serverService;port=$port} | ConvertTo-Json | Set-Content $addressFile
    if((Select-HubServerPort $port $addressFile) -ne $port){throw 'Healthy saved server was not reused.'}
    $serverRoot='C:\different-install'
    if(Test-HubServer){throw 'Server belonging to another install was accepted.'}
    $newPort=Select-HubServerPort $port $addressFile
    if($newPort -eq $port -or -not (Test-HubPortFree $newPort)){throw 'Occupied foreign port was not skipped.'}
    'PASS: legacy/unknown/foreign servers rejected, healthy saved server reused, occupied port skipped.'
} finally {
    if($child){if(-not $child.HasExited){$child.Kill();$child.WaitForExit()};$child.Dispose()}
    Remove-Item -LiteralPath $fixture -Force
    if(Test-Path $addressFile){Remove-Item -LiteralPath $addressFile -Force}
    Remove-Item -LiteralPath $testDir -Force
}
