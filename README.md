# One Million Futures

An independent news tracker following the **Milburn Review** (*Young People and Work*), the UK review into the
one million 16–24 year olds who are not in education, employment or training.

Every morning a GitHub Action collects new UK coverage and opens a **Daily review** pull request.
A person checks the stories, and merging the pull request publishes them to the site.

## How it works

| Part | File |
|---|---|
| Web page | `index.html`, `css/styles.css`, `js/app.js` |
| All stories (approved and rejected) | `data/stories.json` |
| Published stories (generated) | `data/stories.js` |
| Collector settings: queries, feeds, filters | `pipeline/config.json` |
| Daily collector | `pipeline/collect.ps1` |
| Site build | `pipeline/build.ps1` |
| Automation | `.github/workflows/collect.yml` (daily), `.github/workflows/deploy.yml` (publish) |
| Approver instructions | `docs/APPROVING.md` |

Everything is PowerShell and plain HTML/CSS/JS, with no packages to install and no running costs.

## Run locally (Windows)

```
powershell -ExecutionPolicy Bypass -File pipeline\collect.ps1
powershell -ExecutionPolicy Bypass -File pipeline\build.ps1
powershell -ExecutionPolicy Bypass -File tools\serve.ps1
```

Then open http://localhost:8080.

Headlines, summaries and links belong to their publishers. This site isn't affiliated with the government or the review.
