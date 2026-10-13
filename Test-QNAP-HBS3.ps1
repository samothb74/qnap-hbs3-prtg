#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$sensor = Join-Path $PSScriptRoot 'QNAP-HBS3.ps1'
$config = Join-Path $PSScriptRoot 'HBS3-schema.json'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('hbs3-test-' + [guid]::NewGuid() + '.json')
$id = '11111111-1111-1111-1111-111111111111'
function Check([bool]$Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Run-Fixture($Payload) {
    $Payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $temporary -Encoding UTF8
    $out = @(& $sensor -JobUuid $id -ConfigFile $config -FixtureFile $temporary)
    Check ($out.Count -eq 1) 'Output must be one XML document'
    return [xml]$out[0]
}
try {
    $missingConfig = [xml](& $sensor -JobUuid $id -ConfigFile ($temporary + '.missing'))
    Check ($missingConfig.prtg.text -like '*missing or inaccessible*') 'Missing configuration must have a precise safe message'
    $invalidUuid = [xml](& $sensor -JobUuid 'invalid')
    Check ($invalidUuid.prtg.text -like '*valid UUID*') 'Invalid UUID must have a precise safe message'
    foreach ($case in @(@('Running',0),@('Stopped',1),@('Failed',2))) {
        $job = @{_id=$id;enable=$true;statistics=@{status=$case[0];local_files_remaining=7;local_bytes_remaining=1073741824;progress=30}}
        $xml = Run-Fixture @{jobs=@($job)}
        Check ($xml.prtg.result.Count -eq 6) 'Expected six channels'
        Check ([double]$xml.prtg.result[0].value -eq $case[1]) 'Wrong health'
        Check ([double]$xml.prtg.result[2].value -eq 7) 'Wrong remaining files'
        Check ([double]$xml.prtg.result[3].value -eq 1073741824) 'Wrong remaining bytes'
        Check ([double]$xml.prtg.result[4].value -eq 30) 'Wrong percentage'
    }
    $job.statistics.status = 'unknown'
    Check ((Run-Fixture @{jobs=@($job)}).prtg.error -eq '1') 'Unknown state must fail'
    $job.statistics.status = 'running'; $job.statistics.progress = 101
    Check ((Run-Fixture @{jobs=@($job)}).prtg.error -eq '1') 'Inconsistent counters must fail'
    $job.statistics.progress = 30
    Check ((Run-Fixture @{jobs=@($job,$job)}).prtg.error -eq '1') 'Duplicate UUID must fail'
    Check ((Run-Fixture @{jobs=@()}).prtg.error -eq '1') 'Missing UUID must fail'
    Check ((Run-Fixture @{error='secret sentinel'}).prtg.error -eq '1') 'API error must fail'
    $job.statistics.Remove('local_files_remaining')
    Check ((Run-Fixture @{jobs=@($job)}).prtg.error -eq '1') 'Missing counter must fail'
    $job.statistics = @{status='running';local_files_remaining=0;local_bytes_remaining=0;progress=0}
    $xml = Run-Fixture @{jobs=@($job)}
    Check ([double]$xml.prtg.result[4].value -eq 0) 'Zero remaining must not imply success'
    $job.statistics = @{status='Failed';error_count=0}
    $xml = Run-Fixture @{jobs=@($job)}
    Check ([double]$xml.prtg.result[0].value -eq 2) 'Failed must remain Down without counters'
    Check ([double]$xml.prtg.result[2].value -eq -1) 'Missing counters must be unavailable'
    $job.Remove('statistics')
    $xml = Run-Fixture @{jobs=@($job)}
    Check ([double]$xml.prtg.result[0].value -eq 1) 'Missing history must warn'
    $job.enable = $false
    $xml = Run-Fixture @{jobs=@($job)}
    Check ($xml.prtg.text -like '*Disabled*') 'Disabled job must warn'
    Check ((Run-Fixture @{jobs=@($job);has_more=$true}).prtg.error -eq '1') 'Pagination must not be silently ignored'
    # Mock HTTP transport: verify POST, cookies and headers without any network call.
    $mockState = @{calls=0}
    function Invoke-WebRequest {
        param($Uri,$Method,$Body,$ContentType,$WebSession,[switch]$UseBasicParsing,$TimeoutSec,$MaximumRedirection,$Headers)
        $mockState.calls++
        Check ($MaximumRedirection -eq 0) 'Redirects must be disabled'
        if ($Method -eq 'Post') {
            Check ($Uri -eq 'https://nas.example/cgi-bin/authLogin.cgi') 'Wrong login endpoint'
            Check ($Body.user -eq 'monitor') 'Wrong username'
            Check ($Body.pwd -eq [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('test-password'))) 'Wrong password encoding'
            if ($mockState.ContainsKey('loginContent')) { return @{Content=$mockState.loginContent} }
            return @{Content='<QDocRoot><authPassed>1</authPassed><authSid>test-sid</authSid></QDocRoot>'}
        }
        Check ($Uri -eq 'https://nas.example/cc3/v1/users/system/jobs') 'Wrong HBS endpoint'
        Check ($Headers['X-QNAP-SID'] -eq 'test-sid') 'Missing SID header'
        Check ($Headers['X-Requested-With'] -eq 'XMLHttpRequest') 'Missing XMLHttpRequest header'
        $cookies = $WebSession.Cookies.GetCookies([uri]'https://nas.example/')
        Check ($cookies['NAS_SID'].Value -eq 'test-sid') 'Missing SID cookie'
        Check ($cookies['NAS_USER'].Value -eq 'monitor') 'Missing username cookie'
        Check ($cookies['NAS_PW_STATUS'].Value -eq '0') 'Missing PW status cookie'
        Check ($cookies['home'].Value -eq '1') 'Missing home cookie'
        return @{Content=(Get-Content -LiteralPath (Join-Path $PSScriptRoot 'HBS3-example.json') -Raw)}
    }
    $out = @(& $sensor -NasUrl 'https://nas.example' -JobUuid $id -CredentialSource Parameters -Username monitor -Password test-password)
    $xml = [xml]$out[0]
    Check ($mockState.calls -eq 2) 'Expected two HTTP calls'
    Check ($xml.prtg.result.Count -eq 6) 'Mock authentication must produce channels'
    Check ([double]$xml.prtg.result[2].value -eq 7) 'Synthetic example remaining files mismatch'
    Check ([double]$xml.prtg.result[3].value -eq 1073741824) 'Synthetic example bytes mismatch'
    Check ([double]$xml.prtg.result[4].value -eq 30) 'Synthetic example progress mismatch'
    Check ($xml.prtg.text -eq 'HBS3 - Running') 'Last Message must contain only HBS3 and the state'
    Check ($xml.prtg.result[0].valuelookup -eq 'custom.qnap.hbs3.health') 'Health lookup missing'
    Check ($xml.prtg.result[1].float -eq '0') 'Running lookup must use integers'
    Check ($xml.prtg.result[5].showtable -eq '0') 'Technical counter must be hidden'
    Check ($out[0] -notmatch '<customunit>\s*</customunit>') 'Optional custom units must not be empty elements'
    $healthLookup = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom.qnap.hbs3.health.ovl') -Raw)
    Check ($healthLookup.ValueLookup.Lookups.SingleInt[0].state -eq 'Ok') 'Health zero must be green'
    $runningLookup = [xml](Get-Content -LiteralPath (Join-Path $PSScriptRoot 'custom.qnap.hbs3.running.ovl') -Raw)
    Check ($runningLookup.ValueLookup.Lookups.SingleInt[0].state -eq 'None') 'Inactive must be neutral'
    Check ($out[0] -notmatch 'test-password|test-sid|monitor') 'Secret leaked in XML'
    $mockState.loginContent = '<QDocRoot><authPassed>0</authPassed></QDocRoot>'
    $xml = [xml](& $sensor -NasUrl 'https://nas.example' -JobUuid $id -CredentialSource Parameters -Username monitor -Password test-password)
    Check ($xml.prtg.text -like '*credentials rejected*') 'QTS refusal must be distinguished'
    $mockState.loginContent = '<QDocRoot><authPassed>1</authPassed><authSid>test-sid</authSid><need_2sv>1</need_2sv></QDocRoot>'
    $xml = [xml](& $sensor -NasUrl 'https://nas.example' -JobUuid $id -CredentialSource Parameters -Username monitor -Password test-password)
    Check ($xml.prtg.text -like '*two-step verification*') 'Second factor must be distinguished'
    $mockState.loginContent = 'not XML'
    $xml = [xml](& $sensor -NasUrl 'https://nas.example' -JobUuid $id -CredentialSource Parameters -Username monitor -Password test-password)
    Check ($xml.prtg.text -like '*invalid XML*') 'Invalid QTS response must be distinguished'
    $englishXml = [xml](& $sensor -JobUuid $id -FixtureFile (Join-Path $PSScriptRoot 'HBS3-example.json'))
    Check ($englishXml.prtg.result[0].channel -eq 'Job health') 'English channel name missing'
    Check ($englishXml.prtg.result[4].channel -eq 'Progress') 'English progress name missing'
    Write-Output 'PASS: offline cases; six channels and safe error XML. Live QTS/HBS/PRTG not tested.'
} finally { Remove-Item -LiteralPath $temporary -ErrorAction SilentlyContinue }

