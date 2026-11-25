# LiyaFixes

Source for [liyafixes.dev](https://liyafixes.dev), a Hugo blog (PaperMod theme) deployed to GitHub Pages by GitHub Actions.

## Write a post

```bash
hugo new content posts/my-new-fix.md   # creates a draft
hugo server -D                          # preview at http://localhost:1313
```

Set `draft: false` (or delete the line), fill in `description` (the blurb shown on the home page), commit and push to `main`. The workflow in `.github/workflows/hugo.yml` builds and publishes automatically.

## Clone

The theme is a git submodule:

```bash
git clone --recurse-submodules https://github.com/pandaboy6621/liyafixes.git
```
