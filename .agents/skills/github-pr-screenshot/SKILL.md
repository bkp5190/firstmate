---
name: github-pr-screenshot
description: >-
  Agent-only technique for making a local evidence screenshot actually visible on GitHub.
  Use before referencing a local screenshot path (for example ~/.no-mistakes/evidence/<run-id>/after.png) in a PR description, PR comment, or `done:` status line.
  Uploads the file to GitHub's attachment endpoint and embeds the returned URL as markdown instead.
user-invocable: false
metadata:
  internal: true
---

# github-pr-screenshot

A local file path is meaningless to anyone viewing a PR on github.com.
A crewmate that took a real before/after screenshot as task evidence must upload it to GitHub and embed the resulting URL, never just name the local path, before that path goes into a PR description, PR comment, or `done:` status line.

## Use the wrapper

```
bin/fm-pr-screenshot-upload.sh <owner/repo> <local-file-path> [<local-file-path> ...]
```

Prints one markdown image line per file to stdout, in the form `![filename]` immediately followed by `(url)`, in argument order.
Capture that output straight into a PR body, `gh pr comment`, or a `done:` line.
On a mixed batch, a failed file reports its error on stderr and a nonzero exit while every file that did succeed still prints its markdown line, so partial output is still usable.
The script's own header is the authoritative source for its exact flags and error behavior.

## The underlying technique

GitHub has no officially documented API for uploading an image into a PR or issue body.
The wrapper drives the same undocumented endpoint the github.com web UI itself uses for drag-and-drop attachments:

```
curl -sS -X POST \
  "https://uploads.github.com/user-attachments/assets?name=<filename>&content_type=<mime-type>&repository_id=<numeric-repo-id>" \
  -H "Authorization: Bearer $(gh auth token)" \
  -H "Accept: application/json" \
  --data-binary "@<local-file-path>"
```

This returns `{"url": "https://github.com/user-attachments/assets/<uuid>"}`.
Get `<numeric-repo-id>` with `gh api repos/<owner>/<repo> --jq '.id'`.
Embed the returned URL as `![alt text]` immediately followed by `(url)`; GitHub renders it inline wherever it renders markdown (PR body, PR comment, issue comment).

## Caveats

**Unofficial endpoint.**
`uploads.github.com/user-attachments/assets` is not in GitHub's published REST API documentation and could change or stop working without notice.
Verified working 2026-09-04.
If it breaks, that is an accepted risk of this approach, not a reason to silently fall back to committing screenshots into the repo - escalate instead.

**Requires push access to the target repo.**
The authenticated `gh` token needs write (push) access to `<owner/repo>`.
A pull-only token gets a bare `{"message":"Not Found"}` from the upload call, indistinguishable from a genuinely bad request - if an upload fails against a repo you expect to have write access to, check access first before assuming the endpoint itself broke.

**Private-repo asset URLs need an authenticated viewer.**
On a private repo, the returned asset URL does not resolve for an unauthenticated `curl` (404) - it needs a request from a client with access, the same as any other private-repo image attachment.
This is expected GitHub behavior, not a defect: the image still renders normally to anyone with repo access viewing the PR or issue on github.com.
