<#
  One Million Futures: daily story collector.

  Finds new coverage of the Milburn Review and adds it to data/stories.json.
  New stories are added with status "approved". They only reach the live site
  once the daily review pull request is merged, so the approver rejects anything
  unwanted by changing its status to "rejected" in that pull request.

  Usage (Windows PowerShell 5.1 or PowerShell 7, nothing to install):
    powershell -ExecutionPolicy Bypass -File pipeline\collect.ps1
    powershell -ExecutionPolicy Bypass -File pipeline\collect.ps1 -Backfill            # from config "since" to today
    powershell -ExecutionPolicy Bypass -File pipeline\collect.ps1 -Backfill -From 2026-05-01 -To 2026-06-30
#>
param(
  [switch]$Backfill,
  [string]$From,
  [string]$To,
  [string]$DataFile,
  [string]$ReviewFile,
  [int]$MaxLookups = -1
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch {}

$root = Split-Path -Parent $PSScriptRoot
if (-not $DataFile)   { $DataFile   = Join-Path $root "data\stories.json" }
if (-not $ReviewFile) { $ReviewFile = Join-Path $root "pipeline\out\review.md" }
$config = Get-Content (Join-Path $PSScriptRoot "config.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$utf8 = New-Object System.Text.UTF8Encoding $false
$inv  = [Globalization.CultureInfo]::InvariantCulture
$headers = @{ "User-Agent" = "Mozilla/5.0 (compatible; OneMillionFuturesBot/1.0; news tracker)"; "Accept-Language" = "en-GB,en;q=0.8" }
$since = [DateTime]::ParseExact($config.since, "yyyy-MM-dd", $inv)
$stats = [ordered]@{ fetched = 0; relevant = 0; duplicates = 0; added = 0; failedRequests = 0; titleLookups = 0 }

# ---------------------------------------------------------------- helpers
function Get-Text([string]$url) {
  Start-Sleep -Milliseconds 600
  try {
    $r = Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $headers -TimeoutSec 25
    return $utf8.GetString($r.RawContentStream.ToArray())
  } catch {
    $stats.failedRequests++
    Write-Warning "Request failed: $url ($($_.Exception.Message))"
    return $null
  }
}

function Clean-Text([string]$s) {
  if (-not $s) { return "" }
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  $s = $s -replace "<[^>]+>", " "
  $s = [System.Net.WebUtility]::HtmlDecode($s)
  return ($s -replace "\s+", " ").Trim()
}

function Limit-Words([string]$s, [int]$n) {
  $words = @($s -split " " | Where-Object { $_ })
  if ($words.Count -le $n) { return $s }
  return (($words[0..($n - 1)] -join " ").TrimEnd(",", ";", ":", ".", " ") + [char]0x2026)
}

# Note: this file is kept ASCII-only so Windows PowerShell 5.1 reads it correctly.
$quoteChars = "['``" + '"' + [char]0x2018 + [char]0x2019 + [char]0x201C + [char]0x201D + "]"
$notWordChars = "[^a-z0-9" + [char]0x00A3 + " ]"
function Normalize-Title([string]$t) {
  $t = $t.ToLowerInvariant() -replace $quoteChars, "" -replace $notWordChars, " "
  return ($t -replace "\s+", " ").Trim()
}

function Get-Words([string]$t) {
  return @((Normalize-Title $t) -split " " | Where-Object { $_.Length -gt 2 } | Select-Object -Unique)
}

function Get-Similarity([string]$a, [string]$b) {
  $wa = Get-Words $a; $wb = Get-Words $b
  if ($wa.Count -eq 0 -or $wb.Count -eq 0) { return 0 }
  $inter = @($wa | Where-Object { $wb -contains $_ }).Count
  $union = @($wa + $wb | Select-Object -Unique).Count
  return $inter / $union
}

function Clean-Url([string]$url) {
  try { $u = [Uri]$url } catch { return $url }
  $keep = @()
  if ($u.Query.Length -gt 1) {
    foreach ($p in $u.Query.TrimStart("?").Split("&")) {
      if ($p -and $p -notmatch "^(utm_|syn-|ocid=|cmpid=|at_|fbclid|gclid|ito=|CMP=)") { $keep += $p }
    }
  }
  $q = ""; if ($keep.Count) { $q = "?" + ($keep -join "&") }
  return $u.Scheme + "://" + $u.Host + $u.AbsolutePath + $q
}

function Get-CanonicalKey([string]$url) {
  try { $u = [Uri]$url } catch { return $url.ToLowerInvariant() }
  return (($u.Host -replace "^www\.", "") + $u.AbsolutePath.TrimEnd("/")).ToLowerInvariant()
}

function To-IsoDate([string]$s) {
  if (-not $s) { return $null }
  try { return ([DateTimeOffset]::Parse($s, $inv)).UtcDateTime.ToString("yyyy-MM-dd") } catch { return $null }
}

function Test-Relevant([string]$text, [bool]$strict) {
  $t = $text.ToLowerInvariant()
  foreach ($b in $config.relevance.blockAny) { if ($t.Contains($b)) { return $false } }
  $hasMain = $false; foreach ($m in $config.relevance.mustMatchAny) { if ($t.Contains($m)) { $hasMain = $true } }
  $hasCtx  = $false; foreach ($c in $config.relevance.contextAny)  { if ($t.Contains($c)) { $hasCtx = $true } }
  if ($strict) { return ($hasMain -and $hasCtx) }
  # Search results already matched our Milburn queries, so a looser check is enough
  foreach ($p in $config.relevance.searchPatterns) { if ($text -match $p) { return $true } }
  return $false
}

function Test-BlockedSource($c) {
  # Search engines sometimes surface low-quality sites whose "outlet" is just a web address
  if ($c.outlet -and $c.outlet -match "^https?://") { return $true }
  $target = ([string]$c.url + " " + [string]$c.outlet).ToLowerInvariant()
  foreach ($d in $config.relevance.blockDomains) { if ($target.Contains($d)) { return $true } }
  return $false
}

function Get-Themes([string]$text) {
  $found = @()
  foreach ($p in $config.themes.PSObject.Properties) { if ($text -match $p.Value) { $found += $p.Name } }
  return ,$found
}

function Get-Slug([string]$s) {
  $s = ($s.ToLowerInvariant() -replace "[^a-z0-9]+", "-").Trim("-")
  if ($s.Length -gt 24) { $s = $s.Substring(0, 24).Trim("-") }
  return $s
}

function Get-ShortHash([string]$s) {
  $sha = [System.Security.Cryptography.SHA1]::Create()
  $bytes = $sha.ComputeHash($utf8.GetBytes($s))
  return (($bytes[0..2] | ForEach-Object { $_.ToString("x2") }) -join "")
}

function Get-RssItems([string]$xmlText) {
  $out = @()
  if (-not $xmlText) { return $out }
  try { $x = [xml]$xmlText } catch { Write-Warning "Not valid RSS"; return $out }
  foreach ($i in @($x.rss.channel.item)) {
    if (-not $i) { continue }
    $src = $null; $srcUrl = $null
    foreach ($n in $i.ChildNodes) {
      if ($n.LocalName -eq "source" -or $n.LocalName -eq "Source") {
        $src = $n.InnerText
        if ($n.Attributes -and $n.Attributes["url"]) { $srcUrl = $n.Attributes["url"].Value }
      }
    }
    $title = $i.title; if ($title -isnot [string]) { $title = $i.title.InnerText }
    $desc  = $i.description; if ($desc -and $desc -isnot [string]) { $desc = $desc.InnerText }
    $out += [pscustomobject]@{ title = (Clean-Text $title); link = [string]$i.link; pubDate = [string]$i.pubDate; description = (Clean-Text $desc); source = $src; sourceUrl = $srcUrl }
  }
  return $out
}

function New-Candidate($title, $url, $outlet, $date, $summary, $type, $via, [bool]$needsLookup) {
  return [pscustomobject]@{ title = $title; url = $url; outlet = $outlet; date = $date; summary = $summary; type = $type; via = $via; needsLookup = $needsLookup }
}

# ---------------------------------------------------------------- sources
function Get-BingDecodedUrl([string]$link) {
  if ($link -match "[?&]url=([^&]+)") { return [Uri]::UnescapeDataString($Matches[1]) }
  return $link
}

function Search-Bing([string]$q) {
  $url = "https://www.bing.com/news/search?q=" + [Uri]::EscapeDataString($q) + "&format=rss&setlang=en-GB&cc=GB&count=50"
  $items = Get-RssItems (Get-Text $url)
  $res = @()
  foreach ($i in $items) {
    $res += New-Candidate $i.title (Clean-Url (Get-BingDecodedUrl $i.link)) $i.source (To-IsoDate $i.pubDate) $i.description "news" "bing" $false
  }
  return $res
}

function Search-Google([string]$q) {
  $url = "https://news.google.com/rss/search?q=" + [Uri]::EscapeDataString($q) + "&hl=en-GB&gl=GB&ceid=GB:en"
  $items = Get-RssItems (Get-Text $url)
  $res = @()
  foreach ($i in $items) {
    $title = $i.title
    if ($i.source -and $title.EndsWith(" - " + $i.source)) { $title = $title.Substring(0, $title.Length - $i.source.Length - 3) }
    # Google News descriptions only repeat the headline, so the summary is filled in later
    $res += New-Candidate $title $i.link $i.source (To-IsoDate $i.pubDate) "" "news" "google" $true
  }
  return $res
}

function Search-GovUk([string]$q) {
  $url = "https://www.gov.uk/api/search.json?q=" + [Uri]::EscapeDataString($q) + "&count=25&fields=title,link,description,format"
  $txt = Get-Text $url
  $res = @()
  if (-not $txt) { return $res }
  foreach ($r in ($txt | ConvertFrom-Json).results) {
    if ($config.govuk.skipFormats -contains $r.format) { continue }
    if (-not (Test-Relevant ($r.title + " " + $r.description) $true)) { continue }
    # The search API's timestamp is "last updated"; the content API has the real publication date
    $date = $null
    $content = Get-Text ("https://www.gov.uk/api/content" + $r.link)
    if ($content) { $c = $content | ConvertFrom-Json; $date = To-IsoDate ([string]$c.first_published_at) }
    $res += New-Candidate (Clean-Text $r.title) ("https://www.gov.uk" + $r.link) "GOV.UK" $date (Clean-Text $r.description) "official" "govuk" $false
  }
  return $res
}

function Read-Feed($feed) {
  $res = @()
  foreach ($i in (Get-RssItems (Get-Text $feed.url))) {
    if (-not (Test-Relevant ($i.title + " " + $i.description) $true)) { continue }
    $res += New-Candidate $i.title (Clean-Url $i.link) $feed.name (To-IsoDate $i.pubDate) $i.description "news" "feed" $false
  }
  return $res
}

# ---------------------------------------------------------------- load existing
if (Test-Path $DataFile) {
  $data = Get-Content $DataFile -Raw -Encoding UTF8 | ConvertFrom-Json
} else {
  $data = [pscustomobject]@{ review = [pscustomobject]@{ stage = "awaiting-final"; finalReport = [pscustomobject]@{ status = "awaiting"; expected = "November 2026"; url = $null } }; stories = @() }
}
$existing = @($data.stories)
$seenUrls = @{}; foreach ($s in $existing) { $seenUrls[(Get-CanonicalKey $s.url)] = $true }
$seenTitles = New-Object System.Collections.ArrayList
foreach ($s in $existing) { [void]$seenTitles.Add($s.title) }

function Test-Seen($c) {
  if ($seenUrls.ContainsKey((Get-CanonicalKey $c.url))) { return $true }
  foreach ($t in $seenTitles) { if ((Get-Similarity $t $c.title) -ge 0.75) { return $true } }
  return $false
}

# ---------------------------------------------------------------- collect
$candidates = @()
if ($Backfill) {
  if ($From) { $start = [DateTime]::ParseExact($From, "yyyy-MM-dd", $inv) } else { $start = $since }
  if ($To)   { $end = [DateTime]::ParseExact($To, "yyyy-MM-dd", $inv) } else { $end = (Get-Date).Date }
  $m = New-Object DateTime $start.Year, $start.Month, 1
  while ($m -le $end) {
    $next = $m.AddMonths(1)
    Write-Host ("Backfill " + $m.ToString("MMM yyyy"))
    foreach ($q in $config.googleNews.queries) {
      $candidates += Search-Google ($q + " after:" + $m.ToString("yyyy-MM-dd") + " before:" + $next.ToString("yyyy-MM-dd"))
    }
    $m = $next
  }
} else {
  foreach ($q in $config.googleNews.queries) { $candidates += Search-Google ($q + " " + $config.googleNews.dailyWindow) }
}
# Sources with real links and summaries go first, so they win when duplicates are merged
$primary = @()
foreach ($q in $config.bingNews.queries) { $primary += Search-Bing $q }
foreach ($q in $config.govuk.queries)    { $primary += Search-GovUk $q }
foreach ($f in $config.feeds)            { $primary += Read-Feed $f }
$candidates = $primary + $candidates
$stats.fetched = $candidates.Count

# ---------------------------------------------------------------- filter, merge, enrich
$accepted = New-Object System.Collections.ArrayList
foreach ($c in $candidates) {
  if (-not $c.title -or -not $c.url -or -not $c.date) { continue }
  $d = [DateTime]::ParseExact($c.date, "yyyy-MM-dd", $inv)
  if ($d -lt $since) { continue }
  if (Test-BlockedSource $c) { continue }
  $strict = ($c.via -eq "feed")
  if (-not (Test-Relevant ($c.title + " " + $c.summary) $strict)) { continue }
  $stats.relevant++
  if (Test-Seen $c) { $stats.duplicates++; continue }
  $dup = $false
  foreach ($a in $accepted) {
    if ((Get-CanonicalKey $a.url) -eq (Get-CanonicalKey $c.url) -or (Get-Similarity $a.title $c.title) -ge 0.75) { $dup = $true; break }
  }
  if ($dup) { $stats.duplicates++; continue }
  [void]$accepted.Add($c)
}

# Google-only stories: look the headline up on Bing to get the real link and a summary
foreach ($c in $accepted) {
  if (-not $c.needsLookup) { continue }
  $limit = $config.maxTitleLookups; if ($MaxLookups -ge 0) { $limit = $MaxLookups }
  if ($stats.titleLookups -ge $limit) { break }
  $stats.titleLookups++
  $best = $null; $bestScore = 0
  foreach ($b in (Search-Bing ('"' + $c.title + '"'))) {
    $score = Get-Similarity $b.title $c.title
    if ($score -gt $bestScore) { $best = $b; $bestScore = $score }
  }
  if ($best -and $bestScore -ge 0.7) {
    $c.url = $best.url; $c.summary = $best.summary; $c.needsLookup = $false
    if (-not $c.outlet) { $c.outlet = $best.outlet }
  }
}

# ---------------------------------------------------------------- add to data file
$today = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
$new = @()
foreach ($c in $accepted) {
  if ($seenUrls.ContainsKey((Get-CanonicalKey $c.url))) { continue }   # lookup may have revealed an existing URL
  $seenUrls[(Get-CanonicalKey $c.url)] = $true
  $outlet = $c.outlet; if (-not $outlet) { try { $outlet = ([Uri]$c.url).Host -replace "^www\.", "" } catch { $outlet = "Unknown" } }
  $outlet = ($outlet -replace "\s+on MSN$", "").Trim()
  $summary = [string]$c.summary
  if ($summary -match "\.\.\.$") { $summary = ($summary -replace "\s*\S*\s*\.\.\.$", "").Trim() }   # Bing cuts mid-word; drop the partial word
  $summary = Limit-Words $summary $config.maxSummaryWords
  if ($summary -and $summary -notmatch "[.!?" + [char]0x2026 + "'""]$") { $summary += [char]0x2026 }
  $story = [ordered]@{
    id      = ($c.date -replace "-", "") + "-" + (Get-Slug $outlet) + "-" + (Get-ShortHash (Get-CanonicalKey $c.url))
    status  = "approved"
    type    = $c.type
    outlet  = $outlet
    title   = $c.title
    url     = $c.url
    date    = $c.date
    summary = $summary
    themes  = (Get-Themes ($c.title + " " + $summary))
    foundVia = $c.via
    addedOn = $today
  }
  if (-not $summary) { $story.needsSummary = $true }
  if ($c.needsLookup) { $story.linkIsRedirect = $true }
  $new += [pscustomobject]$story
}
$stats.added = $new.Count

$all = @($existing) + $new | Sort-Object -Property @{ Expression = { $_.date }; Descending = $true }, @{ Expression = { $_.id } }
$data.stories = @($all)
$json = $data | ConvertTo-Json -Depth 8
# Windows PowerShell escapes some characters; restore them so the file is easy to read and edit
$json = $json -replace "\\u0027", "'" -replace "\\u0026", "&" -replace "\\u003c", "<" -replace "\\u003e", ">"
[IO.File]::WriteAllText($DataFile, $json + "`n", $utf8)

# ---------------------------------------------------------------- review summary (pull request body)
$lines = @()
$lines += "## $($new.Count) new " + $(if ($new.Count -eq 1) { "story" } else { "stories" }) + " to review"
$lines += ""
$lines += "**How to review:** open *Files changed* > ``data/stories.json``. For each new story below:"
$lines += "- :white_check_mark: Keep it: do nothing (it is already ``""status"": ""approved""``)."
$lines += "- :x: Reject it: change its status to ``""rejected""`` (keep the entry so it isn't collected again)."
$lines += "- :pencil2: Improve the summary or tags if you like. Stories marked :warning: need a summary written."
$lines += "- Add any LinkedIn posts (see ``docs/APPROVING.md``), then **Merge** to publish."
$lines += ""
foreach ($s in $new) {
  $flag = ""; if ($s.needsSummary) { $flag = " :warning: needs summary" }; if ($s.linkIsRedirect) { $flag += " :link: Google redirect link" }
  $lines += "- **$($s.title)**: $($s.outlet), $($s.date)$flag  "
  $lines += "  [$($s.url)]($($s.url))  "
  if ($s.summary) { $lines += "  _$($s.summary)_" }
}
$lines += ""
$lines += "<sub>Fetched $($stats.fetched) | relevant $($stats.relevant) | duplicates $($stats.duplicates) | title lookups $($stats.titleLookups) | failed requests $($stats.failedRequests)</sub>"
New-Item -ItemType Directory -Force (Split-Path $ReviewFile) | Out-Null
[IO.File]::WriteAllText($ReviewFile, ($lines -join "`n") + "`n", $utf8)

Write-Host ""
Write-Host "Done. Added $($stats.added) new stories." -ForegroundColor Green
$stats.GetEnumerator() | ForEach-Object { Write-Host ("  {0,-15} {1}" -f $_.Key, $_.Value) }
if ($env:GITHUB_OUTPUT) { Add-Content -Path $env:GITHUB_OUTPUT -Value "added=$($stats.added)" }
