// Coverage toggle for method source code
// Button: data-coverage-toggle data-target="source-method-xyz"
// Target: id="source-method-xyz" data-coverage="--110-11"

document.addEventListener('DOMContentLoaded', function() {
  document.addEventListener('click', function(e) {
    // Handle click on button or icon inside button
    let btn = e.target;
    if (btn.tagName === 'I' && btn.parentElement.hasAttribute('data-coverage-toggle')) {
      btn = btn.parentElement;
    }
    if (!btn.hasAttribute('data-coverage-toggle')) return;

    const targetId = btn.dataset.target;
    if (!targetId) return;

    const codeBlock = document.getElementById(targetId);
    if (!codeBlock) return;

    const coverageData = codeBlock.dataset.coverage;
    if (!coverageData) return;

    const icon = btn.querySelector('i');
    const isActive = btn.dataset.coverageToggle === 'on';

    if (isActive) {
      btn.dataset.coverageToggle = '';
      if (icon) {
        icon.className = 'bi bi-eye';
      }
      removeCoverageHighlighting(codeBlock);
    } else {
      btn.dataset.coverageToggle = 'on';
      if (icon) {
        icon.className = 'bi bi-eye-fill';
      }
      applyCoverageHighlighting(codeBlock, coverageData);
    }
  });
});

function applyCoverageHighlighting(codeBlock, coverageData) {
  const html = codeBlock.innerHTML;
  const lines = html.split('\n');

  // Coverage data is for body only (excludes def and end lines)
  // Line 0 = def, lines 1..n-2 = body, line n-1 = end
  const wrappedLines = lines.map((line, idx, arr) => {
    let cov = 'def';
    if (idx > 0 && idx < arr.length - 1) {
      const covIdx = idx - 1;
      if (covIdx < coverageData.length) {
        cov = coverageData[covIdx]; // '1', '0', or '-'
      }
    }
    // Include newline inside span (except last line)
    const nl = idx < arr.length - 1 ? '\n' : '';
    return `<span data-cov="${cov}">${line}${nl}</span>`;
  });

  codeBlock.innerHTML = wrappedLines.join('');
  codeBlock.dataset.coverageActive = '';
}

function removeCoverageHighlighting(codeBlock) {
  const lines = codeBlock.querySelectorAll('[data-cov]');
  if (lines.length > 0) {
    const plainLines = Array.from(lines).map(span => span.innerHTML);
    codeBlock.innerHTML = plainLines.join('');
  }
  delete codeBlock.dataset.coverageActive;
}
