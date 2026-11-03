# Approving stories: the daily routine

Takes about 2–5 minutes. Works in a desktop browser or the GitHub mobile app.

## Every morning

1. **Look for the email** from GitHub: *"Daily review: N new stories"*. No email means there was nothing new.
2. **Open the pull request.** The description lists every new story with its link and summary.
3. Go to **Files changed** → `data/stories.json` → the **⋯** menu → **Edit file**.
4. For each new story:
   - **Keep it:** do nothing. It already says `"status": "approved"`.
   - **Reject it** (off-topic, duplicate, not UK, low quality): change it to `"status": "rejected"`.
     Don't delete the entry, because it stops the same story being collected again.
   - **Improve it** (optional): edit the `summary` (aim for 2–3 sentences, in your own words if you can) or the `themes`.
   - Stories flagged **needs summary** have an empty `summary`, so write one or reject the story.
   - Stories flagged **Google redirect link** link through Google News. They still work, but you can paste the real article address into `url` if you have it.
5. **Commit changes** (to the same `daily-review` branch).
6. Click **Merge pull request**. The site updates within about 2 minutes.

> **Merge on the same day.** The next morning's run rebuilds the review branch from scratch, so any
> unmerged edits would be lost (the stories come back, but your changes don't).

## Adding a LinkedIn post (or any story the robot missed)

Add an entry at the top of the `"stories"` list. Copy this, fill it in, and keep the comma between entries:

```json
{
  "id": "20261103-linkedin-jane-smith",
  "status": "approved",
  "type": "linkedin",
  "outlet": "LinkedIn",
  "author": "Jane Smith, Head of Early Careers at Example Ltd",
  "title": "A short headline describing the post",
  "url": "https://www.linkedin.com/posts/...",
  "date": "2026-11-03",
  "summary": "Two or three sentences in your own words about what the post says.",
  "themes": ["Employers"],
  "foundVia": "manual",
  "addedOn": "2026-11-03"
},
```

- `id` must be unique. Use date + source + a short name.
- `type` is `news`, `official` or `linkedin`.
- Only add **public** posts. Credit the author and don't paste the whole post.
- Themes in use: Apprenticeships, Benefits & welfare, Mental health, SEND, Education & FE, Employers, Regional, Politics, Economy.

## Choosing the "Story of the day"

Add `"featured": true` to a story. The newest featured story is shown at the top. Remove the flag from older ones when you like.

## When the final report is published

At the top of `data/stories.json`, change:

```json
"finalReport": { "status": "published", "expected": "November 2026", "url": "https://www.gov.uk/..." }
```

The banner then switches to **"The final report is out. Read it →"**.

## If something goes wrong

- **No email for several days:** check the **Actions** tab in GitHub for a red ✗ on "Daily collection".
- **Site didn't update after merging:** check the "Publish site" run in the **Actions** tab.
- **Lots of junk stories:** add words to `blockAny`, or domains to `blockDomains`, in `pipeline/config.json`.
