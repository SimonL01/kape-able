# KAPE-Able
A handy batch wrapper for KAPE presets - runs targets one-by-one and sorts output folders automatically

```sh
C:\Users\Simon\KAPE>run-kape /banner
==============================================================
KAPE-Able - Batch Runner for KAPE presets
--------------------------------------------------------------
Author: SimonL01
Email: none4rB4s1n3ss
Copyright: GNU General Public License v3.0
--------------------------------------------------------------
Tip: Ctrl+C to stop. Logs are written per target.
Tip: /help for help and usage examples.
--------------------------------------------------------------
\|/           (__)
      `\------(oo)
        ||    (__)
        ||w--||     \|/
\|/                                                                                                                                                          ==============================================================
```

Do not forget that for the script to run, kape.exe must be present, with its folders and respective templates.
Example of the repository structure can be:
```text
kape-able/
├─ cli/
│  ├─ antivirus.cli
│  ├─ windows_artifacts.cli
│  └─ ...
│  └─ make-cli.ps1
│  └─ ...
├─ Modules/
├─ Targets/
├─ gkape.exe
├─ kape.exe
└─ run-kape.bat
```
