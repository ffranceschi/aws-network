#!/usr/bin/env python3
"""Gerador do diagrama de arquitetura hub/spoke com Transit Gateway."""

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch, FancyArrowPatch
import matplotlib.patheffects as pe

fig, ax = plt.subplots(1, 1, figsize=(20, 14))
ax.set_xlim(0, 20)
ax.set_ylim(0, 14)
ax.axis("off")
fig.patch.set_facecolor("#1a1a2e")
ax.set_facecolor("#1a1a2e")

# ── helpers ──────────────────────────────────────────────────────────────────

def box(ax, x, y, w, h, color, alpha=0.15, lw=1.5, ls="-", radius=0.2):
    p = FancyBboxPatch((x, y), w, h,
                        boxstyle=f"round,pad={radius}",
                        linewidth=lw, linestyle=ls,
                        edgecolor=color, facecolor=color, alpha=alpha,
                        zorder=2)
    ax.add_patch(p)
    return p

def label(ax, x, y, text, size=8, color="white", bold=False, ha="center", va="center", zorder=5):
    weight = "bold" if bold else "normal"
    ax.text(x, y, text, fontsize=size, color=color, ha=ha, va=va,
            fontweight=weight, zorder=zorder,
            fontfamily="monospace")

def subnet_box(ax, x, y, w, h, cidr, name, color):
    box(ax, x, y, w, h, color, alpha=0.25, lw=1)
    label(ax, x + w/2, y + h - 0.18, name, size=6.5, color=color, bold=True)
    label(ax, x + w/2, y + 0.18, cidr, size=6, color="#cccccc")

def arrow(ax, x1, y1, x2, y2, color="#aaaaaa", lw=1.5, style="->", zorder=4):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle=style, color=color,
                                lw=lw, connectionstyle="arc3,rad=0.0"),
                zorder=zorder)

def dashed_arrow(ax, x1, y1, x2, y2, color="#ff6b6b", lw=1.2, zorder=4):
    ax.annotate("", xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle="-|>", color=color, lw=lw,
                                linestyle="dashed",
                                connectionstyle="arc3,rad=0.0"),
                zorder=zorder)

# ── colors ───────────────────────────────────────────────────────────────────
C_HUB    = "#4cc9f0"
C_DEV    = "#06d6a0"
C_PROD   = "#ffd166"
C_TGW    = "#c77dff"
C_NET    = "#aaaaaa"
C_BH     = "#ff6b6b"
C_IGW    = "#f8961e"
C_NAT    = "#f3722c"

# ═══════════════════════════════════════════════════════════════════════════
# INTERNET
# ═══════════════════════════════════════════════════════════════════════════
box(ax, 7.8, 12.4, 4.4, 1.2, C_NET, alpha=0.12, lw=1, ls="--")
label(ax, 10, 13.05, "INTERNET", size=11, color=C_NET, bold=True)

# ═══════════════════════════════════════════════════════════════════════════
# HUB ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════
box(ax, 0.4, 5.2, 19.2, 6.9, C_HUB, alpha=0.08, lw=2)
label(ax, 10, 11.82, "HUB ACCOUNT  ·  225119180422", size=10, color=C_HUB, bold=True)
label(ax, 10, 11.45, "VPC: 10.0.0.0/16", size=8.5, color=C_HUB)

# Public subnets ─────────────────────────────────────────────────────────
box(ax, 0.8, 8.5, 4.6, 2.5, C_IGW, alpha=0.15, lw=1.2)
label(ax, 3.1, 10.75, "PUBLIC SUBNETS", size=7.5, color=C_IGW, bold=True)
subnet_box(ax, 1.0, 9.1, 2.0, 1.2, "10.0.0.0/24", "pub-a", C_IGW)
subnet_box(ax, 3.2, 9.1, 2.0, 1.2, "10.0.1.0/24", "pub-b", C_IGW)

# IGW
box(ax, 1.05, 8.55, 1.3, 0.5, C_IGW, alpha=0.35, lw=1)
label(ax, 1.7, 8.8, "IGW", size=7, color=C_IGW, bold=True)

# NAT GW
box(ax, 2.95, 8.55, 1.6, 0.5, C_NAT, alpha=0.35, lw=1)
label(ax, 3.75, 8.8, "NAT GW", size=7, color=C_NAT, bold=True)
label(ax, 3.75, 8.58, "EIP: elastic", size=5.5, color="#cccccc")

