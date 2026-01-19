# Git Push Script
Set-Location "C:\Code\JDCP\DNS"

Write-Host "`nAdding files..." -ForegroundColor Cyan
git add .

Write-Host "`nCommitting changes..." -ForegroundColor Cyan
git commit -m "v4: Complete parity with Microsoft built-in plus enhancements - 59 total policies (25 built-in + 34 custom)"

Write-Host "`nPushing to GitHub..." -ForegroundColor Cyan
git push

Write-Host "`nDone!" -ForegroundColor Green
Write-Host "`nPress any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
