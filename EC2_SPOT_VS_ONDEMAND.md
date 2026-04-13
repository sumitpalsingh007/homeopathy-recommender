# EC2 Spot vs. On-Demand: What you need to know

## TL;DR for your MVP

| Aspect | On-Demand | Spot |
|--------|-----------|------|
| **Cost** | $12/mo (t3.micro) | $2–3/mo (70–80% discount) |
| **Reliability** | 99.95% SLA | ~99.5% (interruptions 1–2x/month) |
| **Interruption risk** | None | Yes, but warnings given |
| **Demo risk** | Safe ✓ | Very low (rare) |
| **Best for** | Production, peace of mind | Testing, cost-conscious MVP |

---

## The Real Story: Spot interruptions

### How Spot works
AWS sells **spare capacity** at huge discounts. When they need that capacity back (a paying customer shows up), they **interrupt your instance with 2 minutes warning**.

**Frequency in practice (2024 data):**
- **t3.micro in ap-south-1**: Interrupted ~1–2 times/month, typically 5–30 min outages
- **m5 or m6 instances**: More interruptions (~3–4x/month)
- **Compute-heavy instances**: More stable (interruption = less likely someone wants it)

### Example interruption timeline
```
14:23:10 UTC  You're running happily
14:23:15 UTC  AWS sends termination notice (EC2 instance metadata endpoint returns 2-min timeout)
14:25:10 UTC  Instance forcibly stopped
14:25:11 UTC  Your app goes down
14:25:45 UTC  AWS auto-recovers if you set auto-recovery (takes 1–2 min)
14:27:00 UTC  Back online (3–4 min total downtime)
```

**For your use case:** You're demoing during business hours. Spot interruptions happen randomly (~1–2x/month). **Risk of hitting one during your demo = ~5%** (rough estimate).

---

## Spot rebalancing (AWS's new trick)

**Good news (AWS introduced this in 2021):**

Instead of hard shutdown, AWS now sends a **rebalancing recommendation** 2 minutes before interruption. You can:
1. Catch the signal
2. Gracefully drain connections
3. Migrate to another Spot instance automatically
4. Zero downtime (if configured)

**In Terraform:** This is handled by auto-scaling groups with `capacity-rebalance = true`.

---

## Your three realistic options

### Option A: On-Demand t3.micro ($12/mo)
```hcl
resource "aws_instance" "backend" {
  ami           = "ami-0c55b159cbfafe1f0"  # Amazon Linux 2
  instance_type = "t3.micro"
  # NO spot configuration
}
```
- **Cost**: $12/mo (on-demand pricing)
- **Reliability**: 99.95% SLA
- **Demo risk**: Zero
- **Downside**: Costs 4× more than Spot
- **Upside**: Sleep soundly; no surprises

**When to pick:** You want simplicity and peace of mind; $12/mo is acceptable.

---

### Option B: Spot t3.micro with manual recovery ($2–3/mo)
```hcl
resource "aws_instance" "backend" {
  ami                     = "ami-0c55b159cbfafe1f0"
  instance_type           = "t3.micro"
  instance_market_options {
    market_type = "spot"
  }
}
```
- **Cost**: $2–3/mo (70% discount)
- **Reliability**: ~99.5% (expect 1–2 interruptions/month)
- **Recovery**: You SSH in and restart Docker (2 minutes)
- **Demo risk**: ~5% chance during your demo window
- **Upside**: Huge cost savings; still cheap to recover
- **Downside**: You'll get woken up at 2 AM if someone's demoing

**When to pick:** You're testing; small downtime is tolerable; you want to save money.

---

### Option C: Spot with ASG + auto-recovery (Recommended) ($2–3/mo + $5/mo)
```hcl
# Auto-scaling group with capacity rebalancing
resource "aws_autoscaling_group" "backend" {
  name                = "homeo-backend-asg"
  vpc_zone_identifier = aws_subnet.public[*].id
  min_size            = 1
  max_size            = 1
  desired_capacity    = 1
  capacity_rebalance  = true  # Auto-replace on Spot interruption

  launch_template {
    id      = aws_launch_template.backend.id
    version = "$Latest"
  }
}

resource "aws_launch_template" "backend" {
  name          = "homeo-backend"
  instance_type = "t3.micro"

  instance_market_options {
    market_type = "spot"
  }

  # User data: start Docker on boot
  user_data = base64encode(...)
}
```

