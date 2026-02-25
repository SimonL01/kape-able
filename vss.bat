@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ----------------------------------------------------------------------
REM run-kape.bat (revised)
REM - Selects a cli\*.cli preset by name/prefix
REM - Materializes tokens %%1..%%8 and %%d %%m %%Y %%H %%M into _kape.cli
REM - Executes ONE KAPE run PER TARGET (splits comma-separated --target lists)
REM - Prints [OK]/[WARN]/[FAIL] per target and writes _kape.status.csv
REM - Supports optional /parallel as a 5th arg
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
set "PARALLEL_FLAG="

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
echo(
echo [%BYEL%INFO%RST%] Using CLI preset: "%MATCH%"

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

REM Optional: a pure token "/parallel" as the fifth arg enables parallel exec
if /i "%~5"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~6"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~7"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~8"=="/parallel" set "PARALLEL_FLAG=/parallel"
if /i "%~9"=="/parallel" set "PARALLEL_FLAG=/parallel"

REM --- Normalize drive-root-ish tokens (quality-of-life) ---
for %%V in (ARG1 ARG2 ARG3 ARG4 ARG5 ARG6 ARG7 ARG8) do (
  for /f "tokens=1,* delims==" %%K in ('set %%V 2^>nul') do (
    if defined %%K (
      set "TMP=!%%K!"
      if "!TMP:~1,1!"==":" if "!TMP:~2!"=="" set "%%K=!TMP!\"
    )
  )
)

REM --- Compute date/time (DD, MM, YYYY, HH, MIN) ---
call :GetNow

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
set "JOBSDIR=%TEMP%\kape_run_%RANDOM%%RANDOM%"
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
    rd /s /q "%JOBSDIR%" >nul 2>&1
)

