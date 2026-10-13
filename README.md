# QNAP HBS3 monitoring for PRTG

A Windows PowerShell 5.1 script for PRTG EXE/Script Advanced sensors. It reads one HBS3 job by UUID and returns six XML channels, with English text and status lookups. No external PowerShell modules are required.

## Files

- `QNAP-HBS3.ps1`: sensor script.
- `HBS3-schema.json`: configurable response paths, cookie definitions and state mappings.
- `custom.qnap.hbs3.health.ovl`, `custom.qnap.hbs3.running.ovl`: PRTG status lookups.
- `Test-QNAP-HBS3.ps1`: offline tests, including simulated HTTP authentication.
- `HBS3-example.json`: entirely synthetic job data, not a real NAS response.
- [DISPLAY.md](DISPLAY.md): channel presentation and migration guidance.
- [SECURITY.md](SECURITY.md): credential handling and limitations.

## Install

1. On the Windows probe server, place the PS1 and schema JSON in the PRTG installation folder's `Custom Sensors\EXEXML` directory.
2. Place the two `.ovl` files in the core server's `lookups\custom` directory. For a Local Probe, this is the same server. Reload lookups under Setup → System Administration → Administrative Tools. In a cluster, install on the relevant nodes.
3. On the parent device, configure Credentials for Script Sensors: Placeholder 1 = QNAP username; Placeholder 2 = QNAP password. Interrupt inheritance if needed.
4. Add an EXE/Script Advanced sensor and select `QNAP-HBS3.ps1`. Create one sensor per job.

| Setting | Value |
|---|---|
| Environment | Default |
| Security Context | Use security context of PRTG probe service |
| Sensor timeout | 60 seconds |
| Initial interval | 5 minutes |
| Mutex Name | `QNAP-HBS3-nas-example` (same value for sensors contacting the same NAS) |

Example parameters — replace the reserved example hostname and synthetic UUID:

```text
-NasUrl "https://nas.example:443" -JobUuid "11111111-1111-1111-1111-111111111111" -CredentialSource Parameters -Username "%scriptplaceholder1" -Password "%scriptplaceholder2" -TimeoutSec 20
```

Use the actual QTS HTTPS port and a certificate trusted by the probe. To explicitly allow an HTTP installation, use an `http://` URL and add `-AllowHttp`; HTTP exposes credentials and session cookies in transit. Do not enter literal credentials in Parameters.

If using Windows credential storage instead, the script accepts `%windowsuser` and `%windowspassword` with CredentialSource Parameters. Keep the probe-service security context; a NAS account is not a Windows execution account. Environment modes ScriptEnvironment and WindowsEnvironment are also supported, but depend on PRTG exposing the appropriate `prtg_` variables and increase credential exposure in the process environment.

Downloaded scripts may be blocked by Windows. After reviewing this file, an administrator can unblock only the installed script:

```powershell
Unblock-File -LiteralPath 'C:\Program Files (x86)\PRTG Network Monitor\Custom Sensors\EXEXML\QNAP-HBS3.ps1'
```

Under AllSigned, a trusted signature is required even after unblocking. Inspect `Get-ExecutionPolicy -List` rather than globally disabling execution controls.

## Channels and state handling

| Channel | Meaning |
|---|---|
| Job health | 0 = OK, 1 = check required, 2 = failed, 3 = never run, 4 = running |
| Job running | 1 = running, 0 = inactive |
| Files remaining | `statistics.local_files_remaining` |
| Remaining size | `statistics.local_bytes_remaining` in bytes |
| Progress | `statistics.progress`, already a percentage |
| Counters available | Technical flag, hidden by default |

Last Message is `HBS3 - Running`, or the mapped state. The script does not start, stop or modify a job.

The bundled state map recognizes Running, Stopped, Failed, Finished, Success, Never Run and NeverRun. Finished/Success map to OK and remain healthy while the latest returned run is successful. Running intentionally puts the sensor in Warning, rendered yellow/orange by PRTG. Stopped and disabled jobs also produce Warning; Failed produces Down. NeverRun, including a job without returned statistics, stays green with the distinct label Never run. This is a monitoring policy, not evidence of a successful backup or proof that the job has never executed. Other labels remain unknown until explicitly configured. This API may vary by HBS3 version; no universal list of state labels is claimed.

Select Job health as the primary channel to show Running, Never run or OK beneath the sensor name. Warning notification triggers can fire during normal job execution because Running intentionally uses PRTG's Warning state. Failed jobs retain their channels and the native lookup error message, including the HBS3 - Error text.

Unavailable counters on an inactive/failed/successful job are represented by -1, with Counters available = 0. Exclude these sentinels from reports. Missing or invalid counters on a running job produce an error. Error counts above zero promote an otherwise healthy job to Warning. Counters can describe the latest run, and zero remaining files does not establish success. Pagination (`has_more=true`) is refused rather than silently ignoring jobs.

## Tests and troubleshooting

### Updating an existing installation

Replace the PS1, schema JSON and both .ovl files, then reload lookups before scanning. The health lookup must contain value 3 (Never run, Ok) and value 4 (Running, Warning). An Undefined lookup value (4) error means PRTG has not loaded the updated health definition, or the channel uses the wrong lookup. Keep the lookup IDs unchanged.

### Offline tests and sensor logs

```powershell
powershell.exe -NoProfile -File .\Test-QNAP-HBS3.ps1
```

Offline tests validate job selection, six-channel XML, state handling, synthetic counters, credential encoding, cookies and headers. They do not certify live NAS connectivity or PRTG rendering. Never configure FixtureFile on a production sensor; it bypasses the NAS connection.

For a failed scan, enable Result Handling → Store result and inspect `Logs\sensors\Result of Sensor [ID].txt` beneath your configured PRTG data directory. The adjacent `.Data.txt` file contains execution settings and may contain secrets. Do not commit either file. Restore Discard result after troubleshooting.

PE233 can result from PowerShell emitting an error instead of XML, including a script-signature block. Inspect the actual output first. Diagnostic messages distinguish configuration, QTS authentication, HBS3 response, UUID selection and counter failures without echoing raw responses or credentials.

## References

[PRTG EXE/Script Advanced](https://manuals.paessler.com/exe_script_advanced_sensor.htm), [PRTG Custom Sensors](https://manuals.paessler.com/custom_sensors.htm), [PRTG lookups](https://www.paessler.com/manuals/prtg/define_lookups), [QTS authentication](https://eu1.qnap.com/dev/QTS_HTTP_API-Authentication_v5.1.0.pdf).

HBS3 cookies and response fields are implementation assumptions to check on your own installation; the QTS authentication reference does not document the complete HBS3 interface.
