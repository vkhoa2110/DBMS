const state = {
  lastQuestion: 'khách hàng bị trừ tiền dù giao dịch thất bại',
};

const elements = {
  overview: document.getElementById('overview'),
  issues: document.getElementById('issues'),
  question: document.getElementById('question'),
  mode: document.getElementById('mode'),
  keyword: document.getElementById('keyword'),
  segment: document.getElementById('segment'),
  risk: document.getElementById('risk'),
  daysBack: document.getElementById('daysBack'),
  searchBtn: document.getElementById('searchBtn'),
  vipBtn: document.getElementById('vipBtn'),
  refreshBtn: document.getElementById('refreshBtn'),
  resultMeta: document.getElementById('resultMeta'),
  resultsBody: document.getElementById('resultsBody'),
  triageList: document.getElementById('triageList'),
  similarMeta: document.getElementById('similarMeta'),
  similarList: document.getElementById('similarList'),
  vectorModal: document.getElementById('vectorModal'),
  vectorModalMeta: document.getElementById('vectorModalMeta'),
  vectorModalText: document.getElementById('vectorModalText'),
  vectorModalStats: document.getElementById('vectorModalStats'),
  vectorPreview: document.getElementById('vectorPreview'),
  vectorFull: document.getElementById('vectorFull'),
  vectorCopyBtn: document.getElementById('vectorCopyBtn'),
  vectorCopyStatus: document.getElementById('vectorCopyStatus'),
};

let currentVectorJson = '';

function riskClass(risk) {
  return `risk risk-${String(risk || '').toLowerCase()}`;
}

function score(row) {
  if (row.similarity !== undefined && row.similarity !== null) {
    return Number(row.similarity).toFixed(4);
  }
  return '';
}

function setBusy(isBusy) {
  elements.searchBtn.disabled = isBusy;
  elements.vipBtn.disabled = isBusy;
  elements.refreshBtn.disabled = isBusy;
}

async function requestJson(url, options = {}) {
  const response = await fetch(url, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  });
  const payload = await response.json();
  if (!response.ok || payload.error) {
    throw new Error(payload.error || `HTTP ${response.status}`);
  }
  return payload;
}

function renderOverview(payload) {
  const overview = payload.overview || {};
  const realEmbedding = payload.realEmbedding || {};
  const embeddedCount = realEmbedding.embedded_feedback_count > 0
    ? realEmbedding.embedded_feedback_count
    : overview.embedded_feedback_count;
  const embeddedLabel = realEmbedding.embedded_feedback_count > 0
    ? `Real · ${realEmbedding.model_name || payload.ollamaModel || ''}`
    : 'Embedded';
  elements.overview.innerHTML = `
    <div><dt>Feedback</dt><dd>${overview.feedback_count ?? 0}</dd></div>
    <div><dt>${embeddedLabel}</dt><dd>${embeddedCount ?? 0}</dd></div>
    <div><dt>Critical</dt><dd>${overview.critical_count ?? 0}</dd></div>
    <div><dt>VIP</dt><dd>${overview.vip_count ?? 0}</dd></div>
  `;

  const issues = payload.issues || [];
  elements.issues.innerHTML = issues.map((issue) => `
    <div class="issue-row">
      <strong>${issue.SourceIssueGroup}</strong>
      <span>${issue.count}</span>
    </div>
  `).join('');
}

function renderResults(rows, meta) {
  elements.resultMeta.textContent = meta;
  if (!rows.length) {
    elements.resultsBody.innerHTML = `<tr><td colspan="7" class="empty">No matching feedback found</td></tr>`;
    return;
  }

  elements.resultsBody.innerHTML = rows.map((row) => `
    <tr>
      <td>${row.FeedbackId}</td>
      <td>${row.Product}</td>
      <td>${row.CustomerSegment}</td>
      <td><span class="${riskClass(row.RiskLevel)}">${row.RiskLevel}</span></td>
      <td class="feedback">${row.FeedbackText}</td>
      <td class="score">${score(row)}</td>
      <td><button class="secondary row-action" data-similar="${row.FeedbackId}">Similar</button></td>
      <td><button class="secondary row-action" data-vector="${row.FeedbackId}">Vector</button></td>
    </tr>
  `).join('');
}

function renderTriage(rows) {
  if (!rows.length) {
    elements.triageList.innerHTML = `<div class="empty">No triage data</div>`;
    return;
  }

  elements.triageList.innerHTML = rows.map((row) => `
    <div class="triage-row">
      <div>
        <strong>${row.Product}</strong>
        <span>${row.RiskLevel}</span>
      </div>
      <div class="score">${Number(row.best_similarity).toFixed(4)}</div>
      <span>${row.hit_count} hits</span>
      <span>avg ${Number(row.avg_similarity).toFixed(4)}</span>
    </div>
  `).join('');
}

function renderSimilar(feedbackId, rows) {
  elements.similarMeta.textContent = `Seed case #${feedbackId}`;
  if (!rows.length) {
    elements.similarList.innerHTML = `<div class="empty">No similar cases</div>`;
    return;
  }

  elements.similarList.innerHTML = rows.map((row) => `
    <div class="similar-row">
      <strong>#${row.FeedbackId} · ${row.Product}</strong>
      <span>${row.CustomerSegment} · ${row.RiskLevel} · ${Number(row.similarity).toFixed(4)}</span>
      <p>${row.FeedbackText}</p>
    </div>
  `).join('');
}

