# REANNZ training environment: Better Research Software

An Open OnDemand app that gives each learner **VS Code in the browser**
([code-server](https://github.com/coder/code-server)) in their own pod on the
training environment, set up to run the Carpentries Incubator lesson
[Building Better Research Software][brs].

It is derived from [training-environment-vscode-app][vscode-app] v1.0.2 with the
GPU and Slurm emulators removed, and adds the lesson's **spacewalks** example
project and a local wheelhouse for the Python packages the lesson installs.

[brs]: https://carpentries-incubator.github.io/better-research-software/
[vscode-app]: https://github.com/MattBixley/training-environment-vscode-app

## What a learner gets

- VS Code (code-server 4.139.1), opened at `~/spacewalks`. The **Connect to VS
  Code** button logs straight in.
- `~/spacewalks`, copied from the lesson's
  [`spacewalks.zip`](https://github.com/carpentries-incubator/better-research-software/raw/refs/heads/main/learners/spacewalks.zip)
  on first start. It is never refreshed, so learners' renames, deletions and
  commits survive a restart. A clean copy stays at `/opt/spacewalks`:

  ```bash
  cp -a /opt/spacewalks ~/spacewalks-fresh
  ```

- Extensions: Python, Python Debugger, basedpyright (Pylance is not on Open
  VSX), autoDocstring, Git Graph and Live Preview. Live Preview opens the
  `htmlcov/` coverage report and the `site/` built by mkdocs.
- Python 3.12 with `venv` and `pip`. **No packages are installed in the system
  Python.** Episode 3 has learners create `venv_spacewalks` and install into
  it, and that only makes sense if the packages are missing beforehand.
- `/etc/pip.conf` points pip at `/opt/wheelhouse`, which holds wheels for
  pandas, matplotlib, numpy, pytest, pytest-cov, mkdocs, mkdocstrings[python]
  and mkdocs-material. It holds both the latest releases and the versions
  episode 7 pins (`pandas==2.2.2 matplotlib==3.8.4 numpy==2.0.0
  pytest==7.4.2`). pip still uses PyPI as well; the wheelhouse means a room of
  learners installing at once does not depend on PyPI being fast.
- git with `init.defaultBranch main` and `core.editor "nano -w"` set system
  wide. Learners set their own `user.name` and `user.email`, as the setup
  check asks.
- `ssh`, `ssh-keygen` and the GitHub CLI (`gh`). SSH to `github.com` goes over
  port 443 (`ssh.github.com`), and GitHub's host keys are pinned in
  `/etc/ssh/ssh_known_hosts`. Keys live in the learner's NFS home and survive
  restarts.
- A `code` command that wraps code-server, so the lesson's setup check
  (`code --version`, `code --list-extensions`) works.
- `.DS_Store` is visible in the Explorer. VS Code hides it by default, but
  episode 1 asks learners to look at it.

## Things the lesson does deliberately

Do not "fix" these in the image:

- `my code v2.py` has a space in its name and hardcodes
  `/home/sarah/Projects/astronaut-analysis/data.json`. Episode 1 runs it to
  show the `FileNotFoundError`.
- `spacewalks/.DS_Store` is there for episode 3 to add to `.gitignore`.
- There is no `.git` in spacewalks. Learners run `git init` in episode 2.

## Notes for instructors

- **Episode 2 remote URL typo.** The lesson shows
  `git remote add origin git@github.com/<handle>/spacewalks.git`. The correct
  form uses a colon: `git@github.com:<handle>/spacewalks.git`.
- **GitHub authentication.** The lesson uses SSH keys
  (`ssh-keygen -t ed25519`, paste the `.pub` into
  <https://github.com/settings/ssh/new>, then `ssh -T git@github.com`). This
  works here over port 443. Ask learners to remove the key from GitHub after
  the workshop. Learners who cannot use SSH can run `gh auth login` and use an
  `https://` remote instead. Pushing `.github/workflows/*.yml` needs the
  `workflow` scope.
- **Browser-only steps.** Creating repositories, issues, pull requests,
  GitHub Actions, GitHub Pages, cffinit and Zenodo Sandbox all happen in the
  learner's own browser and GitHub account.
- **Catch-up repository.**
  [carpentries-incubator/bbrs-software-project](https://github.com/carpentries-incubator/bbrs-software-project)
  has one branch per episode for learners who fall behind.

## Resources

The launch form offers 2 or 4 CPUs, 4 or 8 GB of memory and 1 to 12 hours. The
defaults (2 CPUs, 4 GB, 8 hours) are enough for the whole lesson.

## Running it locally

```bash
./run-local.sh --build      # build from this checkout and open http://localhost:8443/
./run-local.sh --shell      # a terminal in the same environment
```

There is no password, LDAP or NFS locally, and the home directory is thrown
away when the container stops.

## Layout

| Path | Purpose |
|---|---|
| `docker/Dockerfile` | Ubuntu 24.04 image: code-server, extensions, git, gh, wheelhouse, spacewalks |
| `docker/code-server/settings.json` | Default VS Code settings, written only if the learner has none |
| `docker/ssh/` | GitHub over port 443, pinned GitHub host keys |
| `template/before.sh.erb` | Picks the port and generates the session password |
| `template/script.sh.erb` | Stages spacewalks, extensions and settings, then starts code-server |
| `template/after.sh.erb` | Waits for code-server to listen |
| `form.yml`, `submit.yml.erb` | Launch form and the k8s pod spec |
| `view.html.erb` | The Connect button on the session card |
| `icon.png` | REANNZ logo, the app's dashboard tile |

## Releasing

The image tag in `submit.yml.erb` is what a session runs. It must match the git
tag; CI fails a tag build when they differ.

1. Set `image:` in `submit.yml.erb` to the new tag.
2. Commit, then `git tag vX.Y.Z && git push origin main vX.Y.Z`.
3. CI builds and pushes `ghcr.io/mattbixley/training-environment-better-research-software-app:vX.Y.Z`.
   New ghcr packages are private; make the package public so the cluster can pull it.
4. In `training-environment`, on a workshop branch with no underscores in its
   name, add the app to `vars/ondemand-config.yml.example` with matching
   `k8s_container` and `version`, then run the deploy workflow.

To move spacewalks to a newer lesson commit, update `LESSON_HASH` and
`SPACEWALKS_SHA256` in `docker/Dockerfile` together.

## Licence

The app is MIT licensed (see `LICENSE`). The lesson is CC-BY 4.0 by The
Carpentries Incubator contributors. The spacewalks data comes from the NASA
Open Data Portal.
