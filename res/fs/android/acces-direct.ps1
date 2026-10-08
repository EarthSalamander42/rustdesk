<#
  FS Support - Acces direct (enveloppe Windows)

  Prepare un appareil Android pour la prise en main sans personne devant l'ecran.
  A lancer depuis le PC de Jason (Windows), appareil branche en USB (debogage ADB
  active) ou joignable par le reseau.

  Exemples :
    # Appareil en USB :
    powershell -ExecutionPolicy Bypass -File .\acces-direct.ps1

    # Appareil sur le reseau (borne, box TV) + installation de l'APK :
    powershell -ExecutionPolicy Bypass -File .\acces-direct.ps1 -Ip 192.168.1.42 -Apk .\fs-support.apk

  Compatible Windows PowerShell 5.1 : pas d'operateurs && ni ?? ni ?.
#>

[CmdletBinding()]
param(
    [string]$Ip = "",
    [string]$Apk = ""
)

$ErrorActionPreference = "Stop"
$PKG = "fr.fssolutions.support"
$MAIN_ACTIVITY = "$PKG/com.carriez.flutter_hbb.MainActivity"
$SCRIPT_NAME = "acces-direct.sh"
$PLATFORM_TOOLS_URL = "https://dl.google.com/android/repository/platform-tools-latest-windows.zip"

function Write-Etape($texte) {
    Write-Host ""
    Write-Host "==> $texte" -ForegroundColor Cyan
}

function Write-Ok($texte) {
    Write-Host "    OK   : $texte" -ForegroundColor Green
}

function Write-Souci($texte) {
    Write-Host "    SOUCI: $texte" -ForegroundColor Yellow
}

# Trouve adb : PATH, puis le SDK Android par defaut, sinon propose le telechargement.
function Get-AdbPath {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($null -ne $cmd) {
        return $cmd.Source
    }

    $sdkAdb = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
    if (Test-Path $sdkAdb) {
        return $sdkAdb
    }

    $fsAdb = Join-Path $env:LOCALAPPDATA "FS-Support\platform-tools\adb.exe"
    if (Test-Path $fsAdb) {
        return $fsAdb
    }

    Write-Souci "adb (outils Android « platform-tools ») est introuvable sur ce PC."
    $reponse = Read-Host "Telecharger les outils officiels de Google maintenant ? (O/N)"
    if ($reponse -notmatch '^[OoYy]') {
        throw "adb introuvable. Installez les platform-tools Android puis relancez."
    }

    $dest = Join-Path $env:LOCALAPPDATA "FS-Support"
    if (-not (Test-Path $dest)) {
        New-Item -ItemType Directory -Path $dest | Out-Null
    }
    $zip = Join-Path $dest "platform-tools.zip"

    Write-Etape "Telechargement des platform-tools"
    Write-Host "    Source : $PLATFORM_TOOLS_URL"
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    } catch {
        # Anciennes versions : on ignore si Tls12 n'est pas reglable.
    }
    Invoke-WebRequest -Uri $PLATFORM_TOOLS_URL -OutFile $zip -UseBasicParsing
    Write-Ok "Archive telechargee."

    Write-Etape "Extraction"
    if (Test-Path (Join-Path $dest "platform-tools")) {
        Remove-Item (Join-Path $dest "platform-tools") -Recurse -Force
    }
    Expand-Archive -Path $zip -DestinationPath $dest -Force
    Remove-Item $zip -Force

    $fsAdb = Join-Path $dest "platform-tools\adb.exe"
    if (-not (Test-Path $fsAdb)) {
        throw "Extraction terminee mais adb.exe reste introuvable dans $dest."
    }
    Write-Ok "adb installe : $fsAdb"
    return $fsAdb
}

# Appelle adb et renvoie la sortie (texte). Le code de sortie est dans $script:AdbExit.
function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments = $true)] $AdbArgs)
    $all = @()
    if ($script:AdbSerial -ne "") {
        $all += @("-s", $script:AdbSerial)
    }
    $all += $AdbArgs
    $sortie = & $script:Adb @all 2>&1
    $script:AdbExit = $LASTEXITCODE
    return ($sortie | Out-String)
}

$script:Adb = ""
$script:AdbSerial = ""
$script:AdbExit = 0

