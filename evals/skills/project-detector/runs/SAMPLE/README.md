# Example run (worked reference — not a real eval result)

These six `*.json` files are a **synthetic candidate set** used to demonstrate and self-verify
`../../score.py`. They are intentionally imperfect (e.g. `02` omits `netlify`; `06` wrongly marks
the Rust project as a monorepo) so you can see the scorer discriminate. Running:

```
python3 ../../score.py --batch .
```

against this folder produces (at time of authoring):

| case | total | why not 100 |
|------|-------|-------------|
| 01-next-vercel-prisma | 100.0 | perfect |
| 02-vite-react-netlify | 68.2 | missed `netlify` deploy target (hard); no `buildTool` (soft) |
| 03-nest-fly-drizzle | 100.0 | perfect |
| 04-turbo-monorepo | 92.5 | no top-level `framework` for the monorepo (soft) |
| 05-python-fastapi-docker | 83.0 | emitted `"generic docker"` where expected `"docker"` (hard miss, soft-credited) |
| 06-rust-compose | 78.8 | wrongly set `monorepo: true` (hard) |
| **mean** | **87.1** | |

**This is NOT a baseline for the real skill.** A real run goes in `runs/<plugin-sha>/` from the
actual `project-detector` output on each `cases/` fixture, and its mean is what you log to
`../results.tsv` and ratchet on. Keep this folder only as a reference for the scorer's behaviour.
