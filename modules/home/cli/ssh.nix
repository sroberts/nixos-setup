# SSH client configuration shared across all hosts
{ systemSettings, ... }:
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = {
      "lab" = {
        hostname = "10.85.13.19";
        user = systemSettings.username;
      };
    };
  };
}
