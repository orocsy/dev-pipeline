# Delivery evidence and briefing

Keep one dated working record per release or audit. Update the same record when a stage changes. Write it so a successor can resume from the actual branch, run or artifact without rerunning completed work.

| Record | Minimum detail |
|---|---|
| User problem and desired result | Who sees what, where and what they should be able to do |
| Before | Reproduction, URL/version/date, observed effect and source artifact |
| Diagnosis | What the evidence establishes, alternative explanations tested, remaining unknown |
| Change | Which component changed, what it now does, and why this addresses the problem |
| Verification | Test inputs and what each check proves. Identify the real entry, runtime, permissions, substituted components and resulting user behavior |
| Delivery | Source commit, branch, operation/run and readback. Separate local checks, CI, production enablement and live acceptance |
| Outcome | Relevant before/after values and conditions. List remaining failures, external waits and owner/next check |
| Time | Start and end where measured. Separate wall time from parallel jobs and leave unmeasured work unallocated |

Before briefing, compare each claimed result to a receipt. Expand internal names on first use. If the result says “verified”, the reader must know who did what on which system and what they would see. Include a short acceptance example. Prefer an evidence link to a test count. For mixed test/live runs, state the exact part replaced with a fixture.

Example: “A shop administrator could upload a large PNG but customers saw a broken image because the cloud function could not return its encoded bytes. The site now returns a smaller web copy and keeps the original. We fetched five affected URLs and checked the complete bytes. Google is still rechecking the earlier crawl errors.”

Quality pass: read the final briefing alone. Can a reader explain the original problem, what changed, current outcome, proof and what happens next? If any answer depends on a worklog or shorthand, rewrite the relevant sentence. For an external wait, record its last observed state and trigger; don't keep checking a report whose refresh date hasn't changed.

For every unresolved item, record who can act next and what evidence will change the state. Example: “Google is still rechecking five image addresses. The website returned all five correct files today. Check when Google reports a new crawl, then investigate any newly failing exact URL.” Keep deployment or report wait time separate from hands-on work. Open the remaining item before running a second release; use a local reproduction if it can answer the same question.

## Website verification at handoff

Tie each open question to one dated row that the next session can read before starting a new run. Record the live URL or selected page type, change and release identity, evidence and date, current disposition, person or system that can move it, and the single next observation that would change the disposition. If a report has the same data date and its exact examples were already verified, use the last evidence. Reopen the item when an example, report date or live behavior changes.

Before pushing an approved delivery, refresh the remote source and integration refs and check for competing releases. Before a production write, read the versions the affected services actually run and compare them to the proposed source. If either comparison has drifted, inspect the missing changes and confirm the release route before proceeding. Record the current refs, the proposed source and exact operation in the handoff. Push the verified handoff and reusable changes to their authorized remote branches or review PRs so the next agent can continue from them.

Before a consequential change, record which technical guidance was used and which site evidence makes it applicable. When credible options disagree, compare them under matching conditions and keep negative results. Store URL-level measurements in the project. Return reusable diagnostic methods to Engineering Craft and changes to sequencing or evidence requirements to Dev Pipeline.

For a speed change, retain the exact element and metric, before and after sample counts, conditions, observed range and any slower comparison page. Cite one diagnostic trace or measured stage and give the reader a plain explanation of what was waiting. Record a confounded comparison as diagnostic evidence and link the isolated test when it exists. A description of a check must say which user behavior it protects. For example, testing a product's option picker verifies that earlier image loading did not break selecting a configuration or asking for a quote. The picker test does not establish a search result.

Link the one current release run. Count a deployment wait and an external search-platform wait separately. Repeat a failed run after recording the resolved cause or the new hypothesis the run will test. When that work remains queued, report the actual queue state and say which customer-visible result remains unverified.

During a long delivery, put the buyer-visible result or remaining defect first. If a job is still running, identify the exact operation and its latest completed step. Keep work on independent items while the job runs. When a repeat would use the same code, input and observation, record what new evidence would justify it before starting. A failed experiment is a completed finding when its result is documented and the candidate is withdrawn.

When a user asks about an older briefing, start with the actual result they pointed to. State the visitor or operator, the entry they used, the failure or delay, the part changed, and the evidence that answers their question. Link the older receipt from that paragraph. If the results were mixed, include the candidate that got slower and the decision to keep or withdraw it. For case reuse, keep project measurements in the project. Transfer the diagnostic rule with its scope and counterexample to Engineering Craft.

If an authorized release is blocked before the site code runs, name the blocked step and keep its receipt. Keep the launch check as pending. An existing passed test can be cited for the behavior it covers. Re-run the failed attempt only when the dependency recovered or the next attempt tests a changed condition. Do not count queue time, runner setup, or waiting for a third-party report as time spent implementing a fix.