try {
    Write-Host "=== FS Support : preparation de l'acces direct ===" -ForegroundColor White

    $script:Adb = Get-AdbPath
    Write-Host "    adb : $($script:Adb)"

    # Demarre le serveur adb (silencieux).
    Invoke-Adb "start-server" | Out-Null

    # Connexion reseau si -Ip fourni, sinon USB.
    if ($Ip -ne "") {
        Write-Etape "Connexion reseau a $Ip:5555"
        $out = Invoke-Adb "connect" "$Ip`:5555"
        Write-Host "    $($out.Trim())"
        if ($out -notmatch "connected") {
            throw "Impossible de se connecter a $Ip:5555. Verifiez que le debogage ADB sans fil est actif et l'appareil sur le meme reseau."
        }
        $script:AdbSerial = "$Ip`:5555"
        Write-Ok "Connecte a $Ip:5555"
    } else {
        Write-Etape "Recherche de l'appareil en USB"
        $devices = Invoke-Adb "devices"
        $lignes = @()
        foreach ($l in ($devices -split "`n")) {
            $t = $l.Trim()
            if ($t -ne "" -and $t -notmatch "List of devices" -and $t -match "device$") {
                $lignes += $t
            }
        }
        if ($lignes.Count -eq 0) {
            throw "Aucun appareil Android detecte. Branchez l'appareil, activez le debogage USB et acceptez l'autorisation sur l'ecran."
        }
        if ($lignes.Count -gt 1) {
            Write-Souci "Plusieurs appareils detectes : le premier est utilise. Precisez -Ip pour cibler un appareil reseau."
        }
        $script:AdbSerial = ($lignes[0] -split "\s+")[0]
        Write-Ok "Appareil : $($script:AdbSerial)"
    }

    # Installation de l'APK si demandee.
    if ($Apk -ne "") {
        Write-Etape "Installation de l'application"
        if (-not (Test-Path $Apk)) {
            throw "APK introuvable : $Apk"
        }
        $out = Invoke-Adb "install" "-r" $Apk
        Write-Host "    $($out.Trim())"
        if ($script:AdbExit -ne 0 -and $out -notmatch "Success") {
            throw "Installation de l'APK en echec."
        }
        Write-Ok "Application installee."
    }

    # Pousse le script sur l'appareil.
    Write-Etape "Envoi du script de preparation"
    $localScript = Join-Path $PSScriptRoot $SCRIPT_NAME
    if (-not (Test-Path $localScript)) {
        throw "Script $SCRIPT_NAME introuvable a cote de ce fichier ($PSScriptRoot)."
    }
    $out = Invoke-Adb "push" $localScript "/data/local/tmp/$SCRIPT_NAME"
    Write-Host "    $($out.Trim())"
    if ($script:AdbExit -ne 0) {
        throw "Envoi du script en echec."
    }
    Write-Ok "Script envoye."

    # Execute le script SUR l'appareil (exactement comme documente).
    Write-Etape "Preparation de l'appareil (capture, accessibilite, permissions)"
    $out = Invoke-Adb "shell" "sh" "/data/local/tmp/$SCRIPT_NAME"
    Write-Host $out

    # Lance l'application une fois.
    Write-Etape "Ouverture de FS Support"
    $out = Invoke-Adb "shell" "am" "start" "-n" $MAIN_ACTIVITY
    Write-Host "    $($out.Trim())"

    Write-Host ""
    Write-Host "=== Termine ===" -ForegroundColor White
    Write-Host "Sur l'appareil : ouvrez FS Support, activez « Acces direct » sur l'ecran de" -ForegroundColor White
    Write-Host "partage, puis definissez un mot de passe permanent si ce n'est pas deja fait." -ForegroundColor White
    Write-Host "L'appareil sera alors joignable sans personne devant l'ecran." -ForegroundColor White
    Write-Host ""
    Write-Host "Note : sur Android 14+ (API 34+), le systeme peut imposer une fenetre de" -ForegroundColor White
    Write-Host "consentement de capture a chaque demarrage. Dans ce cas, une presence reste" -ForegroundColor White
    Write-Host "necessaire au premier demarrage pour l'accepter." -ForegroundColor White
}
catch {
    Write-Host ""
    Write-Host "ERREUR : $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
