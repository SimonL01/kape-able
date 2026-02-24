# clean-cli.ps1

$defs = @{
  'antivirus.cli' = $true
  'passwords.cli' = $true
  'mft.cli'       = $true
  'cloud.cli'     = $true
  'messaging.cli' = $true
  'remote_access_vpn.cli' = $true
  'virtualization_wsl_linux.cli' = $true
  'browsers.cli' = $true
  'email.cli' = $true
  'file_managers.cli' = $true
  'file_transfer.cli' = $true
  'media_viewers.cli' = $true
  'dev_sysadmin_tools.cli' = $true
  'backup_restore.cli' = $true
  'p2p_usenet.cli' = $true
  'windows_artifacts.cli' = $true
  'triage_collections.cli' = $true
  'webservers_logs.cli' = $true
  'productivity_notes.cli' = $true
  'big_kape.cli' = $true
}

foreach ($name in $defs.Keys) {
    if (Test-Path $name) {
        Remove-Item $name -Force
        Write-Host "Removed $name"
    }
}