# Installe Speechify Boost pour qu'il démarre tout seul avec Windows.
#  - copie le serveur dans %LOCALAPPDATA%\SpeechifyBoost
#  - crée un lanceur silencieux (sans fenêtre)
#  - ajoute un raccourci dans le dossier Démarrage de l'utilisateur
# Désinstaller : supprimer le raccourci « Speechify Boost » du dossier
# shell:startup (et le dossier %LOCALAPPDATA%\SpeechifyBoost si voulu).

$base = Join-Path $env:LOCALAPPDATA 'SpeechifyBoost'
New-Item -ItemType Directory -Force $base | Out-Null
Copy-Item (Join-Path $PSScriptRoot 'speechify_boost.py') $base -Force

# python.exe (pas pythonw) : c'est lui qu'autorise le pare-feu Windows ; la
# fenêtre reste cachée grâce au style 0 de sh.Run.
$pyw = Join-Path $base 'venv\Scripts\python.exe'
$script = Join-Path $base 'speechify_boost.py'
$vbs = Join-Path $base 'start_boost.vbs'
@"
Set sh = CreateObject("WScript.Shell")
sh.Run """$pyw"" ""$script""", 0, False
"@ | Out-File -Encoding ascii $vbs

$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'Speechify Boost.lnk'
$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = 'wscript.exe'
$s.Arguments = "`"$vbs`""
$s.WorkingDirectory = $base
$s.Description = 'Speechify Boost - acceleration de l''app par l''ordinateur'
$s.Save()

Write-Output "Installé. Lanceur : $vbs"
Write-Output "Démarrage automatique : $lnk"
