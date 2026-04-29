# portspy

A small CLI to find out which process is holding a port.

## Install

From source:

```
go install github.com/y1qne/portspy@latest
```

Or clone and build:

```
git clone https://github.com/y1qne/portspy.git
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

## Platforms

macOS and Linux. Windows is not supported yet.

## How it works

`portspy` shells out to `lsof`, which is preinstalled on macOS and most Linux
distributions. Without root you only see ports owned by your user; run with
`sudo` to see everything.

## License

MIT
