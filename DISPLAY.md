# English channel display

Install both `.ovl` files in the core server's `lookups\custom` folder and reload lookups in PRTG.

| Channel | Lookup and display |
|---|---|
| Job health | `custom.qnap.hbs3.health`: OK and Never run green, Running and Check required yellow/orange, Failed red |
| Job running | `custom.qnap.hbs3.running`: Running yellow/orange, Idle neutral |

The running indicator is read-only. Its exact visual shape is controlled by the PRTG interface. Running puts the sensor in Warning and may activate Warning notification triggers. Idle does not trigger an alarm. Job health handles completed, unexecuted and failed jobs.

For existing channels, open the channel's gear icon. Under Lookups and Limits, select Enable alerting based on lookups, choose the relevant lookup and save. This replaces numeric limits as the alerting mechanism. If an old custom unit remains, clear it where the channel editor allows it.

To hide Counters available, disable Show in graphs and Show in tables and refresh the overview. XML settings initialize new channels and do not reset existing channel preferences.

Select Job health as the primary channel to display Running, Never run or OK below the sensor name. Select Progress instead if a percentage is preferred. To display Remaining size in GB, open sensor Settings → Channel Unit Configuration, interrupt inheritance if needed, and set Bytes (Disk) to GByte. The script returns bytes; do not divide the value or replace its unit with a custom GB string.

After updating the files, reload lookups before scanning. If PRTG reports Undefined lookup value (4), verify that custom.qnap.hbs3.health.ovl contains `<SingleInt state="Warning" value="4">Running</SingleInt>`, reload it, and check that Job health uses custom.qnap.hbs3.health. The sensor's error text for Failed remains PRTG's native lookup message to preserve channel measurements.

The script always returns English names. If migrating from an earlier version with different names or floating-point state channels, create a new sensor for a clean setup. Keep the old sensor if its history is needed. Changing returned names may create additional channels. No EnglishChannelNames parameter is supported.
