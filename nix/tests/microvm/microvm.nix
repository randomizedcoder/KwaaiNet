# Parametric MicroVM generator for KwaaiNet.
#
# Uses astro/microvm.nix for minimal VMs with shared /nix/store via 9P.
# Supports x86_64 (KVM), aarch64 (TCG), and riscv64 (TCG).
#
# Returns { mkMicrovm, mkVariant, mkTwoNodeVMs, constants, variants }.
#
{
  pkgs,
  lib,
  nixpkgs,
  microvm,
  kwaainet,
  map-server,
  summit-server ? null,
  containers ? { },
  k8sManifests ? null,
  crossTargets ? { },
}:
let
  constants = import ./constants.nix;

  # The host system we're building on
  hostSystem = pkgs.stdenv.hostPlatform.system;

  # Overlay disabling tests that fail under QEMU cross-arch emulation
  crossEmulationOverlay = import ../../overlays/cross-vm.nix;

  # QEMU without seccomp for cross-arch (seccomp breaks TCG emulation)
  qemuWithoutSandbox = pkgs.qemu.override { seccompSupport = false; };

  # Architecture-specific QEMU extra args (beyond what microvm.nix handles)
  archQemuArgs = {
    x86_64 = [ ];
    aarch64 = [ ];
    riscv64 = [
      "-bios"
      "default"
    ]; # OpenSBI firmware
  };

  # Machine options for TCG acceleration
  archMachineOpts = {
    x86_64 = null; # KVM defaults
    aarch64 = {
      accel = "tcg";
    };
    riscv64 = {
      accel = "tcg";
    };
  };

  mkMicrovm =
    {
      arch ? "x86_64",
      variant,
      portOffset ? 0,
      networking ? "user",
      ram ? constants.defaults.ram,
      vcpus ? constants.defaults.vcpus,
      services ? [ ],
      httpChecks ? [ ],
      # Two-node specific
      macAddress ? "52:54:00:12:34:56",
      initialPeers ? [ ],
      vmIp ? null,
      tapDevice ? null,
      ...
    }:
    let
      archCfg = constants.architectures.${arch};
      needsCross = hostSystem != archCfg.nixSystem;

      # Cross-compiled pkgs for the target architecture
      # Only apply the cross-emulation overlay when actually cross-compiling —
      # modifying outputs (gnutls) or disabling checks on native builds can
      # break the dependency chain.
      overlayedPkgs = import nixpkgs (
        if needsCross then
          {
            localSystem = hostSystem;
            crossSystem = archCfg.nixSystem;
            overlays = [ crossEmulationOverlay ];
          }
        else
          {
            system = archCfg.nixSystem;
          }
      );

      # Select correct binary for this arch
      kwaainetForArch =
        if !needsCross then kwaainet else crossTargets.${constants.archToCrossTarget.${arch}}.kwaainet;
      mapServerForArch =
        if !needsCross then map-server else crossTargets.${constants.archToCrossTarget.${arch}}.map-server;
      # summit-server not yet cross-compiled
      summitServerForArch = if !needsCross then summit-server else null;

      hostname = "kwaainet-${arch}-${variant}-vm";
      consolePorts = constants.consolePorts arch portOffset;
      sshForwardPort = constants.sshForwardPort arch portOffset;
      useTap = networking == "tap";

      hasKwaainet = builtins.elem "kwaainet" services;
      hasMapServer = builtins.elem "kwaainet-map-server" services;
      hasSummitServer = builtins.elem "kwaainet-summit-server" services;
      hasDocker = builtins.elem "docker" services;
      hasPostgres = builtins.elem "postgresql" services;

      # Use variant-specific RAM/vcpus if higher than arch defaults
      effectiveRam =
        let
          variantRam = ram;
          archRam = archCfg.mem;
        in
        if variantRam > archRam then variantRam else archRam;
      effectiveVcpus =
        let
          variantVcpus = vcpus;
          archVcpus = archCfg.vcpu;
        in
        if variantVcpus > archVcpus then variantVcpus else archVcpus;

      nixosSystem = nixpkgs.lib.nixosSystem {
        pkgs = overlayedPkgs;

        specialArgs = {
          kwaainet = kwaainetForArch;
          map-server = mapServerForArch;
          summit-server = summitServerForArch;
        };

        modules = [
          # MicroVM module (replaces qemu-vm.nix)
          microvm.nixosModules.microvm

          # KwaaiNet NixOS modules
          ../../modules

          # Force overlayed pkgs everywhere
          (
            { lib, ... }:
            {
              _module.args.pkgs = lib.mkForce overlayedPkgs;
              nixpkgs.pkgs = lib.mkForce overlayedPkgs;
              nixpkgs.hostPlatform = lib.mkForce overlayedPkgs.stdenv.hostPlatform;
              nixpkgs.buildPlatform = lib.mkForce overlayedPkgs.stdenv.buildPlatform;
            }
          )

          # VM and system configuration
          (
            { config, pkgs, ... }:
            {
              system.stateVersion = "25.11";

              # ─── Minimal system for cross-arch builds ──────────────────────
              documentation.enable = !needsCross;
              documentation.man.enable = !needsCross;
              documentation.doc.enable = false;
              documentation.info.enable = false;
              documentation.nixos.enable = false;
              security.polkit.enable = false;
              programs.command-not-found.enable = false;
              fonts.fontconfig.enable = false;
              nix.enable = false;
              xdg.mime.enable = false;
              boot.supportedFilesystems = lib.mkForce [
                "vfat"
                "ext4"
              ];
              hardware.enableRedistributableFirmware = false;

              # ─── MicroVM configuration ─────────────────────────────────────
              microvm = {
                hypervisor = "qemu";
                mem = effectiveRam;
                vcpu = effectiveVcpus;

                # KVM vs TCG: null cpu → KVM, explicit cpu → TCG
                cpu = if archCfg.useKvm then null else archCfg.qemuCpu;

                # Shared nix store via 9P (no full FS copy)
                shares = [
                  {
                    tag = "ro-store";
                    source = "/nix/store";
                    mountPoint = "/nix/.ro-store";
                    proto = "9p";
                  }
                ];

                volumes = [ ];

                # Network interfaces
                interfaces =
                  if useTap then
                    [
                      {
                        type = "tap";
                        id = tapDevice;
                        mac = macAddress;
                      }
                    ]
                  else
                    [
                      {
                        type = "user";
                        id = "eth0";
                        mac = macAddress;
                      }
                    ];

                # Port forwarding (user-mode networking)
                forwardPorts = lib.optionals (!useTap) (
                  [
                    {
                      from = "host";
                      host.port = sshForwardPort;
                      guest.port = 22;
                    }
                    {
                      from = "host";
                      host.port = constants.defaults.kwaainetPort + portOffset;
                      guest.port = constants.defaults.kwaainetPort;
                    }
                  ]
                  ++ lib.optionals hasMapServer [
                    {
                      from = "host";
                      host.port = 3030 + portOffset;
                      guest.port = 3030;
                    }
                  ]
                  ++ lib.optionals hasSummitServer [
                    {
                      from = "host";
                      host.port = 3000 + portOffset;
                      guest.port = 3000;
                    }
                  ]
                );

                # QEMU configuration
                qemu = {
                  serialConsole = false; # We configure our own TCP consoles
                  machine = archCfg.qemuMachine;
                  package = if archCfg.useKvm then pkgs.qemu_kvm else qemuWithoutSandbox;

                  extraArgs = archQemuArgs.${arch} ++ [
                    "-no-reboot" # Guest reboot → QEMU exits (lifecycle Phase 5 sends systemctl reboot)
                    "-name"
                    "${hostname},process=${hostname}"
                    "-serial"
                    "tcp:127.0.0.1:${toString consolePorts.serial},server,nowait"
                    "-device"
                    "virtio-serial-pci"
                    "-chardev"
                    "socket,id=virtcon,port=${toString consolePorts.virtio},host=127.0.0.1,server=on,wait=off"
                    "-device"
                    "virtconsole,chardev=virtcon"
                    # Explicit -append for cross-arch boot
                    "-append"
                    (builtins.concatStringsSep " " (
                      [
                        "console=${archCfg.consoleDevice},115200"
                        "console=hvc0"
                        "reboot=t"
                        "panic=-1"
                        "loglevel=4"
                        "init=${config.system.build.toplevel}/init"
                      ]
                      ++ config.boot.kernelParams
                    ))
                  ];
                }
                // (if archMachineOpts.${arch} != null then { machineOpts = archMachineOpts.${arch}; } else { });
              };

              # ─── Kernel ────────────────────────────────────────────────────
              boot.kernelPackages = pkgs.${constants.getKernelPackage arch};
              boot.kernelParams = [
                "console=${archCfg.consoleDevice},115200"
                "console=hvc0"
                "systemd.show_status=true"
              ];
              boot.initrd.availableKernelModules = [
                "9p"
                "9pnet"
                "9pnet_virtio"
                "virtio_pci"
                "virtio_console"
              ];

              # ─── KwaaiNet services ─────────────────────────────────────────
              services.kwaainet = lib.mkIf hasKwaainet {
                enable = true;
                package = kwaainetForArch;
                settings = {
                  port = constants.defaults.kwaainetPort;
                  use_gpu = false;
                  initial_peers = initialPeers;
                };
              };

              services.kwaainet-map-server = lib.mkIf hasMapServer {
                enable = true;
                package = mapServerForArch;
              };

              services.kwaainet-summit-server = lib.mkIf (hasSummitServer && summitServerForArch != null) {
                enable = true;
                package = summitServerForArch;
                settings = {
                  DATABASE_URL = "postgresql:///summit?host=/run/postgresql";
                  SUMMIT_SIGNING_KEY_HEX = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
                };
              };

              # ─── PostgreSQL (full-stack variant) ───────────────────────────
              services.postgresql = lib.mkIf hasPostgres {
                enable = true;
                ensureDatabases = [ "summit" ];
                ensureUsers = [
                  {
                    name = "summit";
                    ensureDBOwnership = true;
                  }
                ];
              };

              # ─── Docker (docker/k8s variants) ─────────────────────────────
              virtualisation.docker.enable = hasDocker;

              networking.hostName = hostname;

              # Static IPv6 for TAP networking
              systemd.network = lib.mkIf useTap {
                enable = true;
                networks."10-tap" = {
                  matchConfig.Name = "enp*";
                  networkConfig = {
                    Address = "${vmIp}/64";
                    Gateway = constants.network.gateway;
                    DHCP = "no";
                  };
                };
              };
              networking.useDHCP = lib.mkIf useTap false;

              # SSH for lifecycle test verification
              services.openssh = {
                enable = true;
                settings = {
                  PasswordAuthentication = lib.mkForce true;
                  PermitRootLogin = lib.mkForce "yes";
                  KbdInteractiveAuthentication = lib.mkForce true;
                };
              };
              users.users.root.password = constants.defaults.sshPassword;

              # Container images in VM closure (docker variant)
              environment.etc = lib.mkIf (hasDocker && containers != { }) (
                lib.mapAttrs' (
                  name: image: lib.nameValuePair "kwaainet-containers/${name}" { source = image; }
                ) containers
              );
            }
          )
        ];
      };
    in
    {
      system = nixosSystem;
      runner = nixosSystem.config.microvm.declaredRunner;
      inherit arch;
    };

  # Build a named variant for a specific architecture
  mkVariant =
    arch: name:
    let
      variantConfig = constants.variants.${name};
    in
    mkMicrovm (
      variantConfig
      // {
        inherit arch;
        variant = name;
      }
    );

  # Two-node special case: two VMs with TAP networking
  # vmB is a plain value (no initialPeers function) — peers are injected
  # at runtime via `kwaainet config set initial_peers` over SSH.
  mkTwoNodeVMs = arch: {
    vmA = mkMicrovm {
      inherit arch;
      variant = "two-node-a";
      portOffset = 0;
      networking = "tap";
      services = [ "kwaainet" ];
      httpChecks = [ ];
      macAddress = "52:54:00:12:34:0a";
      vmIp = constants.network.vmA;
      tapDevice = constants.network.tapA;
      initialPeers = [ ];
    };
    vmB = mkMicrovm {
      inherit arch;
      variant = "two-node-b";
      portOffset = 600;
      networking = "tap";
      services = [ "kwaainet" ];
      httpChecks = [ ];
      macAddress = "52:54:00:12:34:0b";
      vmIp = constants.network.vmB;
      tapDevice = constants.network.tapB;
      initialPeers = [ ];
    };
  };

  # Two-node with map-server on VM-A for observing peer discovery
  mkTwoNodeServicesVMs = arch: {
    vmA = mkMicrovm {
      inherit arch;
      variant = "two-node-services-a";
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
      macAddress = "52:54:00:12:34:0a";
      vmIp = constants.network.vmA;
      tapDevice = constants.network.tapA;
      initialPeers = [ ];
    };
    vmB = mkMicrovm {
      inherit arch;
      variant = "two-node-services-b";
      portOffset = 700;
      networking = "tap";
      services = [ "kwaainet" ];
      httpChecks = [ ];
      macAddress = "52:54:00:12:34:0b";
      vmIp = constants.network.vmB;
      tapDevice = constants.network.tapB;
      initialPeers = [ ];
    };
  };

  # Check if an architecture has the required cross-compiled binaries
  archHasBinaries =
    arch:
    let
      needsCross = hostSystem != constants.architectures.${arch}.nixSystem;
      hasCrossTargetName = constants.archToCrossTarget ? ${arch};
    in
    if !needsCross then
      true
    else
      hasCrossTargetName && crossTargets ? ${constants.archToCrossTarget.${arch}};

  # Only architectures where we have the required binaries
  availableArchitectures = lib.filterAttrs (arch: _: archHasBinaries arch) constants.architectures;

  # Generate per-architecture variants (excluding multi-VM tap variants, handled separately)
  mkArchVariants =
    arch:
    lib.mapAttrs (name: _: mkVariant arch name) (
      lib.filterAttrs (
        name: _:
        builtins.elem name constants.archVariants.${arch}
        && name != "two-node"
        && name != "two-node-services"
      ) constants.variants
    );

  # All variants across available architectures, keyed as "<arch>-<variant>"
  variants = lib.concatMapAttrs (
    arch: _: lib.mapAttrs' (name: vm: lib.nameValuePair "${arch}-${name}" vm) (mkArchVariants arch)
  ) availableArchitectures;

in
{
  inherit
    mkMicrovm
    mkVariant
    mkTwoNodeVMs
    mkTwoNodeServicesVMs
    constants
    variants
    ;
}
