/*
  Declares what makes the nix-daemon work on systemd.
  See also
   - nixos/modules/config/nix.nix: the nix.conf
   - nixos/modules/config/nix-remote-build.nix: the nix.conf
*/
{
  config,
  lib,
  pkgs,
  ...
}:
let

  cfg = config.nix;

  nixPackage = cfg.package.out;

  # nixVersion is an attribute which defines the implementation version.
  # This is useful for Nix implementations which don't follow Nix's versioning.
  isNixAtLeast = lib.versionAtLeast (nixPackage.nixVersion or (lib.getVersion nixPackage));

  makeNixBuildUser = nr: {
    name = "nixbld${toString nr}";
    value = {
      description = "Nix build user ${toString nr}";

      /*
        For consistency with the setgid(2), setuid(2), and setgroups(2)
        calls in `libstore/build.cc', don't add any supplementary group
        here except "nixbld".
      */
      uid = builtins.add config.ids.uids.nixbld nr;
      isSystemUser = true;
      group = "nixbld";
      extraGroups = [ "nixbld" ];
    };
  };

  nixbldUsers = lib.listToAttrs (map makeNixBuildUser (lib.range 1 cfg.nrBuildUsers));

in

{
  imports = [
    (lib.mkRenamedOptionModuleWith {
      sinceRelease = 2205;
      from = [
        "nix"
        "daemonIONiceLevel"
      ];
      to = [
        "nix"
        "daemonIOSchedPriority"
      ];
    })
    (lib.mkRenamedOptionModuleWith {
      sinceRelease = 2211;
      from = [
        "nix"
        "readOnlyStore"
      ];
      to = [
        "boot"
        "readOnlyNixStore"
      ];
    })
    (lib.mkRemovedOptionModule [ "nix" "daemonNiceLevel" ] "Consider nix.daemonCPUSchedPolicy instead.")
  ];

  ###### interface

  options = {

    nix = {

      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to enable Nix.
          Disabling Nix makes the system hard to modify and the Nix programs and configuration will not be made available by NixOS itself.
        '';
      };

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.nix;
        defaultText = lib.literalExpression "pkgs.nix";
        description = ''
          This option specifies the Nix package instance to use throughout the system.
        '';
      };

      daemonCPUSchedPolicy = lib.mkOption {
        type = lib.types.enum [
          "other"
          "batch"
          "idle"
        ];
        default = "other";
        example = "batch";
        description = ''
          Nix daemon process CPU scheduling policy. This policy propagates to
          build processes. `other` is the default scheduling
          policy for regular tasks. The `batch` policy is
          similar to `other`, but optimised for
          non-interactive tasks. `idle` is for extremely
          low-priority tasks that should only be run when no other task
          requires CPU time.

          Please note that while using the `idle` policy may
          greatly improve responsiveness of a system performing expensive
          builds, it may also slow down and potentially starve crucial
          configuration updates during load.

          `idle` may therefore be a sensible policy for
          systems that experience only intermittent phases of high CPU load,
          such as desktop or portable computers used interactively. Other
          systems should use the `other` or
          `batch` policy instead.

          For more fine-grained resource control, please refer to
          {manpage}`systemd.resource-control(5)` and adjust
          {option}`systemd.services.nix-daemon` directly.
        '';
      };

      daemonIOSchedClass = lib.mkOption {
        type = lib.types.enum [
          "best-effort"
          "idle"
        ];
        default = "best-effort";
        example = "idle";
        description = ''
          Nix daemon process I/O scheduling class. This class propagates to
          build processes. `best-effort` is the default
          class for regular tasks. The `idle` class is for
          extremely low-priority tasks that should only perform I/O when no
          other task does.

          Please note that while using the `idle` scheduling
          class can improve responsiveness of a system performing expensive
          builds, it might also slow down or starve crucial configuration
          updates during load.

          `idle` may therefore be a sensible class for
          systems that experience only intermittent phases of high I/O load,
          such as desktop or portable computers used interactively. Other
          systems should use the `best-effort` class.
        '';
      };

      daemonIOSchedPriority = lib.mkOption {
        type = lib.types.int;
        default = 4;
        example = 1;
        description = ''
          Nix daemon process I/O scheduling priority. This priority propagates
          to build processes. The supported priorities depend on the
          scheduling policy: With idle, priorities are not used in scheduling
          decisions. best-effort supports values in the range 0 (high) to 7
          (low).
        '';
      };

      # Environment variables for running Nix.
      envVars = lib.mkOption {
        type = lib.types.attrs;
        internal = true;
        default = { };
        description = "Environment variables used by Nix.";
      };

      nrBuildUsers = lib.mkOption {
        type = lib.types.int;
        description = ''
          Number of `nixbld` user accounts created to
          perform secure concurrent builds.  If you receive an error
          message saying that “all build users are currently in use”,
          you should increase this value.
        '';
      };
    };
  };

  ###### implementation

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      nixPackage
      pkgs.nix-info
    ]
    ++ lib.optional (config.programs.bash.completion.enable) pkgs.nix-bash-completions;

    systemd.packages = [ nixPackage ];

    systemd.tmpfiles = lib.mkMerge [
      (lib.mkIf (isNixAtLeast "2.8") {
        packages = [ nixPackage ];
      })
      (lib.mkIf (!isNixAtLeast "2.8") {
        rules = [
          "d /nix/var/nix/daemon-socket 0755 root root - -"
        ];
      })
    ];

    systemd.sockets.nix-daemon.wantedBy = [ "sockets.target" ];

    systemd.services.nix-daemon = {
      path = [
        nixPackage
        pkgs.util-linux
        config.programs.ssh.package
      ]
      ++ lib.optionals cfg.distributedBuilds [ pkgs.gzip ];

      environment =
        cfg.envVars
        // {
          CURL_CA_BUNDLE = config.security.pki.caBundle;
        }
        // config.networking.proxy.envVars;

      unitConfig.RequiresMountsFor = "/nix/store";

      serviceConfig = {
        CPUSchedulingPolicy = cfg.daemonCPUSchedPolicy;
        IOSchedulingClass = cfg.daemonIOSchedClass;
        IOSchedulingPriority = cfg.daemonIOSchedPriority;
        LimitNOFILE = 1048576;
        Delegate = "yes";
        DelegateSubgroup = "supervisor";
      };

      restartTriggers = [ config.environment.etc."nix/nix.conf".source ];

      # `stopIfChanged = false` changes to switch behavior
      # from   stop -> update units -> start
      #   to   update units -> restart
      #
      # The `stopIfChanged` setting therefore controls a trade-off between a
      # more predictable lifecycle, which runs the correct "version" of
      # the `ExecStop` line, and on the other hand the availability of
      # sockets during the switch, as the effectiveness of the stop operation
      # depends on the socket being stopped as well.
      #
      # As `nix-daemon.service` does not make use of `ExecStop`, we prefer
      # to keep the socket up and available. This is important for machines
      # that run Nix-based services, such as automated build, test, and deploy
      # services, that expect the daemon socket to be available at all times.
      #
      # Notably, the Nix client does not retry on failure to connect to the
      # daemon socket, and the in-process RemoteStore instance will disable
      # itself. This makes retries infeasible even for services that are
      # aware of the issue. Failure to connect can affect not only new client
      # processes, but also new RemoteStore instances in existing processes,
      # as well as existing RemoteStore instances that have not saturated
      # their connection pool.
      #
      # Also note that `stopIfChanged = true` does not kill existing
      # connection handling daemons, as one might wish to happen before a
      # breaking Nix upgrade (which is rare). The daemon forks that handle
      # the individual connections split off into their own sessions, causing
      # them not to be stopped by systemd.
      # If a Nix upgrade does require all existing daemon processes to stop,
      # nix-daemon must do so on its own accord, and only when the new version
      # starts and detects that Nix's persistent state needs an upgrade.
      stopIfChanged = false;

    };

    # Set up the environment variables for running Nix.
    environment.sessionVariables = cfg.envVars;

    nix.nrBuildUsers = lib.mkDefault (
      if cfg.settings.auto-allocate-uids or false then
        0
      else
        lib.max 32 (if cfg.settings.max-jobs == "auto" then 0 else cfg.settings.max-jobs)
    );

    users.users = nixbldUsers;

    services.displayManager.hiddenUsers = lib.attrNames nixbldUsers;

    # Legacy configuration conversion.
    nix.settings = lib.mkMerge [
      (lib.mkIf (isNixAtLeast "2.3pre") { sandbox-fallback = false; })
    ];

  };

}
