param(
    [Parameter(Position = 0)]
    [ValidateSet("check", "lint", "format", "test", "preview", "export-web", "serve", "run", "editor", "import", "deploy-pages")]
    [string]$Action = "check",
    [int]$Port = 8080
)

$ErrorActionPreference = "Stop"
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$GodotCmd = Join-Path $env:USERPROFILE ".local\bin\godot.cmd"
$GodotGui = Join-Path $env:USERPROFILE ".local\bin\godot-gui.cmd"
$GdLint = Join-Path $env:USERPROFILE ".local\bin\gdlint.cmd"
$GdFormat = Join-Path $env:USERPROFILE ".local\bin\gdformat.cmd"

if (-not (Test-Path $GodotCmd)) {
    throw "godot.cmd not found at $GodotCmd"
}

function Get-ProjectScripts {
    $legacyRoot = @("debug_orb.gd", "h_box_container.gd", "interactable.gd", "mesh_instance_3d.gd")
    Get-ChildItem -Path $ProjectRoot -Recurse -Filter "*.gd" |
        Where-Object {
            $_.FullName -notmatch '\\\.godot\\|\\addons\\' -and
            ($_.DirectoryName -ne $ProjectRoot -or $legacyRoot -notcontains $_.Name)
        } |
        Select-Object -ExpandProperty FullName
}

