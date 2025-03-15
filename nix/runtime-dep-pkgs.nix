{lib, pkgs, nvidiaPackage} : ((with pkgs; [
    which
    gawk
    procps
  ]) ++ lib.optionals (nvidiaPackage != null) nvidiaPackage)