# TGW Attachment subnets hub ─────────────────────────────────────────────
box(ax, 5.8, 8.5, 4.6, 2.5, C_HUB, alpha=0.15, lw=1.2)
label(ax, 8.1, 10.75, "TGW ATTACHMENT SUBNETS", size=7.5, color=C_HUB, bold=True)
subnet_box(ax, 6.0, 9.1, 2.0, 1.2, "10.0.2.0/28", "tgw-a", C_HUB)
subnet_box(ax, 8.2, 9.1, 2.0, 1.2, "10.0.3.0/28", "tgw-b", C_HUB)

# EC2 label
label(ax, 7.0, 8.68, "EC2: 10.0.2.11", size=5.8, color="#aae4ff")
ax.plot([6.0, 8.0], [8.75, 8.75], color="#aae4ff", lw=0.8, ls="--", zorder=3)

# Route table hub-rt-tgw-attachment
box(ax, 5.8, 8.5, 4.6, 0.55, C_HUB, alpha=0.0, lw=0.8, ls="--")
label(ax, 8.1, 8.77, "rt: hub-rt-tgw-attachment  |  0.0.0.0/0→NAT  |  10.10.0.0/16→TGW  |  10.11.0.0/16→TGW", size=5.2, color="#88bbff")

# ── TRANSIT GATEWAY ──────────────────────────────────────────────────────
box(ax, 10.6, 8.3, 8.6, 2.8, C_TGW, alpha=0.18, lw=2)
label(ax, 14.9, 10.82, "TRANSIT GATEWAY  ·  tgw-0655c5a589d08d398", size=8.5, color=C_TGW, bold=True)
label(ax, 14.9, 10.48, "auto_accept_shared_attachments = enable", size=6.5, color="#ccaaff")

# TGW Route Tables
rt_data = [
    (10.75, 8.85, "hub-tgw-rt-hub", ["10.10.0.0/16 → dev atch", "10.11.0.0/16 → prod atch"], C_HUB),
    (13.65, 8.85, "hub-tgw-rt-dev",  ["10.0.0.0/16  → hub atch", "0.0.0.0/0    → hub atch", "10.11.0.0/16 [BH]"], C_DEV),
    (16.55, 8.85, "hub-tgw-rt-prod", ["10.0.0.0/16  → hub atch", "0.0.0.0/0    → hub atch", "10.10.0.0/16 [BH]"], C_PROD),
]
for rx, ry, rname, routes, rc in rt_data:
    box(ax, rx, ry, 2.7, 1.95, rc, alpha=0.2, lw=1.2, radius=0.1)
    label(ax, rx + 1.35, ry + 1.77, rname, size=6.5, color=rc, bold=True)
    for i, r in enumerate(routes):
        c = C_BH if "blackhole" in r else "#dddddd"
        label(ax, rx + 1.35, ry + 1.47 - i*0.32, r, size=5.6, color=c)

# Attachments label
label(ax, 14.9, 8.62, "Attachments: hub  ·  dev  ·  prod", size=6, color="#bbbbbb")

# RAM share
box(ax, 10.65, 8.32, 8.5, 0.35, C_TGW, alpha=0.0, lw=0.6, ls=":")
label(ax, 14.9, 8.5, "RAM share → 686633026087 (dev)  ·  745416886900 (prod)", size=5.5, color="#ccaaff")

# ── hub VPC route tables (public) ────────────────────────────────────────
box(ax, 0.8, 5.3, 4.6, 3.0, C_HUB, alpha=0.0, lw=0)
label(ax, 3.1, 8.22, "rt: hub-rt-public", size=6, color="#88bbff", bold=True)
label(ax, 3.1, 7.98, "0.0.0.0/0 → IGW", size=5.5, color="#aaaaaa")
label(ax, 3.1, 7.72, "10.10.0.0/16 → TGW", size=5.5, color="#aaaaaa")
label(ax, 3.1, 7.46, "10.11.0.0/16 → TGW", size=5.5, color="#aaaaaa")
ax.plot([0.8, 5.4], [8.28, 8.28], color="#336688", lw=0.6, ls=":", zorder=3)

# ═══════════════════════════════════════════════════════════════════════════
# DEV ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════
box(ax, 0.4, 0.3, 8.8, 4.7, C_DEV, alpha=0.08, lw=2)
label(ax, 4.8, 4.75, "DEV ACCOUNT  ·  686633026087", size=10, color=C_DEV, bold=True)
label(ax, 4.8, 4.38, "VPC: 10.10.0.0/16", size=8.5, color=C_DEV)

