---
layout: post
title: 'When Hunting Becomes Detection: A Practitioner’s Perspective'
date: '2026-03-09 21:22:18 +0100'
category: [Security]
image: /assets/img/posts/huntingPractionerPerspective.png
alt: Cyberpunk-style illustration representing the transition from threat hunting exploration to operational detection engineering.
tags: [threat-hunting, detection-engineering, soc, cybersecurity]
---

## Transparency Note

This post is based on my **personal notes** and lab practice from four learning tracks: [**Practical Threat Hunting**](https://chrissanders.org/training/threat-hunting-training/) (course), [**TH-200**](https://www.offsec.com/courses/th-200/) (training), [**eCTHPv2**](https://ine.com/security/certifications/ecthp-certification) (certification path), and [**Cyber Threat Hunting (Coursera)**](https://www.coursera.org/learn/cyber-threat-hunting) as an introductory and quite basic course. This post reflects personal research, study notes, and lab practice. It does not represent the views of any employer and does not include proprietary detection content.

---

When I started studying threat hunting seriously, I expected the hard part to be writing better queries. In reality, the hardest part was conceptual: understanding where hunting ends and where detection engineering begins. On paper, the distinction looked simple. Hunting was described as proactive, hypothesis-driven, and human-centric; detection use cases were described as repeatable, tuned, and operational. But as soon as I practiced both in labs and note reviews, the line blurred. A hypothesis generated many events, I filtered and enriched them, then I repeated the logic in another cycle. At that point, was I still hunting, or had I already created a use case in disguise?

This confusion became even stronger because many modern SOC workflows use the same building blocks for both activities: the same SIEM, the same enrichment sources, the same ATT&CK mapping language, and often the same analysts. So while learning, I stopped asking “what does the textbook say?” and started asking “what objective am I serving at this exact step?” That ~~shit~~ shift changed everything for me.

---

## Where My Mental Model Changed

Across courses and labs, one common idea kept repeating: threat hunting assumes that something malicious may already be present but not yet surfaced by existing detections. That aligns with the spirit of proactive hunting described by [CISA’s threat hunt assessment service](https://www.cisa.gov/resources-tools/services/cyber-threat-hunt-assessment) and with control intent such as [NIST SP 800-53 RA-10 (Threat Hunting)](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final). Once I framed hunting as **discovery under uncertainty**, the “volume question” started to lose power.

In other words, I learned that hunting is not “big query = hunting.” Hunting is “I do not yet have enough confidence, and I am actively testing assumptions.” A use case is different: it exists when that uncertainty has been reduced enough to justify repeatable monitoring and predictable triage. The query can look similar in both moments, but the mission is different.

---

## ABH and DBH: Useful Labels, But Not Opposites

A lot of my early confusion came from terms like **ABH** and **DBH**. In the Practical Threat Hunting material, these labels are a practical teaching tool: **Attack-Based Hunting (ABH)** means starting from adversary behavior (“Has this happened here?”), while **Data-Based Hunting (DBH)** means starting from a telemetry domain (“What in this dataset is abnormal?”).

What helped me most was realizing ABH and DBH are complementary perspectives, not competing schools. ABH naturally connects to behavior frameworks such as [MITRE ATT&CK](https://attack.mitre.org/) and specifically ATT&CK [Enterprise Tactics](https://attack.mitre.org/tactics/enterprise/), while DBH benefits from strong baselines, anomaly reasoning, and high-quality telemetry. In practical hunts, I rarely stay in only one mode. I usually start in one mode and pivot into the other as evidence evolves.

If you prefer another framing, many teams describe the same split as **hypothesis-led** vs **data-led** hunting. Splunk has a useful practical example of hypothesis-led workflows here: [Hypothesis-Driven Cryptominer Hunting with PEAK](https://www.splunk.com/en_us/blog/security/hypothesis-driven-cryptominer-hunting-with-peak.html). That language maps closely to how ABH/DBH are taught in hands-on training.

---

## Why Volume Feels Like the Main Differentiator

I understand why many practitioners default to volume as the differentiator. Volume is visible. Uncertainty is not. If a hunt returns thousands of records and consumes analyst hours, it feels clearly “hunting-like.” If a detection runs quietly and only escalates high-confidence hits, it feels clearly “use-case-like.” But this is an operational symptom, not a conceptual definition.

Volume affects effort, fatigue, and triage cost; it does not define the nature of the activity. I can run a low-volume hunt on a narrow hypothesis and still be doing real hunting. I can also run a high-volume scheduled rule and still be in detection engineering territory if the logic and response path are already stable.

This is where terminology matters. We already have precise language for signal quality outcomes, including [false positives](https://csrc.nist.gov/glossary/term/false_positive) and [false negatives](https://csrc.nist.gov/glossary/term/false_negative). We also have standard language for evidence types, such as [Indicators of Compromise (IoCs)](https://csrc.nist.gov/glossary/term/indicator_of_compromise) and [TTPs](https://csrc.nist.gov/glossary/term/tactics_techniques_and_procedures). Using those terms consistently helps move teams away from the “only volume matters” shortcut.

---

## The Practical Boundary I Use Today

Today, I separate hunting from use-case engineering with a simple question: **am I trying to discover, or am I trying to operationalize?** If I am testing assumptions, challenging my own hypothesis, and still depending heavily on analyst interpretation, I am hunting. If the logic is already stable enough to run repeatedly with manageable noise and clear ownership, I am building or maintaining a detection use case.

This also matches how modern platforms describe proactive work. For example, Microsoft Sentinel positions hunts as proactive investigations that can start from specific techniques, suspicious behaviors, or custom hypotheses: [Conduct end-to-end proactive threat hunting in Microsoft Sentinel](https://learn.microsoft.com/en-us/azure/sentinel/hunts). The endpoint can be similar to what many teams call a use case, but the starting intent is still discovery.

So instead of forcing a rigid binary, I now treat this as a lifecycle:

- hypothesis and exploration,
- validation and refinement,
- operationalization into repeatable detection,
- feedback into new hypotheses.

This lifecycle perspective removed a lot of unnecessary debate for me.

---

## A Short Story Version of the Same Idea

If I had to summarize my learning journey in one story, it would be this: I started by trying to classify activities by how noisy they were, and I kept getting stuck. The more I practiced, the more I noticed that some of my “hunts” were already almost production-ready detections, while some “simple” queries were still true hunting because they challenged assumptions and uncovered blind spots. Once I switched from a **volume lens** to an **objective-and-confidence lens**, my decisions became clearer, my documentation improved, and my handoff from hunting to detection became more deliberate.

That does not mean the confusion disappears forever. It means the confusion becomes manageable because you have a framework: discovery first, then confidence, then operationalization.

---

## Final Takeaway

If your hypotheses often look similar to use cases, that is not necessarily a sign of poor hunting. It may be a sign that you are operating in the exact transition zone where threat hunting should create long-term defensive value. The key is not to separate the two by event volume, but to make your lifecycle stages explicit and intentional.

---

## References (High-Level)

- CISA Cyber Threat Hunt Assessment:
  - <https://www.cisa.gov/resources-tools/services/cyber-threat-hunt-assessment>
- NIST SP 800-53 Rev.5 (includes RA-10 Threat Hunting):
  - <https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final>
- MITRE ATT&CK:
  - <https://attack.mitre.org/>
- MITRE ATT&CK Enterprise Tactics:
  - <https://attack.mitre.org/tactics/enterprise/>
- NIST Glossary, Indicator of Compromise (IoC):
  - <https://csrc.nist.gov/glossary/term/indicator_of_compromise>
- NIST Glossary, Tactics Techniques and Procedures (TTP):
  - <https://csrc.nist.gov/glossary/term/tactics_techniques_and_procedures>
- NIST Glossary, False Positive:
  - <https://csrc.nist.gov/glossary/term/false_positive>
- NIST Glossary, False Negative:
  - <https://csrc.nist.gov/glossary/term/false_negative>
- Practical Threat Hunting (course page):
  - <https://www.networkdefense.co/courses/hunting/>
- OffSec TH-200 (course page):
  - <https://www.offsec.com/courses/th-200/>
- INE eCTHP Certification (official page):
  - <https://ine.com/security/certifications/ecthp-certification>
- Cyber Threat Hunting (Coursera, introductory/basic level):
  - <https://www.coursera.org/learn/cyber-threat-hunting>
- Microsoft Sentinel hunts (official documentation):
  - <https://learn.microsoft.com/en-us/azure/sentinel/hunts>
- Splunk example of hypothesis-driven hunting:
  - <https://www.splunk.com/en_us/blog/security/hypothesis-driven-cryptominer-hunting-with-peak.html>