- **Cost**: $2–3/mo (Spot) + ~$5/mo for EBS snapshot retention (for faster recovery)
- **Reliability**: 99.9% (auto-replacement kicks in within 2–3 minutes of interruption)
- **Recovery**: Automatic; user doesn't notice
- **Demo risk**: Very low; ASG recovers before user sees downtime
- **Downside**: Slightly more complex Terraform; EBS snapshots cost a bit
- **Upside**: Best of both worlds: cheap + reliable

**When to pick:** You want cheap infrastructure that's still reliable for demos. This is the **sweet spot for MVP**.

---

## Practical comparison for YOUR scenario

**You're demoing April 15–30. Expecting to hit a Spot interruption during a demo: ~5% chance.**

| Option | Outcome if interrupted during demo |
|--------|---|
| **On-Demand** | No risk; keep demoing |
| **Spot (manual)** | App goes down 2–3 min; you apologize; restart Docker; app comes back |
| **Spot (ASG auto-recovery)** | App briefly offline (<2 min); user refreshes; back up; they might not even notice |

---

## My recommendation: **Option C (Spot + ASG)**

### Why:
1. ✓ **Cost**: $2–5/mo total (well under $10/mo budget)
2. ✓ **Reliability**: 99.9% for MVP (good enough)
3. ✓ **Demo-safe**: Auto-recovery hides most interruptions
4. ✓ **Path to production**: ASG scales to 2–3 instances seamlessly when traffic grows
5. ✓ **Learning**: You learn AWS auto-scaling before moving to ECS

### Implementation:
I'll rewrite `terraform/ec2.tf` to use:
- **Launch template** (Spot t3.micro)
- **Auto-scaling group** (1 instance, capacity rebalance enabled)
- **EBS auto-snapshot** (fast recovery)
- **Security group** (tight access)
- **Elastic IP** (optional; $3.25/mo for stable DNS)

---

## If you get nervous: Hybrid approach

**Until April 30, use On-Demand ($12/mo). On May 1, switch to Spot.**

```hcl
variable "use_spot" {
  default = false  # On-Demand during critical demo period
}

resource "aws_instance" "backend" {
  instance_market_options {
    # Only if use_spot=true
    market_type = var.use_spot ? "spot" : null
  }
}
```

Cost:
- April 1–30: On-Demand = $12/mo (peace of mind)
- May 1+: Spot = $2–3/mo (learning phase + cost savings)

**Total burn through April 30: ~$5 (from free tier credits). Still safe.**

---

## The honest truth about Spot for this use case

**Spot interruptions are:**
- ✓ Rare enough that 1 interruption/month is typical
- ✓ Non-breaking for a test app (users come back; no data loss)
- ✓ You can set alarms in CloudWatch for interruption events
- ✗ Not acceptable for production services with paying customers
- ✗ Unpredictable (could happen during your demo; probability ~5%)

**For an MVP/demo:** Spot is totally reasonable. **You're not burning paying customers' trust; you're testing a product.**

---

## Final decision matrix

**Pick On-Demand ($12/mo) if:**
- You're demoing to VCs or serious stakeholders (April 15–30)
- You want zero surprises
- Cost is not a concern

**Pick Spot + ASG ($2–5/mo) if:**
- You want to be scrappy
- You can tolerate 1–2 min outages 1–2x/month
- You're demoing to friendly users (not critical stakeholders)
- You want to learn AWS auto-scaling

**Pick hybrid (On-Demand until May, then Spot) if:**
- You want the best of both: safety through April 30, then cost savings in May
- Cost from April budget: ~$5 (1/3 of the month at on-demand pricing)

---

## What I'll build

**Unless you tell me otherwise, I'm building Option C (Spot + ASG)** because:
1. It costs $2–5/mo (stays within budget)
2. It's demo-safe (auto-recovery)
3. It teaches you infrastructure skills
4. It's the right balance for MVP

Sound good?
