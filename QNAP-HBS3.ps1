#requires -Version 5.1
<# PRTG EXE/Script Advanced. See README.md before production use. #>
param(
    [string]$NasUrl,
    [string]$JobUuid,
    [string]$ConfigFile = "$PSScriptRoot\HBS3-schema.json",
    [string]$Username,
    [string]$Password,
    [string]$CredentialSource = 'ScriptEnvironment',
    [int]$TimeoutSec = 20,
    [switch]$AllowHttp,
    [string]$FixtureFile
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$WarningPreference = 'SilentlyContinue'
$VerbosePreference = 'SilentlyContinue'
$DebugPreference = 'SilentlyContinue'
$stage = 'Configuration'

function Read-Field($Object, $Path) {
    # Path is an array: a property containing a dot remains a literal key.
    foreach ($key in @($Path)) {
        if ($null -eq $Object) { throw 'Missing field' }
        $property = $Object.PSObject.Properties[[string]$key]
        if ($null -eq $property) { throw 'Missing field' }
        $Object = $property.Value
    }
    return ,$Object
}
function Read-Number($Object, $Path) {
    $raw = Read-Field $Object $Path
    $value = 0.0
    if ($null -eq $raw -or $raw -is [bool] -or
        -not [double]::TryParse([string]$raw, [Globalization.NumberStyles]::Float,
            [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or
        [double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -lt 0) {
        throw 'Invalid numeric field'
    }
    return $value
}
function Xml-Escape([string]$Value) {
    return [Security.SecurityElement]::Escape($Value)
}
function Channel([string]$Name, [double]$Value, [string]$Unit, [string]$Extra = '') {
    $number = $Value.ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    $float = if ($Extra -match '<valuelookup>') { 0 } else { 1 }
    return "<result><channel>$(Xml-Escape $Name)</channel><value>$number</value><unit>$Unit</unit><float>$float</float><mode>Absolute</mode>$Extra</result>"
}
try {
    $stage = 'Configuration: TimeoutSec must be between 1 and 120'
    if ($TimeoutSec -lt 1 -or $TimeoutSec -gt 120) { throw 'Invalid timeout' }
    $stage = 'Configuration: JobUuid must be a valid UUID'
    $uuid = [guid]::Empty
    if (-not [guid]::TryParse($JobUuid, [ref]$uuid)) { throw 'Invalid UUID' }
    $stage = 'Configuration: HBS3-schema.json is missing or inaccessible; place it next to the script on the probe'
    if (-not (Test-Path -LiteralPath $ConfigFile -PathType Leaf)) { throw 'Missing config file' }
    $configText = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8
    $stage = 'Configuration: HBS3-schema.json contains invalid JSON'
    $config = $configText | ConvertFrom-Json
    $stage = 'Configuration: schemaVersion must be 1'
    if ($config.schemaVersion -ne 1) { throw 'Invalid schema version' }
    # Refuse unverified guesses during real monitoring. Fixtures remain available for testing.
    $stage = 'Configuration: verifiedAgainstNas must be true; use the supplied schema file'
    if (-not $FixtureFile -and $config.verifiedAgainstNas -ne $true) { throw 'Schema not verified' }
    if ($FixtureFile) {
        $stage = 'Fixture JSON'
        $payload = Get-Content -LiteralPath $FixtureFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $stage = 'Configuration: NasUrl must be an HTTPS root URL; HTTP requires AllowHttp'
        $uri = [uri]$NasUrl
        if (-not $uri.IsAbsoluteUri -or ($uri.Scheme -ne 'https' -and -not ($AllowHttp -and $uri.Scheme -eq 'http')) -or $uri.UserInfo -or
            $uri.AbsolutePath -ne '/' -or $uri.Query -or $uri.Fragment) { throw 'HTTPS root URL required' }
        $root = $uri.GetLeftPart([UriPartial]::Authority)
        $stage = 'Configuration: CredentialSource must be ScriptEnvironment, WindowsEnvironment or Parameters'
        switch ($CredentialSource) {
            'ScriptEnvironment' {
                $Username = $env:prtg_scriptplaceholder1
                $Password = $env:prtg_scriptplaceholder2
            }
            'WindowsEnvironment' {
                $Username = $env:prtg_windowsuser
                $Password = $env:prtg_windowspassword
            }
            'Parameters' { }
            default { throw 'Invalid credential source' }
        }
        $stage = switch ($CredentialSource) {
            'ScriptEnvironment' { 'Configuration: missing credentials; set script placeholders 1 and 2 and enable Environment values' }
            'WindowsEnvironment' { 'Configuration: missing Windows credentials; set device credentials and enable Environment values' }
            'Parameters' { 'Configuration: Username or Password is missing; check placeholders in Parameters' }
        }
        if ([string]::IsNullOrEmpty($Username) -or [string]::IsNullOrEmpty($Password)) { throw 'Missing credentials' }
        $stage = 'Configuration: PRTG did not resolve a placeholder; check parent device credentials'
        if ($Username -match '^%(scriptplaceholder[1-5]|windowsuser)$' -or $Password -match '^%(scriptplaceholder[1-5]|windowspassword)$') { throw 'Unresolved placeholder' }
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
        $stage = 'QTS authentication'
        $body = @{
            user = $Username
            pwd = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Password))
            remme = '0'
        }
        try {
            $login = Invoke-WebRequest -Uri "$root/cgi-bin/authLogin.cgi" -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -WebSession $session -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 0
        } catch {
            $stage = 'QTS authentication: HTTP connection failed; check protocol, port and access from the probe'
            if ($_.Exception -is [Net.WebException]) {
                $stage = 'QTS authentication: transport ' + [string]$_.Exception.Status
                if ($null -ne $_.Exception.Response -and $_.Exception.Response -is [Net.HttpWebResponse]) {
                    $stage += ' ; HTTP ' + [int]$_.Exception.Response.StatusCode
                }
            }
            throw
        }
        $stage = 'QTS authentication: invalid XML response; check QTS port and redirects'
        # Disable DTD/external entity resolution on untrusted XML.
        $settings = New-Object Xml.XmlReaderSettings
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new([string]$login.Content), $settings)
        try {
            $doc = New-Object Xml.XmlDocument
            $doc.XmlResolver = $null
            $doc.Load($reader)
        } finally { $reader.Dispose() }
        $passed = $doc.SelectSingleNode('//authPassed')
        $sidNode = $doc.SelectSingleNode('//authSid')
        $twoStep = $doc.SelectSingleNode('//need_2sv')
        $stage = 'QTS authentication: authPassed is missing; check the QTS endpoint'
        if ($null -eq $passed) { throw 'Missing authPassed' }
        $stage = 'QTS authentication: authPassed is not 1; credentials rejected or account blocked'
        if ($passed.InnerText -ne '1') { throw 'Authentication rejected' }
        $stage = 'QTS authentication: two-step verification required'
        if ($null -ne $twoStep -and $twoStep.InnerText -eq '1') { throw 'Second factor required' }
        $stage = 'QTS authentication: authSid is missing or empty'
        if ($null -eq $sidNode -or [string]::IsNullOrWhiteSpace($sidNode.InnerText)) { throw 'Missing SID' }
        $stage = 'QTS authentication: session cookie creation failed'
        # Cookie names must match the original working script / observed QTS session.
        foreach ($definition in @($config.cookies)) {
            $cookieValue = switch ($definition.source) {
                'sid' { $sidNode.InnerText }
                'username' { $Username }
                'literal' { [string]$definition.value }
                default { throw 'Invalid cookie source' }
            }
            $cookie = New-Object Net.Cookie([string]$definition.name, [string]$cookieValue, '/', $uri.Host)
            $cookie.Secure = ($uri.Scheme -eq 'https')
            $session.Cookies.Add($cookie)
        }
        $stage = 'HBS3 request'
        $response = Invoke-WebRequest -Uri "$root/cc3/v1/users/system/jobs" -Method Get -WebSession $session -UseBasicParsing -TimeoutSec $TimeoutSec -MaximumRedirection 0 -Headers @{'X-QNAP-SID'=$sidNode.InnerText;'X-Requested-With'='XMLHttpRequest';Accept='application/json'}
        $payload = $response.Content | ConvertFrom-Json
    }
    $stage = 'HBS3 schema and UUID selection'
    if ($null -eq $payload -or $null -ne $payload.PSObject.Properties['error'] -or $payload.has_more -eq $true) { throw 'HBS error or incomplete response' }
    $collection = if (@($config.jobsPath).Count -eq 0) { $payload } else { Read-Field $payload $config.jobsPath }
    $jobs = @($collection)
    $matches = @($jobs | Where-Object { [string](Read-Field $_ $config.uuidPath) -eq $uuid.ToString() })
    if ($matches.Count -ne 1) { throw 'UUID absent or duplicated' }
    $job = $matches[0]
    $stage = 'HBS3 status'
    $statistics = $job.PSObject.Properties['statistics']
    $hasStatistics = ($null -ne $statistics -and $null -ne $statistics.Value)
    if (-not $hasStatistics) {
        $state = 'NeverRun'
    } else {
        $rawState = [string](Read-Field $job $config.statePath)
        $mapped = $config.stateMap.PSObject.Properties[$rawState]
        if ($null -eq $mapped -or [string]$mapped.Value -notin @('OK','Running','Warning','Error','Stopped','Paused','Disabled','NeverRun')) {
            throw 'Unknown state'
        }
        $state = [string]$mapped.Value
    }
    if ($job.enable -eq $false) { $state = 'Disabled' }
    $health = switch ($state) {
        'OK' { 0 }; 'Running' { 4 }; 'Warning' { 1 }; 'Error' { 2 }
        'Paused' { 1 }; 'Disabled' { 1 }; 'NeverRun' { 3 }
        'Stopped' { 1 }
    }
    $stage = 'HBS3 counters'
    $available = 1
    try {
        $remaining = Read-Number $job $config.remainingFilesPath
        $bytes = Read-Number $job $config.remainingBytesPath
        $percentage = (Read-Number $job $config.progressPath) * [double]$config.progressMultiplier
        if ($remaining % 1 -ne 0 -or $bytes % 1 -ne 0 -or $percentage -gt 100 -or
            [double]$config.progressMultiplier -notin @(1,100)) { throw 'Inconsistent counters' }
    } catch {
        if ($state -in @('Running','Warning')) { throw }
        # Stable channels: -1 means unavailable, never a fabricated zero.
        $available = 0
        $remaining = -1; $bytes = -1; $percentage = -1
    }
    if ($hasStatistics -and $null -ne $statistics.Value.PSObject.Properties['error_count']) {
        if ((Read-Number $job @('statistics','error_count')) -gt 0 -and $health -in @(0,3,4)) { $health = 1 }
    }
    $xml = '<prtg>'
    $xml += Channel 'Job health' $health 'Custom' '<valuelookup>custom.qnap.hbs3.health</valuelookup><limitmode>0</limitmode>'
    $xml += Channel 'Job running' ([int]($state -eq 'Running')) 'Custom' '<valuelookup>custom.qnap.hbs3.running</valuelookup><limitmode>0</limitmode>'
    $xml += Channel 'Files remaining' $remaining 'Count'
    $xml += Channel 'Remaining size' $bytes 'BytesDisk' '<volumesize>GigaByte</volumesize>'
    $xml += Channel 'Progress' $percentage 'Percent'
    $xml += Channel 'Counters available' $available 'Custom' '<showchart>0</showchart><showtable>0</showtable>'
    # Message deliberately contains only script-owned text, no API/credential values.
    $xml += "<text>HBS3 - $state</text></prtg>"
    $sensorOutput = $xml
} catch {
    # Never echo exception bodies, URLs, credentials, cookies, raw JSON or job names.
    $sensorOutput = "<prtg><error>1</error><text>$(Xml-Escape ('Error: ' + $stage + '. See the troubleshooting guide.'))</text></prtg>"
} finally {
    $Password = $null
    $body = $null
    $session = $null
    $sidNode = $null
    $login = $null
    $doc = $null
}
Write-Output $sensorOutput
# XML determines PRTG status, including <error>1. Do not mix exit codes with channels.

