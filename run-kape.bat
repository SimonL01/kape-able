@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ----------------------------------------------------------------------
REM run-kape.bat
REM - Selects a cli\*.cli preset by name/prefix
REM - Materializes tokens %%1..%%8 and %%d %%m %%Y %%H %%M into _kape.cli
REM - Executes ONE KAPE run PER TARGET (splits comma-separated --target lists)
REM - Prints [OK]/[WARN]/[FAIL] per target and writes _kape.status.csv
REM - Supports optional /parallel and /nozip control flags
REM ----------------------------------------------------------------------

REM ===== ANSI colors (safe ASCII banner) =====
for /f "delims=" %%e in ('echo prompt $E^|cmd') do set "ESC=%%e"
set "RST=%ESC%[0m"
set "BOLD=%ESC%[1m"
set "DIM=%ESC%[2m"
set "RED=%ESC%[31m"
set "GRN=%ESC%[32m"
set "CYN=%ESC%[36m"
set "WHT=%ESC%[37m"
set "YEL=%ESC%[33m"

REM Bright variants
set "BRED=%ESC%[91m"
set "BGRN=%ESC%[92m"
set "BCYN=%ESC%[96m"
set "BMAG=%ESC%[95m"
set "BYEL=%ESC%[93m"
if not defined KAPE_MIN_FREE_GB set "KAPE_MIN_FREE_GB=20"
if not defined KAPE_MAX_PARALLEL set "KAPE_MAX_PARALLEL=4"
if not defined KAPE_USE_EXTERNAL_TOOLS set "KAPE_USE_EXTERNAL_TOOLS=1"
if not defined KAPE_DATE_ORDER set "KAPE_DATE_ORDER=DMY"

REM --- Paths ---
set "SCRIPT_DIR=%~dp0"
set "CLI_DIR=%SCRIPT_DIR%cli"

REM If KAPE_TMP_DIR is set by the wrapper, write _kape.cli & status there
if defined KAPE_TMP_DIR (
  set "TARGET=%KAPE_TMP_DIR%_kape.cli"
  set "STATUS_CSV=%KAPE_TMP_DIR%_kape.status.csv"
) else (
  set "TMPBASE=%TEMP%\kape_%RANDOM%%RANDOM%"
  if not exist "%TMPBASE%" mkdir "%TMPBASE%" >nul 2>&1
  set "TARGET=%TMPBASE%\_kape.cli"
  set "STATUS_CSV=%TMPBASE%\_kape.status.csv"
)
set "KAPE_EXE=%SCRIPT_DIR%kape.exe"

if not exist "%CLI_DIR%" (
  echo [%BRED%ERROR%RST%] CLI folder not found: "%CLI_DIR%"
  exit /b 5
)

REM --- Arguments ---
set "ARG1=%~1"
set "KAPE_ORIG_ARG1=%~1"
set "KAPE_ORIG_ARG2=%~2"
set "KAPE_ORIG_ARG3=%~3"
set "KAPE_ORIG_ARG4=%~4"
set "KAPE_ORIG_ARG5=%~5"
set "KAPE_ORIG_ARG6=%~6"
set "KAPE_ORIG_ARG7=%~7"
set "KAPE_ORIG_ARG8=%~8"
set "KAPE_ORIG_ARG9=%~9"
set "PARALLEL_FLAG="
set "NOZIP_FLAG="

if /i "%ARG1%"=="/?"      set "ARG1=/help"
if /i "%ARG1%"=="-h"      set "ARG1=/help"
if /i "%ARG1%"=="--help"  set "ARG1=/help"
if /i "%ARG1%"=="/help" (
    call :ShowUsage
    exit /b 0
)

if /i "%ARG1%"=="-l"       set "ARG1=/list"
if /i "%ARG1%"=="--list"   set "ARG1=/list"
if /i "%ARG1%"=="/list" (
    call :ShowConfigs
    exit /b 0
)

if /i "%ARG1%"=="-b"       set "ARG1=/banner"
if /i "%ARG1%"=="--banner" set "ARG1=/banner"
if /i "%ARG1%"=="/banner" (
    call :Show_Banner
    exit /b 0
)

REM --- Determine selection (name or interactive) ---
set "CHOICE=%ARG1%"

