# English channel display

Install both `.ovl` files in the core server's `lookups\custom` folder and reload lookups in PRTG.

| Channel | Lookup and display |
|---|---|
| Job health | `custom.qnap.hbs3.health`: OK green, Check required yellow, Failed red |
| Job running | `custom.qnap.hbs3.running`: Running green, Idle neutral |

The running indicator is read-only. Its exact visual shape is controlled by the PRTG interface. Idle does not trigger an alarm; Job health handles failures.

For existing channels, open the channel's gear icon. Under Lookups and Limits, select Enable alerting based on lookups, choose the relevant lookup and save. This replaces numeric limits as the alerting mechanism. If an old custom unit remains, clear it where the channel editor allows it.

To hide Counters available, disable Show in graphs and Show in tables and refresh the overview. XML settings initialize new channels and do not reset existing channel preferences.

Set Progress as the primary channel. To display Remaining size in GB, open sensor Settings → Channel Unit Configuration, interrupt inheritance if needed, and set Bytes (Disk) to GByte. The script returns bytes; do not divide the value or replace its unit with a custom GB string.

The script always returns English names. If migrating from an earlier version with different names or floating-point state channels, create a new sensor for a clean setup. Keep the old sensor if its history is needed. Changing returned names may create additional channels. No EnglishChannelNames parameter is supported.
