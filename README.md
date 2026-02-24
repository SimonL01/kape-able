# KAPE-Able
A handy batch wrapper for KAPE presets - runs targets one-by-one and sorts output folders automatically

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
