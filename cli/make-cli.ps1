# Run: .\make-cli.ps1
# Produces:
#  - per-preset .cli files (one line each, like before)
#  - big_kape.cli (one line per target)

$base = @(
  '--tsource %1',
  '--tdest %2\%d-%m'
)

$footer = @(
  '--zip %3'
)

$defs = @{
  'antivirus.cli'                = 'Antivirus,Avast,AVG,AviraAVLogs,Bitdefender,Combofix,Cybereason,Emsisoft,ESET,FSecure,HitmanPro,Malwarebytes,McAfee,McAfee_ePO,RogueKiller,SecureAge,SentinelOne,Sophos,SUPERAntiSpyware,Symantec_AV_Logs,TotalAV,TrendMicro,VIPRE,Webroot,WinDefendDetectionHist,WindowsDefender';
  'passwords.cli'                = '1Password';
  'mft.cli'                      = '$MFT';
  'cloud.cli'                    = 'BoxDrive_Metadata,BoxDrive_UserFiles,CloudStorage_All,CloudStorage_Metadata,CloudStorage_OneDriveExplorer,Dropbox_Metadata,Dropbox_UserFiles,GoogleDrive_Metadata,GoogleDriveBackupSync_UserFiles,OneDrive_Metadata,OneDrive_UserFiles,pCloudDatabase,SugarSync';
  'messaging.cli'                = 'CiscoJabber,ConfluenceLogs,Discord,HexChat,IceChat,Mattermost,MicrosoftTeams,mIRC,MessagingClients,IRCClients,Signal,Skype,Slack,Telegram,Viber,WhatsApp,WindowsYourPhone,Zoom';
  'remote_access_vpn.cli'        = 'Ammyy,AnyDesk,AteraAgent,Kaseya,LogMeIn,mRemoteNG,OpenSSHClient,OpenSSHServer,OpenVPNClient,ProtonVPN,Radmin,RemoteAdmin,RemoteUtilities_app,ScreenConnect,Splashtop,SupremoRemoteDesktop,TeamViewerLogs,Ultraviewer,VNCLogs';
  'virtualization_wsl_linux.cli' = 'VirtualBox,VirtualBoxConfig,VirtualBoxLogs,VirtualBoxMemory,VirtualDisks,VMware,VMwareInventory,VMwareMemory,WSL,WindowsSubsystemforAndroid,Debian,Kali,openSUSE,SUSELinuxEnterpriseServer,Ubuntu';
  'browsers.cli'                 = 'BraveBrowser,BrowserCache,Chrome,ChromeExtensions,ChromeFileSystem,Edge,EdgeChromium,Firefox,InternetExplorer,Opera,PuffinSecureBrowser,WebBrowsers';
  'email.cli'                    = 'Exchange,ExchangeClientAccess,ExchangeCve-2021-26855,ExchangeTransport,OutlookPSTOST,Thunderbird';
  'file_managers.cli'            = 'DirectoryOpus,DoubleCommander,EFCommander,Everything (VoidTools),FileExplorerReplacements,FreeCommander,MidnightCommander,MultiCommander,OneCommander,Q-Dir,SpeedCommander,TablacusExplorer,TotalCommander,TreeSize,XYplorer';
  'file_transfer.cli'            = 'AsperaConnect,FTPClients,FileZillaClient,FileZillaServer,FreeDownloadManager,FreeFileSync,JDownloader2,PeaZip,ShareX,TeraCopy,WinSCP';
  'media_viewers.cli'            = '4KVideoDownloader,GoogleEarth,IrfanView,MediaMonkey,SumatraPDF,VLC Media Player';
  'dev_sysadmin_tools.cli'       = 'HeidiSQL,JavaWebCache,Nessus,Notepad++,PowerShellConsole,QFinderPro (QNAP),SiemensTIA,Snagit,SublimeText';
  'backup_restore.cli'           = 'AcronisTrueImage,MacriumReflect,iTunesBackup,XPRestorePoints';
  'p2p_usenet.cli'               = 'BitTorrent,DC++,Freenet,FrostWire,Gigatribe,NewsbinPro,Newsleecher,Nicotine++,NZBGet,P2PClients,qBittorrent,SABnbzd,Shareaza,Soulseek,TorrentClients,Torrents,uTorrent,Usenet,UsenetClients';
  'windows_artifacts.cli'        = '$Boot,$J,$LogFile,$MFT,$MFTMirr,$SDS,$T,Amcache,AppCompatPCA,ApplicationEvents,AssetAdvisorLog,BCD,BITS,CertUtil,EncapsulationLogging,EventLogs,EventLogs-RDP,EventTraceLogs,EventTranscriptDB,EvidenceOfExecution,FileSystem,GroupPolicy,LinuxOnWindowsProfileFiles,LNKFilesAndJumpLists,LogFiles,MemoryFiles,MOF,NETCLRUsageLogs,OfficeAutosave,OfficeDiagnostics,OfficeDocumentCache,Prefetch,RDPCache,RDPLogs,RecentFileCache,RecycleBin,RecycleBin_DataFiles,RecycleBin_InfoFiles,RegistryHives,RegistryHivesOther,RegistryHivesSystem,RegistryHivesUser,RoamingProfile,SDB,ScheduledTasks,SignatureCatalog,SnipAndSketch,SRUM,StartupFolders,StartupInfo,SUM,Syscache,ThumbCache,USBDetective,USBDevicesLogs,VirtualDisks,WBEM,WER,WindowsFirewall,WindowsIndexSearch,WindowsNotificationsDB,WindowsOSUpgradeArtifacts,WindowsPowerDiagnostics,WindowsTelemetryDiagnosticsLegacy,WindowsTimeline';
  'triage_collections.cli'       = '!BasicCollection,!SANS_Triage,CombinedLogs,KapeTriage,MiniTimelineCollection,ServerTriage,SOFELK,SQLiteDatabases';
  'webservers_logs.cli'          = 'ApacheAccessLog,IISLogFiles,ManageEngineLogs,MSSQLErrorLog,NGINXLogs,WebServers';
  'productivity_notes.cli'       = 'AceText,ClipboardMaster,Evernote,MicrosoftOneNote,MicrosoftStickyNotes,MicrosoftToDo,Fences';
}

