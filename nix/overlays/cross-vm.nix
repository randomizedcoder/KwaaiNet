# Overlay to disable tests for packages that fail under QEMU cross-architecture
# emulation. These packages build successfully but their test suites fail under
# QEMU TCG due to threading, I/O timing, or syscall emulation bugs.
#
# Used by nix/tests/microvm/microvm.nix when building aarch64/riscv64 NixOS VMs
# on an x86_64 host.
#
# Reference: xdp2 nix/microvms/mkVm.nix:72-147
final: prev: {
  # boehm-gc: QEMU plugin bug with threading
  #   ERROR:../plugins/core.c:292:qemu_plugin_vcpu_init__async: assertion failed
  boehmgc = prev.boehmgc.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

  # libuv: I/O and event loop tests fail under QEMU emulation
  libuv = prev.libuv.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

  # libseccomp: seccomp BPF simulation tests fail under QEMU emulation
  libseccomp = prev.libseccomp.overrideAttrs (oldAttrs: {
    doCheck = false;
  });

  # meson: Tests timeout under QEMU emulation
  meson = prev.meson.overrideAttrs (oldAttrs: {
    doCheck = false;
    doInstallCheck = false;
  });

  # gnutls: doc tools try to run target binaries on build host
  gnutls = prev.gnutls.overrideAttrs (oldAttrs: {
    configureFlags = (oldAttrs.configureFlags or [ ]) ++ [ "--disable-doc" ];
    outputs = builtins.filter (o: o != "devdoc" && o != "man") (oldAttrs.outputs or [ "out" ]);
  });

  # tbb: -fcf-protection=full is x86-only
  tbb = prev.tbb.overrideAttrs (oldAttrs: {
    hardeningDisable = (oldAttrs.hardeningDisable or [ ]) ++ [ "cet" ];
    postPatch = (oldAttrs.postPatch or "") + ''
      find . -type f \( -name "GNU.cmake" -o -name "Clang.cmake" \) -exec \
        sed -i '/fcf-protection/d' {} \; -print
    '';
  });

  # Python packages that fail tests under QEMU emulation
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pyFinal: pyPrev: {
      # psutil: Network ioctl tests fail under QEMU
      psutil = pyPrev.psutil.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
      });

      # pytest-timeout: Timing tests unreliable under emulation
      pytest-timeout = pyPrev.pytest-timeout.overrideAttrs (old: {
        doCheck = false;
        doInstallCheck = false;
      });
    })
  ];
}
