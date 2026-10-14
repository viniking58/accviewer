# Gera todos os icones e logos do AccViewer a partir dos PNG grandes de
# accviewer-marca\png (renderizados dos SVG desta pasta) e grava por cima dos
# arquivos do RustDesk: Windows (.ico/.png), Flutter (assets) e Android (mipmap).
# Rodar de novo sempre que o desenho mudar.

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$Marca = $PSScriptRoot
$Raiz = Split-Path $Marca -Parent
$Png = Join-Path $Marca 'png'

function Redimensionar([string]$origem, [int]$largura, [int]$altura) {
    $img = [System.Drawing.Image]::FromFile($origem)
    try {
        $bmp = New-Object System.Drawing.Bitmap($largura, $altura, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
        $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $atributos = New-Object System.Drawing.Imaging.ImageAttributes
        $atributos.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
        $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, $largura, $altura)), 0, 0, $img.Width, $img.Height, [System.Drawing.GraphicsUnit]::Pixel, $atributos)
        $g.Dispose()
        return $bmp
    } finally { $img.Dispose() }
}

function Salvar-Png([string]$origem, [int]$tamanho, [string]$destino) {
    $bmp = Redimensionar $origem $tamanho $tamanho
    New-Item -ItemType Directory -Force -Path (Split-Path $destino -Parent) | Out-Null
    $bmp.Save($destino, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
}

# .ico com DIB 32 bits nos tamanhos pequenos e PNG no de 256 (o formato que o
# rc.exe, o Windows Explorer e a bandeja aceitam sem surpresa).
function Salvar-Ico([string]$origem, [int[]]$tamanhos, [string]$destino) {
    $imagens = @()
    foreach ($t in $tamanhos) {
        $bmp = Redimensionar $origem $t $t
        if ($t -ge 256) {
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $imagens += , @($t, $ms.ToArray())
        } else {
            $ms = New-Object System.IO.MemoryStream
            $w = New-Object System.IO.BinaryWriter($ms)
            $w.Write([int32]40); $w.Write([int32]$t); $w.Write([int32]($t * 2))
            $w.Write([int16]1); $w.Write([int16]32); $w.Write([int32]0)
            $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0); $w.Write([int32]0)
            for ($y = $t - 1; $y -ge 0; $y--) {
                for ($x = 0; $x -lt $t; $x++) {
                    $c = $bmp.GetPixel($x, $y)
                    $w.Write([byte]$c.B); $w.Write([byte]$c.G); $w.Write([byte]$c.R); $w.Write([byte]$c.A)
                }
            }
            $linhaMascara = [int]([math]::Ceiling($t / 32.0) * 4)
            $w.Write((New-Object byte[] ($linhaMascara * $t)))
            $w.Flush()
            $imagens += , @($t, $ms.ToArray())
        }
        $bmp.Dispose()
    }
    $saida = New-Object System.IO.MemoryStream
    $w = New-Object System.IO.BinaryWriter($saida)
    $w.Write([int16]0); $w.Write([int16]1); $w.Write([int16]$imagens.Count)
    $deslocamento = 6 + 16 * $imagens.Count
    foreach ($i in $imagens) {
        $t = $i[0]; $dados = $i[1]
        $lado = if ($t -ge 256) { 0 } else { $t }
        $w.Write([byte]$lado); $w.Write([byte]$lado); $w.Write([byte]0); $w.Write([byte]0)
        $w.Write([int16]1); $w.Write([int16]32); $w.Write([int32]$dados.Length); $w.Write([int32]$deslocamento)
        $deslocamento += $dados.Length
    }
    foreach ($i in $imagens) { $w.Write([byte[]]$i[1]) }
    $w.Flush()
    [System.IO.File]::WriteAllBytes($destino, $saida.ToArray())
}

$icone = Join-Path $Png 'icone.png'
$frente = Join-Path $Png 'icone-frente.png'
$notificacao = Join-Path $Png 'icone-notificacao.png'

# Windows
Copy-Item $icone (Join-Path $Raiz 'res\icon.png') -Force
Salvar-Png $icone 32 (Join-Path $Raiz 'res\32x32.png')
Salvar-Png $icone 64 (Join-Path $Raiz 'res\64x64.png')
Salvar-Png $icone 128 (Join-Path $Raiz 'res\128x128.png')
Salvar-Png $icone 256 (Join-Path $Raiz 'res\128x128@2x.png')
Salvar-Ico $icone @(16, 20, 24, 32, 40, 48, 64, 128, 256) (Join-Path $Raiz 'res\icon.ico')
Salvar-Ico $icone @(16, 20, 24, 32, 40, 48, 64) (Join-Path $Raiz 'res\tray-icon.ico')
Copy-Item (Join-Path $Raiz 'res\icon.ico') (Join-Path $Raiz 'flutter\windows\runner\resources\app_icon.ico') -Force

# Flutter (telas do programa)
Copy-Item (Join-Path $Marca 'icone.svg') (Join-Path $Raiz 'flutter\assets\icon.svg') -Force
Salvar-Png $icone 256 (Join-Path $Raiz 'flutter\assets\icon.png')
Copy-Item (Join-Path $Raiz 'res\icon.ico') (Join-Path $Raiz 'flutter\assets\icon.ico') -Force
Copy-Item (Join-Path $Png 'logo-escuro.png') (Join-Path $Raiz 'flutter\assets\logo_dark.png') -Force
Copy-Item (Join-Path $Png 'logo-claro.png') (Join-Path $Raiz 'flutter\assets\logo_light.png') -Force

# Android
$res = Join-Path $Raiz 'flutter\android\app\src\main\res'
$densidades = [ordered]@{ mdpi = 1.0; hdpi = 1.5; xhdpi = 2.0; xxhdpi = 3.0; xxxhdpi = 4.0 }
foreach ($d in $densidades.Keys) {
    $f = $densidades[$d]
    $pasta = Join-Path $res "mipmap-$d"
    Salvar-Png $icone ([int](48 * $f)) (Join-Path $pasta 'ic_launcher.png')
    Salvar-Png $icone ([int](48 * $f)) (Join-Path $pasta 'ic_launcher_round.png')
    Salvar-Png $frente ([int](108 * $f)) (Join-Path $pasta 'ic_launcher_foreground.png')
    Salvar-Png $notificacao ([int](24 * $f)) (Join-Path $pasta 'ic_stat_logo.png')
}

Write-Host 'AccViewer: imagens geradas.'
