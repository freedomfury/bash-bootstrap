// qemu-virtiofsd — QEMU wrapper invoked via qemu_binary in Packer source blocks.
//
// Parses the virtiofsd socket path from the QEMU arg list, starts a per-build
// virtiofsd instance as a direct child process, then runs the real QEMU binary.
//
// Both virtiofsd and QEMU are started with Pdeathsig=SIGTERM so the kernel
// automatically signals them if this wrapper dies — including via SIGKILL.
//
// Environment:
//
//	VIRTIOFSD_SHARED_DIR   Host directory to share read-only (required)
//	VIRTIOFSD_BIN          virtiofsd binary path (default: /usr/libexec/virtiofsd)
//	QEMU_BIN               Real QEMU binary (default: /usr/bin/qemu-system-x86_64)
package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"
	"time"
)

const (
	defaultVirtiofsdBin = "/usr/libexec/virtiofsd"
	defaultQEMUBin      = "/usr/bin/qemu-system-x86_64"
	socketTimeout      = 5 * time.Second
	socketPollInterval = 250 * time.Millisecond
)

func main() { os.Exit(run()) }

func run() int {
	args := os.Args[1:]
	if len(args) == 0 {
		fatalf("no arguments — called directly?")
	}

	// Pass-through: version/help queries come from Packer before the build starts.
	// Packer calls qemu_binary -version (single dash) to detect the QEMU version.
	for _, arg := range args {
		switch arg {
		case "-version", "--version", "--help", "-h":
			execQEMU(args)
		}
	}

	sharedDir := os.Getenv("VIRTIOFSD_SHARED_DIR")
	if sharedDir == "" {
		fatalf("VIRTIOFSD_SHARED_DIR is not set")
	}

	socketPath, ok := parseVfsdSocket(args)
	if !ok {
		fatalf("could not find -chardev id=vfsd in QEMU args")
	}

	if err := os.MkdirAll(filepath.Dir(socketPath), 0o755); err != nil {
		fatalf("failed to create socket directory: %v", err)
	}

	// -- Start virtiofsd as a direct child.
	// Pdeathsig ensures virtiofsd receives SIGTERM if this process dies for any
	// reason, including SIGKILL (handled by the kernel, not a signal handler).
	virtiofsdBin := os.Getenv("VIRTIOFSD_BIN")
	if virtiofsdBin == "" {
		virtiofsdBin = defaultVirtiofsdBin
	}
	vfsd := exec.Command(virtiofsdBin,
		"--socket-path="+socketPath,
		"--shared-dir="+sharedDir,
		"--readonly",
	)
	vfsd.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
	vfsd.Stdout = os.Stderr // virtiofsd stdout merged into wrapper stderr
	vfsd.Stderr = os.Stderr

	if err := vfsd.Start(); err != nil {
		fatalf("failed to start virtiofsd: %v", err)
	}
	defer func() {
		vfsd.Process.Signal(syscall.SIGTERM) //nolint:errcheck
		vfsd.Wait()                          //nolint:errcheck
		os.Remove(socketPath)                //nolint:errcheck
	}()

	if err := waitForSocket(socketPath, socketTimeout); err != nil {
		fatalf("virtiofsd: %v", err)
	}
	fmt.Fprintf(os.Stderr, "qemu-virtiofsd: virtiofsd ready (socket=%s)\n", socketPath)

	// -- Start QEMU as a direct child, also with Pdeathsig.
	qemuBin := os.Getenv("QEMU_BIN")
	if qemuBin == "" {
		qemuBin = defaultQEMUBin
	}
	qemu := exec.Command(qemuBin, args...)
	qemu.SysProcAttr = &syscall.SysProcAttr{Pdeathsig: syscall.SIGTERM}
	qemu.Stdin = os.Stdin
	qemu.Stdout = os.Stdout
	qemu.Stderr = os.Stderr

	if err := qemu.Start(); err != nil {
		fatalf("failed to start QEMU: %v", err)
	}

	// Forward SIGTERM and SIGINT to QEMU.
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, syscall.SIGTERM, syscall.SIGINT)
	go func() {
		for sig := range sigs {
			qemu.Process.Signal(sig) //nolint:errcheck
		}
	}()

	rc := 0
	if err := qemu.Wait(); err != nil {
		if exitErr, ok := err.(*exec.ExitError); ok {
			rc = exitErr.ExitCode()
		} else {
			rc = 1
		}
	}

	signal.Stop(sigs)
	close(sigs)

	return rc
}

// execQEMU replaces the current process with QEMU (used for pass-through queries).
func execQEMU(args []string) {
	qemuBin := os.Getenv("QEMU_BIN")
	if qemuBin == "" {
		qemuBin = defaultQEMUBin
	}
	binary, err := exec.LookPath(qemuBin)
	if err != nil {
		fatalf("QEMU binary not found: %s", qemuBin)
	}
	if err := syscall.Exec(binary, append([]string{binary}, args...), os.Environ()); err != nil {
		fatalf("exec %s: %v", binary, err)
	}
}

// parseVfsdSocket scans the QEMU arg list for:
//
//	-chardev socket,...,id=vfsd,...,path=<value>,...
//
// and returns the path value.
func parseVfsdSocket(args []string) (string, bool) {
	for i := 0; i+1 < len(args); i++ {
		if args[i] != "-chardev" {
			continue
		}
		val := args[i+1]
		if !strings.Contains(val, "id=vfsd") {
			continue
		}
		for _, part := range strings.Split(val, ",") {
			if v, ok := strings.CutPrefix(part, "path="); ok {
				return v, true
			}
		}
	}
	return "", false
}

// waitForSocket polls until the socket file appears or the timeout elapses.
func waitForSocket(path string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if fi, err := os.Stat(path); err == nil && fi.Mode()&os.ModeSocket != 0 {
			return nil
		}
		time.Sleep(socketPollInterval)
	}
	return fmt.Errorf("socket %s did not appear within %s", path, timeout)
}

func fatalf(format string, args ...any) {
	fmt.Fprintf(os.Stderr, "qemu-virtiofsd: FATAL: "+format+"\n", args...)
	os.Exit(1)
}
