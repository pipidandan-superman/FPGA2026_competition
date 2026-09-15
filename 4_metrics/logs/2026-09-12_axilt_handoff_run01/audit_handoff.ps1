$ErrorActionPreference='Stop'
$root='E:\competition\2_fpga\2_axi_lite_test'
$run='E:\competition\4_metrics\logs\2026-09-12_axilt_handoff_run01'
$build='E:\competition\4_metrics\logs\2026-09-12_axilt_reg_build_run03'
$sim='E:\competition\4_metrics\logs\2026-09-12_axilt_reg_sim_run02'
$rtl=@(Get-ChildItem -LiteralPath (Join-Path $root 'rtl') -File | ForEach-Object {
    $hash=(Get-FileHash -LiteralPath $_.FullName).Hash
    [pscustomobject]@{file=$_.Name;sha256=$hash;
        build_match=$hash -eq (Get-FileHash -LiteralPath (Join-Path $build ('source\rtl\'+$_.Name))).Hash;
        sim_match=$hash -eq (Get-FileHash -LiteralPath (Join-Path $sim ('source\rtl\'+$_.Name))).Hash}
})
$baseline=@((Get-Content -LiteralPath (Join-Path $build 'baseline_hashes.json') -Raw -Encoding UTF8 | ConvertFrom-Json) | ForEach-Object {
    [pscustomobject]@{path=$_.path;unchanged=$_.sha256 -eq (Get-FileHash -LiteralPath $_.path).Hash}
})
$links=@(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.md' | ForEach-Object {
    $file=$_.FullName
    $directory=$_.DirectoryName
    foreach($m in [regex]::Matches((Get-Content -LiteralPath $file -Raw -Encoding UTF8),'\[[^\]]+\]\(([^)]+)\)')){
        $target=$m.Groups[1].Value.Trim('<','>')
        if($target -notmatch '^(https?:|#)'){
            $path=[IO.Path]::GetFullPath((Join-Path $directory ($target.Split('#')[0])))
            [pscustomobject]@{file=$file;target=$path;exists=(Test-Path -LiteralPath $path)}
        }
    }
})
$ok=(@($rtl | Where-Object { -not $_.build_match -or -not $_.sim_match }).Count -eq 0) -and
    (@($baseline | Where-Object { -not $_.unchanged }).Count -eq 0) -and
    (@($links | Where-Object { -not $_.exists }).Count -eq 0)
$result=[pscustomobject]@{
    marker=$(if($ok){'AXILT_HANDOFF_AUDIT_PASS'}else{'FAIL'});
    rtl=$rtl;baseline=$baseline;links=$links;
    board_status='REG_BOARD_PENDING';bram_status='NOT_STARTED_GATE_PENDING'
}
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $run 'handoff_audit.json') -Encoding UTF8
if(Test-Path -LiteralPath (Join-Path $run 'handoff_source')){throw 'Handoff snapshot already exists'}
Copy-Item -LiteralPath $root -Destination (Join-Path $run 'handoff_source') -Recurse
$result | ConvertTo-Json -Depth 5
if(-not $ok){exit 1}
