[Console]::OutputEncoding = [Text.Encoding]::UTF8;
$base = "C:\Users\12983\github_dev\smartvision2\04-middleware\中间件列表";
$folders = @("已采用", "推荐采用", "未采用");
$files = Get-ChildItem -Path $base -Recurse -Filter "*.md" | Where-Object { $folders -contains $_.Directory.Name };
$gbk = [System.Text.Encoding]::GetEncoding(936);
$utf8 = [System.Text.Encoding]::UTF8;
foreach ($f in $files) {
    $garbled = [System.IO.File]::ReadAllText($f.FullName, $utf8);
    $recovered_bytes = $gbk.GetBytes($garbled);
    $recovered = $utf8.GetString($recovered_bytes);
    $bytes_with_bom = ([byte[]](239,187,191)) + $utf8.GetBytes($recovered);
    [System.IO.File]::WriteAllBytes($f.FullName, $bytes_with_bom);
    Write-Host ("Recovered: " + $f.Name);
}