echo(
echo [%BYEL%INFO%RST%] Completed processing of "%MATCH%".
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
set "LOG_ONE=!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.log"
set "RCFILE=!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.rc"
set "DESTFILE=!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.dest"
set "JOBFILE=!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.cmd"
echo(!DEST!>"!DESTFILE!"
echo(!CMD_LINE!>"!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.args"
echo %TIME%>"!JOBSDIR!\%TGT%_L%IDX%_!STAMP!.start"
>  "!JOBFILE!" echo @echo off
>> "!JOBFILE!" echo setlocal EnableExtensions DisableDelayedExpansion
>> "!JOBFILE!" echo cd /d "%SCRIPT_DIR%"
>> "!JOBFILE!" echo "%KAPE_EXE%" !CMD_LINE! 0^< nul 1^> "!LOG_ONE!" 2^>^&1
>> "!JOBFILE!" echo (echo %%errorlevel%%)^> "!RCFILE!"

if /i "!DO_PAR!"=="/parallel" (
  REM Throttle: wait until fewer than 8 jobs are running
  :throttle
  set "RUNNING=0"
  for %%J in ("!JOBSDIR!\*.cmd") do (
    if not exist "!JOBSDIR!\%%~nJ.rc" set /a RUNNING+=1
  )
  if !RUNNING! geq 8 (
    timeout /t 1 /nobreak >nul 2>nul
    goto :throttle
  )
  start "" /b cmd /c "!JOBFILE!"
  endlocal & exit /b 0
)

call "!JOBFILE!"
set /p RC=<"!RCFILE!" 2>nul
if not defined RC set "RC=1"

call :AssessOne "!LOG_ONE!" "!DEST!" ZIPFOUND ZIPFILE OKLOG
>> "%STATUS_CSV%" echo !TGT!,!IDX!,!RC!,!OKLOG!,!ZIPFOUND!,"!LOG_ONE!","!ZIPFILE!"

if "!RC!"=="0" (
  if /i "!OKLOG!"=="true" (
    echo [ %ESC%[92mOK%ESC%[0m ] !TGT! RC=!RC! zip=!ZIPFOUND!
  ) else (
    echo [ %ESC%[93mWARN%ESC%[0m ] !TGT! RC=!RC! logOK=!OKLOG! zip=!ZIPFOUND!
    echo        See "!LOG_ONE!"
  )
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
set "LOGF=%STEM%log"
findstr /i /c:"IOException" /c:"WinIOError" /c:"being used by another process" "%LOGF%" >nul 2>&1
if errorlevel 1 endlocal & exit /b 0

REM Read original KAPE arguments (strip trailing CR from echo/CRLF)
set "ARGSF=%STEM%args"
if not exist "%ARGSF%" endlocal & exit /b 0
set "ORIG_ARGS="
for /f "usebackq delims=" %%A in ("%ARGSF%") do if not defined ORIG_ARGS set "ORIG_ARGS=%%A"
if not defined ORIG_ARGS endlocal & exit /b 0
set "ORIG_ARGS=%ORIG_ARGS:~0,-1%"
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

for /f "delims=" %%e in ('echo prompt $E^|cmd') do set "ESC=%%e"

echo(
echo [%BYEL%RETRY%RST%] %NM% -- file-lock error detected, retrying with --vss ...
"%KAPE_EXE%" %NEW_ARGS% 0<nul 1>"%RLOG%" 2>&1
set "RRC2=%ERRORLEVEL%"

call :AssessOne "%RLOG%" "%RDEST%" RZIPFOUND RZIPFILE ROKLOG
>> "%STATUS_CSV%" echo %NM%_retry,0,%RRC2%,%ROKLOG%,%RZIPFOUND%,"%RLOG%","%RZIPFILE%"

if "%RRC2%"=="0" (
    if /i "%ROKLOG%"=="true" (
        echo [ %ESC%[92mOK%ESC%[0m ] %NM% (VSS retry) RC=%RRC2% zip=%RZIPFOUND%
    ) else (
        echo [ %ESC%[93mWARN%ESC%[0m ] %NM% (VSS retry) RC=%RRC2% logOK=%ROKLOG%
        echo        See "%RLOG%"
    )
) else (
    echo [ %ESC%[91mFAIL%ESC%[0m ] %NM% (VSS retry) RC=%RRC2%
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
        set "TGTN=%%~nR"
        for /f "tokens=1 delims=_" %%x in ("!TGTN!") do set "TGTNAME=%%x"
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
        call :AssessOne "!LOGONE!" "!DESTONE!" ZIPFOUND ZIPFILE OKLOG
        >> "%STATUS_CSV%" echo !TGTNAME!,0,!RCC!,!OKLOG!,!ZIPFOUND!,"!LOGONE!","!ZIPFILE!"
        if "!RCC!"=="0" (
            if /i "!OKLOG!"=="true" (
                if defined ELAPSED_STR (
                    echo [ %ESC%[92mOK%ESC%[0m ] !TGTNAME! RC=!RCC! zip=!ZIPFOUND! time=!ELAPSED_STR!
                ) else (
                    echo [ %ESC%[92mOK%ESC%[0m ] !TGTNAME! RC=!RCC! zip=!ZIPFOUND!
                )
            ) else (
                echo [ %ESC%[93mWARN%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND! time=!ELAPSED_STR!
                echo        See "!LOGONE!"
            )
        ) else (
            echo [ %ESC%[91mFAIL%ESC%[0m ] !TGTNAME! RC=!RCC! logOK=!OKLOG! zip=!ZIPFOUND! time=!ELAPSED_STR!
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
  for /f "tokens=1,* delims=:" %%x in ('findstr /c:"Copied " "%LOGF%" 2^>nul') do (
    echo %%y | findstr /c:" out of " >nul && set "OKLOG=true"
  )
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
echo %BCYN%Examples:%RST%
echo   %~nx0 test "C:" ".\out" "CASE-SLO"
echo   %~nx0 test "C:" ".\out" "CASE-SLO" /parallel
echo(
exit /b 0

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
