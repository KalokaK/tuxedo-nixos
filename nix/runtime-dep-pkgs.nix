{lib, pkgs, nvidiaPackage} : ((with pkgs; [
    which
    gawk
    procps
  ]) ++ lib.optional (nvidiaPackage != null) nvidiaPackage)