param([string]$ScenePath = (Join-Path $PSScriptRoot 'scene.json'))
$ErrorActionPreference = 'Stop'
$scene = Get-Content -LiteralPath $ScenePath -Raw -Encoding UTF8 | ConvertFrom-Json
$app = $null
$saveBase = Join-Path $scene.output_dir $scene.basename
function Set-Cell($shape, [string]$name, [string]$formula) { $shape.CellsU($name).FormulaU=$formula }
function N([double]$value) { return $value.ToString('0.#####',[cultureinfo]::InvariantCulture) }
function Get-Rgb([string]$hex) {
 $r=[Convert]::ToInt32($hex.Substring(1,2),16);$g=[Convert]::ToInt32($hex.Substring(3,2),16);$b=[Convert]::ToInt32($hex.Substring(5,2),16)
 return "RGB($r,$g,$b)"
}
function Add-Node($s) {
 $shape=$page.DrawRectangle($s.x*$scale,($height-$s.y-$s.h)*$scale,($s.x+$s.w)*$scale,($height-$s.y)*$scale)
 $shape.NameU=$s.id; $shape.Text=$s.text
 Set-Cell $shape 'FillPattern' $(if($s.fill -eq 'none'){'0'}else{'1'})
 if($s.fill -ne 'none'){Set-Cell $shape 'FillForegnd' (Get-Rgb $s.fill)}
 Set-Cell $shape 'LinePattern' $(if($s.stroke -eq 'none'){'0'}elseif($s.dash){'2'}else{'1'})
 if($s.stroke -ne 'none'){Set-Cell $shape 'LineColor' (Get-Rgb $s.stroke)}
 Set-Cell $shape 'LineWeight' ((N ($s.lw*$scale*72))+' pt')
 Set-Cell $shape 'Rounding' ((N ($s.radius*$scale))+' in')
 Set-Cell $shape 'Char.Font' 'FONT("Microsoft YaHei")'
 Set-Cell $shape 'Char.AsianFont' 'FONT("Microsoft YaHei")'
 Set-Cell $shape 'Char.Size' ((N ($s.fs*$scale*72))+' pt')
 Set-Cell $shape 'Char.Style' $(if($s.bold){'1'}else{'0'})
 Set-Cell $shape 'Char.Color' (Get-Rgb $s.color)
 Set-Cell $shape 'Para.HorzAlign' ([string]$s.align)
 Set-Cell $shape 'VerticalAlign' '1'
 Set-Cell $shape 'LeftMargin' '0.012 in';Set-Cell $shape 'RightMargin' '0.012 in'
 Set-Cell $shape 'TopMargin' '0.004 in';Set-Cell $shape 'BottomMargin' '0.004 in'
 $byId[$s.id]=$shape; $sourceById[$s.id]=$s
}
function Add-Edge($e) {
 [double[]]$points=@()
 foreach($p in $e.points){$points+=([double]$p[0]*$scale);$points+=(($height-[double]$p[1])*$scale)}
 $shape=$page.DrawPolyline([ref]$points,8);$shape.NameU=$e.id
 Set-Cell $shape 'LineColor' (Get-Rgb $e.color)
 Set-Cell $shape 'LineWeight' ((N ($e.lw*$scale*72))+' pt')
 Set-Cell $shape 'LinePattern' $(if($e.dash){'2'}else{'1'})
 Set-Cell $shape 'BeginArrow' $(if($e.start){'13'}else{'0'})
 Set-Cell $shape 'EndArrow' $(if($e.end){'13'}else{'0'})
 Set-Cell $shape 'BeginArrowSize' '1';Set-Cell $shape 'EndArrowSize' '1'
 Set-Cell $shape 'FillPattern' '0'; $lines[$e.id]=$shape
}
try {
 $app=New-Object -ComObject Visio.InvisibleApp
 $doc=$app.Documents.Add('');$doc.Title='EES-331 PC PS PL System Atlas';$doc.Subject='Fixed action payload and v1.4 software, planned extensions labelled'
 $audit=@();$i=0
 foreach($sheet in $scene.pages){
  $page=$(if($i -eq 0){$doc.Pages.Item(1)}else{$doc.Pages.Add()});$page.Name=$sheet.name
  $scale=[double]$sheet.width_inches/[double]$sheet.width;$height=[double]$sheet.height
  $byId=@{};$sourceById=@{};$lines=@{}
  Set-Cell $page.PageSheet 'PageWidth' ((N $sheet.width_inches)+' in')
  Set-Cell $page.PageSheet 'PageHeight' ((N $sheet.height_inches)+' in')
  Set-Cell $page.PageSheet 'PrintPageOrientation' '2'
  foreach($s in $sheet.shapes | Where-Object {$_.kind -eq 'container'}){Add-Node $s}
  foreach($e in $sheet.edges){Add-Edge $e}
  foreach($s in $sheet.shapes | Where-Object {$_.kind -ne 'container'}){Add-Node $s}
  $glued=0
  foreach($e in $sheet.edges){
   foreach($which in @('src','dst')){
    $id=$e.$which;if(-not $id){continue};$s=$sourceById[$id]
    $p=$(if($which -eq 'src'){$e.points[0]}else{$e.points[-1]})
    $fx=([double]$p[0]-$s.x)/$s.w;$fy=1-([double]$p[1]-$s.y)/$s.h
    $cell=$(if($which -eq 'src'){'BeginX'}else{'EndX'})
    $lines[$e.id].CellsU($cell).GlueToPos($byId[$id],$fx,$fy);$glued++
   }
  }
  $page.Export((Join-Path $scene.output_dir ($sheet.basename+'.svg')))
  $audit += [ordered]@{page=$sheet.name;shapes=$page.Shapes.Count;native_nodes=$sheet.shapes.Count;native_connectors=$sheet.edges.Count;glued_endpoints=$glued}
  Write-Output ('PAGE_BUILT '+$sheet.name+' shapes='+$page.Shapes.Count)
  $i++
 }
 $doc.SaveAs($saveBase+'.vsdx');$doc.ExportAsFixedFormat(1,$saveBase+'.pdf',1,0)
 $doc.Close()
 $check=$app.Documents.Open($saveBase+'.vsdx')
 if($check.Pages.Count -ne 6){throw 'Wrong number of pages after native round trip'}
 $result=[ordered]@{marker='VISIO_BUILD_PASS';visio_version=$app.Version;pages=$check.Pages.Count;round_trip='PASS';page_details=$audit}
 $result | ConvertTo-Json -Depth 7 | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'visio_build.json') -Encoding UTF8
 $check.Close();Write-Output 'VISIO_BUILD_PASS pages=6'
} finally {if($null -ne $app){$app.Quit()}}
