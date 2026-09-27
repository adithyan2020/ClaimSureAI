# ClaimSureAI: Live Demo Script (~2:45)

**Before recording:** run `jac start --dev main.jac` on a fresh graph so the six demo claims are seeded. Have `denial-letter.jpg` ready to upload, and keep `services/claims.jac` open in a second tab.

---

### 0:00 – 0:15 · Dashboard

**[Screen]** The dashboard at `/`, with all six claim cards visible.

> "This is ClaimSureAI. Each card is a claim in our knowledge graph. Two agents watch every one: the Risk Predictor before a denial happens, and the Appeal Executor after one does. Let me show you both."

---

### 0:15 – 0:45 · Agent 1: Risk Predictor

**[Screen]** Open the **Knee arthroscopy** card (Grace Liu, not yet filed).

> "This knee surgery hasn't been filed yet, and the Risk Predictor already flags it as high risk. It isn't a black box. It compares the claim against 72 historical claims using a weighted nearest-neighbour search."

**[Screen]** Scroll to **What is driving the risk**, then **Most similar historical claims**.

> "Here are the ranked factors: out-of-network, and no prior authorization, each with its historical denial rate. Below them are the most similar past claims and how they turned out. Because this claim isn't filed, the agent recommends prevention: fix the prior auth before you submit."

**[Screen]** Point to the **Prevent this: fix before filing** button.

---

### 0:45 – 1:15 · Uploading a denial letter

**[Screen]** Go back to the dashboard and click **Upload a denial letter**. Upload `denial-letter.jpg`.

> "Now say a claim has already been denied. I upload a photo of the letter. A typed `by llm()` vision call pulls out structured fields: patient, payer, claim number, the denial code CO-197, and the appeal deadline, along with a confidence score."

**[Screen]** Show the **Check what we read** form. Edit one field.

> "Every field can be edited. If confidence were below 60 percent, or the code weren't a recognized CARC code, the agent would stop and send it to a person. It never guesses."

**[Screen]** Click **Looks right: build my appeal**.

---

### 1:15 – 1:55 · Agent 2: Appeal Executor

**[Screen]** The appeal page. Walk down **What the agent has done**.

> "The Appeal Executor is a Jac walker running a read, ground, decide, draft loop. It matched the denial to a specific plan clause, citing the section and page, and classified the denial as likely wrongful."

**[Screen]** Open the **Matched policy clause** card, then click through the **Appeal packet** tabs.

> "Then it drafted the whole packet: a cover letter that quotes the clause word for word, a medical necessity note, a records request to the provider, and an attachment checklist."

**[Screen]** Point to the **Awaiting your approval** banner.

> "Then it stops. Nothing goes to the payer, provider or patient until I approve, edit or reject it."

**[Screen]** Click **Approve & Send**.

---

### 1:55 – 2:20 · Follow-up after filing

**[Screen]** The timeline updates with Submitted to payer and Tracking response.

> "After approval it files the appeal, requests records, notifies the patient, and starts a 30-day follow-up timer. These actions are simulated in the demo."

**[Screen]** Click **Payer upholds**.

> "The agent doesn't stop at one attempt. If the payer upholds the denial, it prepares a second-level appeal and waits for my approval again. If the denial is upheld twice, like the physical therapy claim on the dashboard, it escalates to a person for external review."

---

### 2:20 – 2:35 · Audit log

**[Screen]** Go to `/audit` and type the claim number into the filter.

> "Every step shows up here: the Risk Predictor, Policy Matcher, Classifier, Document Assembler, Dispatcher and Tracker, each with what it did and the evidence it used."

---

### 2:35 – 2:50 · Under the hood (quick code view)

**[Screen]** Switch to `services/claims.jac` and scroll to the `walker appeal_executor` and `node` definitions.

> "All of this is built in Jac. The claims, policies and appeals are nodes in one shared graph, the two agents are walkers that move across it, the LLM calls return typed objects, and the React UI is written in Jac too. So the AI prepares the case, and people stay in control of the decision."

---

**Optional beat (+15s):** Upload a file with `blur` in its name. Without an LLM key, the fallback extractor gives it a 46% confidence score, so the appeal pauses with **The agent paused for a person to check**. This shows the "never guesses" guardrail live.
