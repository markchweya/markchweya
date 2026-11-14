# space/

Builds the animated panels under `assets/space/` that make up the profile page.

- `build.py`: fetches live data from GitHub's GraphQL API and writes self-contained animated SVGs
  (no scripts, external fonts or images) in the Lunar / Solar palette of the Repo Constellation hero.
- `config.json`: the hand-picked parts, which are the featured repositories and the tech stack groups.
- `fixture.json`: synthetic data for previews and tests only. Never commit panels rendered from it.
- `.github/workflows/space.yml`: runs daily, on demand and on changes here, and commits the panels.

Every number on the page comes from GitHub at build time. The default Actions token sees public
activity; add a `PROFILE_TOKEN` secret (fine-grained PAT, read-only) to include private contributions.

```sh
python3 -m unittest discover space/tests
python3 space/build.py --fixture space/fixture.json --out /tmp/space   # offline preview
```
