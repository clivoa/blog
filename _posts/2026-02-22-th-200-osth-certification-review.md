---
layout: post
title: TH-200 OSTH / Certification Review
date: '2026-02-22 14:56:29 +0100'
category: [Exam, Review]
image: /assets/img/posts/osth.png
tags: [osth]
---

Last year, I completed the **TH-200: Foundational Threat Hunting** course and the corresponding **OSTH certification exam**. I originally wrote my notes about a week after receiving my exam results. Rather than leaving those reflections as private notes, I decided to refine and publish them here.

---

## Why I Chose TH-200

I enrolled in **TH-200: Foundational Threat Hunting** after transitioning into a Threat Hunter role. I already had several years of experience in cybersecurity, having worked as an Incident Responder and Threat Model Analyst. However, stepping into a dedicated Threat Hunting position felt like a significant shift — new responsibilities, new expectations, and a need for deeper specialization.

Before committing to TH-200, I completed the *Practical Threat Hunting* training by Chris Sanders. While it was an excellent course, I felt that some topics lacked technical depth. That gap led me to search for a more structured and rigorous certification.

I chose **OffSec** because of its reputation for demanding, hands-on examinations. Although I do find their pricing high — and I am not particularly fond of the “Try Harder” motto (a topic for another discussion) — their brand is strongly associated with exam rigor and practical validation of skills.

---

## Course Content Overview

According to the official description, TH-200 covers:
- Understanding the threat actor landscape, with a focus on ransomware and Advanced Persistent Threats (APTs)
- Utilizing both network and endpoint Indicators of Compromise (IoCs) for proactive threat detection
- Highlighting the role of Intrusion Detection Systems (IDS) and Intrusion Prevention Systems (IPS), like Suricata, in monitoring for suspicious activities
- Explorations of various ransomware groups, including LockBit, CLOP, and BlackCat/ALPHV, with examples of how they exploit specific vulnerabilities
- Recognizing custom threat hunting, focusing on behavioral analysis and data correlation to detect advanced threats, using tools like CrowdStrike Falcon

Trending tools, well-known threat groups, modern hunting workflows — sounds compelling, right?

When I first read the syllabus, it felt aligned with exactly what I needed to study, especially since I was already familiar with some of the technologies mentioned.

I opted for the **90-day bundle**, giving myself roughly three months to complete the course. However, since much of the material overlapped with my prior experience, I was able to finish it in less time.

---

## Course Structure

The course is divided into the following modules:

1. **Threat Hunting Concepts and Practices**  
2. **Threat Actor Landscape Overview**  
3. **Communication and Reporting for Threat Hunters**  
4. **Hunting with Network Data**  
5. **Hunting on Endpoints**  
6. **Threat Hunting Without IoCs**  
7. **Threat Hunting Challenge Labs**

The progression is logical and structured, moving from theory and context into hands-on hunting scenarios.

---

## The Exam Experience

The exam format is as follows:

> The exam’s an 8-hour sprint with 24 hours to submit a report, max 70 points, and you need 50 to pass. It’s got **seven questions**, each worth 10 points, just like the **challenge labs**. You get a universal VPN or Web Browser to connect to exam machines, including Splunk and Dev (which you put the flags), plus a breached network topology, Sysmon configs on all machines, and a threat intel report with APT details, tools, and IoCs.

I chose to begin the exam early in the morning, planning a short break for food midway through the session. The exam is proctored but the experience was smooth and professional.

During the exam, I relied heavily on my notes and did not find the investigative process particularly difficult. Having prior experience with SIEM platforms is a significant advantage. Familiarity with **Splunk** is especially helpful. The required tasks are not overly complex — in fact, simple keyword searches related to known attacker tools can help guide you if you feel stuck or unsure where to begin.

---

## The Most Challenging Part: Documentation

The most demanding aspect of the exam was not the hunting itself — it was the documentation.

Structuring findings clearly, concisely, and professionally takes time. I strongly recommend using a dedicated note-taking system. Although the course briefly mentions some tools, it does not go into much detail.

I took notes using Markdown (Obsidian) and Microsoft Word. I had recently discovered SysReptor, but at the time there was no specific OSTH template available, and I did not want to waste time adapting one. Since the content was still fresh in my mind and I was motivated to attempt the exam quickly, I stuck with tools I was already comfortable with.

After completing the 8-hour exam and submitting my report, I waited a few days for the results.

![OSTH email results](/assets/img/osth_email.png)
---

## What Could Be Improved

Not everything is positive.

The course provides a solid foundation and offers strong references, especially regarding reporting and structured documentation. However, in my opinion, the technical depth could be significantly improved.

I felt that the Splunk and CrowdStrike Falcon sections lacked advanced coverage. For example, more complex hunting queries, deeper EDR telemetry analysis, and richer investigative workflows would have made the course far more impactful.

The overall feeling was similar to visiting a beautiful beach but only dipping your feet in the water.

When compared to emerging certifications such as those from Hack The Box — particularly CPTS, CBBH, or even CJCA — which tend to be extremely technical and tightly aligned with hands-on skill validation, TH-200 feels less demanding from a technical standpoint.

That said, TH-200 is still relatively new. It may simply need time to mature and evolve. I hope future iterations expand the technical depth, especially around advanced telemetry analysis and real-world hunting tradecraft.

---

### Pros  
  
- **Hands-on, Practical Exam**    
  The 8-hour lab-based exam with reporting requirement validates real investigative and documentation skills.  
- **Strong Foundational Structure**    
  Covers core threat hunting concepts, ransomware/APT landscape, IoC-based and behavior-based hunting.  
- **Focus on Reporting & Communication**    
  Emphasizes structured findings and professional documentation — highly relevant for real-world SOC environments.  
- **Recognized OffSec Brand**    
  Backed by OffSec’s reputation for practical certifications and proctored exams.  
  
---  
  
### Cons
  
- **Limited Technical Depth**    
  Advanced Splunk queries and deeper EDR telemetry analysis (e.g., complex Falcon investigations) are not explored in depth.
- **Feels Introductory for Experienced Hunters** 
  Professionals with strong SIEM and IR backgrounds may find the content less challenging.
- **Tool Coverage Could Be More Advanced**    
  Hunting workflows using real-world telemetry could be more technical and scenario-driven.  
- **Pricing vs. Depth**    
  Cost may feel high relative to the technical depth delivered compared to newer, highly technical certifications.

---
## Final Thoughts

TH-200 is a solid foundational certification for professionals transitioning into Threat Hunting. It provides structure, methodology, and a practical exam experience aligned with modern tooling.

However, for experienced practitioners seeking deep technical challenge, it may feel introductory rather than advanced.

Would I recommend it?  
Yes — particularly for professionals entering or formalizing their Threat Hunting career path.

Would I like to see it evolve?  
Absolutely.