# Workload subnets dev
box(ax, 0.8, 2.1, 4.0, 2.0, C_DEV, alpha=0.18, lw=1.2)
label(ax, 2.8, 3.85, "WORKLOAD SUBNETS", size=7, color=C_DEV, bold=True)
subnet_box(ax, 0.95, 2.45, 1.7, 1.3, "10.10.0.0/24", "workload-a", C_DEV)
subnet_box(ax, 2.9, 2.45, 1.7, 1.3, "10.10.1.0/24", "workload-b", C_DEV)
label(ax, 2.8, 2.18, "rt: 0.0.0.0/0 → TGW  |  10.0.0.0/16 → TGW", size=5.2, color="#88ddbb")

# TGW attachment subnets dev
box(ax, 5.0, 2.1, 3.9, 2.0, C_DEV, alpha=0.12, lw=1.2)
label(ax, 6.95, 3.85, "TGW ATTACH SUBNETS", size=7, color=C_DEV, bold=True)
subnet_box(ax, 5.15, 2.45, 1.6, 1.3, "10.10.2.0/28", "tgw-a", C_DEV)
subnet_box(ax, 6.95, 2.45, 1.6, 1.3, "10.10.3.0/28", "tgw-b", C_DEV)
label(ax, 6.95, 2.18, "NACL: allow 10.0.0.0/8 | TCP eph | ICMP", size=5.2, color="#88ddbb")

# Dev NACL summary
box(ax, 0.8, 0.5, 8.2, 1.45, C_DEV, alpha=0.08, lw=0.8, ls="--")
label(ax, 4.9, 1.72, "hub-tgw-rt-dev:", size=6, color=C_DEV, bold=True)
label(ax, 4.9, 1.42, "10.0.0.0/16 → hub  |  0.0.0.0/0 → hub  |  10.11.0.0/16 [BH]", size=5.5, color="#dddddd")
label(ax, 4.9, 1.12, "dev→prod: BLOQUEADO por blackhole route", size=5.5, color=C_BH)
label(ax, 4.9, 0.78, "Egresso internet: dev → TGW → hub → NAT GW → Internet", size=5.5, color="#aaaaaa")

# ═══════════════════════════════════════════════════════════════════════════
# PROD ACCOUNT
# ═══════════════════════════════════════════════════════════════════════════
box(ax, 10.0, 0.3, 9.5, 4.7, C_PROD, alpha=0.08, lw=2)
label(ax, 14.75, 4.75, "PROD ACCOUNT  ·  745416886900", size=10, color=C_PROD, bold=True)
label(ax, 14.75, 4.38, "VPC: 10.11.0.0/16", size=8.5, color=C_PROD)

# Workload subnets prod
box(ax, 10.4, 2.1, 4.2, 2.0, C_PROD, alpha=0.18, lw=1.2)
label(ax, 12.5, 3.85, "WORKLOAD SUBNETS", size=7, color=C_PROD, bold=True)
subnet_box(ax, 10.55, 2.45, 1.8, 1.3, "10.11.0.0/24", "workload-a", C_PROD)
subnet_box(ax, 12.55, 2.45, 1.8, 1.3, "10.11.1.0/24", "workload-b", C_PROD)
label(ax, 12.5, 2.18, "rt: 0.0.0.0/0 → TGW  |  10.0.0.0/16 → TGW", size=5.2, color="#ffdd88")

# TGW attachment subnets prod
box(ax, 14.8, 2.1, 4.3, 2.0, C_PROD, alpha=0.12, lw=1.2)
label(ax, 16.95, 3.85, "TGW ATTACH SUBNETS", size=7, color=C_PROD, bold=True)
subnet_box(ax, 14.95, 2.45, 1.8, 1.3, "10.11.2.0/28", "tgw-a", C_PROD)
subnet_box(ax, 16.95, 2.45, 1.8, 1.3, "10.11.3.0/28", "tgw-b", C_PROD)
label(ax, 16.95, 2.18, "NACL: allow 10.0.0.0/8 | TCP eph | ICMP", size=5.2, color="#ffdd88")

# Prod NACL summary
box(ax, 10.4, 0.5, 8.8, 1.45, C_PROD, alpha=0.08, lw=0.8, ls="--")
label(ax, 14.8, 1.72, "hub-tgw-rt-prod:", size=6, color=C_PROD, bold=True)
label(ax, 14.8, 1.42, "10.0.0.0/16 → hub  |  0.0.0.0/0 → hub  |  10.10.0.0/16 [BH]", size=5.5, color="#dddddd")
label(ax, 14.8, 1.12, "prod→dev: BLOQUEADO por blackhole route", size=5.5, color=C_BH)
label(ax, 14.8, 0.78, "Egresso internet: prod → TGW → hub → NAT GW → Internet", size=5.5, color="#aaaaaa")

