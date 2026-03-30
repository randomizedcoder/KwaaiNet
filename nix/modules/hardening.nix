# Shared systemd security baseline for KwaaiNet services.
# Merge into each service's serviceConfig via: hardening // { per-service-overrides }
{
  NoNewPrivileges = true;
  ProtectSystem = "strict";
  ProtectHome = true;
  ProtectKernelTunables = true;
  ProtectKernelModules = true;
  ProtectControlGroups = true;
  ProtectKernelLogs = true;
  PrivateDevices = true;
  PrivateTmp = true;
  RestrictRealtime = true;
  RestrictSUIDSGID = true;
  RestrictNamespaces = true;
  LockPersonality = true;
  ProtectHostname = true;
  ProtectClock = true;
  MemoryDenyWriteExecute = true;
  UMask = "0077";

  # Drop all capabilities — empty string means "no capabilities at all".
  # NB: an empty *list* [] produces no directive and systemd defaults to all caps.
  CapabilityBoundingSet = "";

  SystemCallArchitectures = [ "native" ];
  SystemCallFilter = [
    "@system-service"
    "~@privileged"
    "~@mount"
    "~@debug"
    "~@module"
    "~@reboot"
    "~@swap"
    "~@clock"
    "~@cpu-emulation"
    "~@obsolete"
    "~@raw-io"
    "~@resources"
  ];

  RemoveIPC = true;
  ProtectProc = "invisible";
  ProcSubset = "pid";

  # IPC isolation — private System V IPC + POSIX message queues
  PrivateIPC = true;

  # Kernel keyring isolation
  KeyringMode = "private";

  # No sd_notify needed (Type=simple)
  NotifyAccess = "none";

  # Explicit device policy (PrivateDevices=true implies, but scoring checks separately)
  DevicePolicy = "closed";
  DeviceAllow = "";

  # Explicit empty ambient capabilities
  AmbientCapabilities = "";

  # Default-deny IP addresses at systemd level
  # Each service overrides with IPAddressAllow for its needs
  IPAddressDeny = "any";

  # Prevent code execution from data directories
  # All executables live in /nix/store (Nix hermetic builds)
  NoExecPaths = [
    "/var"
    "/tmp"
    "/run"
    "/home"
    "/root"
  ];
  ExecPaths = [ "/nix/store" ];

  Restart = "always";
  RestartSec = "1s";
}
