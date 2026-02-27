---
layout: post
title: 'RSS, Overload, and Morning Calls: Structuring Security Information'
description: 'A practical reflection on managing information overload in cybersecurity: from building a structured catalog of security RSS feeds to generating a daily, operationally focused SOC morning briefing that turns external news into actionable priorities.'
date: '2026-02-23 14:02:58 +0100'
category: [Security]
image: /assets/img/posts/security_feeds.png
alt: Responsive rendering of Chirpy theme on multiple devices.
tags: [feeds]
---

Staying up to date is a structural part of working in information security. New critical vulnerabilities emerge daily, campaigns shift from opportunistic to targeted within hours, public exploits appear before patches are widely deployed, and vendor advisories continue to accumulate.

In larger organizations, there is usually a dedicated Threat Intelligence function, paid feed services, continuous monitoring, and integrations with SIEM and TIP platforms. Even with that structure in place, the core challenge remains: volume.

In my case, I have always tried to follow the landscape through multiple sources — newsletters, RSS feeds, technical Telegram groups, Twitter/X, vendor blogs, CERT advisories, and specialized forums. Over time, it became clear that the issue was not lack of information. It was excess.

Tools like Feedly, Feedbin, and Inoreader help significantly with aggregation. However, I wanted more control: the ability to organize feeds into specific categories, store the data in a structured way, and eventually use that historical data for deeper analysis. That is when I started cataloging security feeds on my own.

