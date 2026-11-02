---
layout: post
title: 'Threat Hunting in Practice: A Field Guide from Hypothesis to Detection'
description: 'A practical guide to threat hunting: how to frame hypotheses, assess telemetry, run an investigation, work across teams, and turn findings into durable detections.'
date: '2026-11-02 00:00:00 +0100'
category: [Security, Threat Hunting]
image: /assets/img/posts/threat_hunting_notes.png
tags: [threat-hunting, detection-engineering, incident-response, threat-intelligence, mitre-attack]
---

> This article reflects my experience across incident response, threat modeling, and threat hunting, together with notes from training, labs, and the references linked throughout the text. Parts of it had been sitting in my notes for some time, but I never really had the motivation to finish and publish it. That changed after a message from my mate [Roncari](https://github.com/GabrielRoncari), which encouraged me to revisit the material, refine my thoughts, and finally share it.
>
> The views expressed here are my own and do not represent those of any employer or include proprietary detection content. The ATT&CK references were checked against version 20.0, released on October 13, 2026. ATT&CK evolves over time, so always consult the latest version before applying a technique, analytic, or relationship in a live hunt. ([MITRE ATT&CK Version History](https://attack.mitre.org/resources/versions/))

When I began studying threat hunting seriously, I expected queries to be the hard part. They can certainly become complicated, but they were rarely where I got stuck. The harder questions came earlier and later: What am I actually looking for? Can our data show it? What would weaken my hypothesis? If I find something, who owns the next decision?

Threat hunting is often summarized as “looking for threats that security tools did not detect.” That is a useful starting point, although it leaves out most of the work. NIST control RA-10 describes threat hunting as a proactive search for signs of threats that may have evaded existing controls, with the purpose of detecting, tracking, and disrupting them while improving protection and response. ([NIST SP 800-53 Rev. 5, RA-10](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final))

My own starting point is more concrete. If an action took place, what traces should it have left behind? A process changes system state. A credential produces authentication events. A connection crosses several layers of the network. Persistence has to survive some form of transition. MITRE's TTP-based hunting method works from a similar premise: adversary behavior tends to outlive individual indicators and can be translated into evidence to search for in local data. ([MITRE, TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting))

That question sounds a little like digital forensics, and there is a real relationship between the two. Forensics places particular weight on the collection, preservation, examination, and interpretation of digital evidence. A hunt may begin with operational telemetry, sampling, and exploratory queries whose immediate purpose is to decide whether there is a case worth escalating. Once evidence of compromise appears, the work may move into a formal incident response or forensic process with different requirements for preservation and handling. ([NIST SP 800-86](https://csrc.nist.gov/pubs/sp/800/86/final); [NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))

I also do not see “threat hunter” as a mandatory job title. Some organizations have a dedicated team. In others, SOC analysts, incident responders, detection engineers, intelligence analysts, and endpoint specialists hunt when the situation calls for it. The NICE Framework makes a useful distinction between work roles, which group tasks and knowledge, and the jobs an organization creates from those roles. The need to investigate under uncertainty often appears before the budget or maturity for a dedicated position. ([NIST NICE, Occupations, Jobs, and Work Roles](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center/resources/occupations-jobs-and-work))

## 1. A working definition

This is the definition I use in practice:

> Threat hunting is a deliberate, iterative investigation conducted under uncertainty to find and interpret evidence of adversary activity or relevant exposure that existing controls do not explain well enough.

The hunt should end with a decision. That may be to close the hypothesis with a documented rationale, expand collection, fix a visibility gap, validate a candidate detection, or transfer the case to incident response.

The definition carries a few practical conditions:

- A hunt has a reason, a scope, and a question. Browsing dashboards can generate ideas, but by itself it is still exploration.
- The process is iterative. The result of one query changes the next question. TaHiTI organizes hunting into initiation, execution, and finalization for the same reason: the work needs direction and a defined handoff. ([TaHiTI Threat Hunting Methodology](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/))
- Uncertainty is explicit. At the beginning, we may not know whether the behavior occurred, whether it is malicious, or whether our telemetry can distinguish it from normal operations.
- Claims follow evidence. A convincing threat story without observable data is still a possibility. A query with no relationship to a question is technical exploration.
- The result has to support action. Finding an intruder is one outcome. A hunt can also expose missing logs, unsafe configuration, recurring false positives, a weak assumption, or a detection opportunity. PEAK treats those improvements as part of the value of hunting. ([Splunk, PEAK Threat Hunting Framework](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html))

“Proactive” does not mean predicting the future or proving that a hidden attacker exists. It means beginning an investigation without waiting for a conclusive alert. The assume-breach mindset is a way to test visibility and resilience, not evidence that a breach occurred. Hunting techniques can also support a reactive or post-incident investigation by looking for related entities, earlier activity, or variants missed by the original detection. Microsoft uses advanced hunting for both proactive exploration and alert investigation. ([Microsoft Defender XDR, Advanced Hunting Overview](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-overview))

### Where hunting sits next to other security work

| Activity                        | Main question                                                                 | Practical boundary                                                                                                  | Reference                                                                                                                                |
| ------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| Alert triage                    | “Is this known alert true, and how urgent is it?”                             | Starts from an operationalized condition. Most of the uncertainty is in classifying the event.                      | [NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final)                                                                   |
| Incident response               | “How do we contain, eradicate, and recover from this incident?”               | Begins once there is enough basis to treat the event as a potential or confirmed incident.                          | [NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final)                                                                   |
| Digital forensics               | “What happened, and what evidence supports that conclusion?”                  | Gives specific attention to acquiring, preserving, and examining evidence for the purpose of the investigation.     | [NIST SP 800-86](https://csrc.nist.gov/pubs/sp/800/86/final)                                                                             |
| Detection engineering           | “How do we turn understood behavior into reliable, testable, operable logic?” | Builds and maintains a repeatable control, including testing, deployment, ownership, and monitoring.                | [Sigma Rule Specification](https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html)                          |
| Threat intelligence             | “Which actors, campaigns, capabilities, and indicators matter to us?”         | Supplies context and priorities. Hunting tests that context against the local environment and returns observations. | [NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final)                                                                           |
| Red team or adversary emulation | “Can our controls prevent and observe an authorized adversary behavior?”      | Executes controlled behavior. Hunting searches for its traces and can use the exercise to validate telemetry.       | [MITRE ATT&CK, Adversary Emulation and Red Teaming](https://attack.mitre.org/resources/get-started/adversary-emulation-and-red-teaming/) |

These activities overlap. A hunt may begin with intelligence, use a Red Team emulation, produce a detection, identify an incident, and end in a forensic investigation. Naming each transition helps the team assign ownership and use the right handling process.

## 2. Discovery or operationalization?

One question cleared up much of my early confusion: **Am I trying to discover, or am I trying to operationalize?**

Query size is a poor boundary. A simple search can be a real hunt if it tests a possibility that the team does not yet understand. A large correlation can be a detection use case if the signals, thresholds, and triage procedure are already stable.

I use these meanings:

- Discovery asks whether a behavior exists locally, how it appears in the data, which signals separate it from normal activity, and which benign explanations still compete with the hypothesis.
- Operationalization takes behavior that is understood well enough to run repeatedly. It needs stable telemetry, tests, predictable triage, ownership, and maintenance.

This maps well to the different hunting modes described in PEAK and to the idea of turning repeatable findings into detection improvements. I like the “hunt once” principle as a direction: automate the part that has become well understood. Some investigations will not produce an automated alert, and forcing them to do so usually creates a brittle rule. ([Splunk, PEAK Threat Hunting Framework](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html); [Sigma Specification](https://sigmahq.io/sigma-specification/))

For backlog management, I use three working states:

| State               | Purpose                                                      | What it looks like                                                                      | Expected output                                                             |
| ------------------- | ------------------------------------------------------------ | --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Discovery hunt      | Learn how a threat or anomaly appears in this environment    | High uncertainty; queries and pivots change as the analyst learns                       | Evidence, a visibility gap, a new question, a case, or a documented closure |
| Validation hunt     | Test whether candidate signals are stable and discriminating | Clearer behavior and scope; historical replay and controlled testing                    | Criteria, known false-positive classes, coverage, and a recommendation      |
| Detection candidate | Prepare logic for continuous operation                       | Stable telemetry, testable logic, estimated volume, a triage owner, and a response path | Rule, tests, documentation, runbook, and monitoring plan                    |

These names are my operational shorthand, not a universal taxonomy. Their purpose is to show when the team is still learning and when it is accepting responsibility for a production control.

Before I promote a finding to detection, I check whether:

1. the source and required fields have known coverage and latency;
2. the logic survives historical replay and, where safe, an authorized test;
3. the main false-positive classes are documented;
4. volatile details have an update mechanism;
5. severity, owner, queue, SLA, and triage steps are defined;
6. the rule can be versioned, tested, monitored, and retired.

Sigma provides an open specification for log detection logic, but portability does not remove differences in schema, collection, or semantics. Local validation still decides whether the rule works. ([Sigma Rule Specification](https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html))

## 3. The knowledge that supports a hunt

There is no single route into threat hunting. Experience across several layers helps because investigations routinely cross systems built and owned by different teams.

### Network behavior

DNS, TCP/IP, HTTP(S), proxies, VPNs, routing, and common communication patterns give network events meaning. Zeek produces structured records of observed protocols and activity, while Suricata can record alerts and transactions in EVE JSON. Their usefulness depends on sensor placement, visible traffic, and configuration, and they answer different questions. ([Zeek Log Files](https://docs.zeek.org/en/current/reference/logs/index.html); [Suricata EVE JSON Output](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html))

### Operating systems and endpoints

Processes, modules, services, scheduled tasks, registry state, files, memory, and authentication form the basic language of endpoint investigation. On Windows, audit event 4688 records process creation when the relevant policy is enabled. Sysmon adds other event types whose meaning should be checked against the official documentation. One small example matters here because it is often repeated incorrectly: Sysmon Event ID 7 is **Image Load**, while Event ID 10 is **Process Access**. ([Microsoft, Event 4688](https://learn.microsoft.com/windows/security/threat-protection/auditing/event-4688); [Microsoft, Sysmon Events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events))

### Identity, applications, and cloud

Important actions do not always appear as a suspicious endpoint process. Privilege changes, application consent, key creation, token use, API calls, and authentication often live in identity and control-plane logs. Joint logging guidance recommends prioritizing critical systems, identity services, edge devices, administrative workstations, applications, and cloud services, then centralizing and protecting those records. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))

### Data and query languages

SPL, KQL, SQL, and other languages are useful, but the transferable skills sit underneath the syntax: filtering, aggregation, cardinality, time windows, joins, normalization, null handling, deduplication, and bias. Microsoft Defender advanced hunting uses KQL and its own schema; another platform will expose a different model. I try to phrase the question so that it survives a tool change even when the implementation does not. ([Microsoft Defender XDR, Advanced Hunting Overview](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-overview))

### Automation

Python, PowerShell, shell, and APIs remove repetitive work and make enrichment or analysis reproducible. I delay automation until I understand the interpretation I am about to encode. PowerShell logging, including Script Block Logging, can improve visibility, although collection, protection, and retention remain part of the control design. ([Microsoft, PowerShell Security Features](https://learn.microsoft.com/en-us/powershell/scripting/learn/security-features))

### Adversary behavior

ATT&CK gives teams a common vocabulary for objectives, techniques, software, groups, and evidence. It still needs local context. In the current ATT&CK model, detection work should use **Detection Strategies**, **Analytics**, and **Data Components** linked to techniques. The older **Data Sources** pages were deprecated beginning with version 18. ([MITRE ATT&CK Detection Strategies](https://attack.mitre.org/detectionstrategies/); [MITRE ATT&CK Data Components](https://attack.mitre.org/datacomponents/); [MITRE ATT&CK Data Sources deprecation notice](https://attack.mitre.org/datasources/))

### Communication

A finding only becomes useful when the person who can act on it understands the observation, confidence, limitations, and recommendation. TaHiTI includes preparation and finalization because the last query does not close the hunt. The work ends when evidence and recommendations reach the responsible process. ([TaHiTI Threat Hunting Methodology](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/))

Nobody needs to master every layer before starting. What changes with experience is the quality of the hypothesis and the pivots. A broader technical base makes it easier to imagine competing explanations, choose better data, and recognize when another specialist should take the lead.

## 4. Security is not an island

I have seen technically sound investigations head in the wrong direction because nobody knew why a service existed, how an application authenticated, which support tools were approved, or what changed during the period under review. SIEM access does not answer those questions. Local context changes the meaning of the evidence.

A working hunting relationship usually includes:

- CTI, which turns campaigns, actors, exploited vulnerabilities, TTPs, and indicators into local priorities. Hunting tests those priorities and returns observations. NIST SP 800-150 describes structured processes for producing, consuming, publishing, and maintaining threat information. ([NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final))
- Red Team, penetration testing, and adversary emulation, which reproduce authorized behavior to test prevention and visibility. MITRE and the Center for Threat-Informed Defense publish emulation plans that can support this work. ([MITRE ATT&CK Adversary Emulation Plans](https://attack.mitre.org/resources/adversary-emulation-plans/); [CTID Adversary Emulation Library](https://ctid.mitre.org/resources/adversary-emulation-library/))
- The SOC, which understands the real alert flow, volume, triage process, and escalation path. It receives mature detections and reports whether they are usable.
- Incident Response and DFIR, which take over when a case needs containment, scope analysis, eradication, recovery, or formal evidence handling. ([NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))
- Detection Engineering, which converts validated signals into operable controls and maintains their tests, code, content, and telemetry dependencies.
- Infrastructure, identity, application, cloud, and business owners, who explain expected behavior and approved changes.
- Vulnerability Management, which connects technical exposure, asset criticality, observed exploitation, and remediation. CISA's KEV catalog records vulnerabilities known to be exploited, while EPSS estimates the probability of observed exploitation in the next 30 days. Neither replaces local impact and exposure analysis. ([CISA Known Exploited Vulnerabilities Catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog); [FIRST EPSS FAQ](https://www.first.org/epss/faq))

### When a new threat, CVE, or bypass appears

I avoid beginning with a query copied from a public report. First I work through a short sequence:

1. Qualify the source. What was observed, by whom, in which product, and with what confidence? Keep confirmed exploitation separate from a public proof of concept or a theoretical path.
2. Check local relevance. Does the affected asset, version, service, identity, or architecture exist here? KEV, EPSS, and intelligence help with priority, while local inventory establishes exposure. ([CISA KEV](https://www.cisa.gov/known-exploited-vulnerabilities-catalog); [FIRST EPSS](https://www.first.org/epss/))
3. Model the behavior. What preconditions and actions would exploitation require? Which ATT&CK techniques genuinely apply? ([MITRE ATT&CK Enterprise Matrix](https://attack.mitre.org/matrices/enterprise/))
4. Map visibility. Which events should appear before, during, and after the action? Check coverage, latency, and retention.
5. Validate the interpretation. CTI can check the intelligence, system owners can confirm the architecture, and a Red Team or lab can reproduce behavior when authorization and safe conditions exist.
6. Run the hunt. Search the relevant scope and period, record limitations, and keep benign explanations alive.
7. Act on the result. The output may be an IR case, remediation, new collection, a detection candidate, temporary monitoring, or a documented closure.

This sequence gives the team room to distinguish a real local exposure from public noise without dismissing a threat simply because the literal IoC did not appear.

## 5. Visibility comes before the hypothesis

A hypothesis is testable only when there is a plausible link between the action and the collected data. Missing events may mean the activity did not occur. They may also mean that a sensor was absent, ingestion failed, retention was too short, a filter removed the event, clocks were wrong, or the architecture contained a blind spot. In my notes, “not found” never becomes “did not happen” without a statement about coverage.

Joint logging guidance recommends an organizational policy, centralized collection, integrity protection, time synchronization, suitable retention, cross-source correlation, and monitoring of pipeline health. It also recommends choosing logs according to risk and investigative value, since collecting everything forever is neither realistic nor necessarily useful. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))

### Useful data domains

| Domain              | Examples                                                                       | Questions it can answer                                                    | References                                                                                                                                                                                                                   |
| ------------------- | ------------------------------------------------------------------------------ | -------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Endpoint            | Process, command line, hash, module, service, task, file, registry, connection | What executed? Who started it? What state changed?                         | [Sysmon Events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events); [Windows Event 4688](https://learn.microsoft.com/windows/security/threat-protection/auditing/event-4688) |
| Network             | DNS, flow, proxy, TLS, HTTP, IDS, selected PCAP                                | Which systems communicated? Does the pattern fit the asset's function?     | [Zeek Logs](https://docs.zeek.org/en/current/reference/logs/index.html); [Suricata EVE](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html); [Wireshark Documentation](https://www.wireshark.org/docs/)      |
| Identity            | Login, MFA, token, consent, privilege, group change, failure                   | Who authenticated, from where, to which resource, and with what privilege? | [Best Practices for Event Logging](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection)                                                                                               |
| Cloud and SaaS      | API calls, control plane, audit, storage, workload, email                      | What configuration or data changed outside a traditional endpoint?         | [Best Practices for Event Logging](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection)                                                                                               |
| Application         | Authentication, session, transaction, error, business event                    | Did the technical action make sense for the application and user?          | [OWASP Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)                                                                                                                         |
| Internal context    | Inventory, owner, function, criticality, vulnerability, change, approved tool  | Is this event expected for this asset at this time?                        | [NIST CSF 2.0](https://www.nist.gov/cyberframework)                                                                                                                                                                          |
| Threat intelligence | TTP, infrastructure, malware, campaign, indicator validity and confidence      | Why are we looking for this, and over which period?                        | [NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final)                                                                                                                                                               |

Before using a dataset, I record:

- which population of assets, users, or workloads sends data;
- what the event proves and what it only suggests;
- whether the required fields are consistently populated;
- time synchronization, normalized time zone, and ingestion latency;
- whether retention covers the hypothesis window;
- whether an attacker or local administrator could disable, change, or delete the source;
- whether hostnames, accounts, IPs, and IDs resolve across sources;
- whether enough history exists for comparison;
- whether access, privacy, purpose, and minimization are defined.

ATT&CK Data Components provide product-neutral names for observable properties such as process creation and file modification. Each team still has to map those properties to its sensors, schemas, and local gaps. ([MITRE ATT&CK Data Components](https://attack.mitre.org/datacomponents/))

## 6. Ways to start a hunt

The labels vary across methodologies. I find it more useful to record the trigger, the uncertainty, and the method than to argue over a universal taxonomy. TaHiTI provides a structured cycle, PEAK separates hypothesis-driven, baseline, and model-assisted approaches, and MITRE's TTP-based method begins with adversary behavior. The categories below are my practical combination of those ideas. ([TaHiTI](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/); [Splunk, The PEAK Threat Hunting Framework](https://www.splunk.com/en_us/form/the-peak-threat-hunting-framework.html); [Cisco Talos PEAK content](https://github.com/Cisco-Talos/PEAK); [MITRE TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting))

### Behavior or hypothesis driven

This approach starts with a plausible action: abuse of a legitimate remote access tool, token misuse, scheduled-task persistence, or lateral movement with valid credentials. ATT&CK can help decompose the behavior, but the local hypothesis still needs entities, evidence, and context.

A useful hypothesis might say:

> If an operator used unapproved remote access software to maintain access to administrative workstations, I expect to see unusual installation or execution, related persistence, and connections to infrastructure outside the approved support process on the same asset and within the same period.

“Search for T1219” is only a label. ATT&CK technique T1219 describes known use of remote access software and provides procedures and detection material, but the local model still belongs to the hunting team. ([MITRE ATT&CK T1219, Remote Access Software](https://attack.mitre.org/techniques/T1219/))

### Data or baseline driven

This approach begins with a property of the environment: rare processes within an asset class, newly observed domains, interactive use of service accounts, new source-destination pairs, or an unusual sequence of changes. Frequency and historical comparison can produce candidates. Rarity alone does not make them malicious. A useful baseline accounts for peers, seasonality, planned change, and source quality. PEAK treats baseline hunting as its own approach, with questions that emerge from the data. ([Splunk, PEAK Threat Hunting Framework](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html))

### Indicator or intelligence driven

Here the starting point is a hash, domain, IP address, certificate, path, name, or another artifact connected to a threat. It works well for retrospective search and scoping. Indicators have different validity periods, contexts, and fidelity, so a match does not prove compromise and a missing match does not exclude related behavior. NIST recommends that shared threat information include enough context to support proper use and handling. ([NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final))

### Situational or entity driven

The trigger is local: an acquisition, business launch, high-risk trip, critical asset, privileged account, compromised third party, new exposure, or period of fraud. The value comes from relevance to the organization. Priority should combine criticality, threat, vulnerability, and impact, which is consistent with the risk-management approach in NIST CSF 2.0. ([NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework))

### Reactive or post-incident

An alert or confirmed case starts the work, but the hunt goes beyond the known procedure. It may search for other identities, hosts, time windows, techniques, infrastructure, or variants. This work needs to stay under the incident response process so that it does not interfere with containment or evidence preservation. ([NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))

I rarely stay inside one category. A public report may produce the first hypothesis, the local data exposes an anomaly, CTI adds an indicator, a system owner explains the baseline, and an emulation validates the telemetry. Changing method during a hunt is normal. The notes should explain why the direction changed.

## 7. From trigger to decision

The workflow below combines TaHiTI, MITRE's TTP-based approach, and PEAK. A small hunt may need only a few lines for each step. The record should be detailed enough for another analyst to review the reasoning and understand why the hunt stopped. ([TaHiTI](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/); [MITRE TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting); [Splunk PEAK](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html))

One resource I keep coming back to is the **Threat Hunter Playbook**, the open community project by [Roberto Rodriguez (@Cyb3rWard0g)](https://twitter.com/Cyb3rWard0g) and [Jose Luis Rodriguez (@Cyb3rPandaH)](https://twitter.com/Cyb3rPandaH). Its hunts follow **Plan, Execute, and Report**. The notebooks keep analytics, datasets, assumptions, and decisions together, which lets the reader follow the investigation instead of seeing only the final query. It is one of the clearest practical references for reproducible hunting. ([Threat Hunter Playbook Introduction](https://threathunterplaybook.com/intro.html))

### Step 0: define authority, safety, and boundaries

Confirm that the activity, sources, and data handling are authorized. Any controlled execution belongs in a lab or explicitly approved environment, with stop conditions and informed owners. Atomic Red Team's own guidance calls for permission, a test machine, and coordination with the security controls before execution. ([Atomic Red Team Getting Started](https://www.atomicredteam.io/docs/atomic-red-team))

Hunting data may expose names, communications, locations, habits, and sensitive content. Least access, a defined purpose, suitable retention, and report protection should be part of the design. ([NIST Privacy Framework](https://www.nist.gov/privacy-framework))

Decide when the hunt must stop or transfer: evidence of an active incident, operational risk, regulated data outside the scope, a need for forensic acquisition, or an action that might alert the adversary. The incident response process and its designated authority take precedence in those cases. ([NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))

### Step 1: record the trigger and priority

The trigger may be intelligence, environmental change, a coverage gap, an anomaly, a previous incident, a new vulnerability, or a business question. Record the source, date, reliability, possible impact, and the reason this deserves time now. Local relevance and risk produce a better priority than public attention alone. ([NIST CSF 2.0](https://www.nist.gov/cyberframework))

A compact hunt brief can start with:

```text
Title:
Trigger and source:
Why it matters to this environment:
Assets, identities, or services in scope:
Time window:
Owner and reviewers:
Sharing classification:
Escalation and stop conditions:
```

### Step 2: research enough to model the behavior

Describe what the adversary would need to accomplish, the preconditions, the likely actions, and the relevant variations. Use ATT&CK, CTI reports, product documentation, and system-owner knowledge. Keep observed behavior, inference, and possibility separate. ATT&CK is a knowledge base of observed adversary behaviors, not a mandatory attack sequence. ([MITRE ATT&CK Get Started](https://attack.mitre.org/resources/))

If the source provides IoCs, record their validity and context before searching. When the information carries a Traffic Light Protocol marking, follow the distribution limits defined in TLP 2.0. ([FIRST Traffic Light Protocol 2.0](https://www.first.org/tlp/))

### Step 3: write a testable hypothesis

A useful hypothesis connects behavior, entity, expected evidence, and time:

> If **[a plausible actor or capability]** performs **[behavior]** against **[assets or identities]** during **[time window]**, I expect to observe **[signals]** in **[sources]**, distinguishable from legitimate use through **[context]**.

I add three questions:

- Which benign activities could produce the same signals?
- Which result would weaken the hypothesis?
- What conclusion can the available data not support?

Competing explanations make confirmation bias easier to notice. MITRE's TTP-based methodology similarly recommends decomposing the hypothesis into observable behaviors and developing analytics to find them. ([MITRE TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting))

### Step 4: build an evidence map

For each expected action, map the evidence, the actual source, and its limitations:

| Modeled action | Expected evidence                          | Local source                  | Coverage or limitation                    | Alternative                        |
| -------------- | ------------------------------------------ | ----------------------------- | ----------------------------------------- | ---------------------------------- |
| Execution      | Process, parent, user, command, hash       | EDR and process creation      | Servers covered; legacy endpoints partial | Windows 4688 audit                 |
| Persistence    | Service, task, or configuration change     | EDR and system events         | 30-day retention                          | Inventory or configuration records |
| Communication  | DNS, destination, periodicity, volume, TLS | DNS, proxy, Zeek, or firewall | Partial direct traffic; encrypted content | Endpoint network events            |
| Identity use   | Login, token, privilege, source, resource  | Identity provider             | Local accounts outside the source         | Host or application logs           |

The map forces the team to decide in advance what each query can prove. ATT&CK Data Components provide names for observable evidence, while joint logging guidance helps assess collection, centralization, and integrity. ([MITRE ATT&CK Data Components](https://attack.mitre.org/datacomponents/); [Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))

### Step 5: plan queries, pivots, and exit criteria

Start broad enough that the first filter does not encode every assumption. Narrow the results with asset, identity, time, and sequence context. Plan likely pivots in advance: process to file, file to hash, host to user, user to authentication, domain to other hosts, and event to approved change.

Set a time budget and exit criteria. A hunt can close when:

- the evidence supports escalation;
- the hypothesis has weakened within coverage the team considers sufficient;
- the data is inadequate and the team has opened a visibility requirement;
- a more important question has emerged as a separate hunt;
- the signal is understood well enough to enter validation or detection engineering.

TaHiTI treats finalization and transfer as part of the method, which helps prevent an investigation from staying open only because one more pivot is always possible. ([TaHiTI](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/))

### Step 6: move from broad to specific

During execution, keep a short journal with the query, time, dataset, count, interpretation, and next step. Store useful queries in version control and note schema changes. A count with no reference population says little. Compare candidates with peers, history, and asset function before calling them anomalous.

Three analytical moves show up repeatedly:

1. Stack values to inspect frequency, tails, rarity, and change.
2. Sequence events by entity and time to reconstruct action and consequence.
3. Correlate independent sources to raise or lower confidence.

Tools can automate all three, although their quality depends on event semantics and reliable correlation keys. PEAK shows how baseline and hypothesis-driven hunts use different techniques and still converge in the same investigation. ([Splunk PEAK Threat Hunting Framework](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html))

### Step 7: validate and try to falsify

For each candidate, ask:

- Is there a change ticket, approved tool, or administrator action that explains it?
- Does the same pattern appear among comparable peers?
- Are timestamps and identities consistent across sources?
- Does the event prove the action, or is it only compatible with it?
- Is there independent evidence that strengthens the interpretation?
- Can an authorized test reproduce the same data?

Adversary emulation can validate visibility and analytic logic when it is coordinated and safe. MITRE describes emulation plans as a way to test defenses through intelligence-based sequences. Those plans do not authorize uncoordinated production testing. ([MITRE ATT&CK Adversary Emulation Plans](https://attack.mitre.org/resources/adversary-emulation-plans/))

### Step 8: classify and route the result

I use explicit result categories:

- Evidence of malicious activity goes to the incident process.
- Suspicious but inconclusive activity receives an owner, a deadline, and a plan for additional data or validation.
- Legitimate but risky activity becomes a configuration, process, or privilege issue.
- A visibility gap becomes a collection requirement with a testable outcome.
- A stable candidate signal enters validation and detection engineering.
- An unsupported hypothesis closes with its coverage, limitations, and reopening conditions.

A candidate needs validation before it becomes an incident. Likewise, “benign” can still expose an abuse path or an unmanaged exception.

### Step 9: document, share, and feed the result back

Produce a decision summary and a reproducible technical record. Update the backlog, ATT&CK coverage, data-quality work, detection content, runbooks, and intelligence where the result warrants it. SNARE provides a specific structure for documenting hunts, while TLP 2.0 helps mark sharing boundaries for sensitive intelligence. ([Splunk SNARE Threat Hunting Documentation Framework](https://www.splunk.com/en_us/blog/security/threat-hunting-documentation-snare-framework-guide.html); [FIRST TLP 2.0](https://www.first.org/tlp/))

## 8. Worked example: abuse of remote access software

This example uses generic fields and does not depend on a particular product. Its purpose is to follow the investigation, not to reproduce an offensive technique.

### Trigger

CTI reports that a recent campaign used legitimate remote access tools to maintain control of endpoints. ATT&CK records this behavior under T1219 and notes that adversaries may abuse the same products an organization uses for legitimate support. That makes policy and context part of the detection logic. ([MITRE ATT&CK T1219](https://attack.mitre.org/techniques/T1219/))

### Local relevance

The organization permits two support tools, limited to defined asset groups and specific accounts. Its inventory of portable tools is unreliable. A search for every remote access product would create a large, weak queue, so the hunt focuses on **use outside policy accompanied by persistence or unusual access**.

### Hypothesis

> If an operator installed or executed unapproved remote access software to maintain access to corporate endpoints during the last 30 days, I expect to see a rare executable or service, persistence creation, and recurring communication with destinations outside the support process, possibly close to unusual authentication or execution by the same identity.

Competing explanations include approved emergency support, a vendor assessment, portable software used by a developer, outdated inventory, or a product recorded under a different commercial name.

### Evidence map

- Process and file evidence includes path, signature, hash, parent, user, and first and last observation. Process-creation events and EDR telemetry can show who executed what; configuration determines whether the command line is available. ([Microsoft Event 4688](https://learn.microsoft.com/windows/security/threat-protection/auditing/event-4688))
- Persistence evidence may include a service, scheduled task, automatic startup, or a product-specific mechanism. Scheduled tasks are one documented possibility under T1053, but the hunt should not assume that mechanism without evidence. ([MITRE ATT&CK T1053, Scheduled Task/Job](https://attack.mitre.org/techniques/T1053/))
- Network evidence includes DNS, connections, periodicity, volume, and presence on other hosts. Zeek can record connections and observed protocols, depending on analyzers and sensor position. ([Zeek Log Files](https://docs.zeek.org/en/current/reference/logs/index.html))
- Identity and context include logins, privilege, support accounts, asset owner, asset function, and change window.
- Policy data includes approved tools, asset groups, vendors, accounts, destinations, and validity dates.

### Exploratory query

The following is pseudocode. Table and field names need to be mapped to the local schema, and this is not a production detection rule.

```text
process_events
| where timestamp between hunt_start and hunt_end
| where remote_access_family == true
       or filename in candidate_names
       or hash in intelligence_candidates
| enrich asset_inventory on device_id
| enrich approved_remote_tools on
         (tool_family, asset_group, user_id, valid_time)
| where approval_match == false
| summarize
      first_seen=min(timestamp),
      last_seen=max(timestamp),
      devices=dcount(device_id),
      users=values(user_id),
      paths=values(file_path),
      parents=values(parent_process)
  by signer, hash, tool_family
| sort by devices asc, first_seen desc
```

The first result is a candidate list. It does not prove compromise. For each candidate:

1. retrieve the process tree and file events;
2. search for service creation, scheduled tasks, or another persistence mechanism;
3. correlate network destinations and periodicity;
4. inspect authentication and identity activity in the same period;
5. compare with equivalent assets and approved changes;
6. confirm the signer, vendor, and purpose with the owner.

### What a concerning timeline could look like

Imagine a signed but unapproved binary appearing on a finance workstation. A service is created a few minutes later, followed by periodic connections to a domain not previously seen in the environment. An account that does not administer that asset group also logs on interactively. Each signal has a possible benign explanation. Together, the sequence, asset mismatch, and missing change record justify escalation to IR. NIST recommends correlating events and context to determine incident scope, impact, and response instead of relying on one indicator. ([NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))

The team may instead confirm a limited, approved assessment. That still exposes an operational problem: the exception was absent from inventory and looked identical to abuse. The output may be improved governance, documented destinations, and a detection for use outside the authorized scope.

### Promotion to detection

A candidate detection might combine:

- execution or installation of a remote access product family;
- no valid approval for the asset and user;
- related persistence or communication;
- versioned exclusions for legitimate support;
- higher severity for privileged accounts or critical assets.

It should enter production only after historical replay, authorized testing, volume estimation, exception documentation, and agreement with the SOC. Sigma can represent part of the event logic, while inventory, authorization state, and cross-source correlation may require platform-specific features. ([Sigma Rule Specification](https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html))

## 9. Leaving something useful behind

I consider a hunt successful when it leaves reusable work. A confirmed incident is one possible output, but far from the only one.

Depending on the result, the package may contain:

- a timeline and evidence for IR;
- a new detection or improvement to an existing one;
- a validation test with expected telemetry;
- a fix for logging, parsing, retention, or coverage;
- inventory and allowlist updates;
- new intelligence or an updated indicator validity period;
- a hardening or privilege-reduction recommendation;
- a versioned query or reproducible notebook;
- a rejected hypothesis and the conditions under which it should be reopened.

Counting only “threats found” ignores most of these outputs and encourages analysts to choose easy hypotheses or overclassify weak evidence. PEAK recommends measures tied to outcomes, capability, and improvement alongside incident counts. ([Splunk PEAK Threat Hunting Metrics](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-metrics.html))

### Detection tests belong with the logic

A mature detection needs positive, negative, and boundary examples; version control; review; observable deployment; and monitoring for source changes. Sigma defines formal sections for selections, conditions, metadata, and severity, but a backend may not preserve every part of the semantics. ([Sigma Rule Specification](https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html))

Atomic tests and adversary emulation can provide known positive events. Run them only under an authorized plan, and record the expected result at each layer: execution, collection, transport, parsing, query, alert, and triage. Atomic Red Team publishes small ATT&CK-mapped tests together with explicit safety guidance. ([Atomic Red Team Documentation](https://www.atomicredteam.io/docs/atomic-red-team))

After deployment, watch volume, operational precision, delays, missing fields, baseline changes, and missed cases. The SOC should be able to say whether the rule supports a decision or simply moves the original uncertainty into an alert queue. A rule that never fires may reflect effective prevention, real rarity, broken logic, or missing collection. Health telemetry and controlled tests separate those explanations.

## 10. Documentation and communication

A useful report separates observation, interpretation, and recommendation. “The host queried domain X at 14:03” is an observation. “The query was command and control” is an interpretation that needs supporting evidence. “Isolate the host” is a decision that depends on context and response authority.

### Report template

```text
# Title and identifier

## Executive summary
- Why the hunt was conducted
- What was or was not found
- Impact or risk
- Requested decision and owner

## Scope
- Investigated period
- Assets, identities, and environments
- Sources and known coverage
- Exclusions and limitations

## Hypothesis
- Modeled behavior
- Expected evidence
- Competing explanations
- Escalation criteria

## Method
- Queries and versions
- Enrichment
- Pivots and validation

## Findings
- Factual observations
- Interpretation and confidence
- Timeline
- Linked evidence

## Outcome
- Classification
- Immediate actions
- Detection, data, or control improvements
- Owners and due dates

## Appendices
- Reproducible queries
- ATT&CK mapping
- IoCs with source, validity, and context
- Decision log
```

SNARE is a hunting-specific documentation reference, and TaHiTI covers communication and transfer during finalization. ([Splunk SNARE](https://www.splunk.com/en_us/blog/security/threat-hunting-documentation-snare-framework-guide.html); [TaHiTI](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/))

### Confidence

I avoid artificial percentages. Categories such as low, moderate, and high work better when the report explains the choice through source quality, independent evidence, competing explanations, and gaps. A reader should understand why the confidence received that level and what evidence could change it.

### Sharing

Mark the document according to internal policy and, where appropriate, TLP 2.0. Remove personal data and secrets that are not needed for the purpose. STIX 2.1 defines objects and relationships for structured threat information, while TAXII 2.1 defines an exchange API. Those formats still require governance, trust, and context. ([FIRST TLP 2.0](https://www.first.org/tlp/); [OASIS STIX 2.1](https://docs.oasis-open.org/cti/stix/v2.1/os/stix-v2.1-os.html); [OASIS TAXII 2.1](https://docs.oasis-open.org/cti/taxii/v2.1/os/taxii-v2.1-os.html))

## 11. Metrics that do not punish honest results

A target such as “find five threats per month” encourages reclassification, easy hypotheses, and false-positive hunting. The team does not control how many adversaries are present. It does control the quality of its questions, data coverage, investigation time, and follow-through.

I separate metrics by purpose.

### Data health

- percentage of the critical population with required telemetry;
- ingestion delay, loss, and interruption;
- completeness of required fields;
- effective retention against investigation windows;
- time to detect and correct a collection failure.

Joint logging guidance recommends monitoring pipeline health and protecting event records because analysis depends on the availability and integrity of its sources. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))

### Discovery discipline

- hunts closed with hypothesis, scope, limitations, and decision documented;
- time from trigger to the first useful answer;
- hypotheses closed, reformulated, or promoted;
- hunts that produced a verifiable improvement;
- backlog age and priority.

### Engineering and operations

- candidates that passed replay, testing, and review;
- time from discovery to deployment;
- rules with positive and negative tests and a named owner;
- volume, escalation rate, and false-positive classes;
- regressions caused by source or schema changes.

### Risk reduction and learning

- incidents or exposures identified before greater impact;
- telemetry gaps fixed;
- privileges, unsafe configurations, or attack surface reduced;
- knowledge transferred to SOC, IR, CTI, and service owners;
- shorter response time when the same behavior returns.

PEAK proposes measuring hunting effort, impact, and outcomes. The Hunting Maturity Model offers another view of how far an organization has moved from reactive procedures toward data- and hypothesis-driven hunting. Local risk, size, and capacity should still decide which measures matter. ([Splunk PEAK Threat Hunting Metrics](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-metrics.html); [SANS Hunting Maturity Model](https://www.sans.org/tools/hunting-maturity-model))

Counts need a denominator and a trend. “Twenty rules created” tells me little. “Eighteen of twenty rules have tests, an owner, and healthy telemetry, and twelve closed a prioritized coverage gap” supports a decision.

## 12. Building a hunting program

A platform can simplify searching and correlation. The capability still depends on people with authority, access, reliable data, protected time, a method, escalation paths, and a way to turn findings into change. The SANS Hunting Maturity Model relates maturity to data collection, analysis, and the degree of proactive work. ([SANS Hunting Maturity Model](https://www.sans.org/tools/hunting-maturity-model))

The levels below are my planning shorthand rather than a replacement for HMM.

### Level 0: prerequisites

- minimum inventory of critical assets, identities, and services;
- essential sources with owners and health monitoring;
- authorized access and an incident response process;
- a small backlog based on real risk.

At this level, the first hunt may be a visibility assessment. Learning that the team cannot answer an important question is more useful than writing a confident conclusion from incomplete data.

### Level 1: opportunistic practice

- hunts begin when a relevant trigger appears;
- documentation and queries vary by analyst;
- results depend heavily on individual knowledge;
- the immediate goal is a shared template and repeatable output.

### Level 2: repeatable process

- prioritized backlog, cadence, and protected time;
- hypothesis briefs, exit criteria, and peer review;
- versioned query library;
- clear handoffs to IR, engineering, CTI, and data owners.

### Level 3: integrated capability

- risk and intelligence drive coverage and hypotheses;
- Red Team and hunters validate telemetry together;
- findings feed detection, architecture, and hardening;
- metrics follow quality and impact rather than raw activity.

### Level 4: adaptive learning

- incidents, detections, and environmental changes update priorities quickly;
- tests cover the path from event generation to analyst decision;
- models, automation, and baselines are monitored for degradation;
- the program can explain where it has reliable coverage and where it does not.

Progress is uneven. An organization may be mature on endpoints and weak in SaaS, or strong in test automation and weak in retention. I assess each domain separately and choose the improvements that most reduce the chance of a wrong conclusion.

A modest operating rhythm might include a weekly backlog review, a time-boxed hunt, a technical checkpoint, an explicit exit decision, and a monthly retrospective on data and detection improvements. TaHiTI also uses phases and deliverables, while SANS recommends beginning with a pragmatic scope instead of waiting for a perfect program. ([TaHiTI](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/); [SANS, From Alerts to Adversaries](https://www.sans.org/blog/from-alerts-to-adversaries-a-pragmatic-guide-to-launching-and-maturing-your-threat-hunting-program))

## 13. A learning path for new hunters

The work crosses networks, operating systems, identity, data, security operations, and communication. Waiting to “know everything” only delays the first useful exercise. I prefer short learning cycles: understand one behavior, find its traces, explain the data, and write down what remains unclear.

The phases below are not a calendar. Progress is better measured by the artifact you can produce.

### Phase 1: observable fundamentals

The goal is to explain what happens when a user authenticates, a process starts, a name resolves, and a connection opens.

Study TCP/IP, DNS, HTTP(S), proxies, and VPNs. Learn processes, services, tasks, files, and permissions on Windows and Linux. Add identity basics, especially authentication and privilege. Keep event, log, alert, evidence, and interpretation as separate concepts.

As an exercise, draw the timeline of a simple action such as opening an application and connecting to a service. Map every step to a possible data source. Zeek and Wireshark provide open network documentation, and Microsoft documents Windows and Sysmon events. ([Zeek Documentation](https://docs.zeek.org/en/current/); [Wireshark User's Guide](https://www.wireshark.org/docs/wsug_html_chunked/); [Microsoft Sysmon Events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events))

### Phase 2: telemetry and queries

Learn to state a question without tying it to one tool, then implement it in one query language. The foundations are filters, aggregations, time windows, cardinality, joins, time and identity normalization, source quality, retention, and basic peer comparison.

For a practical output, use a known dataset to build a table of rare processes or destinations and explain five false positives. Microsoft publishes KQL examples and schemas for Defender advanced hunting. Splunk's public Boss of the SOC datasets provide material for SPL practice. ([Microsoft Defender XDR Advanced Hunting](https://learn.microsoft.com/en-us/defender-xdr/hunting-overview); [Splunk Boss of the SOC dataset](https://www.splunk.com/en_us/blog/security/boss-of-the-soc-scoring-server-questions-and-answers-and-dataset-open-sourced-and-ready-for-download.html))

### Phase 3: behavior and hypotheses

Move from names toward actions and expected evidence. Study ATT&CK tactics, techniques, procedures, Detection Strategies, and Data Components. Learn how an indicator differs from behavior and context, and enough CTI to assess source, relevance, and validity.

Choose one technique relevant to your lab. Write a hypothesis and map action to evidence, source, and limitation. Use the current Enterprise matrix and Detection Strategies as references instead of copying an entire technique page into a local plan. ([MITRE ATT&CK Enterprise Matrix](https://attack.mitre.org/matrices/enterprise/); [MITRE ATT&CK Detection Strategies](https://attack.mitre.org/detectionstrategies/))

### Phase 4: complete hunts and validation

Run three small hunts: one behavior driven, one baseline driven, and one intelligence or situation driven. For each, deliver the hypothesis, sources, query journal, candidates, competing explanations, decision, limitations, and one improvement. Any emulation belongs in an authorized environment under the project's safety guidance. ([Atomic Red Team Getting Started](https://www.atomicredteam.io/docs/atomic-red-team))

### Phase 5: detection, communication, and a portfolio

Build one candidate rule with tests, a one-page decision summary, a reproducible technical appendix, and an honest retrospective. Sigma is useful for learning an open representation of log detection rules. YARA is appropriate for patterns in files and other objects when the conditions have been tested and contextualized. ([Sigma Specification](https://sigmahq.io/sigma-specification/); [YARA, Writing Rules](https://yara.readthedocs.io/en/stable/writingrules.html))

A portfolio does not need real company data. Use your own lab or public datasets, remove secrets, explain the limitations, and show your reasoning. The sentence “these data do not support that conclusion” demonstrates a skill that a complicated query cannot replace.

## 14. Where to practice

Useful practice needs authorization and either a known answer or a result that can be validated. Use isolated labs, educational platforms, and public datasets. Never run techniques against a third party or production environment without an explicit mandate.

### Open resources and datasets

- **MITRE ATT&CK and CTID:** use techniques, Detection Strategies, and emulation plans as modeling material rather than a coverage checklist. ([MITRE ATT&CK Resources](https://attack.mitre.org/resources/); [CTID Adversary Emulation Library](https://ctid.mitre.org/resources/adversary-emulation-library/))
- **Atomic Red Team:** small ATT&CK-mapped tests for validation in an authorized lab. Read the safety guidance first. ([Atomic Red Team](https://www.atomicredteam.io/docs/atomic-red-team))
- **Threat Hunter Playbook:** hunt plans, guided investigations, executable notebooks, and recorded datasets that connect behavior, telemetry, and analysis. ([Threat Hunter Playbook](https://threathunterplaybook.com/intro.html))
- **Splunk Boss of the SOC and Security Datasets:** public material for reconstructing defensive investigations. ([Splunk BOTS dataset](https://www.splunk.com/en_us/blog/security/boss-of-the-soc-scoring-server-questions-and-answers-and-dataset-open-sourced-and-ready-for-download.html); [Splunk Security Datasets](https://github.com/splunk/securitydatasets))
- **The DFIR Report:** detailed reports based on observed intrusions. I use them to reconstruct timelines, extract behavior, and turn a case into a hunt hypothesis or detection idea. A report supports what happened in that case; it does not establish universal prevalence. ([The DFIR Report](https://thedfirreport.com/))
- **Zeek and Wireshark:** capture traffic only where you have authorization, then practice moving between packets, transactions, and structured logs. ([Zeek Monitoring](https://docs.zeek.org/en/current/monitoring.html); [Wireshark Documentation](https://www.wireshark.org/docs/))

### Guided platforms

- **CyberDefenders** provides blue-team labs centered on evidence analysis. Check the current requirements and objectives before choosing a lab. ([CyberDefenders Blue Team Labs](https://cyberdefenders.org/blue-team-labs/))
- **TryHackMe** maintains a SOC Level 2 path and threat hunting material. Its catalog and access model can change. ([TryHackMe SOC Level 2](https://tryhackme.com/path/outline/soclevel2); [TryHackMe Threat Hunting module](https://tryhackme.com/module/threat-hunting))

### Courses and professional training

- **OffSec TH-200** is a foundational threat hunting course covering network, endpoint, and custom investigation material. Review the current syllabus, prerequisites, and delivery model before investing. ([OffSec TH-200](https://www.offsec.com/courses/th-200/))
- **Practical Threat Hunting by Chris Sanders** teaches a foundational, structured, repeatable hunting process. ([Chris Sanders, Practical Threat Hunting Training](https://chrissanders.org/training/threat-hunting-training/))
- **SANS FOR508** combines advanced incident response, threat hunting, and digital forensics. ([SANS FOR508](https://www.sans.org/cyber-security-courses/advanced-incident-response-threat-hunting-training))
- **SANS FOR578** focuses on Cyber Threat Intelligence and is relevant to intelligence requirements, analysis, and context production for hunting. ([SANS FOR578](https://www.sans.org/cyber-security-courses/cyber-threat-intelligence))

My view of Chris Sanders' course is mixed in a useful way. The explanations are good, and the course made me consider several investigative paths that I had not organized clearly before. The hands-on work may feel light to someone expecting extreme technical depth. I would still treat it as solid foundational training, with that expectation set in advance.

Completing a lab shows that you followed that scenario. To get more from it, repeat the work without the walkthrough, change the time window, test a benign explanation, and write a conclusion that another analyst can review.

## 15. Books and living references

Older books can still teach durable mental models, although commands, tools, and operating-system details age. I pair them with current product documentation.

### Books

- **The Practice of Network Security Monitoring**, by Richard Bejtlich, is a strong foundation for thinking about network collection, analysis, and response. ([No Starch Press](https://nostarch.com/nsm/))
- **Practical Malware Analysis**, by Michael Sikorski and Andrew Honig, develops a method for static and dynamic analysis. Use an isolated lab and check current tool documentation. ([No Starch Press](https://nostarch.com/malware))
- **Intelligence-Driven Incident Response, 2nd Edition**, by Scott J. Roberts and Rebekah Brown, connects intelligence, analysis, and response in an operational cycle. ([O'Reilly](https://www.oreilly.com/library/view/intelligence-driven-incident-response/9781098120672/))
- **The Art of Memory Forensics**, by Michael Hale Ligh, Andrew Case, Jamie Levy, and Aaron Walters, remains a substantial reference for memory evidence. Profiles, platforms, and tools need to be updated for the system under analysis. ([Wiley](https://www.wiley.com/en-us/shop/general-introductory-computer-science/the-art-of-memory-forensics-detecting-malware-and-threats-in-windows-linux-and-mac-memory-p-9781118825099))
- **Practical Threat Intelligence and Data-Driven Threat Hunting: A Hands-On Guide to Threat Hunting with the ATT&CK Framework and Open Source Tools**, by Valentina Costa-Gazcón, connects the intelligence cycle to hypotheses, data, and hunting with open tools. Different editions exist, so confirm the ISBN and contents before buying. ([Amazon Spain, ISBN 1838556370](https://www.amazon.es/-/en/Practical-Threat-Intelligence-Data-Driven-Hunting/dp/1838556370))
- **Advanced Cyber Threat Intelligence and Hunting: Detect APTs and Zero-Day Attacks Using CTI, Behavioral Analytics, and AI Techniques**, by Gianluca Tiepolo and Dan Sorensen, moves from CTI operations into behavior-based hunting across endpoint, network, and cloud. Its companion repository contains chapter artifacts and queries in ES|QL, EQL, KQL, SPL, and Sigma. ([Amazon](https://www.amazon.com/dp/1806380390); [Packt companion repository](https://github.com/PacktPublishing/Advanced-Cyber-Threat-Intelligence-and-Hunting))

### References that stay useful

- **NIST SP 800-53 RA-10** defines the purpose and control objectives for threat hunting. ([NIST](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final))
- **TaHiTI** provides a structured method for initiating, running, and finalizing hunts. ([Nederlandse Vereniging van Banken](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/))
- **MITRE ATT&CK** documents adversary behavior, Detection Strategies, and Data Components. ([MITRE ATT&CK](https://attack.mitre.org/))
- **Threat Hunter Playbook**, by Roberto Rodriguez and Jose Luis Rodriguez, provides hunt plans, guided hunts, notebooks, and datasets for reproducible analysis. ([Threat Hunter Playbook](https://threathunterplaybook.com/intro.html))
- **PEAK**, or *Prepare, Execute, and Act with Knowledge*, covers hypothesis-driven, baseline, and model-assisted hunts together with deliverables, metrics, and maturity. The official guide, the Cisco Talos repository, and Hunt.io's worked explanation are useful from different angles. ([Splunk official guide](https://www.splunk.com/en_us/form/the-peak-threat-hunting-framework.html); [Cisco Talos PEAK repository](https://github.com/Cisco-Talos/PEAK); [Hunt.io overview and examples](https://hunt.io/glossary/peak-threat-hunting-framework))
- **The DFIR Report** publishes public intrusion reports for studying timelines, TTPs, and detection opportunities. ([The DFIR Report](https://thedfirreport.com/))
- **Hunting Maturity Model** offers a view of collection and analysis maturity. ([SANS](https://www.sans.org/tools/hunting-maturity-model))
- **Best Practices for Event Logging and Threat Detection** covers logging policy, centralization, protection, and use. ([Australian Signals Directorate and partners](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))
- **NIST SP 800-61 Rev. 3 and SP 800-86** explain the boundary and integration with incident response and digital forensics. ([NIST SP 800-61r3](https://csrc.nist.gov/pubs/sp/800/61/r3/final); [NIST SP 800-86](https://csrc.nist.gov/pubs/sp/800/86/final))

## 16. Quick glossary

- **ATT&CK:** MITRE's knowledge base of adversary behavior, organized through tactics, techniques, and related objects. It is neither a product nor a complete list of everything an adversary may do. ([MITRE ATT&CK Get Started](https://attack.mitre.org/resources/))
- **Baseline:** a reference built from expected or historically observed behavior in a comparable population. It needs revision as the environment changes. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))
- **CTI:** Cyber Threat Intelligence, meaning threat information and analysis produced with enough context to support a decision. ([NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final))
- **Data Component:** an observable property relevant to detection, such as process creation or file modification, used by ATT&CK to connect behavior to evidence. ([MITRE ATT&CK Data Components](https://attack.mitre.org/datacomponents/))
- **Detection Strategy and Analytics:** in the current ATT&CK model, a strategy describes a detection approach and its analytics describe the related logic and evidence. ([MITRE ATT&CK Detection Strategies](https://attack.mitre.org/detectionstrategies/))
- **DFIR:** Digital Forensics and Incident Response, combining incident handling with the collection, examination, and analysis of digital evidence. ([NIST SP 800-86](https://csrc.nist.gov/pubs/sp/800/86/final))
- **EDR:** Endpoint Detection and Response, technology used to collect and analyze endpoint activity for visibility, detection, and response. Its value depends on coverage and configuration. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))
- **IoC:** Indicator of Compromise, an observable such as infrastructure or an artifact that may relate to adversary activity and needs source, validity, and context. ([NIST SP 800-150](https://csrc.nist.gov/pubs/sp/800/150/final))
- **IR:** Incident Response, the preparation, detection, response, and recovery work surrounding incidents within the organization's risk process. ([NIST SP 800-61 Rev. 3](https://csrc.nist.gov/pubs/sp/800/61/r3/final))
- **SIEM:** Security Information and Event Management, a capability for centralizing and analyzing events from multiple sources. It cannot repair missing collection or missing context on its own. ([Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection))
- **TTPs:** Tactics, techniques, and procedures describing adversary goals, methods, and observed implementations. ([MITRE TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting))
- **Telemetry:** data generated or collected by systems and sensors to make states and actions observable. Semantics and coverage matter as much as volume. ([MITRE ATT&CK Data Components](https://attack.mitre.org/datacomponents/))

## 17. One-page checklist

### Before the hunt

- [ ] Is there an authorized owner?
- [ ] Are the trigger and local relevance documented?
- [ ] Does the hypothesis connect behavior, entity, evidence, and time?
- [ ] Are competing explanations and escalation criteria recorded?
- [ ] Are source coverage, semantics, and retention known?
- [ ] Are privacy, TLP, and sharing boundaries defined?
- [ ] Does the plan have a time budget and stop conditions?

### During the hunt

- [ ] Are relevant queries and results recorded?
- [ ] Are candidates compared with peers and history?
- [ ] Has the team correlated independent sources where possible?
- [ ] Were changes, approved tools, and service owners checked?
- [ ] Did the team try to weaken the hypothesis as well as support it?
- [ ] Was a potential incident transferred to the right process?

### After the hunt

- [ ] Are facts, inferences, and limitations separate?
- [ ] Does the result have a category, owner, and next action?
- [ ] Did data gaps become testable requirements?
- [ ] Do detection candidates have tests, replay, and a triage owner?
- [ ] Can someone reproduce the queries, evidence, and decisions?
- [ ] Did the learning return to CTI, SOC, IR, Red Team, and service owners?

## Closing thoughts

After working in incident response, threat modeling, and hunting, I pay less attention to query size and more attention to the question behind it. A good hunt shows what the telemetry can prove, which explanations still compete with the hypothesis, and who needs to take part in the decision.

No lab reproduces the ambiguity of a real organization. Undocumented services, changes outside the expected window, old exceptions, and collection gaps are part of the work. In those moments, technical breadth and collaboration matter more than query syntax.

For someone starting out, I would choose one small hunt, document it well, and ask another analyst to review it. Even when the hunt finds no malicious activity, it may expose a weak source, a bad assumption, or a control that needs testing. That is already useful work, and it makes the next investigation better.

## References

### Standards, frameworks and methodologies

- [MITRE ATT&CK](https://attack.mitre.org/)
- [MITRE ATT&CK: Data Components](https://attack.mitre.org/datacomponents/)
- [MITRE ATT&CK: deprecated Data Sources pages](https://attack.mitre.org/datasources/)
- [MITRE ATT&CK: Detection Strategies](https://attack.mitre.org/detectionstrategies/)
- [MITRE ATT&CK: Enterprise Matrix](https://attack.mitre.org/matrices/enterprise/)
- [MITRE ATT&CK: resources and getting started](https://attack.mitre.org/resources/)
- [MITRE ATT&CK: Adversary Emulation Plans](https://attack.mitre.org/resources/adversary-emulation-plans/)
- [MITRE ATT&CK: Adversary Emulation and Red Teaming](https://attack.mitre.org/resources/get-started/adversary-emulation-and-red-teaming/)
- [MITRE ATT&CK: Version History](https://attack.mitre.org/resources/versions/)
- [MITRE ATT&CK T1053: Scheduled Task/Job](https://attack.mitre.org/techniques/T1053/)
- [MITRE ATT&CK T1219: Remote Access Software](https://attack.mitre.org/techniques/T1219/)
- [MITRE: TTP-Based Hunting](https://www.mitre.org/news-insights/publication/ttp-based-hunting)
- [Center for Threat-Informed Defense: Adversary Emulation Library](https://ctid.mitre.org/resources/adversary-emulation-library/)
- [NIST SP 800-150: Guide to Cyber Threat Information Sharing](https://csrc.nist.gov/pubs/sp/800/150/final)
- [NIST SP 800-53 Rev. 5, including RA-10 Threat Hunting](https://csrc.nist.gov/pubs/sp/800/53/r5/upd1/final)
- [NIST SP 800-61 Rev. 3: Incident Response Recommendations and Considerations](https://csrc.nist.gov/pubs/sp/800/61/r3/final)
- [NIST SP 800-86: Guide to Integrating Forensic Techniques into Incident Response](https://csrc.nist.gov/pubs/sp/800/86/final)
- [NIST Cybersecurity Framework 2.0](https://www.nist.gov/cyberframework)
- [NIST NICE: Occupations, Jobs and Work Roles](https://www.nist.gov/itl/applied-cybersecurity/nice/nice-framework-resource-center/resources/occupations-jobs-and-work)
- [NIST Privacy Framework](https://www.nist.gov/privacy-framework)
- [TaHiTI: Threat Hunting Methodology](https://www.nvb.nl/afspraken-gedragscodes-en-samenwerkingen/security-en-cybercrime-samenwerking-fi-isac/tahiti/)
- [CISA: Known Exploited Vulnerabilities Catalog](https://www.cisa.gov/known-exploited-vulnerabilities-catalog)
- [FIRST: EPSS](https://www.first.org/epss/)
- [FIRST: EPSS FAQ](https://www.first.org/epss/faq)
- [FIRST: Traffic Light Protocol 2.0](https://www.first.org/tlp/)
- [OASIS: STIX 2.1](https://docs.oasis-open.org/cti/stix/v2.1/os/stix-v2.1-os.html)
- [OASIS: TAXII 2.1](https://docs.oasis-open.org/cti/taxii/v2.1/os/taxii-v2.1-os.html)
- [Australian Signals Directorate and partners: Best Practices for Event Logging and Threat Detection](https://www.cyber.gov.au/publication/best-practices-for-event-logging-and-threat-detection)
- [OWASP: Logging Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Logging_Cheat_Sheet.html)

### Telemetry, detection and analysis tools

- [Microsoft Defender XDR: Advanced Hunting Overview](https://learn.microsoft.com/en-us/defender-xdr/advanced-hunting-overview)
- [Microsoft Defender XDR: Hunt for threats with advanced hunting](https://learn.microsoft.com/en-us/defender-xdr/hunting-overview)
- [Microsoft: PowerShell security features](https://learn.microsoft.com/en-us/powershell/scripting/learn/security-features)
- [Microsoft: Sysmon events](https://learn.microsoft.com/en-us/windows/security/operating-system-security/sysmon/sysmon-events)
- [Microsoft: Windows security audit event 4688](https://learn.microsoft.com/windows/security/threat-protection/auditing/event-4688)
- [Suricata: EVE JSON output](https://docs.suricata.io/en/latest/output/eve/eve-json-output.html)
- [Zeek Documentation](https://docs.zeek.org/en/current/)
- [Zeek: Monitoring with Zeek](https://docs.zeek.org/en/current/monitoring.html)
- [Zeek: Log Files](https://docs.zeek.org/en/current/reference/logs/index.html)
- [Wireshark Documentation](https://www.wireshark.org/docs/)
- [Wireshark User's Guide](https://www.wireshark.org/docs/wsug_html_chunked/)
- [Sigma Specification](https://sigmahq.io/sigma-specification/)
- [Sigma Rules Specification](https://sigmahq.io/sigma-specification/specification/sigma-rules-specification.html)
- [YARA: Writing rules](https://yara.readthedocs.io/en/stable/writingrules.html)
- [Atomic Red Team Documentation](https://www.atomicredteam.io/docs/atomic-red-team)

### Threat hunting research and community resources

- [Threat Hunter Playbook](https://threathunterplaybook.com/intro.html)
- [Jose Luis Rodriguez: @Cyb3rPandaH](https://twitter.com/Cyb3rPandaH)
- [Roberto Rodriguez: @Cyb3rWard0g](https://twitter.com/Cyb3rWard0g)
- [Cisco Talos: PEAK threat hunting content](https://github.com/Cisco-Talos/PEAK)
- [Hunt.io: PEAK Threat Hunting Framework](https://hunt.io/glossary/peak-threat-hunting-framework)
- [Splunk: The PEAK Threat Hunting Framework](https://www.splunk.com/en_us/form/the-peak-threat-hunting-framework.html)
- [Splunk: PEAK Threat Hunting Framework article](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-framework.html)
- [Splunk: PEAK Threat Hunting Metrics](https://www.splunk.com/en_us/blog/security/peak-threat-hunting-metrics.html)
- [Splunk: SNARE Threat Hunting Documentation Framework](https://www.splunk.com/en_us/blog/security/threat-hunting-documentation-snare-framework-guide.html)
- [The DFIR Report](https://thedfirreport.com/)
- [SANS: Hunting Maturity Model](https://www.sans.org/tools/hunting-maturity-model)
- [SANS: From Alerts to Adversaries](https://www.sans.org/blog/from-alerts-to-adversaries-a-pragmatic-guide-to-launching-and-maturing-your-threat-hunting-program)

### Training, labs and public datasets

- [CyberDefenders: Blue Team Labs](https://cyberdefenders.org/blue-team-labs/)
- [TryHackMe: Threat Hunting module](https://tryhackme.com/module/threat-hunting)
- [TryHackMe: SOC Level 2](https://tryhackme.com/path/outline/soclevel2)
- [OffSec: TH-200 Foundational Threat Hunting](https://www.offsec.com/courses/th-200/)
- [Chris Sanders: Practical Threat Hunting Training](https://chrissanders.org/training/threat-hunting-training/)
- [SANS FOR508: Advanced Incident Response, Threat Hunting, and Digital Forensics](https://www.sans.org/cyber-security-courses/advanced-incident-response-threat-hunting-training)
- [SANS FOR578: Cyber Threat Intelligence](https://www.sans.org/cyber-security-courses/cyber-threat-intelligence)
- [Splunk: Boss of the SOC dataset](https://www.splunk.com/en_us/blog/security/boss-of-the-soc-scoring-server-questions-and-answers-and-dataset-open-sourced-and-ready-for-download.html)
- [Splunk Security Datasets](https://github.com/splunk/securitydatasets)

### Books and companion material

- [Advanced Cyber Threat Intelligence and Hunting](https://www.amazon.com/dp/1806380390)
- [Practical Threat Intelligence and Data-Driven Threat Hunting](https://www.amazon.es/-/en/Practical-Threat-Intelligence-Data-Driven-Hunting/dp/1838556370)
- [Packt: Advanced Cyber Threat Intelligence and Hunting companion repository](https://github.com/PacktPublishing/Advanced-Cyber-Threat-Intelligence-and-Hunting)
- [No Starch Press: Practical Malware Analysis](https://nostarch.com/malware)
- [No Starch Press: The Practice of Network Security Monitoring](https://nostarch.com/nsm/)
- [O'Reilly: Intelligence-Driven Incident Response, 2nd Edition](https://www.oreilly.com/library/view/intelligence-driven-incident-response/9781098120672/)
- [Wiley: The Art of Memory Forensics](https://www.wiley.com/en-us/shop/general-introductory-computer-science/the-art-of-memory-forensics-detecting-malware-and-threats-in-windows-linux-and-mac-memory-p-9781118825099)
