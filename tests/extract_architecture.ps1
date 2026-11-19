$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = 'Z:/GITHUB/_ASSETS/ASSETS/3D/Buildings-Shops/Downtown City MegaKit[Standard].zip'
$destination = Join-Path $PSScriptRoot '../sydney/architecture/megakit'
[IO.Directory]::CreateDirectory($destination) | Out-Null
$zip = [IO.Compression.ZipFile]::OpenRead($archive)
$prefix = 'Exports/glTF (Godot)/'
$modules = @('Brick_Window_Square_Single','Brick_Window_CurvedDouble','Trim_Window','Trim_FirstFloor_Window_Columns','Metal_FullWindow','Metal_FirstFloor_Window','Cornice_Trim_Center','Prop_ACUnit')
$files = [Collections.Generic.HashSet[string]]::new()
$inventory = @()
foreach ($module in $modules) {
    $entry = $zip.GetEntry($prefix + $module + '.gltf')
    $reader = [IO.StreamReader]::new($entry.Open())
    $model = $reader.ReadToEnd() | ConvertFrom-Json
    $reader.Dispose()
    $files.Add($entry.FullName) | Out-Null
    foreach ($dependency in @($model.buffers) + @($model.images)) {
        $files.Add($prefix + $dependency.uri) | Out-Null
    }
    $inventory += [pscustomobject]@{name=$module; nodes=$model.nodes; positionAccessors=@($model.accessors | Where-Object {$_.type -eq 'VEC3' -and $_.min}); materials=$model.materials}
}
$files.Add('License_Standard.txt') | Out-Null
foreach ($file in $files) {
    $entry = $zip.GetEntry($file)
    if ($null -eq $entry) { throw "Missing dependency $file" }
    $target = Join-Path $destination $entry.Name
    if (Test-Path -LiteralPath $target) { throw "Refusing to overwrite $target" }
    [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target)
}
$inventory | ConvertTo-Json -Depth 15 | Set-Content -Encoding UTF8 (Join-Path $destination 'inventory.json')
Get-FileHash -LiteralPath $archive -Algorithm SHA256 | Format-List
$zip.Dispose()
Write-Output "Extracted $($modules.Count) models and only their dependencies ($($files.Count) files)."