if "%CHOICE%"=="" (
    echo(
    echo No argument provided. Available configurations:
    call :ShowConfigs
    echo(
    set /p "CHOICE=Type a name (without .cli) or a prefix, then ENTER: "
    if not defined CHOICE (
        echo [%BRED%ERROR%RST%] No selection made.
        exit /b 1
    )
) else (
    REM Strip optional .cli if the user provided it
    if /i "%CHOICE:~-4%"==".cli" set "CHOICE=%CHOICE:~0,-4%"
)

REM --- Resolve MATCH by precedence ---
set "MATCH="

if exist "%CLI_DIR%\%CHOICE%_kape.cli" (
    set "MATCH=%CHOICE%_kape.cli"
) else if exist "%CLI_DIR%\%CHOICE%.cli" (
    set "MATCH=%CHOICE%.cli"
) else (
    for /f "delims=" %%F in ('dir /b /a:-d "%CLI_DIR%\%CHOICE%*.cli" 2^>nul') do (
        set "MATCH=%%F"
        goto :FoundMatch
    )
)

if not defined MATCH (
    echo [%BRED%ERROR%RST%] No .cli matched "%CHOICE%".
    echo         Expected one of:
    echo           - "%CHOICE%_kape.cli"
    echo           - "%CHOICE%.cli"
    echo           - or any file starting with "%CHOICE%"
    echo         Tip: run with /list to see available configurations.
    exit /b 2
)

:FoundMatch
call :MakeSafeName "%MATCH%" KAPE_PRESET_SAFE

REM --- Capture extra arguments for template tokens %1..%9 ---
REM     %~2 becomes ARG1 (template %1), %~3 -> ARG2 (template %2), etc.
set "ARG1=%~2"
set "ARG2=%~3"
set "ARG3=%~4"
set "ARG4=%~5"
set "ARG5=%~6"
set "ARG6=%~7"
set "ARG7=%~8"
set "ARG8=%~9"

REM Optional control flags can appear after DEST_ROOT, with or without ZIP_TAG
if /i "%ARG3%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG3="
if /i "%ARG4%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG4="
if /i "%ARG5%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG5="
if /i "%ARG6%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG6="
if /i "%ARG7%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG7="
if /i "%ARG8%"=="/parallel" set "PARALLEL_FLAG=/parallel" & set "ARG8="

if /i "%ARG3%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG3="
if /i "%ARG4%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG4="
if /i "%ARG5%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG5="
if /i "%ARG6%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG6="
if /i "%ARG7%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG7="
if /i "%ARG8%"=="/batonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG8="

if /i "%ARG3%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG3="
if /i "%ARG4%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG4="
if /i "%ARG5%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG5="
if /i "%ARG6%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG6="
if /i "%ARG7%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG7="
if /i "%ARG8%"=="/batchonly" set "KAPE_USE_EXTERNAL_TOOLS=0" & set "ARG8="

if /i "%ARG3%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG3="
if /i "%ARG4%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG4="
if /i "%ARG5%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG5="
if /i "%ARG6%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG6="
if /i "%ARG7%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG7="
if /i "%ARG8%"=="/external" set "KAPE_USE_EXTERNAL_TOOLS=1" & set "ARG8="

if /i "%ARG3%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG3="
if /i "%ARG4%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG4="
if /i "%ARG5%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG5="
if /i "%ARG6%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG6="
if /i "%ARG7%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG7="
if /i "%ARG8%"=="/nozip" set "NOZIP_FLAG=1" & set "ARG8="

if /i "%ARG3%"=="/raw" set "NOZIP_FLAG=1" & set "ARG3="
if /i "%ARG4%"=="/raw" set "NOZIP_FLAG=1" & set "ARG4="
if /i "%ARG5%"=="/raw" set "NOZIP_FLAG=1" & set "ARG5="
if /i "%ARG6%"=="/raw" set "NOZIP_FLAG=1" & set "ARG6="
if /i "%ARG7%"=="/raw" set "NOZIP_FLAG=1" & set "ARG7="
if /i "%ARG8%"=="/raw" set "NOZIP_FLAG=1" & set "ARG8="

REM Optional: a token starting with "/parallel" as arg 5-9 enables parallel exec
if /i "%~5"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~6"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~7"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~8"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~9"=="/parallel" set "PARALLEL_FLAG=/parallel"

if not defined ARG1 (
    echo [%BRED%ERROR%RST%] Missing source path.
    call :ShowUsage
    exit /b 6
)
if not defined ARG2 (
    echo [%BRED%ERROR%RST%] Missing destination root.
    call :ShowUsage
    exit /b 6
)
if not defined ARG3 if not defined NOZIP_FLAG (
    echo [%BRED%ERROR%RST%] Missing ZIP tag.
    call :ShowUsage
    exit /b 6
)
if defined NOZIP_FLAG (
    set "KAPE_EXPECT_ZIP=0"
) else (
    set "KAPE_EXPECT_ZIP=1"
)

REM --- Normalize drive-root-ish tokens (quality-of-life) ---
for %%V in (ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8) do (
  for /f "tokens=1,* delims==" %%K in ('set %%V 2^>nul') do (
    if defined %%K (
      set "TMP=!%%K!"
      if "!TMP:~1,1!"==":" if "!TMP:~2!"=="" set "%%K=!TMP!\"
    )
  )
)

for %%I in ("%ARG2%") do set "CASE_ROOT=%%~fI"
if not exist "%CASE_ROOT%" mkdir "%CASE_ROOT%" >nul 2>&1
set "CASE_STATUS_CSV=%CASE_ROOT%\_kape.status.csv"
set "HASH_MANIFEST=%CASE_ROOT%\SHA256SUMS.txt"
set "SYSTEM_CONTEXT_FILE=%CASE_ROOT%\SystemContext.txt"
set "SUMMARY_FILE=%CASE_ROOT%\_kape.summary.txt"
set "CONSOLE_TRANSCRIPT=%CASE_ROOT%\_kape.console.txt"
set "KAPE_CONSOLE_TRANSCRIPT=%CONSOLE_TRANSCRIPT%"
set "KAPE_CASE_ROOT=%CASE_ROOT%"
set "KAPE_PRESET_NAME=%MATCH%"

call :NormalizeExternalToolsFlag

if "%KAPE_USE_EXTERNAL_TOOLS%"=="1" if /i not "%KAPE_CONSOLE_TEE_ACTIVE%"=="1" (
  set "KAPE_SELF=%~f0"
  powershell -NoProfile -Command ^
    "$env:KAPE_CONSOLE_TEE_ACTIVE='1'; $argsList = @(); foreach ($i in 1..9) { $name = 'KAPE_ORIG_ARG' + $i; $value = [Environment]::GetEnvironmentVariable($name); if ($null -ne $value -and $value -ne '') { $argsList += $value } }; & $env:KAPE_SELF @argsList 2>&1 | Tee-Object -LiteralPath $env:KAPE_CONSOLE_TRANSCRIPT; $exitCode = $LASTEXITCODE; exit $exitCode"
  exit /b !ERRORLEVEL!
)

echo(
echo [%BYEL%INFO%RST%] Using CLI preset: "%MATCH%"
if "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
  echo [%BYEL%INFO%RST%] Extended helper mode enabled.
) else (
  echo [%BYEL%INFO%RST%] Batch-native mode enabled. Transcript, hashing, free-space, and external helper commands are disabled.
)
if defined NOZIP_FLAG (
  echo [%BYEL%INFO%RST%] Raw collection mode enabled. Any --zip option from the preset will be ignored.
)

call :NormalizeParallelLimit
if /i "%PARALLEL_FLAG%"=="/parallel" (
  echo [%BYEL%INFO%RST%] Parallel collection enabled. Max concurrent jobs: %KAPE_MAX_PARALLEL%
)

call :RequireAdmin
if errorlevel 1 exit /b 7

call :CheckFreeSpace "%CASE_ROOT%"
if errorlevel 1 exit /b 8

REM --- Compute date/time (DD, MM, YYYY, HH, MIN) ---
call :GetNow

call :CaptureSystemContext
if errorlevel 1 (
    echo [%BRED%ERROR%RST%] Failed to capture system context in "%SYSTEM_CONTEXT_FILE%".
    exit /b 9
)

REM --- Materialize the template into TARGET (tokens resolved) ---
if exist "%TARGET%" del "%TARGET%" >nul 2>&1
setlocal DisableDelayedExpansion

if not exist "%CLI_DIR%\%MATCH%" (
    echo [%BRED%ERROR%RST%] Template not found: "%CLI_DIR%\%MATCH%"
    exit /b 3
)

> "%TARGET%" (
  for /f "usebackq delims=" %%L in ("%CLI_DIR%\%MATCH%") do (
    set "line=%%L"
    setlocal EnableDelayedExpansion
    set "work=!line!"
    REM Replace %%1..%%8
    set "work=!work:%%1=%ARG1%!"
    set "work=!work:%%2=%ARG2%!"
    set "work=!work:%%3=%ARG3%!"
    set "work=!work:%%4=%ARG4%!"
    set "work=!work:%%5=%ARG5%!"
    set "work=!work:%%6=%ARG6%!"
    set "work=!work:%%7=%ARG7%!"
    set "work=!work:%%8=%ARG8%!"
    REM Replace doubled-%% date/time tokens
    set "work=!work:%%d=%DD%!"
    set "work=!work:%%m=%MM%!"
    set "work=!work:%%Y=%YYYY%!"
    set "work=!work:%%H=%HH%!"
    set "work=!work:%%M=%MIN%!"
    echo(!work!
    endlocal
  )
)
endlocal

if errorlevel 1 (
    echo [%BRED%ERROR%RST%] Failed to process template "%CLI_DIR%\%MATCH%" into "%TARGET%".
    exit /b 3
)

echo(
echo [%BYEL%DEBUG%RST%] Materialized KAPE CLI:
type "%TARGET%"

if not exist "%KAPE_EXE%" (
    echo [%BRED%ERROR%RST%] kape.exe not found at "%KAPE_EXE%".
    exit /b 4
)

REM --- Per-run temp job directory (unique so stale files never mix) ---
set "JOBSDIR=%CASE_ROOT%\_kape_jobs\%KAPE_PRESET_SAFE%_%YYYY%%MM%%DD%_%HH%%MIN%_%RANDOM%"
mkdir "%JOBSDIR%" >nul 2>&1

REM --- Prepare status CSV and run per target ---
> "%STATUS_CSV%" echo target,line_index,rc,log_ok,zip_found,log_file,zip_path

set "ESC=" & for /F "delims=" %%e in ('echo prompt $E^|cmd') do set "ESC=%%e"

setlocal EnableDelayedExpansion
set "LINEIDX=0"

set "JOBS="

for /f "usebackq delims=" %%A in ("%TARGET%") do (
  set /a LINEIDX+=1
  set "_KAPE_LINE=%%A"
  call :RunPerTarget "!LINEIDX!" "%PARALLEL_FLAG%"
)

REM If parallel, wait for all children and then print statuses
if /i "%PARALLEL_FLAG%"=="/parallel" (
    call :WaitForAll
    call :RetryVss
)

call :FinalizeCaseOutput
if errorlevel 1 exit /b 10

echo(
echo [%BYEL%INFO%RST%] Completed processing of "%MATCH%".
echo [%BYEL%INFO%RST%] Status CSV: "%CASE_STATUS_CSV%"
echo [%BYEL%INFO%RST%] SHA256 manifest: "%HASH_MANIFEST%"
echo [%BYEL%INFO%RST%] System context: "%SYSTEM_CONTEXT_FILE%"
echo [%BYEL%INFO%RST%] Summary file: "%SUMMARY_FILE%"
if "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
  echo [%BYEL%INFO%RST%] Console transcript: "%CONSOLE_TRANSCRIPT%"
) else (
  echo [%BYEL%INFO%RST%] Console transcript: disabled in batch-native mode.
)
if defined SUM_TOTAL (
  echo [%BYEL%INFO%RST%] Final summary: total=!SUM_TOTAL! ok=!SUM_OK! warn=!SUM_WARN! fail=!SUM_FAIL!
)
exit /b 0


REM ======================================================================
REM Subroutines
REM ======================================================================

:RunPerTarget
REM _KAPE_LINE = full line (env var), %~1 = line index, %~2 = /parallel or empty
setlocal EnableDelayedExpansion
set "LINE=!_KAPE_LINE!"
set "IDX=%~1"
set "DO_PAR=%~2"

REM Split LINE on " to find quoted --target "LIST", or fall back to unquoted token
set "PREFIX="
set "TGT_RAW="
set "SUFFIX="
set "UNQUOTED_TARGET="
set "_PARSE_TMP=%TEMP%\kape_parse_%RANDOM%.tmp"
>"%_PARSE_TMP%" echo(!LINE!
for /f usebackq^ tokens^=1^,2^,3*^ delims^=^" %%A in ("%_PARSE_TMP%") do (
  set "PREFIX=%%A"
  set "TGT_RAW=%%B"
  set "SUFFIX=%%C"
)
del "%_PARSE_TMP%" >nul 2>&1

REM If no quoted target found, try unquoted: --target TOKEN
if not defined TGT_RAW (
  if not "!LINE:--target =!"=="!LINE!" (
    for /f "tokens=1" %%T in ("!LINE:*--target =!") do set "TGT_RAW=%%T"
    set "UNQUOTED_TARGET=1"
  )
)

if not defined TGT_RAW (
  set "_KAPE_LINE=!LINE!"
  call :RunOneTarget "!IDX!" "NO-TARGET" "!DO_PAR!"
  endlocal & exit /b 0
)

REM Unquoted single target: pass line as-is
if defined UNQUOTED_TARGET (
  set "_KAPE_LINE=!LINE!"
  call :RunOneTarget "!IDX!" "!TGT_RAW!" "!DO_PAR!"
  endlocal & exit /b 0
)

REM Quoted target list: split on commas and run once per target
set "REST=!TGT_RAW!"
:_rpt_next
for /f "tokens=1* delims=," %%A in ("!REST!") do (
  set "ONE=%%A"
  set "REST=%%B"
)
for /f "tokens=* delims= " %%X in ("!ONE!") do set "ONE=%%X"

set Q="
set "_KAPE_LINE=!PREFIX!!Q!!ONE!!Q!!SUFFIX!"
call :RunOneTarget "!IDX!" "!ONE!" "!DO_PAR!"

if defined REST goto :_rpt_next
endlocal & exit /b 0

:BuildLineWithoutTarget
REM Rebuild line with exactly one --target "one"
REM %~1 = original line, %~2 = target name, OUTVAR = var name to set
setlocal EnableDelayedExpansion
set "SRC=%~1"
set "ONE=%~2"

REM Use a marker to replace --target and its value, then insert back
REM First, extract the portion before --target
for /f "tokens=*" %%X in ("!SRC:--target*=MARKER!") do (
  set "BEFORE=%%X"
)

REM The BEFORE will have MARKER at the end
set "BEFORE=!BEFORE:MARKER=!"

REM Reconstruct: BEFORE + new --target
set "OUT=!BEFORE! --target !ONE!"

endlocal & set "%~3=%OUT%"
exit /b 0

:RunOneTarget
REM _KAPE_LINE = finalized one-target line (env var)
REM %~1 = line index
REM %~2 = target name
REM %~3 = /parallel?
setlocal EnableDelayedExpansion
set "CMD_LINE=!_KAPE_LINE!"
set "IDX=%~1"
set "TGT=%~2"
set "DO_PAR=%~3"

call :RestoreBangTarget CMD_LINE "%TGT%"
if defined NOZIP_FLAG call :StripZipArgument CMD_LINE

REM Extract --tdest (first token after it)
set "DEST="
if not "!CMD_LINE:--tdest =!"=="!CMD_LINE!" (
  for /f "tokens=1" %%E in ("!CMD_LINE:*--tdest =!") do set "DEST=%%E"
)
set "DEST=!DEST:\"=!"
if not defined DEST set "DEST=%CD%"

for %%I in ("!DEST!") do set "DEST=%%~fI"
if not exist "!DEST!" mkdir "!DEST!" >nul 2>&1

call :GetNow
set "STAMP=!YYYY!!MM!!DD!_!HH!!MIN!"
call :MakeSafeName "!TGT!" SAFE_TGT
if not defined SAFE_TGT set "SAFE_TGT=NO_TARGET"
set "FILE_STEM=!KAPE_PRESET_SAFE!_L!IDX!_!SAFE_TGT!_!STAMP!_!RANDOM!"
set "LOG_ONE=!JOBSDIR!\!FILE_STEM!.log"
set "RCFILE=!JOBSDIR!\!FILE_STEM!.rc"
set "DESTFILE=!JOBSDIR!\!FILE_STEM!.dest"
set "JOBFILE=!JOBSDIR!\!FILE_STEM!.cmd"
set "TGTFILE=!JOBSDIR!\!FILE_STEM!.tgt"
echo(!DEST!>"!DESTFILE!"
echo(!CMD_LINE!>"!JOBSDIR!\!FILE_STEM!.args"
echo %TIME%>"!JOBSDIR!\!FILE_STEM!.start"
echo(!TGT!>"!TGTFILE!"
>  "!JOBFILE!" echo @echo off
>> "!JOBFILE!" echo setlocal EnableExtensions DisableDelayedExpansion
>> "!JOBFILE!" echo cd /d "%SCRIPT_DIR%"
call :AppendJobCommand "!JOBFILE!" CMD_LINE "!LOG_ONE!" "!RCFILE!"

if /i "!DO_PAR!"=="/parallel" (
  REM Throttle: wait until fewer than KAPE_MAX_PARALLEL jobs are running
  :throttle
  set "RUNNING=0"
  for %%J in ("!JOBSDIR!\*.cmd") do (
    if not exist "!JOBSDIR!\%%~nJ.rc" set /a RUNNING+=1
  )
  if !RUNNING! geq %KAPE_MAX_PARALLEL% (
    timeout /t 1 /nobreak >nul 2>nul
    goto :throttle
  )
  start "" /b cmd /c "!JOBFILE!"
  endlocal & exit /b 0
)

call "!JOBFILE!"
set /p RC=<"!RCFILE!" 2>nul
if not defined RC set "RC=1"

call :RenameDestinationLogs "!DEST!" "!TGT!" ""
call :AssessOne "!LOG_ONE!" "!DEST!" ZIPFOUND ZIPFILE OKLOG
>> "%STATUS_CSV%" echo !TGT!,!IDX!,!RC!,!OKLOG!,!ZIPFOUND!,"!LOG_ONE!","!ZIPFILE!"
call :DetermineOutcome "!RC!" "!OKLOG!" "!ZIPFOUND!" RESULT

if /i "!RESULT!"=="OK" (
  echo [ %ESC%[92mOK%ESC%[0m ] !TGT! RC=!RC! zip=!ZIPFOUND!
) else if /i "!RESULT!"=="WARN" (
  echo [ %ESC%[93mWARN%ESC%[0m ] !TGT! RC=!RC! logOK=!OKLOG! zip=!ZIPFOUND!
  echo        See "!LOG_ONE!"
) else (
  echo [ %ESC%[91mFAIL%ESC%[0m ] !TGT! RC=!RC! logOK=!OKLOG! zip=!ZIPFOUND!
  echo        See "!LOG_ONE!"
)

endlocal & exit /b 0

:RetryVss
REM Scan parallel-job results; for any that failed with a file-lock error,
REM re-run them once with --vss (sequentially) to bypass running-process locks.
REM Each .rc file is handled by :RetryVss_ProcessOne to keep nesting flat.
setlocal EnableDelayedExpansion
set "RETRY_COUNT=0"
for %%R in ("%JOBSDIR%\*.rc") do (
    call :RetryVss_ProcessOne "%%~fR" "%%~nR"
)
if "!RETRY_COUNT!"=="0" (
    echo([%BYEL%INFO%RST%] No file-lock errors detected; no VSS retry needed.
)
endlocal & exit /b 0

:RetryVss_ProcessOne
REM %~1 = full path to .rc file   %~2 = filename stem (no extension)
setlocal EnableDelayedExpansion
set "RCPATH=%~1"
set "NM=%~2"

REM Skip retry results from a previous pass
if not "%NM:_retry=%"=="%NM%" endlocal & exit /b 0

REM Read exit code – tokens=1 strips CR from CRLF
set "RCC="
for /f "usebackq tokens=1" %%v in ("%RCPATH%") do if not defined RCC set "RCC=%%v"
if not defined RCC set "RCC=1"

REM Only bother when the job actually failed
if "%RCC%"=="0" endlocal & exit /b 0

REM Check if the log mentions a file-lock error
set "STEM=%RCPATH:~0,-3%"
set "LOGF=%STEM%.log"
findstr /i /c:"IOException" /c:"WinIOError" /c:"being used by another process" "%LOGF%" >nul 2>&1
if errorlevel 1 endlocal & exit /b 0

REM Read original KAPE arguments (strip trailing CR from echo/CRLF)
set "ARGSF=%STEM%.args"
if not exist "%ARGSF%" endlocal & exit /b 0
set "ORIG_ARGS="
for /f "usebackq delims=" %%A in ("%ARGSF%") do if not defined ORIG_ARGS set "ORIG_ARGS=%%A"
if not defined ORIG_ARGS endlocal & exit /b 0

REM Append --vss if not already present
set "NEW_ARGS=%ORIG_ARGS%"
if "%NEW_ARGS:--vss=%"=="%NEW_ARGS%" set "NEW_ARGS=%NEW_ARGS% --vss"

REM Extract --tdest from the argument string
set "RDEST="
if not "%NEW_ARGS:--tdest =%"=="%NEW_ARGS%" (
    for /f "tokens=2" %%E in ("%NEW_ARGS%") do if not defined RDEST set "RDEST=%%E"
    for /f "tokens=1" %%E in ("%NEW_ARGS:*--tdest =%") do set "RDEST=%%E"
)
if not defined RDEST set "RDEST=%CD%"
for %%I in ("%RDEST%") do set "RDEST=%%~fI"

set /a RETRY_COUNT+=1
set "RLOG=%JOBSDIR%\%NM%_retry.log"
set "RETRY_TGT=%NM%"
if exist "%STEM%.tgt" (
    set "RETRY_TGT="
    for /f "usebackq delims=" %%A in ("%STEM%.tgt") do if not defined RETRY_TGT set "RETRY_TGT=%%A"
)

for /f "delims=" %%e in ('echo prompt $E^|cmd') do set "ESC=%%e"

echo(
echo [%BYEL%RETRY%RST%] !RETRY_TGT! -- file-lock error detected, retrying with --vss ...
"%KAPE_EXE%" %NEW_ARGS% 0<nul 1>"%RLOG%" 2>&1
set "RRC2=%ERRORLEVEL%"

call :RenameDestinationLogs "%RDEST%" "!RETRY_TGT!" "retry"
call :AssessOne "%RLOG%" "%RDEST%" RZIPFOUND RZIPFILE ROKLOG
>> "%STATUS_CSV%" echo !RETRY_TGT!_retry,0,%RRC2%,%ROKLOG%,%RZIPFOUND%,"%RLOG%","%RZIPFILE%"
call :DetermineOutcome "%RRC2%" "%ROKLOG%" "%RZIPFOUND%" RETRY_RESULT

if /i "%RETRY_RESULT%"=="OK" (
    echo [ %ESC%[92mOK%ESC%[0m ] !RETRY_TGT! (VSS retry) RC=%RRC2% zip=%RZIPFOUND%
) else if /i "%RETRY_RESULT%"=="WARN" (
    echo [ %ESC%[93mWARN%ESC%[0m ] !RETRY_TGT! (VSS retry) RC=%RRC2% logOK=%ROKLOG% zip=%RZIPFOUND%
    echo        See "%RLOG%"
) else (
    echo [ %ESC%[91mFAIL%ESC%[0m ] !RETRY_TGT! (VSS retry) RC=%RRC2% logOK=%ROKLOG% zip=%RZIPFOUND%
    echo        See "%RLOG%"
)
endlocal & set "RETRY_COUNT=%RETRY_COUNT%" & exit /b 0

:WaitForAll
REM Report each job as soon as its .rc appears, with elapsed time
setlocal EnableDelayedExpansion

set "EXPECTED=0"
for %%J in ("%JOBSDIR%\*.cmd") do set /a EXPECTED+=1
if !EXPECTED! equ 0 ( endlocal & exit /b 0 )

echo([%BYEL%INFO%RST%] Waiting for !EXPECTED! parallel job(s) to complete...

set "DONE=0"

:wfa_poll
for %%R in ("%JOBSDIR%\*.rc") do (
    set "_RN=%%~nR"
    REM Skip if already reported
    if not defined _seen_%%~nR (
        set "_seen_%%~nR=1"
        set "RCC="
        for /f "usebackq tokens=1" %%v in ("%%~fR") do if not defined RCC set "RCC=%%v"
        if not defined RCC set "RCC=1"
        set "LOGONE=%%~dpnR.log"
        set "DESTONE="
        for /f "usebackq delims=" %%d in ("%%~dpnR.dest") do if not defined DESTONE set "DESTONE=%%d"
        if not defined DESTONE set "DESTONE=%JOBSDIR%"
        set "TGTNAME=%%~nR"
        set "TGTNAME_FROM_FILE="
        if exist "%%~dpnR.tgt" (
            for /f "usebackq delims=" %%n in ("%%~dpnR.tgt") do if not defined TGTNAME_FROM_FILE set "TGTNAME_FROM_FILE=%%n"
        )
        if defined TGTNAME_FROM_FILE set "TGTNAME=!TGTNAME_FROM_FILE!"
        REM Compute elapsed time from .start file
        set "ELAPSED_STR="
        set "T0="
        if exist "%%~dpnR.start" (
            for /f "usebackq delims=" %%t in ("%%~dpnR.start") do if not defined T0 set "T0=%%t"
        )
        if defined T0 (
            set "_T0=!T0: =0!"
            set "_T1=!TIME: =0!"
            set /a "_S0=(10!_T0:~0,2!%%100)*3600+(10!_T0:~3,2!%%100)*60+(10!_T0:~6,2!%%100)"
            set /a "_S1=(10!_T1:~0,2!%%100)*3600+(10!_T1:~3,2!%%100)*60+(10!_T1:~6,2!%%100)"
            set /a "_EL=_S1-_S0"
            if !_EL! lss 0 set /a "_EL+=86400"
            if !_EL! geq 60 (
                set /a "_EM=_EL/60"
                set /a "_ES=_EL%%60"
                set "ELAPSED_STR=!_EM!m !_ES!s"
            ) else (
                set "ELAPSED_STR=!_EL!s"
            )
        )
        
        if not defined ELAPSED_STR set "ELAPSED_STR="
        
        call :RenameDestinationLogs "!DESTONE!" "!TGTNAME!" ""
        call :AssessOne "!LOGONE!" "!DESTONE!" ZIPFOUND ZIPFILE OKLOG
        >> "%STATUS_CSV%" echo !TGTNAME!,0,!RCC!,!OKLOG!,!ZIPFOUND!,"!LOGONE!","!ZIPFILE!"
        call :DetermineOutcome "!RCC!" "!OKLOG!" "!ZIPFOUND!" RESULT
        
        if /i "!RESULT!"=="OK" (
            if defined ELAPSED_STR if not "!ELAPSED_STR!"=="" (
                echo [ %ESC%[92mOK%ESC%[0m ] !TGTNAME! RC=!RCC! zip=!ZIPFOUND! time=!ELAPSED_STR!
            ) else (
                echo [ %ESC%[92mOK%ESC%[0m ] !TGTNAME! RC=!RCC! zip=!ZIPFOUND!
            )
        ) else if /i "!RESULT!"=="WARN" (
            if defined ELAPSED_STR if not "!ELAPSED_STR!"=="" (
                echo [ %ESC%[93mWARN%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND! time=!ELAPSED_STR!
            ) else (
                echo [ %ESC%[93mWARN%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND!
            )
            echo        See "!LOGONE!"
        ) else (
            if defined ELAPSED_STR if not "!ELAPSED_STR!"=="" (
                echo [ %ESC%[91mFAIL%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND! time=!ELAPSED_STR!
            ) else (
                echo [ %ESC%[91mFAIL%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND!
            )
            echo        See "!LOGONE!"
        )
        set /a DONE+=1
    )
)
if !DONE! lss !EXPECTED! (
    timeout /t 1 /nobreak >nul 2>nul
    goto :wfa_poll
)
endlocal & exit /b 0


:AssessOne
REM %~1=LOG_FILE  %~2=DEST_ROOTorFolder  out: ZIPFOUND var, ZIPFILE var, OKLOG var
setlocal EnableDelayedExpansion
set "LOGF=%~1"
set "DESTROOT=%~2"
set "OKLOG=false"
set "ZIP="
findstr /c:"Total execution time:" "%LOGF%" >nul 2>&1 && set "OKLOG=true"
if /i "!OKLOG!"=="false" (
  findstr /r /c:"Copied .* out of " "%LOGF%" >nul 2>&1 && set "OKLOG=true"
)
REM Look for zip anywhere below DESTROOT (line-specific --tdest child folder)
for /r "%DESTROOT%" %%Z in (*.zip) do (
  if not defined ZIP set "ZIP=%%~fZ"
)
set "ZIPFOUND=false"
if defined ZIP set "ZIPFOUND=true"
endlocal & (
  set "%~3=%ZIPFOUND%"
  set "%~4=%ZIP%"
  set "%~5=%OKLOG%"
)
exit /b 0

:RestoreBangTarget
REM %~1=variable name holding command line, %~2=plain target name
setlocal DisableDelayedExpansion
set "TARGET_NAME=%~2"
if not defined TARGET_NAME endlocal & exit /b 0
if "%TARGET_NAME:~0,2%"=="^!" set "TARGET_NAME=%TARGET_NAME:~2%"
if "%TARGET_NAME:~0,1%"=="!" set "TARGET_NAME=%TARGET_NAME:~1%"
if not defined TARGET_NAME endlocal & exit /b 0
dir /b /s /a:-d "%SCRIPT_DIR%Targets\!%TARGET_NAME%.tkape" >nul 2>&1
if errorlevel 1 endlocal & exit /b 0
call set "LINE=%%%~1%%"
if not defined LINE endlocal & exit /b 0
call set "LINE=%%LINE:--target %TARGET_NAME%=--target __KAPE_BANG__%TARGET_NAME%%%"
call set "LINE=%%LINE:--target !%TARGET_NAME%=--target __KAPE_BANG__%TARGET_NAME%%%"
call set "LINE=%%LINE:--target ^!%TARGET_NAME%=--target __KAPE_BANG__%TARGET_NAME%%%"
call set "LINE=%%LINE:--target \"%TARGET_NAME%\"=--target \"__KAPE_BANG__%TARGET_NAME%\"%%"
call set "LINE=%%LINE:--target \"!%TARGET_NAME%\"=--target \"__KAPE_BANG__%TARGET_NAME%\"%%"
call set "LINE=%%LINE:--target \"^!%TARGET_NAME%\"=--target \"__KAPE_BANG__%TARGET_NAME%\"%%"
endlocal & set "%~1=%LINE%" & exit /b 0

:AppendJobCommand
REM %~1=job file  %~2=variable name holding command line  %~3=log file  %~4=rc file
setlocal DisableDelayedExpansion
set "JOBFILE=%~1"
set "LOGFILE=%~3"
set "RCFILE=%~4"
call set "LINE=%%%~2%%"
if not defined LINE endlocal & exit /b 1
set "LINE=%LINE:__KAPE_BANG__=!%"
>> "%JOBFILE%" echo "%KAPE_EXE%" %LINE% 0^< nul 1^> "%LOGFILE%" 2^>^&1
>> "%JOBFILE%" echo (echo %%errorlevel%%)^> "%RCFILE%"
endlocal & exit /b 0

:RenameDestinationLogs
REM %~1=DEST folder  %~2=target name  %~3=optional suffix tag (e.g. retry)
setlocal EnableDelayedExpansion
set "DEST=%~1"
if not defined DEST endlocal & exit /b 0
if not exist "%DEST%" endlocal & exit /b 0
call :MakeSafeName "%~2" SAFE_TGT
if not defined SAFE_TGT set "SAFE_TGT=target"
set "PREFIX=!SAFE_TGT!"
if not "%~3"=="" set "PREFIX=!PREFIX!_%~3"
call :PrefixMatchingFiles "%DEST%" "*ConsoleLog*.*" "!PREFIX!"
call :PrefixMatchingFiles "%DEST%" "*CopyLog*.*" "!PREFIX!"
call :PrefixMatchingFiles "%DEST%" "*SkipLog*.*" "!PREFIX!"
endlocal & exit /b 0

:PrefixMatchingFiles
REM %~1=folder  %~2=wildcard pattern  %~3=prefix
setlocal EnableDelayedExpansion
set "DEST=%~1"
set "PATTERN=%~2"
set "PREFIX=%~3"
for /f "delims=" %%F in ('dir /b /a:-d "%DEST%\%PATTERN%" 2^>nul') do (
  echo(%%F| findstr /b /i /c:"!PREFIX!_" >nul
  if errorlevel 1 (
    call :PrefixOneFile "%DEST%\%%F" "!PREFIX!"
  )
)
endlocal & exit /b 0

:PrefixOneFile
REM %~1=full path to file  %~2=prefix to prepend
setlocal
set "FULL=%~1"
set "DIR=%~dp1"
set "OLD=%~nx1"
set "PREFIX=%~2"
set "NEW=%PREFIX%_%OLD%"
if /i "%OLD%"=="%NEW%" endlocal & exit /b 0
call :GetUniqueFileName "%DIR%" "%NEW%" UNIQUE_NAME
if /i not "%OLD%"=="%UNIQUE_NAME%" ren "%FULL%" "%UNIQUE_NAME%" >nul 2>&1
endlocal & exit /b 0

:GetUniqueFileName
REM %~1=directory  %~2=preferred filename  out: %~3=available filename
setlocal EnableDelayedExpansion
set "DIR=%~1"
set "NAME=%~2"
if not exist "%DIR%%NAME%" (
  endlocal & set "%~3=%~2" & exit /b 0
)
for %%I in ("%NAME%") do (
  set "BASE=%%~nI"
  set "EXT=%%~xI"
)
set /a N=1
:gufn_loop
set "CANDIDATE=!BASE!_!N!!EXT!"
if exist "%DIR%!CANDIDATE!" (
  set /a N+=1
  goto :gufn_loop
)
endlocal & set "%~3=%CANDIDATE%" & exit /b 0

:DetermineOutcome
REM %~1=RC  %~2=OKLOG  %~3=ZIPFOUND  out: %~4=OK/WARN/FAIL
setlocal
set "RC=%~1"
set "OKLOG=%~2"
set "ZIPFOUND=%~3"
set "RESULT=FAIL"
if defined NOZIP_FLAG (
  if "%RC%"=="0" (
    if /i "%OKLOG%"=="true" (
      set "RESULT=OK"
    ) else (
      set "RESULT=WARN"
    )
  )
) else (
  if /i "%OKLOG%"=="true" if /i "%ZIPFOUND%"=="true" (
    set "RESULT=OK"
  ) else if "%RC%"=="0" (
    set "RESULT=WARN"
  )
)
endlocal & set "%~4=%RESULT%" & exit /b 0


REM ======================================================================
REM Functions
REM ======================================================================

:ShowUsage
echo(
echo %BCYN%Usage:%RST%
echo   %~nx0 /list                                 ^> %BYEL%Show available configurations and exit%RST%
echo   %~nx0 /help                                 ^> %BYEL%Show this help and exit%RST%
echo   %~nx0 /banner                               ^> %BYEL%Show banner and exit%RST%
echo   %~nx0 NAME SRC DEST_ROOT ZIP_TAG            ^> %BYEL%Name of CLI. Runs each CLI line, splits --target A,B,C%RST%
echo   %~nx0 NAME SRC DEST_ROOT ZIP_TAG /parallel  ^> %BYEL%Same, but run targets in parallel%RST%
echo   %~nx0 NAME SRC DEST_ROOT /nozip             ^> %BYEL%Collect raw files only. Ignores any --zip in the preset%RST%
echo   %~nx0 NAME SRC DEST_ROOT ZIP_TAG /nozip     ^> %BYEL%Same as above, but keeps the usual argument shape%RST%
echo   %~nx0 NAME SRC DEST_ROOT ZIP_TAG /batonly   ^> %BYEL%Disable PowerShell, transcript, hashing, free-space, and external helper commands%RST%
echo   %~nx0 NAME SRC DEST_ROOT ZIP_TAG /external  ^> %BYEL%Force extended helper mode ^(default^)%RST%
echo   set KAPE_MAX_PARALLEL=4                     ^> %BYEL%Optional: cap /parallel concurrency ^(default 4^)%RST%
echo   set KAPE_USE_EXTERNAL_TOOLS=0               ^> %BYEL%Optional: default to batch-native mode%RST%
echo   set KAPE_DATE_ORDER=DMY                     ^> %BYEL%Optional: batch-native fallback date order ^(DMY or MDY^)%RST%
echo %BCYN%Examples:%RST%
echo   %~nx0 test "C:" ".\out" "CASE-SLO"
echo   %~nx0 workstation "C:" "E:\Cases\CASE-001\HOST01" "CASE-001_HOST01"
echo   %~nx0 server "C:" "E:\Cases\CASE-001\HOST01" "CASE-001_HOST01"
echo   %~nx0 test "C:" ".\out" "CASE-SLO" /parallel
echo   %~nx0 server "C:" ".\out" /nozip
echo   %~nx0 full "C:" ".\out" /nozip /batonly
echo(
exit /b 0

:StripZipArgument
setlocal EnableDelayedExpansion
set "LINE=!%~1!"
if not "!LINE: --zip =!"=="!LINE!" (
  set "LINE=!LINE: --zip =|!"
  for /f "tokens=1 delims=|" %%A in ("!LINE!") do set "LINE=%%A"
)
for /f "tokens=* delims= " %%A in ("!LINE!") do set "LINE=%%A"
endlocal & set "%~1=%LINE%" & exit /b 0

:ShowConfigs
echo(
echo ====================== %CYN%Available KAPE configurations%RST% ======================
set "FOUND_ANY="
for /f "delims=" %%F in ('dir /b /a:-d "%CLI_DIR%\*.cli" 2^>nul') do (
    set "N=%%~nF"
    echo   %BCYN%!N!%RST%
    set "FOUND_ANY=1"
)
if not defined FOUND_ANY (
    echo   (No .cli files found in "%CLI_DIR%")
)
echo ==========================================================================
echo(
exit /b 0

:GetNow
if not "%KAPE_USE_EXTERNAL_TOOLS%"=="1" goto :GetNow_Batch
setlocal EnableExtensions EnableDelayedExpansion
for /f "skip=1 delims=" %%T in ('
  wmic os get LocalDateTime 2^>nul ^| findstr /R "^[0-9]"
') do (
  set "ldt=%%T"
  set "YYYY=!ldt:~0,4!"
  set "MM=!ldt:~4,2!"
  set "DD=!ldt:~6,2!"
  set "HH=!ldt:~8,2!"
  set "MIN=!ldt:~10,2!"
  goto :gn_export
)
for /f "skip=2 tokens=2,*" %%A in ('
  reg query "HKCU\Control Panel\International" /v sShortDate 2^>nul
') do set "fmt=%%B"
for /f "skip=2 tokens=2,*" %%A in ('
  reg query "HKCU\Control Panel\International" /v sDate 2^>nul
') do set "sep=%%B"
if not defined fmt set "fmt=dd/MM/yyyy"
if not defined sep set "sep=/"
set "sep1=%sep:~0,1%"
set "t=%TIME: =0%"
set "HH=%t:~0,2%"
set "MIN=%t:~3,2%"
for /f "tokens=1-3 delims=%sep1%" %%a in ("%DATE%") do (
  set "p1=%%a" & set "p2=%%b" & set "p3=%%c"
)
for /f "tokens=1-3 delims=%sep1%" %%i in ("%fmt%") do (
  set "f1=%%i" & set "f2=%%j" & set "f3=%%k"
)
set "k1=!f1:~0,1!" & set "k2=!f2:~0,1!" & set "k3=!f3:~0,1!"
for %%# in (1 2 3) do (
  set "kp=!k%%#!"
  set "pv=!p%%#!"
  if /I "!kp!"=="y" set "YYYY=!pv!"
  if /I "!kp!"=="m" set "MM=!pv!"
  if /I "!kp!"=="M" set "MM=!pv!"
  if /I "!kp!"=="d" set "DD=!pv!"
  if /I "!kp!"=="D" set "DD=!pv!"
)
set "MM=0!MM!"  & set "MM=!MM:~-2!"
set "DD=0!DD!"  & set "DD=!DD:~-2!"
set "HH=0!HH!"  & set "HH=!HH:~-2!"
set "MIN=0!MIN!"& set "MIN=!MIN:~-2!"
:gn_export
endlocal & (
  set "YYYY=%YYYY%"
  set "MM=%MM%"
  set "DD=%DD%"
  set "HH=%HH%"
  set "MIN=%MIN%"
)
exit /b 0

:GetNow_Batch
setlocal EnableExtensions EnableDelayedExpansion
set "rawDate=%DATE%"
set "rawTime=%TIME: =0%"
set "HH=!rawTime:~0,2!"
set "MIN=!rawTime:~3,2!"
set "p1="
set "p2="
set "p3="
set "p4="
for /f "tokens=1-4 delims=/.- " %%a in ("!rawDate!") do (
  set "p1=%%a"
  set "p2=%%b"
  set "p3=%%c"
  set "p4=%%d"
)
call :IsDigits "!p1!" P1_NUM
if /i "!P1_NUM!"=="false" (
  set "p1=!p2!"
  set "p2=!p3!"
  set "p3=!p4!"
)
call :IsYearLike "!p1!" P1_YEAR
call :IsYearLike "!p3!" P3_YEAR
if /i "!P1_YEAR!"=="true" (
  set "YYYY=!p1!"
  set "MM=!p2!"
  set "DD=!p3!"
) else (
  if /i "!P3_YEAR!"=="true" (
    set "YYYY=!p3!"
  ) else (
    set "YYYY=!p3!"
  )
  call :ResolveMonthDay "!p1!" "!p2!" MM DD
)
if not defined YYYY set "YYYY=0000"
if not defined MM set "MM=01"
if not defined DD set "DD=01"
set "YYYY=0000!YYYY!" & set "YYYY=!YYYY:~-4!"
set "MM=0!MM!" & set "MM=!MM:~-2!"
set "DD=0!DD!" & set "DD=!DD:~-2!"
set "HH=0!HH!" & set "HH=!HH:~-2!"
set "MIN=0!MIN!" & set "MIN=!MIN:~-2!"
endlocal & (
  set "YYYY=%YYYY%"
  set "MM=%MM%"
  set "DD=%DD%"
  set "HH=%HH%"
  set "MIN=%MIN%"
)
exit /b 0

:Show_Banner
echo(
echo %CYN%==============================================================%RST%
echo %BOLD%%BCYN%KAPE-Able%RST% %DIM%- Batch Runner for KAPE presets%RST%
echo %CYN%--------------------------------------------------------------%RST%
echo %BCYN%Author:%RST% %WHT%SimonL01%RST%
echo %BCYN%Email:%RST% %WHT%none4rB4s1n3ss%RST%
echo %BCYN%Copyright:%RST% %WHT%GNU General Public License v3.0%RST%
echo %CYN%--------------------------------------------------------------%RST%
echo %DIM%Tip:%RST% %YEL%Ctrl+C%RST% to stop. Logs are written per target.
echo %DIM%Tip:%RST% %YEL%/help%RST% for help and usage examples.
echo %CYN%--------------------------------------------------------------%RST%
echo(

echo(
echo     ^\^|/         (__)    
echo         `\------(oo)
echo           ^|^|    (__)
echo           ^|^|w--^|^|     ^\^|/
echo     ^\^|/
echo(

echo %CYN%==============================================================%RST%
exit /b 0

:FinalizeCaseOutput
setlocal EnableDelayedExpansion
if not defined CASE_ROOT endlocal & exit /b 0

if /i not "%STATUS_CSV%"=="%CASE_STATUS_CSV%" (
    copy /y "%STATUS_CSV%" "%CASE_STATUS_CSV%" >nul 2>&1
    if errorlevel 1 (
        echo [%BRED%ERROR%RST%] Failed to copy status CSV to "%CASE_STATUS_CSV%".
        endlocal & exit /b 1
    )
)

call :WriteHashManifest
if errorlevel 1 (
    echo [%BRED%ERROR%RST%] Failed to write SHA256 manifest "%HASH_MANIFEST%".
    endlocal & exit /b 1
)

call :WriteFinalSummary
if errorlevel 1 (
    echo [%BRED%ERROR%RST%] Failed to write final summary "%SUMMARY_FILE%".
    endlocal & exit /b 1
)

endlocal & exit /b 0

:WriteHashManifest
if not "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
  > "%HASH_MANIFEST%" (
    echo SHA256 manifest skipped in batch-native mode.
    echo CaseRoot=%KAPE_CASE_ROOT%
  )
  exit /b 0
)
setlocal
set "KAPE_HASH_MANIFEST=%HASH_MANIFEST%"
powershell -NoProfile -Command ^
  "$root = $env:KAPE_CASE_ROOT; $out = $env:KAPE_HASH_MANIFEST; $files = Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.zip -ErrorAction SilentlyContinue; if (@($files).Count -eq 0) { 'No ZIP files found under ' + $root | Set-Content -LiteralPath $out -Encoding ascii; exit 0 }; $lines = foreach ($f in $files) { $hash = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash; '{0} *{1}' -f $hash, $f.FullName }; Set-Content -LiteralPath $out -Value $lines -Encoding ascii"
set "PS_RC=%ERRORLEVEL%"
endlocal & exit /b %PS_RC%

:WriteFinalSummary
if not "%KAPE_USE_EXTERNAL_TOOLS%"=="1" goto :WriteFinalSummary_Batch
setlocal
set "KAPE_STATUS_FILE=%CASE_STATUS_CSV%"
set "KAPE_SUMMARY_FILE=%SUMMARY_FILE%"
for /f "usebackq tokens=1,2 delims==" %%A in (`powershell -NoProfile -Command ^
  "$zipExpected = $env:KAPE_EXPECT_ZIP -eq '1'; $rows = Import-Csv -LiteralPath $env:KAPE_STATUS_FILE; $results = @{}; foreach ($row in $rows) { $name = $row.target; $isRetry = $false; if ($name -like '*_retry') { $name = $name.Substring(0, $name.Length - 6); $isRetry = $true }; if ($zipExpected) { $status = if (($row.log_ok -eq 'true') -and ($row.zip_found -eq 'true')) { 'OK' } elseif ($row.rc -eq '0') { 'WARN' } else { 'FAIL' } } else { $status = if (($row.rc -eq '0') -and ($row.log_ok -eq 'true')) { 'OK' } elseif ($row.rc -eq '0') { 'WARN' } else { 'FAIL' } }; if ($isRetry -or -not $results.ContainsKey($name)) { $results[$name] = $status } }; $ok = @($results.Values | Where-Object { $_ -eq 'OK' }).Count; $warn = @($results.Values | Where-Object { $_ -eq 'WARN' }).Count; $fail = @($results.Values | Where-Object { $_ -eq 'FAIL' }).Count; $total = $results.Count; $content = @('Preset=' + $env:KAPE_PRESET_NAME, 'CaseRoot=' + $env:KAPE_CASE_ROOT, 'Total=' + $total, 'OK=' + $ok, 'WARN=' + $warn, 'FAIL=' + $fail); Set-Content -LiteralPath $env:KAPE_SUMMARY_FILE -Value $content -Encoding ascii; 'SUM_TOTAL=' + $total; 'SUM_OK=' + $ok; 'SUM_WARN=' + $warn; 'SUM_FAIL=' + $fail"`) do set "%%A=%%B"
set "PS_RC=%ERRORLEVEL%"
endlocal & (
  set "SUM_TOTAL=%SUM_TOTAL%"
  set "SUM_OK=%SUM_OK%"
  set "SUM_WARN=%SUM_WARN%"
  set "SUM_FAIL=%SUM_FAIL%"
  exit /b %PS_RC%
)

:WriteFinalSummary_Batch
setlocal EnableDelayedExpansion
set "SUM_TOTAL=0"
set "SUM_OK=0"
set "SUM_WARN=0"
set "SUM_FAIL=0"
if exist "%CASE_STATUS_CSV%" (
  for /f "usebackq skip=1 tokens=1-5 delims=," %%A in ("%CASE_STATUS_CSV%") do (
    set "ROW_TARGET=%%A"
    set "ROW_RC=%%C"
    set "ROW_LOG_OK=%%D"
    set "ROW_ZIP_FOUND=%%E"
    call :NormalizeSummaryTarget "!ROW_TARGET!" SUMMARY_KEY SUMMARY_IS_RETRY
    call :DetermineOutcome "!ROW_RC!" "!ROW_LOG_OK!" "!ROW_ZIP_FOUND!" ROW_STATUS
    call :RememberSummaryStatus "!SUMMARY_KEY!" "!ROW_STATUS!" "!SUMMARY_IS_RETRY!"
  )
)
> "%SUMMARY_FILE%" (
  echo Preset=%KAPE_PRESET_NAME%
  echo CaseRoot=%KAPE_CASE_ROOT%
  echo Total=!SUM_TOTAL!
  echo OK=!SUM_OK!
  echo WARN=!SUM_WARN!
  echo FAIL=!SUM_FAIL!
)
set "SUMMARY_RC=%ERRORLEVEL%"
endlocal & (
  set "SUM_TOTAL=%SUM_TOTAL%"
  set "SUM_OK=%SUM_OK%"
  set "SUM_WARN=%SUM_WARN%"
  set "SUM_FAIL=%SUM_FAIL%"
  exit /b %SUMMARY_RC%
)

:RequireAdmin
if not "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
    echo [%BYEL%WARN%RST%] Administrative privilege check skipped in batch-native mode.
    exit /b 0
)
fltmc >nul 2>&1
if errorlevel 1 (
    echo [%BRED%ERROR%RST%] Administrative privileges are required. Re-run this shell as Administrator.
    exit /b 1
)
echo [%BYEL%INFO%RST%] Administrative privilege check passed.
exit /b 0

:CheckFreeSpace
if not "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
    echo [%BYEL%INFO%RST%] Free-space check skipped in batch-native mode.
    exit /b 0
)
setlocal EnableDelayedExpansion
set "KAPE_FREE_PATH=%~1"
set "FREE_GB="
for /f "usebackq tokens=1,2 delims==" %%A in (`powershell -NoProfile -Command ^
  "$min = [double]$env:KAPE_MIN_FREE_GB; $path = $env:KAPE_FREE_PATH; $drive = (Get-Item -LiteralPath $path).PSDrive; if (-not $drive) { exit 3 }; $free = [math]::Round($drive.Free / 1GB, 2); 'FREE_GB=' + $free; if ($drive.Free -lt ($min * 1GB)) { exit 2 }"`) do set "%%A=%%B"
set "PS_RC=!ERRORLEVEL!"
if "%PS_RC%"=="2" (
    echo [%BRED%ERROR%RST%] Destination "%~1" has !FREE_GB! GB free. Minimum required is %KAPE_MIN_FREE_GB% GB.
    endlocal & exit /b 1
)
if not "%PS_RC%"=="0" (
    echo [%BRED%ERROR%RST%] Failed to determine free space for "%~1".
    endlocal & exit /b 1
)
echo [%BYEL%INFO%RST%] Destination free space: !FREE_GB! GB ^(minimum %KAPE_MIN_FREE_GB% GB^).
endlocal & exit /b 0

:CaptureSystemContext
setlocal
(
  echo Timestamp: %DATE% %TIME%
  echo Preset: %MATCH%
  echo Source: %ARG1%
  echo DestinationRoot: %CASE_ROOT%
  echo ZipTag: %ARG3%
  echo ParallelMode: %PARALLEL_FLAG%
  echo MaxParallel: %KAPE_MAX_PARALLEL%
  echo ZipExpected: %KAPE_EXPECT_ZIP%
  echo ExternalTools: %KAPE_USE_EXTERNAL_TOOLS%
  echo.
  if "%KAPE_USE_EXTERNAL_TOOLS%"=="1" (
    echo ===== hostname =====
    hostname
    echo.
    echo ===== whoami =====
    whoami
    echo.
    echo ===== ipconfig /all =====
    ipconfig /all
    echo.
  ) else (
    echo ===== external commands skipped =====
    echo hostname, whoami, and ipconfig are disabled in batch-native mode.
    echo.
  )
) > "%SYSTEM_CONTEXT_FILE%" 2>&1
set "CTX_RC=%ERRORLEVEL%"
endlocal & exit /b %CTX_RC%

:NormalizeParallelLimit
setlocal
set "RAW=%KAPE_MAX_PARALLEL%"
if not defined RAW set "RAW=4"
set "BAD="
for /f "delims=0123456789" %%A in ("%RAW%") do set "BAD=%%A"
if defined BAD set "RAW=4"
if "%RAW%"=="0" set "RAW=4"
endlocal & set "KAPE_MAX_PARALLEL=%RAW%" & exit /b 0

:NormalizeExternalToolsFlag
setlocal
set "RAW=%KAPE_USE_EXTERNAL_TOOLS%"
if not defined RAW set "RAW=1"
if /i "%RAW%"=="true" set "RAW=1"
if /i "%RAW%"=="yes" set "RAW=1"
if /i "%RAW%"=="on" set "RAW=1"
if /i "%RAW%"=="false" set "RAW=0"
if /i "%RAW%"=="no" set "RAW=0"
if /i "%RAW%"=="off" set "RAW=0"
if not "%RAW%"=="0" if not "%RAW%"=="1" set "RAW=1"
endlocal & set "KAPE_USE_EXTERNAL_TOOLS=%RAW%" & exit /b 0

:NormalizeSummaryTarget
setlocal EnableDelayedExpansion
set "NAME=%~1"
set "IS_RETRY=0"
if /i "!NAME:~-6!"=="_retry" (
  set "NAME=!NAME:~0,-6!"
  set "IS_RETRY=1"
)
call :MakeSafeName "!NAME!" KEY
if not defined KEY set "KEY=target"
endlocal & (
  set "%~2=%KEY%"
  set "%~3=%IS_RETRY%"
  exit /b 0
)

:RememberSummaryStatus
set "SUMMARY_KEY=%~1"
set "SUMMARY_STATUS=%~2"
set "SUMMARY_IS_RETRY=%~3"
call set "SUMMARY_OLD=%%SUM_STATE_%SUMMARY_KEY%%%"
if defined SUMMARY_OLD if /i not "%SUMMARY_IS_RETRY%"=="1" exit /b 0
if defined SUMMARY_OLD call :AdjustSummaryCount "%SUMMARY_OLD%" -1
if not defined SUMMARY_OLD set /a SUM_TOTAL+=1
call :AdjustSummaryCount "%SUMMARY_STATUS%" 1
call set "SUM_STATE_%SUMMARY_KEY%=%SUMMARY_STATUS%"
exit /b 0

:AdjustSummaryCount
if /i "%~1"=="OK" set /a SUM_OK+=%~2
if /i "%~1"=="WARN" set /a SUM_WARN+=%~2
if /i "%~1"=="FAIL" set /a SUM_FAIL+=%~2
exit /b 0

:IsDigits
setlocal
set "VALUE=%~1"
set "RESULT=true"
if not defined VALUE set "RESULT=false"
for /f "delims=0123456789" %%A in ("%VALUE%") do if not "%%A"=="" set "RESULT=false"
endlocal & set "%~2=%RESULT%" & exit /b 0

:IsYearLike
setlocal
set "VALUE=%~1"
set "RESULT=false"
if defined VALUE if not "%VALUE:~3,1%"=="" if "%VALUE:~4,1%"=="" (
  set "BAD="
  for /f "delims=0123456789" %%A in ("%VALUE%") do if not "%%A"=="" set "BAD=1"
  if not defined BAD set "RESULT=true"
)
endlocal & set "%~2=%RESULT%" & exit /b 0

:ResolveMonthDay
setlocal EnableDelayedExpansion
set "A=%~1"
set "B=%~2"
set "ORDER=%KAPE_DATE_ORDER%"
if not defined ORDER set "ORDER=DMY"
call :IsDigits "!A!" A_NUM
call :IsDigits "!B!" B_NUM
if /i not "!A_NUM!"=="true" set "A=1"
if /i not "!B_NUM!"=="true" set "B=1"
set /a AVAL=1!A! - 100
set /a BVAL=1!B! - 100
if !AVAL! gtr 12 if !BVAL! leq 12 (
  set "MM=!B!"
  set "DD=!A!"
) else if !BVAL! gtr 12 if !AVAL! leq 12 (
  set "MM=!A!"
  set "DD=!B!"
) else if /i "!ORDER!"=="MDY" (
  set "MM=!A!"
  set "DD=!B!"
) else (
  set "MM=!B!"
  set "DD=!A!"
)
endlocal & (
  set "%~3=%MM%"
  set "%~4=%DD%"
  exit /b 0
)

:MakeSafeName
setlocal EnableDelayedExpansion
set "VALUE=%~1"
if not defined VALUE set "VALUE=item"
set "VALUE=!VALUE:.cli=!"
set "VALUE=!VALUE: =_!"
set "VALUE=!VALUE:,=_!"
set "VALUE=!VALUE:/=_!"
set "VALUE=!VALUE:\=_!"
set "VALUE=!VALUE::=_!"
set "VALUE=!VALUE:;=_!"
set "VALUE=!VALUE:(=_!"
set "VALUE=!VALUE:)=_!"
set "VALUE=!VALUE:[=_!"
set "VALUE=!VALUE:]=_!"
endlocal & set "%~2=%VALUE%" & exit /b 0