switch ($Action) {
    "import" {
        Write-Host ">>> Importing Godot resources headless..." -ForegroundColor Cyan
        & $GodotCmd --headless --path $ProjectRoot --import --quit
    }
    "lint" {
        Write-Host ">>> Running gdlint across project GDScript files..." -ForegroundColor Cyan
        $scripts = Get-ProjectScripts
        & $GdLint @scripts
    }
    "format" {
        Write-Host ">>> Formatting GDScript files with gdformat..." -ForegroundColor Cyan
        $scripts = Get-ProjectScripts
        & $GdFormat @scripts
    }
    "test" {
        Write-Host ">>> Running headless automated test suite..." -ForegroundColor Cyan
        & $GodotCmd --headless --path $ProjectRoot --script res://tests/run_tests.gd
    }
    "preview" {
        Write-Host ">>> Capturing 5-wall projector visual screenshots..." -ForegroundColor Cyan
        & $GodotCmd --path $ProjectRoot --windowed --resolution 2400x270 --position 20,20 --script res://tools/capture_preview.gd
    }
    "export-web" {
        $webDir = Join-Path $ProjectRoot "exports\web"
        New-Item -ItemType Directory -Force -Path $webDir | Out-Null
        $indexPath = Join-Path $webDir "index.html"
        Write-Host ">>> Exporting HTML5 (WebGL2) build to $indexPath..." -ForegroundColor Cyan
        & $GodotCmd --headless --path $ProjectRoot --export-release "Web" $indexPath
        if ($LASTEXITCODE -ne 0) {
            throw "Godot HTML5 export failed with exit code $LASTEXITCODE"
        }

        Write-Host ">>> Generating separate synced walls.html and floor.html entrypoints..." -ForegroundColor Cyan
        $baseHtml = Get-Content $indexPath -Raw -Encoding UTF8

        # Kiosk hardening: auto-reload silently on WebGL context loss instead of blocking alert
        $contextLossSnippet = @"
<script>
window.addEventListener('DOMContentLoaded', function () {
	var c = document.getElementById('canvas');
	if (c) {
		c.addEventListener('webglcontextlost', function (e) {
			e.preventDefault();
			setTimeout(function () { window.location.reload(); }, 1500);
		}, false);
	}
});
</script>
"@

        foreach ($entry in @(
            @{ File = "walls.html"; Role = "walls"; Title = "Ephemeral Jeopardy - 4 Walls" },
            @{ File = "floor.html"; Role = "floor"; Title = "Ephemeral Jeopardy - Floor" }
        )) {
            $roleHtml = $baseHtml
            $roleHtml = $roleHtml -replace "<title>[^<]*</title>", "<title>$($entry.Title)</title>"
            $roleHtml = $roleHtml -replace '"args":\[\]', "`"args`":[`"--`",`"--role=$($entry.Role)`"]"
            $roleBootstrap = "<script>window.__IMMERSIVE_ROLE__ = '$($entry.Role)';</script>`n$contextLossSnippet`n</head>"
            $roleHtml = $roleHtml.Replace("</head>", $roleBootstrap)
            $outPath = Join-Path $webDir $entry.File
            Set-Content -Path $outPath -Value $roleHtml -Encoding UTF8
            Write-Host "    Wrote $outPath" -ForegroundColor Green
        }

        # GitHub Pages: serve every file raw (no Jekyll processing)
        $noJekyll = Join-Path $webDir ".nojekyll"
        Set-Content -Path $noJekyll -Value "" -NoNewline -Encoding ASCII
        Write-Host "    Wrote $noJekyll" -ForegroundColor Green
    }
    "deploy-pages" {
        Push-Location $ProjectRoot
        try {
            $originUrl = (& git remote get-url origin 2>$null)
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originUrl)) {
                throw "No 'origin' git remote configured. Create/push the GitHub repo first."
            }
            $originUrl = $originUrl.Trim()
        }
        finally {
            Pop-Location
        }

        foreach ($step in @("check", "export-web")) {
            Write-Host ">>> deploy-pages: running '$step'..." -ForegroundColor Cyan
            & powershell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath $step
            if ($LASTEXITCODE -ne 0) {
                throw "deploy-pages aborted: '$step' failed with exit code $LASTEXITCODE"
            }
        }

        $webDir = Join-Path $ProjectRoot "exports\web"
        $stageDir = Join-Path ([System.IO.Path]::GetTempPath()) ("ephemeral-jeopardy-pages-" + [guid]::NewGuid().ToString("N"))
        Write-Host ">>> Staging $webDir -> $stageDir" -ForegroundColor Cyan
        New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
        try {
            Copy-Item -Path (Join-Path $webDir "*") -Destination $stageDir -Recurse -Force
            $stagedNoJekyll = Join-Path $stageDir ".nojekyll"
            if (-not (Test-Path $stagedNoJekyll)) {
                Set-Content -Path $stagedNoJekyll -Value "" -NoNewline -Encoding ASCII
            }

            Push-Location $stageDir
            try {
                & git -c init.defaultBranch=gh-pages init -q -b gh-pages
                if ($LASTEXITCODE -ne 0) { throw "git init failed" }
                & git config core.autocrlf false
                & git add -A
                if ($LASTEXITCODE -ne 0) { throw "git add failed" }
                & git commit -q -m "Deploy Ephemeral Jeopardy WebGL2 to GitHub Pages"
                if ($LASTEXITCODE -ne 0) { throw "git commit failed" }
                Write-Host ">>> Force-pushing single-commit gh-pages to $originUrl..." -ForegroundColor Cyan
                & git push --force $originUrl gh-pages:gh-pages
                if ($LASTEXITCODE -ne 0) { throw "git push to gh-pages failed with exit code $LASTEXITCODE" }
            }
            finally {
                Pop-Location
            }
        }
        finally {
            Remove-Item -Recurse -Force -Path $stageDir -ErrorAction SilentlyContinue
        }
        Write-Host ">>> GitHub Pages deploy pushed (gh-pages, 1 commit)." -ForegroundColor Green
    }
    "serve" {
        $serveScript = Join-Path $ProjectRoot "tools\serve_room.py"
        python $serveScript --port $Port
    }
    "run" {
        & $GodotGui --path $ProjectRoot
    }
    "editor" {
        & $GodotGui --editor --path $ProjectRoot
    }
    "check" {
        Write-Host ">>> 1/3 Importing & verifying Godot scenes/scripts..." -ForegroundColor Cyan
        & $GodotCmd --headless --path $ProjectRoot --import --quit
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        Write-Host ">>> 2/3 Running gdlint..." -ForegroundColor Cyan
        $scripts = Get-ProjectScripts
        & $GdLint @scripts
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        if (Test-Path (Join-Path $ProjectRoot "tests\run_tests.gd")) {
            Write-Host ">>> 3/3 Running headless tests..." -ForegroundColor Cyan
            & $GodotCmd --headless --path $ProjectRoot --script res://tests/run_tests.gd
            if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
        }
        Write-Host ">>> All checks passed!" -ForegroundColor Green
    }
}