function showError(message) {
  elements.resultsBody.innerHTML = `<tr><td colspan="8"><div class="error">${message}</div></td></tr>`;
  elements.resultMeta.textContent = 'Error';
}

function openVectorModal() {
  elements.vectorModal.hidden = false;
  elements.vectorCopyStatus.textContent = '';
}

function closeVectorModal() {
  elements.vectorModal.hidden = true;
  currentVectorJson = '';
}

function fmt(value, digits = 6) {
  return Number(value).toFixed(digits);
}

function renderVector(payload) {
  const values = payload.values || [];
  const dim = payload.dimensionCount ?? values.length;
  const sample = values.slice(0, 20);

  elements.vectorModalMeta.textContent =
    `Feedback #${payload.feedbackId} · ${payload.source}`;
  elements.vectorModalText.textContent = payload.feedbackText || '';

  const stats = [
    ['Model', payload.modelName || '-'],
    ['Dimensions', dim],
    ['Norm', payload.norm != null ? fmt(payload.norm) : '-'],
    ['Min', values.length ? fmt(Math.min(...values)) : '-'],
    ['Max', values.length ? fmt(Math.max(...values)) : '-'],
    ['Mean', values.length ? fmt(values.reduce((a, b) => a + b, 0) / values.length) : '-'],
  ];
  elements.vectorModalStats.innerHTML = stats
    .map(([k, v]) => `<div><dt>${k}</dt><dd>${v}</dd></div>`)
    .join('');

  elements.vectorPreview.textContent = sample
    .map((v, i) => `[${i}] ${fmt(v, 8)}`)
    .join('\n');

  currentVectorJson = JSON.stringify(values);
  elements.vectorFull.textContent = currentVectorJson;
}

async function loadVector(feedbackId) {
  openVectorModal();
  elements.vectorModalMeta.textContent = `Loading vector for #${feedbackId}...`;
  elements.vectorModalText.textContent = '';
  elements.vectorModalStats.innerHTML = '';
  elements.vectorPreview.textContent = '';
  elements.vectorFull.textContent = '';
  try {
    const payload = await requestJson('/api/embedding', {
      method: 'POST',
      body: JSON.stringify({ feedbackId }),
    });
    renderVector(payload);
  } catch (error) {
    elements.vectorModalMeta.textContent = `Error: ${error.message}`;
  }
}

async function loadOverview() {
  const payload = await requestJson('/api/overview');
  renderOverview(payload);
}

async function search() {
  setBusy(true);
  try {
    const body = {
      mode: elements.mode.value,
      question: elements.question.value,
      keyword: elements.keyword.value,
      segment: elements.mode.value === 'keyword' ? '' : elements.segment.value,
      risk: elements.mode.value === 'keyword' ? '' : elements.risk.value,
      daysBack: Number(elements.daysBack.value || 30),
      top: 20,
    };
    state.lastQuestion = body.question;
    const payload = await requestJson('/api/search', {
      method: 'POST',
      body: JSON.stringify(body),
    });
    const label = payload.mode === 'keyword'
      ? `Keyword search: "${body.keyword}"`
      : `Semantic-like search profile: ${payload.queryProfile}`;
    renderResults(payload.rows || [], label);
    await loadTriage();
  } catch (error) {
    showError(error.message);
  } finally {
    setBusy(false);
  }
}

async function loadTriage() {
  const payload = await requestJson('/api/triage', {
    method: 'POST',
    body: JSON.stringify({ question: state.lastQuestion }),
  });
  renderTriage(payload.rows || []);
}

async function loadSimilar(feedbackId) {
  const payload = await requestJson('/api/similar', {
    method: 'POST',
    body: JSON.stringify({ feedbackId, top: 12 }),
  });
  renderSimilar(feedbackId, payload.rows || []);
}

elements.searchBtn.addEventListener('click', search);
elements.refreshBtn.addEventListener('click', async () => {
  await loadOverview();
  await loadTriage();
});
elements.vipBtn.addEventListener('click', () => {
  elements.mode.value = 'semantic';
  elements.question.value = 'khách hàng VIP gặp lỗi thanh toán nghiêm trọng';
  elements.segment.value = 'VIP';
  elements.risk.value = 'Critical';
  search();
});
elements.resultsBody.addEventListener('click', (event) => {
  const similarBtn = event.target.closest('[data-similar]');
  if (similarBtn) {
    loadSimilar(Number(similarBtn.dataset.similar));
    return;
  }
  const vectorBtn = event.target.closest('[data-vector]');
  if (vectorBtn) {
    loadVector(Number(vectorBtn.dataset.vector));
  }
});

elements.vectorModal.addEventListener('click', (event) => {
  if (event.target.matches('[data-modal-close]')) {
    closeVectorModal();
  }
});

document.addEventListener('keydown', (event) => {
  if (event.key === 'Escape' && !elements.vectorModal.hidden) {
    closeVectorModal();
  }
});

elements.vectorCopyBtn.addEventListener('click', async () => {
  if (!currentVectorJson) return;
  try {
    await navigator.clipboard.writeText(currentVectorJson);
    elements.vectorCopyStatus.textContent = 'Copied to clipboard';
  } catch (error) {
    elements.vectorCopyStatus.textContent = `Copy failed: ${error.message}`;
  }
});

async function boot() {
  try {
    await loadOverview();
    await search();
  } catch (error) {
    showError(`${error.message}. Run scripts/run_compat_2022_demo.ps1 first.`);
  }
}

boot();
