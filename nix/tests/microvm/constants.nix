# Shared constants for KwaaiNet MicroVM lifecycle testing.
# All ports, timeouts, network config, VM resources, variant definitions,
# and multi-architecture support.
rec {
  network = {
    bridge = "kwaaibr0";
    prefix = "fd00:c0aa:1::/48";
    gateway = "fd00:c0aa:1::1";
    vmA = "fd00:c0aa:1::a";
    vmB = "fd00:c0aa:1::b";
    vmC = "fd00:c0aa:1::c";
    vmD = "fd00:c0aa:1::d";
    tapA = "kwaitap0";
    tapB = "kwaitap1";
    tapC = "kwaitap2";
    tapD = "kwaitap3";
  };

  defaults = {
    ram = 1024;
    vcpus = 2;
    sshPort = 15522;
    sshPassword = "kwaainet";
    kwaainetPort = 15580;
  };

  # ─── Architecture definitions ──────────────────────────────────────────
  # KwaaiNet targets Raspberry Pi (aarch64) and Banana Pi (riscv64).
  # All variants run on all architectures to catch platform-specific issues.

  architectures = {
    x86_64 = {
      nixSystem = "x86_64-linux";
      qemuMachine = "pc";
      qemuCpu = "host";
      useKvm = true;
      consoleDevice = "ttyS0";
      mem = 1024;
      vcpu = 2;
      description = "x86_64 (KVM accelerated)";
    };
    aarch64 = {
      nixSystem = "aarch64-linux";
      qemuMachine = "virt";
      qemuCpu = "cortex-a72";
      useKvm = false;
      consoleDevice = "ttyAMA0";
      mem = 1024;
      vcpu = 2;
      description = "aarch64 (ARM64, QEMU emulated)";
    };
    riscv64 = {
      nixSystem = "riscv64-linux";
      qemuMachine = "virt";
      qemuCpu = "rv64";
      useKvm = false;
      consoleDevice = "ttyS0";
      mem = 1024;
      vcpu = 2;
      description = "riscv64 (RISC-V 64-bit, QEMU emulated)";
    };
  };

  # All variants available on all architectures
  allVariantNames = builtins.attrNames variants;
  archVariants = {
    x86_64 = allVariantNames;
    aarch64 = allVariantNames;
    riscv64 = allVariantNames;
  };

  variants = {
    single-node = {
      portOffset = 0;
      networking = "user";
      services = [ "kwaainet" ];
      httpChecks = [ ];
    };
    two-node = {
      portOffset = 0;
      networking = "tap";
      services = [ "kwaainet" ];
      httpChecks = [ ];
    };
    map-server = {
      portOffset = 200;
      networking = "user";
      services = [
        "kwaainet"
        "kwaainet-map-server"
      ];
      httpChecks = [
        {
          path = "/health";
          port = 3030;
          expect = 200;
        }
      ];
    };
    full-stack = {
      portOffset = 300;
      networking = "user";
      # summit-server + postgresql added once summit-server is in the Cargo workspace
      services = [
        "kwaainet"
        "kwaainet-map-server"
      ];
      httpChecks = [
        {
          path = "/health";
          port = 3030;
          expect = 200;
        }
      ];
    };
    docker = {
      portOffset = 400;
      networking = "user";
      ram = 2047; # not 2048 — QEMU hangs at exactly 2GB (microvm.nix #171)
      services = [ "docker" ];
      httpChecks = [ ];
    };
    k8s = {
      portOffset = 500;
      networking = "user";
      ram = 4096;
      vcpus = 4;
      services = [ "docker" ];
      httpChecks = [ ];
    };
    two-node-services = {
      portOffset = 100;
      networking = "tap";
      services = [
        "kwaainet"
        "kwaainet-map-server"
      ];
      httpChecks = [
        {
          path = "/health";
          port = 3030;
          expect = 200;
        }
      ];
    };
    four-node = {
      portOffset = 0;
      networking = "tap";
      services = [ "kwaainet" ];
      httpChecks = [ ];
    };
    four-node-services = {
      portOffset = 100;
      networking = "tap";
      services = [
        "kwaainet"
        "kwaainet-map-server"
      ];
      httpChecks = [
        {
          path = "/health";
          port = 3030;
          expect = 200;
        }
      ];
    };
  };

  # ─── Per-arch timeouts ─────────────────────────────────────────────────
  # KVM is fast; QEMU TCG is slower; RISC-V TCG is slowest.
  # Base values scale by multiplier (1x KVM, 2x QEMU, 3x RISC-V);
  # keys with non-linear scaling are passed as overrides.

  baseTimeouts = {
    services = 60;
    security = 30;
    node = 30;
    http = 30;
    p2p = 60;
    shutdown = 30;
    waitExit = 60;
    startupSequence = 30;
    deepValidation = 30;
    resilience = 90;
    p2pBootstrap = 60;
    p2pDiscovery = 90;
    p2pMapCrawl = 180;
  };

  mkTimeouts =
    multiplier: overrides: (builtins.mapAttrs (_: v: v * multiplier) baseTimeouts) // overrides;

  timeouts = mkTimeouts 1 {
    build = 600;
    start = 5;
    serial = 30;
    virtio = 45;
    containers = 120;
    k8s = 300;
  };

  timeoutsQemu = mkTimeouts 2 {
    build = 2400;
    start = 5;
    serial = 30;
    virtio = 45;
    containers = 600;
    k8s = 1800;
  };

  timeoutsQemuSlow = mkTimeouts 3 {
    build = 3600;
    start = 10;
    serial = 60;
    virtio = 90;
    containers = 1200;
    k8s = 3600;
  };

  getTimeouts =
    arch:
    if architectures.${arch}.useKvm then
      timeouts
    else if arch == "riscv64" then
      timeoutsQemuSlow
    else
      timeoutsQemu;

  # ─── Port allocation ───────────────────────────────────────────────────
  # All test ports live in the 155xx–157xx range to avoid conflicts with
  # common services (SSH 22, HTTP 8080, dev servers, etc.).
  #
  # Console ports: x86_64 15500+, aarch64 15600+, riscv64 15700+
  # SSH ports:     x86_64 15522+, aarch64 15622+, riscv64 15722+
  archPortBase = {
    x86_64 = 15500;
    aarch64 = 15600;
    riscv64 = 15700;
  };

  consolePorts =
    arch: portOffset:
    let
      base = archPortBase.${arch};
      idx = portOffset / 100;
    in
    {
      serial = base + idx * 2 + 1;
      virtio = base + idx * 2 + 2;
    };

  sshForwardPort =
    arch: portOffset:
    let
      archSshBase = {
        x86_64 = 15522;
        aarch64 = 15622;
        riscv64 = 15722;
      };
    in
    archSshBase.${arch} + (portOffset / 100);

  # ─── Kernel selection ──────────────────────────────────────────────────
  getKernelPackage =
    arch: if architectures.${arch}.useKvm then "linuxPackages" else "linuxPackages_latest";

  # ─── Cross target name mapping ─────────────────────────────────────────
  archToCrossTarget = {
    aarch64 = "aarch64-linux-gnu";
    riscv64 = "riscv64-linux-gnu";
  };
}
