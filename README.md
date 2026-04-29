# portspy

A small CLI to find out which process is holding a port.

## Install

From source:

```
go install github.com/CZEpitech/portspy@latest
```

Or clone and build:

```
git clone https://github.com/CZEpitech/portspy.git
cd portspy
go build -o portspy
```

## Usage

```
portspy                 list every listening TCP and UDP port
portspy 8000            show what is on port 8000
portspy 8000-8100       show ports in a range
portspy --tcp           TCP only
portspy --udp           UDP only
portspy --json          machine-readable output
portspy --watch         live refresh every two seconds
portspy --kill 8000     send SIGTERM to whoever holds port 8000
portspy --kill 8000 -y  same, without confirmation
```

Example:

```
$ portspy 3306
PROTO  PORT   ADDRESS    PID   USER    COMMAND
-----  -----  ---------  ----  ------  --------
tcp    3306   127.0.0.1  1021  chakib  mysqld
```

## Menu bar app (macOS)

A small SwiftUI status bar app lives in `menubar/`. It puts a network icon
with the live count of listening ports next to the clock; clicking it opens
a popover with the same information as the CLI plus a quick filter and a
per-row kill button.

Build and run:

```
cd menubar
./build.sh
open .build/Portspy.app
```

Requires Xcode 15 or later and macOS 13 or later. The build script produces
a universal binary (arm64 + x86_64) and ad-hoc signs it for local use.

## Platforms

CLI: macOS and Linux. Menu bar app: macOS 13 or later. Windows is not
supported yet.

## How it works

`portspy` shells out to `lsof`, which is preinstalled on macOS and most Linux
distributions. Without root you only see ports owned by your user; run with
`sudo` to see everything.

## License

MIT