function Normalize-NameForPath([string]$t) {
    if ($t.StartsWith('!')) { return $t.Substring(1) }
    return $t
}

function Quote-TargetForSingleLine([string]$t) {
  # For single-target lines:
  # - KAPE artifact tokens like $MFT should be unquoted
  # - Anything else quoted only if it contains spaces
  if ($t.StartsWith('$')) { return $t }
  
  # If target starts with bang, escape it for CMD
  if ($t.StartsWith('!')) {
      $escaped = '^!' + $t.Substring(1)
      return $escaped
  }

  if ($t -match '\s') { return '"' + $t + '"' }
  return $t
}

function Quote-TargetListForPreset([string]$list) {
  # Quote if the list contains spaces or commas (multi-target lists always need quotes)
  # Single bare tokens starting with $ (like $MFT alone) stay unquoted
  if ($list -match '[,\s]') { return '"' + $list + '"' }
  return $list
}

function Sanitize-ForPath([string]$name) {
  # Make target safe-ish for folder/file names (Windows):
  # Replace invalid path chars with underscore; keep parentheses
  $invalid = [IO.Path]::GetInvalidFileNameChars()
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $name.ToCharArray()) {
    if ($invalid -contains $ch) { [void]$sb.Append('_') }
    else { [void]$sb.Append($ch) }
  }
  # Optional: collapse spaces to underscore (comment out if you want spaces)
  return ($sb.ToString() -replace '\s+', '_')
}

# Where to write output
$outDir = $PSScriptRoot
$bigPath = Join-Path $outDir 'big_kape.cli'

# Start fresh
if (Test-Path $bigPath) { Remove-Item -Force $bigPath }

foreach ($name in $defs.Keys) {
  $targetList = [string]$defs[$name]
  $presetName = [IO.Path]::GetFileNameWithoutExtension($name)

  # --- 1) Write the per-preset .cli (same as your current behavior) ---
  $targetPart = '--target ' + (Quote-TargetListForPreset $targetList)
  $oneLine = @($base + $targetPart + $footer) -join ' '
  $outPath = Join-Path $outDir $name
  Set-Content -Path $outPath -Encoding ASCII -NoNewline -Value $oneLine
  Write-Host "Wrote $name"

  # --- 2) Append to big_kape.cli: one line per target ---
  # If list starts with "$" and contains commas, we still split and output one per token.
  # If it's a single "$MFT" (no comma), it's just one line.
  $targets = $targetList -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

  foreach ($t in $targets) {
    $tForCmd = Quote-TargetForSingleLine $t

    # Build a tdest that includes preset + target + date
    # Example: %2antivirus\Avast_%d-%m
    $pathName = Normalize-NameForPath($t) # strip leading '!'
    $safeT = Sanitize-ForPath $pathName
    $tdest = '--tdest %2\' + $presetName + '\' + $safeT + '_%d-%m'

    $line = @(
      '--tsource %1',
      $tdest,
      '--target' + $tForCmd,
      '--zip %3'
    ) -join ' '

    Add-Content -Path $bigPath -Encoding ASCII -Value $line
  }
}

Write-Host "Wrote big_kape.cli"
