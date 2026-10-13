# Security and privacy

## Credentials and transport

- Store credentials in PRTG placeholders, not in the script, schema file or literal sensor parameters.
- Use HTTPS with a certificate trusted by the probe. Base64 password encoding is not encryption. AllowHttp explicitly opts into an unencrypted connection.
- Run under the probe service's Windows context. Use a dedicated NAS account with the required HBS3 API permissions where supported, and verify those permissions on the target installation.
- Restrict script/configuration write access to authorized administrators and limit probe-to-NAS network access.
- Local administrators can inspect process arguments or environment. Clearing variables is not a guarantee of physical memory erasure.

QTS authentication POSTs to authLogin.cgi, checks authPassed/authSid and rejects a response requiring an additional authentication step. HBS3 requests use NAS_SID, NAS_USER, NAS_PW_STATUS and home cookies plus X-QNAP-SID and X-Requested-With headers. No secrets are written to the XML messages. Redirects are disabled and untrusted authentication XML is parsed with DTD/external entities disabled.

Each scan creates a new session and does not explicitly log out; QTS expires sessions. Use the shared mutex and an appropriate polling interval to limit load. There is no repeated login loop within one scan.

## Do not publish local data

Never commit PRTG result logs, actual NAS responses, credentials, session IDs, internal hostnames, domains, job names, job UUIDs, share paths or screenshots. Scrub issue attachments before posting. The included fixture uses synthetic identifiers and measurements and contains no production job inventory.

The example schema has verifiedAgainstNas=true to make it usable as a starting configuration. This is not a certification of compatibility with any NAS: verify the response paths and states on your own system. Unknown states and incomplete responses fail explicitly.
