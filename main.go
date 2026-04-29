package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"time"
)

const version = "0.1.0"

type Listener struct {
	Proto   string `json:"proto"`
	Port    int    `json:"port"`
	Address string `json:"address"`
	PID     int    `json:"pid"`
	User    string `json:"user"`
	Command string `json:"command"`
}

type filter struct {
	port    int
	portMin int
	portMax int
	proto   string
	json    bool
	watch   bool
	killTgt int
	killYes bool
}

func main() {
	f, err := parseArgs(os.Args[1:])
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}

	if f.killTgt > 0 {
		if err := killPort(f.killTgt, f.killYes); err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			os.Exit(1)
		}
		return
	}

	if f.watch {
		runWatch(f)
		return
	}

	listeners, err := list(f.proto)
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	listeners = applyFilter(listeners, f)

	if f.json {
		printJSON(listeners)
	} else {
		printTable(listeners)
	}
}

func usage() {
	fmt.Print(`portspy ` + version + ` - list listening TCP/UDP ports

USAGE
  portspy [PORT|RANGE] [flags]

EXAMPLES
  portspy                 list all listening ports
  portspy 8000            who is on port 8000
  portspy 8000-8100       ports 8000 through 8100
  portspy --tcp           TCP only
  portspy --json          JSON output
  portspy --watch         live refresh every 2s
  portspy --kill 8000     kill the process on port 8000
  portspy --kill 8000 -y  kill without asking

FLAGS
  --tcp / --udp           filter by protocol
  --json                  machine-readable output
  --watch                 redraw every 2 seconds
  --kill PORT             send SIGTERM to the process bound to PORT
  -y, --yes               skip confirmation for --kill
  -h, --help              show help
  -v, --version           print version
`)
}

func parseArgs(args []string) (filter, error) {
	f := filter{proto: "any"}
	for i := 0; i < len(args); i++ {
		a := args[i]
		switch a {
		case "-h", "--help":
			usage()
			os.Exit(0)
		case "-v", "--version":
			fmt.Println("portspy " + version)
			os.Exit(0)
		case "--tcp":
			f.proto = "tcp"
		case "--udp":
			f.proto = "udp"
		case "--json":
			f.json = true
		case "--watch":
			f.watch = true
		case "-y", "--yes":
			f.killYes = true
		case "--kill":
			if i+1 >= len(args) {
				return f, fmt.Errorf("--kill requires a port")
			}
			i++
			p, err := strconv.Atoi(args[i])
			if err != nil || p < 1 || p > 65535 {
				return f, fmt.Errorf("invalid port for --kill: %s", args[i])
			}
			f.killTgt = p
		default:
			if strings.HasPrefix(a, "-") {
				return f, fmt.Errorf("unknown flag: %s (try --help)", a)
			}
			if strings.Contains(a, "-") {
				parts := strings.SplitN(a, "-", 2)
				lo, err1 := strconv.Atoi(parts[0])
				hi, err2 := strconv.Atoi(parts[1])
				if err1 != nil || err2 != nil || lo < 1 || hi > 65535 || lo > hi {
					return f, fmt.Errorf("invalid range: %s", a)
				}
				f.portMin, f.portMax = lo, hi
			} else {
				p, err := strconv.Atoi(a)
				if err != nil || p < 1 || p > 65535 {
					return f, fmt.Errorf("invalid port: %s", a)
				}
				f.port = p
			}
		}
	}
	return f, nil
}

func applyFilter(in []Listener, f filter) []Listener {
	out := in[:0]
	for _, l := range in {
		if f.port != 0 && l.Port != f.port {
			continue
		}
		if f.portMin != 0 && (l.Port < f.portMin || l.Port > f.portMax) {
			continue
		}
		out = append(out, l)
	}
	return out
}

func list(proto string) ([]Listener, error) {
	switch runtime.GOOS {
	case "darwin", "linux":
		return listLsof(proto)
	default:
		return nil, fmt.Errorf("portspy does not yet support %s", runtime.GOOS)
	}
}

func listLsof(proto string) ([]Listener, error) {
	var listeners []Listener
	if proto == "any" || proto == "tcp" {
		l, err := runLsof("-iTCP", "-sTCP:LISTEN")
		if err != nil {
			return nil, err
		}
		for i := range l {
			l[i].Proto = "tcp"
		}
		listeners = append(listeners, l...)
	}
	if proto == "any" || proto == "udp" {
		l, err := runLsof("-iUDP")
		if err != nil {
			return nil, err
		}
		for i := range l {
			l[i].Proto = "udp"
		}
		listeners = append(listeners, l...)
	}
	sort.Slice(listeners, func(i, j int) bool {
		if listeners[i].Port != listeners[j].Port {
			return listeners[i].Port < listeners[j].Port
		}
		return listeners[i].Proto < listeners[j].Proto
	})
	return listeners, nil
}

