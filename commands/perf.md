---
description: Diagnose web or backend performance from measurements and verify matched before/after results.
---

# Performance audit

Choose a representative user journey, measure the baseline, record the dominant delay, then validate the candidate with matched conditions. Load engineering-craft's [web-performance-audit](https://github.com/orocsy/engineering-craft) skill from its installed package or reviewed checkout. Use the existing [skill routing](../skills/skill-router/SKILL.md) fallbacks when unavailable, with [Chrome DevTools](https://developer.chrome.com/docs/devtools/performance/reference/) and [Web Vitals](https://web.dev/articles/vitals) as primary references.

Use the project's actual measurement and deployment entries. Begin with the live symptom and trace. Run profiling, bundle or code analysis when it addresses that symptom. Apply the chosen repair via the appropriate [workflow route](../docs/WORKFLOW_ROUTES.md) if within scope. Preserve the baseline, individual results, failed samples, release identity and concrete remaining work using the [delivery evidence](../docs/DELIVERY_EVIDENCE.md) record.

For a material decision, compare the relevant viewpoints from the technical skill and its references. For example, compare browser measurements with framework guidance and platform timings when the delay crosses those layers. Record which practices fit the observed bottleneck, which were set aside and why. If two options remain plausible, run a matched, reversible comparison and keep the individual results. When the symptom is a large production archive or a long release, confirm the deployed archive and source commit, then time build, backup, transfer, and live checks separately.
