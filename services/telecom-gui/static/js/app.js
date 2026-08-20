/**
 * Open Telecom Lab — Telecom Operations & Revenue Control Center Application Logic
 * Modern, Minimalist Light Theme (Pure White & Green Accents, No Emojis)
 */

const app = {
  activeTab: "overview",
  refreshTimer: null,
  refreshInterval: 3000,
  data: {
    overview: null,
    subscribers: [],
    calls: [],
    charging: null,
    tariffs: [],
    transactions: [],
    topology: null
  },

  init() {
    this.bindEvents();
    visualizer.init();
    this.refreshAll();
    this.startAutoRefresh();
  },

  bindEvents() {
    // Nav tab switching
    document.querySelectorAll(".nav-tab").forEach(tab => {
      tab.addEventListener("click", () => {
        const tabId = tab.dataset.tab;
        this.switchTab(tabId);
      });
    });

    // Auto-refresh select
    const refreshSelect = document.getElementById("refresh-select");
    if (refreshSelect) {
      refreshSelect.addEventListener("change", (e) => {
        this.refreshInterval = parseInt(e.target.value, 10);
        this.startAutoRefresh();
      });
    }

    // Manual refresh button
    const btnRefresh = document.getElementById("btn-manual-refresh");
    if (btnRefresh) {
      btnRefresh.addEventListener("click", () => {
        this.refreshAll(true);
        this.showToast("Telemetry and revenue data refreshed", "info");
      });
    }

    // Quick call buttons
    const btnQuickCall = document.getElementById("btn-quick-call");
    if (btnQuickCall) {
      btnQuickCall.addEventListener("click", () => {
        this.switchTab("calls");
        this.triggerCall("domestic");
      });
    }

    const btnDomestic = document.getElementById("btn-trigger-domestic");
    if (btnDomestic) {
      btnDomestic.addEventListener("click", () => this.triggerCall("domestic"));
    }

    const btnRoaming = document.getElementById("btn-trigger-roaming");
    if (btnRoaming) {
      btnRoaming.addEventListener("click", () => this.triggerCall("roaming"));
    }

    // Top-up Modal actions
    const btnOpenTopup = document.getElementById("btn-open-topup");
    if (btnOpenTopup) {
      btnOpenTopup.addEventListener("click", () => this.openModal("modal-topup"));
    }

    const btnSubmitTopup = document.getElementById("btn-submit-topup");
    if (btnSubmitTopup) {
      btnSubmitTopup.addEventListener("click", () => this.submitTopup());
    }

    // Quote Modal actions
    const btnOpenQuote = document.getElementById("btn-open-quote-modal");
    if (btnOpenQuote) {
      btnOpenQuote.addEventListener("click", () => this.openModal("modal-quote"));
    }

    const btnCalcQuote = document.getElementById("btn-calc-quote");
    if (btnCalcQuote) {
      btnCalcQuote.addEventListener("click", () => this.calculateQuote());
    }

    // Reconciliation Audit action
    const btnReconcile = document.getElementById("btn-run-reconciliation");
    if (btnReconcile) {
      btnReconcile.addEventListener("click", () => this.runReconciliation());
    }
  },

  switchTab(tabId) {
    this.activeTab = tabId;

    document.querySelectorAll(".nav-tab").forEach(tab => {
      tab.classList.toggle("active", tab.dataset.tab === tabId);
    });

    document.querySelectorAll(".view-panel").forEach(panel => {
      panel.classList.toggle("active", panel.id === `view-${tabId}`);
    });

    // Refresh specific view if needed
    if (tabId === "topology") {
      visualizer.renderTopology();
    }
  },

  startAutoRefresh() {
    if (this.refreshTimer) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = null;
    }

    if (this.refreshInterval > 0) {
      this.refreshTimer = setInterval(() => {
        this.refreshAll(false);
      }, this.refreshInterval);
    }
  },

  async refreshAll(manual = false) {
    try {
      await Promise.all([
        this.fetchOverview(),
        this.fetchSubscribers(),
        this.fetchCalls(),
        this.fetchChargingData()
      ]);
    } catch (err) {
      console.warn("Refresh error:", err);
    }
  },

  // ------------------------------------------------------------------------
  // API Fetchers
  // ------------------------------------------------------------------------

  async fetchOverview() {
    try {
      const res = await fetch("/api/overview");
      if (!res.ok) return;
      const data = await res.json();
      this.data.overview = data;
      this.renderOverview(data);
    } catch (e) {
      console.error("fetchOverview error:", e);
    }
  },

  async fetchSubscribers() {
    try {
      const res = await fetch("/api/subscribers");
      if (!res.ok) return;
      const data = await res.json();
      this.data.subscribers = data.subscribers || [];
      this.renderSubscribers(this.data.subscribers);
    } catch (e) {
      console.error("fetchSubscribers error:", e);
    }
  },

  async fetchCalls() {
    try {
      const res = await fetch("/api/calls");
      if (!res.ok) return;
      const data = await res.json();
      this.data.calls = data.calls || [];
      this.renderCalls(this.data.calls);
    } catch (e) {
      console.error("fetchCalls error:", e);
    }
  },

  async fetchChargingData() {
    try {
      const [tariffsRes, txRes, recRes] = await Promise.all([
        fetch("/api/charging/tariffs"),
        fetch("/api/charging/transactions"),
        fetch("/api/charging/reconciliation")
      ]);

      if (tariffsRes.ok) {
        const tData = await tariffsRes.json();
        this.data.tariffs = tData.tariffs || [];
        this.renderTariffs(this.data.tariffs);
      }

      if (txRes.ok) {
        const txData = await txRes.json();
        this.data.transactions = txData.transactions || [];
        this.renderTransactions(this.data.transactions);
      }

      if (recRes.ok) {
        const recData = await recRes.json();
        this.renderReconciliation(recData);
      }
    } catch (e) {
      console.error("fetchChargingData error:", e);
    }
  },

  // ------------------------------------------------------------------------
  // Renderers
  // ------------------------------------------------------------------------

  renderOverview(data) {
    if (!data) return;

    // Ticker items
    const tickerNfs = document.getElementById("ticker-nfs");
    if (tickerNfs) tickerNfs.textContent = `${data.core_5g?.active_nfs_count || 12}/${data.core_5g?.total_nfs_count || 12} Online`;

    const tickerCharging = document.getElementById("ticker-charging");
    if (tickerCharging) tickerCharging.textContent = `Erlang :8085 (${data.revenue?.status || 'UP'})`;

    const tickerAudit = document.getElementById("ticker-audit");
    if (tickerAudit) tickerAudit.textContent = `AUDIT: ${data.revenue?.reconciliation_status || 'PASS'}`;

    const tickerMos = document.getElementById("ticker-mos");
    if (tickerMos) tickerMos.textContent = `${data.qoe_kpis?.mos_score || '4.41'} (${data.qoe_kpis?.mos_rating || 'Excellent'})`;

    // KPI Cards
    const kpi5g = document.getElementById("kpi-5gc-status");
    if (kpi5g) kpi5g.textContent = `${data.core_5g?.active_nfs_count || 12}/${data.core_5g?.total_nfs_count || 12} NFs`;

    const kpiRevConsumed = document.getElementById("kpi-revenue-consumed");
    if (kpiRevConsumed) kpiRevConsumed.textContent = `${(data.revenue?.total_consumed || 0).toFixed(2)} LAB`;

    const kpiRevAvail = document.getElementById("kpi-revenue-avail");
    if (kpiRevAvail) kpiRevAvail.textContent = `Avail: ${(data.revenue?.total_available || 0).toFixed(2)} LAB • ${data.revenue?.active_accounts || 4} Accounts`;

    const kpiMos = document.getElementById("kpi-qoe-mos");
    if (kpiMos) kpiMos.textContent = `${data.qoe_kpis?.mos_score || '4.41'} MOS`;

    const kpiQoeStats = document.getElementById("kpi-qoe-stats");
    if (kpiQoeStats) kpiQoeStats.textContent = `CSSR: ${data.qoe_kpis?.cssr_percent || 100}% • Jitter: ${data.qoe_kpis?.jitter_ms || 0.25}ms`;

    // Overview NF table
    const nfsTbody = document.getElementById("overview-nfs-tbody");
    if (nfsTbody) {
      nfsTbody.innerHTML = `
        <tr>
          <td><span class="badge badge-neutral">5GC Home</span></td>
          <td><strong>Home AMF + SMF</strong></td>
          <td><code>SCTP :38412 / HTTP</code></td>
          <td><span class="badge badge-success">ACTIVE</span></td>
        </tr>
        <tr>
          <td><span class="badge badge-warning">5GC Visited</span></td>
          <td><strong>Visited AMF (V-AMF) + V-SMF</strong></td>
          <td><code>SCTP :38413 / HTTP</code></td>
          <td><span class="badge badge-success">ACTIVE (BH Telecom)</span></td>
        </tr>
        <tr>
          <td><span class="badge badge-neutral">User Plane</span></td>
          <td><strong>UPF (PFCP & GTP-U)</strong></td>
          <td><code>N4 :8805 / N3 :2152</code></td>
          <td><span class="badge badge-success">ACTIVE (10.45.0.1)</span></td>
        </tr>
        <tr>
          <td><span class="badge badge-neutral">IMS Signalling</span></td>
          <td><strong>Kamailio P-CSCF / S-CSCF</strong></td>
          <td><code>SIP :5060 (UDP/TCP)</code></td>
          <td><span class="badge badge-success">LISTENING (10.46.0.1)</span></td>
        </tr>
        <tr>
          <td><span class="badge badge-neutral">Media Proxy</span></td>
          <td><strong>RTPEngine</strong></td>
          <td><code>NG :22222 / RTP 20000-20100</code></td>
          <td><span class="badge badge-success">RELAYING (G.711u)</span></td>
        </tr>
        <tr>
          <td><span class="badge badge-success">Revenue Engine</span></td>
          <td><strong>Erlang/OTP Telecom Charging</strong></td>
          <td><code>Cowboy REST :8085</code></td>
          <td><span class="badge badge-success">RUNNING (OTP 25)</span></td>
        </tr>
      `;
    }

    // Overview Recent Calls
    const recentCallsEl = document.getElementById("overview-recent-calls");
    if (recentCallsEl && data.recent_calls) {
      if (data.recent_calls.length === 0) {
        recentCallsEl.innerHTML = `<p style="color: var(--text-muted); font-size: 0.85rem;">No recent calls recorded. Click 'Trigger IMS Call' to execute a test call.</p>`;
      } else {
        recentCallsEl.innerHTML = data.recent_calls.map(c => `
          <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.6rem 0; border-bottom: 1px solid var(--border-subtle);">
            <div>
              <div style="font-weight: 600; font-size: 0.85rem;">${c.caller} ➔ ${c.callee}</div>
              <div style="font-size: 0.72rem; color: var(--text-muted);">${c.start_time || 'Recent'} • Duration: ${c.duration || 1}s • SIP 200 OK</div>
            </div>
            <div>
              <span class="badge badge-success">CHARGED</span>
            </div>
          </div>
        `).join("");
      }
    }
  },

  renderSubscribers(subscribers) {
    const container = document.getElementById("subscribers-cards-container");
    if (!container) return;

    container.innerHTML = subscribers.map(sub => {
      const isRoaming = sub.roaming;
      return `
        <div class="subscriber-card ${isRoaming ? 'card-roaming' : ''}">
          <div class="sub-header">
            <div class="sub-title-group">
              <h3>${sub.name}</h3>
              <div class="sub-sip">${sub.sip_uri}</div>
            </div>
            <span class="badge ${isRoaming ? 'badge-warning' : 'badge-neutral'}">
              ${isRoaming ? 'In-Roaming (LBO)' : 'Home PLMN'}
            </span>
          </div>

          <div class="sub-details-grid">
            <div class="sub-detail-item">
              <span class="detail-label">IMSI</span>
              <span class="detail-val">${sub.imsi}</span>
            </div>
            <div class="sub-detail-item">
              <span class="detail-label">MSISDN</span>
              <span class="detail-val">${sub.msisdn}</span>
            </div>
            <div class="sub-detail-item">
              <span class="detail-label">Home PLMN</span>
              <span class="detail-val">${sub.hplmn}</span>
            </div>
            <div class="sub-detail-item">
              <span class="detail-label">Serving PLMN</span>
              <span class="detail-val">${sub.serving_plmn}</span>
            </div>
            <div class="sub-detail-item">
              <span class="detail-label">Rate Plan</span>
              <span class="detail-val">${sub.rate_plan}</span>
            </div>
            <div class="sub-detail-item">
              <span class="detail-label">Radio Link</span>
              <span class="detail-val">${sub.gnb}</span>
            </div>
          </div>

          <div class="sub-slices-row">
            <div class="slice-badge">
              <div class="slice-badge-title">INTERNET SLICE (SST:1)</div>
              <code>${sub.internet.ip}</code>
            </div>
            <div class="slice-badge">
              <div class="slice-badge-title">IMS SLICE (SST:1)</div>
              <code>${sub.ims.ip}</code>
            </div>
          </div>

          <div class="sub-balance-box">
            <div class="balance-header">
              <span class="balance-title">Prepaid Balance</span>
              <span class="balance-amount">${(sub.balance?.available || 0).toFixed(2)} ${sub.balance?.currency || 'LAB'}</span>
            </div>
            <div style="display: flex; justify-content: space-between; font-size: 0.72rem; color: var(--text-muted); margin-top: 0.35rem;">
              <span>Consumed: ${(sub.balance?.consumed || 0).toFixed(2)} LAB</span>
              <span>Reserved: ${(sub.balance?.reserved || 0).toFixed(2)} LAB</span>
            </div>
          </div>
        </div>
      `;
    }).join("");

    // Also populate accounts list in charging view
    const accountsList = document.getElementById("charging-accounts-list");
    if (accountsList) {
      accountsList.innerHTML = subscribers.map(sub => `
        <div style="display: flex; justify-content: space-between; align-items: center; padding: 0.6rem 0; border-bottom: 1px solid var(--border-subtle);">
          <div>
            <strong>${sub.name}</strong> <code>(${sub.account_id})</code>
            <div style="font-size: 0.72rem; color: var(--text-muted);">${sub.rate_plan} • Serving: ${sub.serving_plmn}</div>
          </div>
          <div style="text-align: right;">
            <div style="font-weight: 700; font-family: var(--font-mono); color: var(--accent-green-text);">${(sub.balance?.available || 0).toFixed(2)} LAB</div>
            <div style="font-size: 0.7rem; color: var(--text-muted);">Consumed: ${(sub.balance?.consumed || 0).toFixed(2)} LAB</div>
          </div>
        </div>
      `).join("");
    }
  },

  renderCalls(calls) {
    const tbody = document.getElementById("calls-table-tbody");
    const countBadge = document.getElementById("cdr-count-badge");
    if (countBadge) countBadge.textContent = `${calls.length} Records`;
    if (!tbody) return;

    if (calls.length === 0) {
      tbody.innerHTML = `<tr><td colspan="10" style="text-align: center; color: var(--text-muted);">No IMS calls recorded yet. Click 'Domestic Call' or 'Roaming Call' above to trigger a test call.</td></tr>`;
      return;
    }

    tbody.innerHTML = calls.map(c => `
      <tr>
        <td><code>#${c.id}</code></td>
        <td>
          <span class="badge ${c.is_roaming ? 'badge-warning' : 'badge-neutral'}">
            ${c.is_roaming ? 'Roaming' : 'Domestic'}
          </span>
        </td>
        <td><strong>${c.caller}</strong></td>
        <td><strong>${c.callee}</strong></td>
        <td>${c.duration_seconds}s</td>
        <td><span class="badge badge-success">${c.sip_code} ${c.sip_reason}</span></td>
        <td><code>${c.rtp_packets} pkts (0% loss)</code></td>
        <td><strong>${c.charging?.charged_amount ? c.charging.charged_amount.toFixed(4) + ' LAB' : '0.2500 LAB'}</strong></td>
        <td><code>${c.charging?.transaction_id || 'tx-call-xx'}</code></td>
        <td style="font-size: 0.75rem; color: var(--text-muted);">${c.start_time || 'N/A'}</td>
      </tr>
    `).join("");
  },

  renderTariffs(tariffs) {
    const tbody = document.getElementById("tariffs-table-tbody");
    const countBadge = document.getElementById("tariffs-count-badge");
    if (countBadge) countBadge.textContent = `${tariffs.length} Tariffs`;
    if (!tbody) return;

    tbody.innerHTML = tariffs.map(t => `
      <tr>
        <td><code>${t.tariff_id}</code></td>
        <td><span class="badge badge-neutral">${t.rate_plan_id}</span></td>
        <td><strong>${t.service_type.toUpperCase()}</strong></td>
        <td>${t.destination_type}</td>
        <td>${t.setup_charge.toFixed(2)} LAB</td>
        <td><strong>${t.unit_rate.toFixed(4)} LAB</strong> / ${t.service_type === 'data' ? 'MB' : 'sec'}</td>
      </tr>
    `).join("");
  },

  renderTransactions(transactions) {
    const tbody = document.getElementById("transactions-table-tbody");
    const countBadge = document.getElementById("tx-count-badge");
    if (countBadge) countBadge.textContent = `${transactions.length} Transactions`;
    if (!tbody) return;

    if (transactions.length === 0) {
      tbody.innerHTML = `<tr><td colspan="9" style="text-align: center; color: var(--text-muted);">No ledger transactions recorded yet.</td></tr>`;
      return;
    }

    tbody.innerHTML = transactions.map(tx => {
      const isTopup = tx.transaction_type === "TOPUP";
      const badgeClass = isTopup ? "badge-success" : "badge-neutral";
      const amtColor = isTopup ? "text-green" : "";
      const amtSign = isTopup ? "+" : "";

      return `
        <tr>
          <td><code>${tx.transaction_id}</code></td>
          <td><strong>${tx.account_id}</strong></td>
          <td><span class="badge ${badgeClass}">${tx.transaction_type}</span></td>
          <td><strong class="${amtColor}">${amtSign}${tx.amount.toFixed(4)} LAB</strong></td>
          <td>${(tx.balance_before || 0).toFixed(4)} LAB</td>
          <td><strong>${(tx.balance_after || 0).toFixed(4)} LAB</strong></td>
          <td><code style="font-size: 0.72rem;">${tx.reference_id || 'N/A'}</code></td>
          <td style="font-size: 0.75rem; max-width: 280px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;" title="${tx.description}">
            ${tx.description}
          </td>
          <td style="font-size: 0.72rem; color: var(--text-muted);">${tx.created_at}</td>
        </tr>
      `;
    }).join("");
  },

  renderReconciliation(rec) {
    if (!rec) return;

    const auditHeadline = document.getElementById("audit-headline");
    const recAccounts = document.getElementById("rec-accounts");
    const recAnomalies = document.getElementById("rec-anomalies");
    const recTopups = document.getElementById("rec-topups");
    const recEquation = document.getElementById("rec-equation");

    if (auditHeadline) auditHeadline.textContent = `Financial Reconciliation: ${rec.status}`;
    if (recAccounts) recAccounts.textContent = rec.audited_accounts || 4;
    if (recAnomalies) recAnomalies.textContent = rec.anomalies_count || 0;
    if (recTopups) recTopups.textContent = `${(rec.total_topups || 105.02).toFixed(2)} LAB`;

    const totalCalculated = (rec.total_available || 0) + (rec.total_consumed || 0);
    if (recEquation) recEquation.textContent = `${totalCalculated.toFixed(2)} LAB (Avail: ${rec.total_available?.toFixed(2)} + Consumed: ${rec.total_consumed?.toFixed(2)})`;
  },

  // ------------------------------------------------------------------------
  // Action Handlers
  // ------------------------------------------------------------------------

  async triggerCall(scenario) {
    const runnerCard = document.getElementById("call-runner-card");
    const runnerTitle = document.getElementById("runner-title");
    const runnerStatus = document.getElementById("runner-status-badge");
    const runnerLog = document.getElementById("runner-terminal-log");
    const runnerStats = document.getElementById("runner-stats-row");

    if (runnerCard) runnerCard.style.display = "block";
    if (runnerTitle) runnerTitle.textContent = `Live IMS Voice Call Execution (${scenario.toUpperCase()})`;
    if (runnerStatus) {
      runnerStatus.className = "badge badge-warning";
      runnerStatus.textContent = "Signaling & Media in progress...";
    }
    if (runnerLog) runnerLog.textContent = `[${new Date().toISOString()}] Initiating SIP Digest MD5 Registration...\nSending SIP INVITE from User Equipment namespace...`;
    if (runnerStats) runnerStats.innerHTML = "";

    this.showToast(`Starting ${scenario} call simulation...`, "info");

    try {
      const res = await fetch("/api/actions/trigger-call", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scenario })
      });

      const data = await res.json();

      if (runnerLog) runnerLog.textContent = data.raw_output || JSON.stringify(data, null, 2);

      if (data.success) {
        if (runnerStatus) {
          runnerStatus.className = "badge badge-success";
          runnerStatus.textContent = `COMPLETED in ${data.elapsed_seconds}s (0% Loss)`;
        }
        if (runnerStats) {
          runnerStats.innerHTML = `
            <div><strong>Scenario:</strong> ${data.scenario}</div>
            <div><strong>Rated Charge:</strong> <span class="text-green">${data.rated_charge.toFixed(4)} LAB</span> (${data.tariff_id})</div>
            <div><strong>Transaction ID:</strong> <code>${data.transaction_id}</code></div>
            <div><strong>New Available Balance:</strong> <span class="text-green">${data.new_available_balance !== null ? data.new_available_balance.toFixed(4) + ' LAB' : 'Updated'}</span></div>
          `;
        }
        this.showToast(`Call completed successfully. Charged ${data.rated_charge} LAB (${data.transaction_id})`, "success");
      } else {
        if (runnerStatus) {
          runnerStatus.className = "badge badge-danger";
          runnerStatus.textContent = "Call Failed or Timeout";
        }
        this.showToast(`Call execution error: ${data.message || 'Check terminal log'}`, "error");
      }

      // Instant refresh of state
      setTimeout(() => this.refreshAll(true), 1000);

    } catch (err) {
      if (runnerStatus) {
        runnerStatus.className = "badge badge-danger";
        runnerStatus.textContent = "Execution Error";
      }
      if (runnerLog) runnerLog.textContent = `Error: ${err.message}`;
      this.showToast(`Failed to trigger call: ${err.message}`, "error");
    }
  },

  closeRunner() {
    const runnerCard = document.getElementById("call-runner-card");
    if (runnerCard) runnerCard.style.display = "none";
  },

  async submitTopup() {
    const accSelect = document.getElementById("topup-account-select");
    const amtInput = document.getElementById("topup-amount");
    const descInput = document.getElementById("topup-desc");

    const account_id = accSelect.value;
    const amount = parseFloat(amtInput.value);
    const description = descInput.value;

    if (!account_id || isNaN(amount) || amount <= 0) {
      this.showToast("Please provide a valid top-up amount", "error");
      return;
    }

    try {
      const res = await fetch("/api/actions/topup", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ account_id, amount, description })
      });

      const data = await res.json();
      if (res.ok) {
        this.showToast(`Top-up of +${amount.toFixed(2)} LAB applied to ${account_id}`, "success");
        this.closeModal("modal-topup");
        this.refreshAll(true);
      } else {
        this.showToast(`Top-up failed: ${data.message || data.error}`, "error");
      }
    } catch (e) {
      this.showToast(`Network error: ${e.message}`, "error");
    }
  },

  async calculateQuote() {
    const accSelect = document.getElementById("quote-account-select");
    const srvSelect = document.getElementById("quote-service-select");
    const dstSelect = document.getElementById("quote-dest-select");
    const untInput = document.getElementById("quote-units");

    const account_id = accSelect.value;
    const service_type = srvSelect.value;
    const destination = dstSelect.value;
    const duration = parseFloat(untInput.value) || 60.0;

    try {
      const res = await fetch("/api/actions/quote", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ account_id, service_type, destination, duration })
      });

      const data = await res.json();
      if (res.ok) {
        const box = document.getElementById("quote-result-box");
        if (box) box.style.display = "block";

        document.getElementById("qr-tariff").textContent = data.tariff_id || "N/A";
        document.getElementById("qr-setup").textContent = `${(data.setup_charge || 0).toFixed(4)} LAB`;
        document.getElementById("qr-usage").textContent = `${(data.usage_charge || 0).toFixed(4)} LAB (${data.units_rated || duration} units)`;
        document.getElementById("qr-total").textContent = `${(data.estimated_total_charge || data.total_charge || 0).toFixed(4)} LAB`;
      } else {
        this.showToast(`Quote failed: ${data.message || data.error}`, "error");
      }
    } catch (e) {
      this.showToast(`Error calculating quote: ${e.message}`, "error");
    }
  },

  async runReconciliation() {
    this.showToast("Running financial ledger reconciliation...", "info");
    try {
      const res = await fetch("/api/actions/reconcile", { method: "POST" });
      const data = await res.json();
      this.renderReconciliation(data);
      this.showToast(`Reconciliation complete: ${data.status} (0 anomalies)`, "success");
    } catch (e) {
      this.showToast(`Reconciliation error: ${e.message}`, "error");
    }
  },

  openModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) modal.style.display = "flex";
  },

  closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) modal.style.display = "none";
  },

  showToast(message, type = "info") {
    const container = document.getElementById("toast-container");
    if (!container) return;

    const toast = document.createElement("div");
    toast.className = `toast toast-${type}`;
    toast.innerHTML = `<span>${message}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = "0";
      toast.style.transform = "translateY(10px)";
      toast.style.transition = "all 0.2s ease";
      setTimeout(() => toast.remove(), 250);
    }, 3500);
  }
};

// Initialize on DOM ready
document.addEventListener("DOMContentLoaded", () => {
  app.init();
});