The idea began to take shape after discovering [https://securityfeeds.org/](https://securityfeeds.org/). It already did a solid job of aggregation, but many of the feeds I regularly followed were not listed there. I decided to build an expanded version, organized in a more granular way. I grouped feeds into categories such as:

- Crypto & Blockchain Security
- Cybercrime, Darknet & Leaks
- DFIR & Forensics
- Government / CERT & Advisories
- Malware & Threat Research
- Vulnerabilities, CVEs & Exploits
- Vendors & Product Blogs
- OSINT, Communities & Subreddits
- Podcasts & YouTube
  
The result was:

[http://awesomesecurityfeeds.com/](http://awesomesecurityfeeds.com/)  
[https://github.com/clivoa/awesome-security-feeds](https://github.com/clivoa/awesome-security-feeds)

The concept is simple: an open catalog with more feeds, category organization, and automatic OPML export for compatible readers. I also started experimenting with an automated feed discovery prototype using GitHub Actions to identify and validate new [security-related sources](https://github.com/clivoa/awesome-security-feeds/actions/workflows/discover_security_feeds.yml), it is still experimental, but the long-term goal is to introduce some type of relevance scoring or filtering mechanism.

However, even after organizing dozens of feeds, the core problem remained. Centralizing everything does not change the fact that the daily volume is too high for detailed manual reading. Instead of reducing overload, I had simply structured it.

At that point, I shifted the focus. Instead of trying to read everything, I started thinking about how to extract only what truly matters for daily operations.

This led to the idea of generating a daily operational summary in the form of a SOC “morning call.” The goal was not to create a generic news digest, but something that could be read quickly during shift handover and help prioritize the day.

The persona defined in the system prompt is a senior cybersecurity consultant supporting a 24/7 SOC in a financial institution. This is intentional. It forces prioritization around operational impact, active exploitation, relevant campaigns, and vulnerabilities with realistic abuse potential.

The model receives curated news from the last 24 hours and generates a structured briefing with:

- Executive Summary
- High-priority items
- Monitoring and detection recommendations
- Medium-term follow-ups

**Prompt**:
```python
def build_system_prompt() -> str:
    """
    Persona: Senior cybersecurity consultant
    """
    return (
        "You are a seasoned cybersecurity consultant and threat intelligence lead "
        "supporting a 24/7 SOC for a critical financial institution.\n"
        "You have:\n"
        "- Deep experience in incident response, threat hunting and cyber defense.\n"
        "- Strong understanding of MITRE ATT&CK, ransomware operations, exploitation "
        "  of vulnerabilities, cloud security and financial sector threats.\n"
        "- The ability to quickly triage external news and translate it into concrete "
        "  operational guidance for SOC analysts (L1–L3).\n\n"
        "Your goal: Based on the last 24 hours of external security news, produce a SHORT, "
        "highly actionable *morning call* in English for the SOC team.\n"
        "Always prioritize:\n"
        "- Threats with potential direct operational impact (exploitable CVEs, active campaigns,\n"
        "  0-days, ransomware groups, supply-chain incidents, critical vendor advisories,\n"
        "  financial-sector targeting).\n"
        "- Clear recommendations on monitoring, detections, and immediate actions.\n"
        "- Brevity and clarity. The audience will read this during a very time-constrained shift handover.\n\n"
        "IMPORTANT STYLE CONSTRAINTS:\n"
        "- Aim for a total length of roughly 600–900 words.\n"
        "- Use short bullet points (one or two lines each).\n"
        "- Avoid narrative paragraphs and repeated background details.\n"
        "- Group similar items together instead of describing each news item separately.\n"
    )
```

**Tasks**:
```python
def build_user_prompt(context_snippet: str, hours: int, total_items: int) -> str:
    """
    Detailed instructions for the model, focusing on SOC-friendly and lean output.
    """
    return (
        f"The following list summarizes curated security-related news items collected during the last "
        f"{hours} hours.\n"
        f"There are {total_items} curated items in that time window. A subset of them is listed below.\n\n"
        "NEWS CONTEXT (each item includes timestamp, source, title, link and tags):\n"
        "------------------------------------------------------------\n"
        f"{context_snippet}\n"
        "------------------------------------------------------------\n\n"
        "TASK:\n"
        "Write a *morning call* style briefing in English for a Security Operations Center (SOC) "
        "supporting critical financial services. Assume your audience are SOC L1–L3 analysts, "
        "incident responders and threat hunters.\n\n"
        "STRUCTURE YOUR ANSWER AS MARKDOWN WITH THE FOLLOWING SECTIONS (KEEP IT TIGHT AND FOCUSED):\n"
        "1. `### Executive Summary`\n"
        "   - 3 bullet points MAX summarizing the most important developments.\n"
        "\n"
        "2. `### High-priority items (immediate attention)`\n"
        "   - Focus on the TOP 3–5 issues only (do not list everything).\n"
        "   - For each issue, use EXACTLY three bullets:\n"
        "     - What happened (1 short line)\n"
        "     - Why it matters operationally (1 short line)\n"
        "     - Recommended immediate actions for the SOC today (1–2 short actions, same bullet)\n"
        "   - Group similar items together (e.g. 'several critical VPN CVEs') instead of repeating similar news.\n"
        "\n"
        "3. `### Monitoring & detection recommendations`\n"
        "   - 5–8 bullets MAX.\n"
        "   - Each bullet should map 1–2 relevant news themes to:\n"
        "     - Specific log sources (EDR, firewall, VPN, email, cloud, IdP, etc.)\n"
        "     - Optional MITRE ATT&CK technique IDs when they add value.\n"
        "   - Keep bullets short and practical (what to hunt / monitor TODAY).\n"
        "\n"
        "4. `### Medium-term follow-ups`\n"
        "   - 4–6 bullets MAX.\n"
        "   - Items that are important but not urgent for TODAY (patching backlog, policy updates, awareness, "
        "     hardening tasks, vendor follow-up, etc.).\n\n"
        "CONSTRAINTS & STYLE:\n"
        "- Use concise bullet points, not long paragraphs.\n"
        "- Avoid repeating the same background explanation for multiple items.\n"
        "- If many news items relate to the same theme (e.g. multiple ransomware posts), summarize them as a group.\n"
        "- If the information is incomplete or unclear, explicitly state assumptions.\n"
        "- Do NOT invent specific IOCs (hashes, IPs, domains) unless they are clearly given in the news items.\n"
        "- You may refer to news items generically (e.g. 'a critical RCE in a mainstream VPN appliance') "
        "instead of repeating full titles.\n"
        "- Focus on *operational impact* and *what the SOC should do today*."
    )
```

The structure enforces objectivity. Similar news items are grouped together. Excessive background is avoided. There is no room for long narratives. The focus is always: what does this mean for the SOC [today](https://clivoa.github.io/S33R/morning)?

When relevant, recommendations may reference MITRE ATT&CK ([https://attack.mitre.org/](https://attack.mitre.org/)), particularly to support hunting activities or adjustments to existing detections. At the moment, the workflow is [limited to 3000 tokens](https://github.com/clivoa/S33R/blob/main/.github/workflows/morning_call.yml#L50).

This technical constraint is actually useful. It forces pre-selection of news items and keeps the output within a size that can realistically be consumed in a few minutes.

In practice, this relatively simple project has brought tangible improvements. Time spent navigating between sources has decreased. Daily prioritization is more consistent. Recurring patterns — such as waves of VPN exploitation or specific phishing campaigns — have become easier to identify. In some cases, the daily briefing has served as the starting point for new hunting hypotheses.

The process is still evolving. Future improvements may include automated criticality classification, sector-based filtering (for example, financial-sector focus), weekly trend summaries, and integration with collaboration platforms such as Slack or Teams.

Organizing feeds was only the first step. The more important change was introducing structure into how external information is translated into something usable in day-to-day operations.