# ═══════════════════════════════════════════════════════════════════════════
# ARROWS
# ═══════════════════════════════════════════════════════════════════════════

# Internet ↔ IGW
arrow(ax, 10, 12.4, 1.9, 9.4, color=C_IGW, lw=1.5, style="<->")
ax.text(5.2, 11.2, "internet traffic\n(HTTP/S, ICMP…)", fontsize=6, color=C_IGW,
        ha="center", style="italic")

# IGW ↔ NAT GW
arrow(ax, 2.35, 8.55, 2.35, 8.3, color=C_IGW, lw=1.2, style="-")
arrow(ax, 3.75, 8.3, 3.75, 8.55, color=C_NAT, lw=1.2, style="-")
ax.plot([1.7, 5.4], [8.3, 8.3], color="#555555", lw=0.8, ls=":", zorder=3)

# NAT GW → internet (egress)
arrow(ax, 3.75, 9.3, 9.2, 12.5, color=C_NAT, lw=1.8, style="->")
label(ax, 7.3, 11.2, "egresso internet\n(spokes via hub)", size=6, color=C_NAT)

# Hub TGW attachment ↔ TGW
arrow(ax, 8.1, 9.1, 11.5, 9.5, color=C_TGW, lw=2, style="<->")
label(ax, 10.0, 9.55, "hub attachment", size=6, color=C_TGW)

# TGW ↔ Dev
arrow(ax, 13.5, 8.3, 7.5, 4.8, color=C_DEV, lw=2, style="<->")
label(ax, 10.2, 7.0, "dev attachment\n10.10.0.0/16", size=6.5, color=C_DEV, bold=False)

# TGW ↔ Prod
arrow(ax, 15.5, 8.3, 16.0, 4.8, color=C_PROD, lw=2, style="<->")
label(ax, 16.5, 7.0, "prod attachment\n10.11.0.0/16", size=6.5, color=C_PROD, bold=False)

# Dev ↔↔ Prod BLOCKED
ax.annotate("", xy=(10.0, 2.5), xytext=(9.2, 2.5),
            arrowprops=dict(arrowstyle="<->", color=C_BH, lw=1.5, linestyle="dashed"),
            zorder=4)
label(ax, 9.6, 2.8, "[X] BLOCKED\nblackhole", size=6, color=C_BH, bold=True)

# Hub RT public → TGW (return path for spokes)
ax.annotate("", xy=(10.8, 8.8), xytext=(5.4, 8.1),
            arrowprops=dict(arrowstyle="->", color="#4488bb", lw=1,
                            linestyle="dotted", connectionstyle="arc3,rad=-0.2"),
            zorder=3)
label(ax, 8.2, 7.7, "return path\n(public RT → TGW)", size=5.5, color="#4488bb")

# ═══════════════════════════════════════════════════════════════════════════
# LEGEND
# ═══════════════════════════════════════════════════════════════════════════
legend_items = [
    (C_HUB,  "Hub account / VPC"),
    (C_DEV,  "Dev account / VPC"),
    (C_PROD, "Prod account / VPC"),
    (C_TGW,  "Transit Gateway + Route Tables"),
    (C_NAT,  "NAT Gateway (egresso centralizado)"),
    (C_BH,   "Blackhole route (tráfego bloqueado)"),
]
for i, (c, t) in enumerate(legend_items):
    bx = 0.6 + i * 3.3
    ax.add_patch(mpatches.Rectangle((bx, 5.25), 0.25, 0.18,
                                     color=c, alpha=0.8, zorder=6))
    label(ax, bx + 0.38, 5.34, t, size=5.8, color="#cccccc", ha="left")

# Title
label(ax, 10, 13.7, "AWS Hub/Spoke Network Architecture  ·  Transit Gateway",
      size=13, color="white", bold=True)
label(ax, 10, 13.35,
      "Hub: 225119180422  ·  Dev: 686633026087  ·  Prod: 745416886900",
      size=8, color="#aaaaaa")

plt.tight_layout(pad=0.3)
out = "/Users/fernando/Work/estudos/aws-network/architecture.png"
plt.savefig(out, dpi=150, bbox_inches="tight", facecolor=fig.get_facecolor())
print(f"Diagrama salvo em: {out}")
plt.close()