func runLsof(args ...string) ([]Listener, error) {
	full := append([]string{"-P", "-n", "-F", "pcunPL"}, args...)
	cmd := exec.Command("lsof", full...)
	out, err := cmd.Output()
	if err != nil {
		if ee, ok := err.(*exec.ExitError); ok && ee.ExitCode() == 1 {
			if len(out) == 0 {
				return nil, nil
			}
		} else {
			return nil, fmt.Errorf("lsof failed: %w", err)
		}
	}
	return parseLsofF(string(out)), nil
}

func parseLsofF(out string) []Listener {
	var listeners []Listener
	var cur Listener
	for _, line := range strings.Split(out, "\n") {
		if line == "" {
			continue
		}
		tag, val := line[0], line[1:]
		switch tag {
		case 'p':
			cur = Listener{}
			pid, _ := strconv.Atoi(val)
			cur.PID = pid
		case 'c':
			cur.Command = val
		case 'u':
			cur.User = lookupUser(val)
		case 'n':
			addr, port := splitAddrPort(val)
			if port == 0 {
				continue
			}
			cur.Address = addr
			cur.Port = port
			listeners = append(listeners, cur)
		}
	}
	return listeners
}

func splitAddrPort(s string) (string, int) {
	if i := strings.Index(s, "->"); i >= 0 {
		s = s[:i]
	}
	idx := strings.LastIndex(s, ":")
	if idx == -1 {
		return s, 0
	}
	addr := s[:idx]
	port, err := strconv.Atoi(s[idx+1:])
	if err != nil {
		return s, 0
	}
	addr = strings.Trim(addr, "[]")
	if addr == "*" {
		addr = "0.0.0.0"
	}
	return addr, port
}

func lookupUser(uid string) string {
	if uid == "" {
		return ""
	}
	if _, err := strconv.Atoi(uid); err != nil {
		return uid
	}
	out, err := exec.Command("id", "-un", uid).Output()
	if err != nil {
		return uid
	}
	return strings.TrimSpace(string(out))
}

func printTable(listeners []Listener) {
	if len(listeners) == 0 {
		fmt.Println("no listening ports matched")
		return
	}
	rows := [][]string{{"PROTO", "PORT", "ADDRESS", "PID", "USER", "COMMAND"}}
	for _, l := range listeners {
		rows = append(rows, []string{
			l.Proto,
			strconv.Itoa(l.Port),
			l.Address,
			strconv.Itoa(l.PID),
			l.User,
			l.Command,
		})
	}
	widths := make([]int, len(rows[0]))
	for _, r := range rows {
		for i, c := range r {
			if len(c) > widths[i] {
				widths[i] = len(c)
			}
		}
	}
	for ri, r := range rows {
		for i, c := range r {
			if i == len(r)-1 {
				fmt.Print(c)
			} else {
				fmt.Printf("%-*s  ", widths[i], c)
			}
		}
		fmt.Println()
		if ri == 0 {
			for i, w := range widths {
				if i == len(widths)-1 {
					fmt.Print(strings.Repeat("-", w))
				} else {
					fmt.Print(strings.Repeat("-", w) + "  ")
				}
			}
			fmt.Println()
		}
	}
}

func printJSON(listeners []Listener) {
	if listeners == nil {
		listeners = []Listener{}
	}
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(listeners)
}

func runWatch(f filter) {
	sig := make(chan os.Signal, 1)
	signal.Notify(sig, os.Interrupt, syscall.SIGTERM)
	tick := time.NewTicker(2 * time.Second)
	defer tick.Stop()

	render := func() {
		fmt.Print("\033[H\033[2J")
		fmt.Printf("portspy %s - %s (Ctrl+C to quit)\n\n", version, time.Now().Format("15:04:05"))
		listeners, err := list(f.proto)
		if err != nil {
			fmt.Fprintln(os.Stderr, "error:", err)
			return
		}
		listeners = applyFilter(listeners, f)
		if f.json {
			printJSON(listeners)
		} else {
			printTable(listeners)
		}
	}

	render()
	for {
		select {
		case <-sig:
			fmt.Println()
			return
		case <-tick.C:
			render()
		}
	}
}

func killPort(port int, yes bool) error {
	listeners, err := list("any")
	if err != nil {
		return err
	}
	var matches []Listener
	for _, l := range listeners {
		if l.Port == port {
			matches = append(matches, l)
		}
	}
	if len(matches) == 0 {
		return fmt.Errorf("no process listening on port %d", port)
	}
	for _, m := range matches {
		fmt.Printf("port %d -> PID %d (%s, user %s)\n", m.Port, m.PID, m.Command, m.User)
	}
	if !yes {
		fmt.Print("kill all? [y/N] ")
		var ans string
		fmt.Scanln(&ans)
		if !strings.EqualFold(strings.TrimSpace(ans), "y") {
			fmt.Println("aborted")
			return nil
		}
	}
	for _, m := range matches {
		if err := syscall.Kill(m.PID, syscall.SIGTERM); err != nil {
			fmt.Fprintf(os.Stderr, "kill %d: %v\n", m.PID, err)
		} else {
			fmt.Printf("sent SIGTERM to PID %d\n", m.PID)
		}
	}
	return nil
}
