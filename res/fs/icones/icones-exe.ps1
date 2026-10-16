# FS Support : contrôle de l'icône embarquée dans l'exécutable Windows compilé (CI des branches fs/logo-*).
#
# Lit le groupe d'icônes de l'exe (ressource RT_GROUP_ICON, celle qu'affichent l'Explorateur, la barre des
# tâches et les raccourcis), vérifie ses tailles et que chaque image est octet pour octet celle de
# res/icon.ico, puis écrit une planche PNG (taille réelle sur barres claire et sombre, et ×6) et un relevé
# texte dans -Sortie. Vérifie aussi data\flutter_assets\assets\icon.ico (icône de la fenêtre, raccourcis).
param(
    [Parameter(Mandatory)] [string] $Exe,
    [Parameter(Mandatory)] [string] $Sortie,
    [int[]] $Attendu = @(16, 20, 24, 32, 40, 48, 64, 128, 256)
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public static class FsIconesExe {
    [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr LoadLibraryEx(string f, IntPtr h, uint flags);
    [DllImport("kernel32")] static extern bool FreeLibrary(IntPtr h);
    [DllImport("kernel32", SetLastError = true)] static extern IntPtr FindResource(IntPtr h, IntPtr name, IntPtr type);
    [DllImport("kernel32")] static extern IntPtr LoadResource(IntPtr h, IntPtr r);
    [DllImport("kernel32")] static extern IntPtr LockResource(IntPtr r);
    [DllImport("kernel32")] static extern uint SizeofResource(IntPtr h, IntPtr r);
    delegate bool EnumProc(IntPtr h, IntPtr type, IntPtr name, IntPtr p);
    [DllImport("kernel32")] static extern bool EnumResourceNames(IntPtr h, IntPtr type, EnumProc cb, IntPtr p);

    static byte[] Lire(IntPtr h, IntPtr name, int type) {
        IntPtr r = FindResource(h, name, (IntPtr)type);
        if (r == IntPtr.Zero) return null;
        uint n = SizeofResource(h, r);
        byte[] b = new byte[n];
        Marshal.Copy(LockResource(LoadResource(h, r)), b, 0, (int)n);
        return b;
    }

    // Premier groupe d'icônes (celui que Windows montre pour l'exe) : liste de (côté, octets de l'image).
    public static List<KeyValuePair<int, byte[]>> PremierGroupe(string exe) {
        IntPtr h = LoadLibraryEx(exe, IntPtr.Zero, 0x2 | 0x20);
        if (h == IntPtr.Zero) throw new Exception("LoadLibraryEx " + Marshal.GetLastWin32Error());
        try {
            // Le nom peut être une chaîne valable seulement pendant l'énumération : lecture dans le rappel.
            byte[] g = null;
            EnumResourceNames(h, (IntPtr)14, (m, t, n, p) => { g = Lire(m, n, 14); return false; }, IntPtr.Zero);
            if (g == null) throw new Exception("aucune ressource RT_GROUP_ICON");
            int count = BitConverter.ToUInt16(g, 4);
            var res = new List<KeyValuePair<int, byte[]>>();
            for (int i = 0; i < count; i++) {
                int o = 6 + 14 * i;
                int cote = g[o] == 0 ? 256 : g[o];
                int id = BitConverter.ToUInt16(g, o + 12);
                res.Add(new KeyValuePair<int, byte[]>(cote, Lire(h, (IntPtr)id, 3)));
            }
            return res;
        } finally { FreeLibrary(h); }
    }

    // Entrées d'un fichier .ico : (côté, octets de l'image).
    public static List<KeyValuePair<int, byte[]>> EntreesIco(byte[] f) {
        int count = BitConverter.ToUInt16(f, 4);
        var res = new List<KeyValuePair<int, byte[]>>();
        for (int i = 0; i < count; i++) {
            int o = 6 + 16 * i;
            int cote = f[o] == 0 ? 256 : f[o];
            int taille = BitConverter.ToInt32(f, o + 8), debut = BitConverter.ToInt32(f, o + 12);
            byte[] b = new byte[taille];
            Array.Copy(f, debut, b, 0, taille);
            res.Add(new KeyValuePair<int, byte[]>(cote, b));
        }
        return res;
    }
}
'@

New-Item -ItemType Directory -Force -Path $Sortie | Out-Null
$racine = Resolve-Path (Join-Path $PSScriptRoot '..\..\..')
$erreurs = New-Object System.Collections.Generic.List[string]
$releve = New-Object System.Collections.Generic.List[string]

$groupe = [FsIconesExe]::PremierGroupe((Resolve-Path $Exe).Path)
$source = [FsIconesExe]::EntreesIco([IO.File]::ReadAllBytes((Join-Path $racine 'res\icon.ico')))
$tailles = @($groupe | ForEach-Object { $_.Key })
$releve.Add("$(Split-Path $Exe -Leaf) : $($tailles -join ', ') px")
if ((@($tailles | Sort-Object) -join ',') -ne (@($Attendu | Sort-Object) -join ',')) {
    $erreurs.Add("tailles de l'icône de l'exe : $($tailles -join ', '), attendu $($Attendu -join ', ')")
}
foreach ($e in $groupe) {
    $s = $source | Where-Object { $_.Key -eq $e.Key } | Select-Object -First 1
    $png = $e.Value.Length -gt 8 -and $e.Value[0] -eq 0x89 -and $e.Value[1] -eq 0x50
    $identique = $s -and ([Convert]::ToBase64String($s.Value) -eq [Convert]::ToBase64String($e.Value))
    $releve.Add("  $($e.Key) px : $($e.Value.Length) octets, $(if ($png) { 'PNG' } else { 'BMP' }), $(if ($identique) { 'identique à res/icon.ico' } else { 'DIFFÉRENT de res/icon.ico' })")
    if (-not $identique) { $erreurs.Add("image $($e.Key) px de l'exe différente de res/icon.ico") }
}

$data = Join-Path (Split-Path $Exe -Parent) 'data\flutter_assets\assets'
foreach ($f in 'icon.ico', 'icon.png', 'logo.png') {
    $p = Join-Path $data $f
    $ref = if ($f -eq 'icon.ico') { 'flutter\assets\icon.ico' } else { "flutter\assets\$f" }
    if (-not (Test-Path $p)) { $erreurs.Add("$f absent de data\flutter_assets\assets"); continue }
    $ok = (Get-FileHash $p).Hash -eq (Get-FileHash (Join-Path $racine $ref)).Hash
    $releve.Add("data\flutter_assets\assets\$f : $(if ($ok) { "identique à $ref" } else { "DIFFÉRENT de $ref" })")
    if (-not $ok) { $erreurs.Add("data\flutter_assets\assets\$f différent de $ref") }
}

# Planche : chaque image de l'exe à taille réelle sur barres claire et sombre, puis les petites ×6.
$images = @($groupe | ForEach-Object {
        $b = $_.Value
        if ($b[0] -eq 0x89 -and $b[1] -eq 0x50) {
            $img = [Drawing.Image]::FromStream((New-Object IO.MemoryStream (, $b)))
        } else {
            # Image DIB (BMP) : non dessinée (les icônes FS sont en PNG ; l'écart est déjà signalé plus haut).
            $img = New-Object Drawing.Bitmap $_.Key, $_.Key
            $gi = [Drawing.Graphics]::FromImage($img)
            $gi.Clear([Drawing.Color]::Magenta)
            $gi.Dispose()
        }
        [pscustomobject]@{ Cote = $_.Key; Image = $img }
    })
$petites = @($images | Where-Object { $_.Cote -le 32 })
$largeur = 40 + (($images | ForEach-Object { [Math]::Max($_.Cote, 40) + 20 }) | Measure-Object -Sum).Sum
$largeur = [Math]::Max($largeur, 40 + (($petites | ForEach-Object { $_.Cote * 6 + 20 }) | Measure-Object -Sum).Sum)
$hauteur = 60 + 2 * (256 + 50) + (32 * 6 + 50) + 20
$bmp = New-Object Drawing.Bitmap ([int]$largeur), ([int]$hauteur)
$g = [Drawing.Graphics]::FromImage($bmp)
$g.Clear([Drawing.Color]::FromArgb(251, 250, 246))
$police = New-Object Drawing.Font 'Segoe UI', 11
$titre = New-Object Drawing.Font 'Segoe UI', 14, ([Drawing.FontStyle]::Bold)
$g.DrawString("FS Support : icône extraite de $(Split-Path $Exe -Leaf) (compilation CI)", $titre, [Drawing.Brushes]::Black, 16, 14)
$y = 60
foreach ($fond in @(@{ C = [Drawing.Color]::FromArgb(243, 243, 243); T = [Drawing.Brushes]::Black }, @{ C = [Drawing.Color]::FromArgb(32, 32, 32); T = [Drawing.Brushes]::Gainsboro })) {
    $g.FillRectangle((New-Object Drawing.SolidBrush $fond.C), 10, $y, $largeur - 20, 256 + 40)
    $x = 24
    foreach ($i in $images) {
        $g.InterpolationMode = 'NearestNeighbor'
        $g.DrawImage($i.Image, $x, $y + 10 + (256 - $i.Cote), $i.Cote, $i.Cote)
        $g.DrawString("$($i.Cote)", $police, $fond.T, $x, $y + 270)
        $x += [Math]::Max($i.Cote, 40) + 20
    }
    $y += 256 + 50
}
$g.FillRectangle((New-Object Drawing.SolidBrush ([Drawing.Color]::FromArgb(243, 243, 243))), 10, $y, $largeur - 20, 32 * 6 + 40)
$x = 24
foreach ($i in $petites) {
    $g.InterpolationMode = 'NearestNeighbor'
    $g.PixelOffsetMode = 'Half'
    $g.DrawImage($i.Image, $x, $y + 10 + (32 - $i.Cote) * 6, $i.Cote * 6, $i.Cote * 6)
    $g.DrawString("$($i.Cote) px ×6", $police, [Drawing.Brushes]::Black, $x, $y + 32 * 6 + 14)
    $x += $i.Cote * 6 + 20
}
$g.Dispose()
$bmp.Save((Join-Path $Sortie 'logo-windows-exe.png'), [Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()

$releve | Set-Content -Encoding utf8 (Join-Path $Sortie 'logo-windows-exe.txt')
$releve | ForEach-Object { Write-Host $_ }
foreach ($e in $erreurs) { Write-Host "::error title=Icône de l'exe Windows::$e" }
if ($erreurs.Count) { exit 1 }
Write-Host "::notice title=Icône de l'exe Windows::$($tailles -join ', ') px, identiques à res/icon.ico"
