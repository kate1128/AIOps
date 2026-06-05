[Console]::OutputEncoding = [Text.Encoding]::UTF8;
$base = "C:\Users\12983\github_dev\smartvision2\04-middleware\中间件列表";
$files = [System.IO.Directory]::GetFiles($base, "*.md", [System.IO.SearchOption]::AllDirectories);
$utf8 = [System.Text.Encoding]::UTF8;
$count = 0;
$emDash = [char]0x2014;
$checkmark = [char]0x2705;
foreach ($f in $files) {
    $data = [System.IO.File]::ReadAllBytes($f);
    $text = $utf8.GetString($data);
    $orig = $text;
    $text = $text -replace "$([char]0xFFFD)$([char]0x003F)", $emDash;
    if ($text -ne $orig) {
        $bytes_with_bom = ([byte[]](239,187,191)) + $utf8.GetBytes($text);
        [System.IO.File]::WriteAllBytes($f, $bytes_with_bom);
        $count++;
        Write-Host ("Fixed: " + $f);
    }
}
Write-Host ("Fixed " + $count + " files");
